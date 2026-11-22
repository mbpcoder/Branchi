//! Git operations, built on `git2` (libgit2 bindings) — the same library
//! Cargo itself uses. This wraps the subset of git a client UI needs:
//! opening/cloning repos, status, history, diffs, branches, staging and
//! committing.

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use git2::{Diff, DiffOptions, Repository, StatusOptions};
use serde::Serialize;
use std::path::Path;

pub struct GitRepo {
    repo: Repository,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FileStatus {
    New,
    Modified,
    Deleted,
    Renamed,
    Typechange,
    Conflicted,
}

#[derive(Debug, Clone, Serialize)]
pub struct StatusEntry {
    pub path: String,
    pub staged: Option<FileStatus>,
    pub unstaged: Option<FileStatus>,
}

#[derive(Debug, Clone, Serialize)]
pub struct CommitInfo {
    pub id: String,
    pub summary: String,
    pub author: String,
    pub email: String,
    pub time: DateTime<Utc>,
    pub parent_ids: Vec<String>,
}

static PRUNE_ON_FETCH: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(true);

/// Whether fetches remove remote-tracking branches that were deleted on the
/// remote (`git fetch --prune`). On by default; the app sets it from its
/// settings.
pub fn set_prune_on_fetch(enabled: bool) {
    PRUNE_ON_FETCH.store(enabled, std::sync::atomic::Ordering::Relaxed);
}

pub fn prune_on_fetch() -> bool {
    PRUNE_ON_FETCH.load(std::sync::atomic::Ordering::Relaxed)
}

/// A run of lines last changed by the same commit, from [`GitRepo::blame`].
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct BlameHunk {
    /// 1-based first line in the blamed text.
    pub start_line: usize,
    pub lines: usize,
    /// None for lines that aren't committed yet.
    pub commit_id: Option<String>,
    /// Author with `.mailmap` applied; empty when uncommitted.
    pub author: String,
    pub email: String,
    pub time: Option<DateTime<Utc>>,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct BranchInfo {
    pub name: String,
    pub is_head: bool,
    pub is_remote: bool,
    /// The default branch this branch is already fully merged into (e.g.
    /// `origin/main`), or `None` when it isn't merged or is the default
    /// branch itself. See [`GitRepo::default_branch`].
    pub merged_into: Option<String>,
    /// When the branch's tip commit was made (committer time), for sorting
    /// by recent activity. Git doesn't record when a branch was created.
    pub last_commit_time: Option<DateTime<Utc>>,
    /// For a local branch: the remote branch it corresponds to - its
    /// upstream, else a same-named branch on a remote (`origin` first).
    pub remote_counterpart: Option<String>,
    /// Commits on this local branch that its counterpart doesn't have (to
    /// push), and the reverse (to pull). 0 without a counterpart.
    pub ahead: usize,
    pub behind: usize,
    /// For a local branch other than the base itself: the branch it is
    /// compared with (e.g. `origin/main`), and how many commits it has that
    /// the base doesn't (`base_ahead`) and the reverse (`base_behind`).
    pub base: Option<String>,
    pub base_ahead: usize,
    pub base_behind: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct RemoteInfo {
    pub name: String,
    pub url: String,
}

/// The `user.name`/`user.email` identity read from git's global config
/// (`~/.gitconfig` or equivalent), independent of any specific repository.
#[derive(Debug, Clone, Default, Serialize)]
pub struct GlobalIdentity {
    pub name: Option<String>,
    pub email: Option<String>,
}

/// A single file's change within a commit's diff against its first parent
/// (or against the empty tree, for a root commit).
#[derive(Debug, Clone, Serialize)]
pub struct DiffFileEntry {
    pub path: String,
    pub status: FileStatus,
    pub additions: usize,
    pub deletions: usize,
    /// Unified diff text (git's standard patch format) for this file.
    pub patch: String,
}

/// Lines added/removed in one file by one commit.
#[derive(Debug, Clone, Serialize)]
pub struct FileChangeStat {
    pub path: String,
    pub additions: usize,
    pub deletions: usize,
}

/// One commit with its line counts, for reports. Merge commits carry no
/// line counts or files (like `git log --numstat`), since diffing them
/// against one parent would count the merged work twice.
#[derive(Debug, Clone, Serialize)]
pub struct CommitStat {
    pub id: String,
    pub summary: String,
    pub author: String,
    pub email: String,
    /// Author date.
    pub time: DateTime<Utc>,
    /// The author's UTC offset when they committed, in minutes, so reports
    /// can show the author's own local time.
    pub offset_minutes: i32,
    pub is_merge: bool,
    pub additions: usize,
    pub deletions: usize,
    pub files: Vec<FileChangeStat>,
}

/// An author's whole-history span, keyed by email (case-insensitive),
/// after applying the repository's `.mailmap`.
#[derive(Debug, Clone, Serialize)]
pub struct AuthorSpan {
    /// The name on the author's most recent commit.
    pub name: String,
    pub email: String,
    pub first: DateTime<Utc>,
    pub last: DateTime<Utc>,
    pub commits: usize,
}

/// Data behind the Report section: the commits in a period (with line
/// counts), how many commits the period before it had, and every author's
/// first/last commit over all of history.
#[derive(Debug, Clone, Serialize)]
pub struct CommitStatsReport {
    pub commits: Vec<CommitStat>,
    pub previous_count: usize,
    pub authors: Vec<AuthorSpan>,
}

/// A local branch compared with the base branch (`main`, else `master`,
/// else the current branch).
#[derive(Debug, Clone, Serialize)]
pub struct BranchStat {
    pub name: String,
    pub is_head: bool,
    pub last_commit_time: DateTime<Utc>,
    pub last_author: String,
    pub last_email: String,
    /// Commits on this branch that the base doesn't have.
    pub ahead: usize,
    /// Commits on the base that this branch doesn't have.
    pub behind: usize,
    /// Fully contained in the base (and not the base itself).
    pub merged: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct BranchReport {
    pub base: Option<String>,
    pub branches: Vec<BranchStat>,
}

/// What a range of commits changed: shown next to commit, pull and push
/// entries in the Activity panel.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize)]
pub struct ChangeStats {
    pub commits: usize,
    pub files: usize,
    pub insertions: usize,
    pub deletions: usize,
}

impl GitRepo {
    /// Open an existing repository at `path`.
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let repo = Repository::open(path.as_ref())
            .with_context(|| format!("failed to open repo at {}", path.as_ref().display()))?;
        Ok(Self { repo })
    }

    /// Initialize a new repository at `path`.
    pub fn init(path: impl AsRef<Path>) -> Result<Self> {
        let repo = Repository::init(path.as_ref())
            .with_context(|| format!("failed to init repo at {}", path.as_ref().display()))?;
        Ok(Self { repo })
    }

    /// Clone `url` into `path`.
    pub fn clone(url: &str, path: impl AsRef<Path>) -> Result<Self> {
        let repo = Repository::clone(url, path.as_ref())
            .with_context(|| format!("failed to clone {url} into {}", path.as_ref().display()))?;
        Ok(Self { repo })
    }

    /// Working directory / index status for every changed file.
    pub fn status(&self) -> Result<Vec<StatusEntry>> {
        let mut opts = StatusOptions::new();
        opts.include_untracked(true).recurse_untracked_dirs(true);

        let statuses = self.repo.statuses(Some(&mut opts))?;

        Ok(statuses
            .iter()
            .filter_map(|entry| {
                let path = entry.path()?.to_string();
                let flags = entry.status();

                let staged = if flags.is_index_new() {
                    Some(FileStatus::New)
                } else if flags.is_index_modified() {
                    Some(FileStatus::Modified)
                } else if flags.is_index_deleted() {
                    Some(FileStatus::Deleted)
                } else if flags.is_index_renamed() {
                    Some(FileStatus::Renamed)
                } else if flags.is_index_typechange() {
                    Some(FileStatus::Typechange)
                } else {
                    None
                };

                let unstaged = if flags.is_conflicted() {
                    Some(FileStatus::Conflicted)
                } else if flags.is_wt_new() {
                    Some(FileStatus::New)
                } else if flags.is_wt_modified() {
                    Some(FileStatus::Modified)
                } else if flags.is_wt_deleted() {
                    Some(FileStatus::Deleted)
                } else if flags.is_wt_renamed() {
                    Some(FileStatus::Renamed)
                } else if flags.is_wt_typechange() {
                    Some(FileStatus::Typechange)
                } else {
                    None
                };

                if staged.is_none() && unstaged.is_none() {
                    return None;
                }

                Some(StatusEntry {
                    path,
                    staged,
                    unstaged,
                })
            })
            .collect())
    }

    /// Commit history reachable from HEAD, newest first, limited to `limit` entries.
    pub fn log(&self, limit: usize) -> Result<Vec<CommitInfo>> {
        let mut revwalk = self.repo.revwalk()?;
        revwalk.push_head()?;

        let mut commits = Vec::with_capacity(limit);
        for oid in revwalk.take(limit) {
            let oid = oid?;
            let commit = self.repo.find_commit(oid)?;
            let author = commit.author();
            let time = DateTime::<Utc>::from_timestamp(commit.time().seconds(), 0)
                .unwrap_or_else(Utc::now);

            commits.push(CommitInfo {
                id: oid.to_string(),
                summary: commit.summary().unwrap_or("").to_string(),
                author: author.name().unwrap_or("").to_string(),
                email: author.email().unwrap_or("").to_string(),
                time,
                parent_ids: commit.parent_ids().map(|id| id.to_string()).collect(),
            });
        }

        Ok(commits)
    }

    /// The file-level diff of `commit_id` against its first parent (or the
    /// empty tree, if it's a root commit), one entry per changed file.
    pub fn commit_diff(&self, commit_id: &str) -> Result<Vec<DiffFileEntry>> {
        let oid = git2::Oid::from_str(commit_id)
            .with_context(|| format!("invalid commit id: {commit_id}"))?;
        let commit = self.repo.find_commit(oid)?;
        let tree = commit.tree()?;
        let parent_tree = commit.parents().next().map(|p| p.tree()).transpose()?;

        let mut opts = DiffOptions::new();
        let diff =
            self.repo
                .diff_tree_to_tree(parent_tree.as_ref(), Some(&tree), Some(&mut opts))?;

        Self::diff_to_file_entries(&diff)
    }

    /// Unified-diff patch (git's standard format, including file and hunk
    /// headers) of the uncommitted changes to `path`. With `staged`, this
    /// is the index against HEAD (`git diff --cached -- <path>`); otherwise
    /// the working tree against the index (`git diff -- <path>`), with
    /// untracked files shown as fully added.
    pub fn working_file_diff(&self, path: &str, staged: bool) -> Result<String> {
        let mut opts = DiffOptions::new();
        opts.pathspec(path).disable_pathspec_match(true);

        let diff = if staged {
            // An unborn HEAD (no commits yet) diffs against the empty tree.
            let head_tree = match self.repo.head() {
                Ok(head) => Some(head.peel_to_tree()?),
                Err(_) => None,
            };
            self.repo
                .diff_tree_to_index(head_tree.as_ref(), None, Some(&mut opts))?
        } else {
            opts.include_untracked(true)
                .recurse_untracked_dirs(true)
                .show_untracked_content(true);
            self.repo.diff_index_to_workdir(None, Some(&mut opts))?
        };

        let mut patch = String::new();
        diff.print(git2::DiffFormat::Patch, |_delta, _hunk, line| {
            if matches!(line.origin(), '+' | '-' | ' ') {
                patch.push(line.origin());
            }
            patch.push_str(&String::from_utf8_lossy(line.content()));
            true
        })
        .with_context(|| format!("failed to diff file: {path}"))?;
        Ok(patch)
    }

    fn diff_to_file_entries(diff: &Diff) -> Result<Vec<DiffFileEntry>> {
        use std::cell::RefCell;
        use std::collections::HashMap;

        struct Entry {
            status: FileStatus,
            additions: usize,
            deletions: usize,
            patch: String,
        }

        let entries: RefCell<HashMap<String, Entry>> = RefCell::new(HashMap::new());
        let order: RefCell<Vec<String>> = RefCell::new(Vec::new());

        diff.foreach(
            &mut |delta, _progress| {
                let path = delta
                    .new_file()
                    .path()
                    .or_else(|| delta.old_file().path())
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_default();

                let status = match delta.status() {
                    git2::Delta::Added => FileStatus::New,
                    git2::Delta::Deleted => FileStatus::Deleted,
                    git2::Delta::Renamed => FileStatus::Renamed,
                    git2::Delta::Typechange => FileStatus::Typechange,
                    _ => FileStatus::Modified,
                };

                order.borrow_mut().push(path.clone());
                entries.borrow_mut().insert(
                    path,
                    Entry {
                        status,
                        additions: 0,
                        deletions: 0,
                        patch: String::new(),
                    },
                );
                true
            },
            None,
            None,
            Some(&mut |delta, _hunk, line| {
                let path = delta
                    .new_file()
                    .path()
                    .or_else(|| delta.old_file().path())
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_default();

                let mut entries = entries.borrow_mut();
                if let Some(entry) = entries.get_mut(&path) {
                    let prefix = match line.origin() {
                        '+' => {
                            entry.additions += 1;
                            "+"
                        }
                        '-' => {
                            entry.deletions += 1;
                            "-"
                        }
                        ' ' => " ",
                        _ => "",
                    };
                    entry.patch.push_str(prefix);
                    entry
                        .patch
                        .push_str(&String::from_utf8_lossy(line.content()));
                }
                true
            }),
        )?;

        let mut entries = entries.into_inner();
        Ok(order
            .into_inner()
            .into_iter()
            .filter_map(|path| {
                entries.remove(&path).map(|entry| DiffFileEntry {
                    path,
                    status: entry.status,
                    additions: entry.additions,
                    deletions: entry.deletions,
                    patch: entry.patch,
                })
            })
            .collect())
    }

    /// Local and remote-tracking branches, each marked with whether it is
    /// already merged into the default branch.
    pub fn branches(&self) -> Result<Vec<BranchInfo>> {
        self.branches_compared_with(None)
    }

    /// Like [`branches`](Self::branches), with each local branch's
    /// ahead/behind counted against `compare_base` (a local or remote
    /// branch name) instead of the default branch. An unknown name falls
    /// back to the default branch.
    pub fn branches_compared_with(&self, compare_base: Option<&str>) -> Result<Vec<BranchInfo>> {
        let head_name = self
            .repo
            .head()
            .ok()
            .and_then(|h| h.shorthand().map(str::to_string));

        let base = self.default_branch();
        let base_tip = base.as_ref().map(|(_, tip)| *tip);
        // The default branch's name on the other side (local `main` for
        // `origin/main`, and the reverse) is the same line of work, so it
        // isn't marked as merged either.
        let base_names: Vec<String> = match &base {
            Some((name, _)) => match name.split_once('/') {
                Some((_, short)) if self.is_remote_branch(name) => {
                    vec![name.clone(), short.to_string()]
                }
                _ => vec![name.clone()],
            },
            None => Vec::new(),
        };

        // What local branches are counted against: the chosen branch, else
        // the default branch. Its own rows (both sides) show no counts.
        let compare = compare_base
            .and_then(|name| {
                let branch = self
                    .repo
                    .find_branch(name, git2::BranchType::Local)
                    .or_else(|_| self.repo.find_branch(name, git2::BranchType::Remote))
                    .ok()?;
                Some((name.to_string(), branch.get().target()?))
            })
            .or_else(|| base.clone());
        let compare_names: Vec<String> = match &compare {
            Some((name, _)) => match name.split_once('/') {
                Some((_, short)) if self.is_remote_branch(name) => {
                    vec![name.clone(), short.to_string()]
                }
                _ => vec![name.clone()],
            },
            None => Vec::new(),
        };

        let mut result = Vec::new();
        for entry in self.repo.branches(None)? {
            let (branch, branch_type) = entry?;
            let name = match branch.name()? {
                Some(name) => name.to_string(),
                None => continue,
            };
            let is_remote = branch_type == git2::BranchType::Remote;
            let is_head = !is_remote && head_name.as_deref() == Some(name.as_str());

            let is_base =
                base_names.iter().any(|b| b == &name) || (is_remote && name.ends_with("/HEAD"));
            let merged_into = match (base_tip, branch.get().target()) {
                (Some(base_tip), Some(tip))
                    if !is_base
                        && self.is_merged(tip, base_tip)
                        && !(!is_remote && self.never_moved(&name)) =>
                {
                    base.as_ref().map(|(name, _)| name.clone())
                }
                _ => None,
            };

            let last_commit_time = branch
                .get()
                .peel_to_commit()
                .ok()
                .and_then(|c| DateTime::<Utc>::from_timestamp(c.time().seconds(), 0));

            let (remote_counterpart, ahead, behind) = if is_remote {
                (None, 0, 0)
            } else {
                self.remote_counterpart(&branch, &name)
            };

            let (cmp_base, base_ahead, base_behind) = match (&compare, branch.get().target()) {
                (Some((cmp_name, cmp_tip)), Some(tip))
                    if !is_remote && !compare_names.iter().any(|n| n == &name) =>
                {
                    match self.repo.graph_ahead_behind(tip, *cmp_tip) {
                        Ok((a, b)) => (Some(cmp_name.clone()), a, b),
                        Err(_) => (None, 0, 0),
                    }
                }
                _ => (None, 0, 0),
            };

            result.push(BranchInfo {
                name,
                is_head,
                is_remote,
                merged_into,
                last_commit_time,
                remote_counterpart,
                ahead,
                behind,
                base: cmp_base,
                base_ahead,
                base_behind,
            });
        }

        Ok(result)
    }

    /// The remote branch matching local branch `name` and how far apart
    /// they are: its upstream if set, else `<remote>/<name>` on the first
    /// remote that has it (`origin` first).
    fn remote_counterpart(
        &self,
        branch: &git2::Branch,
        name: &str,
    ) -> (Option<String>, usize, usize) {
        let upstream = branch
            .upstream()
            .ok()
            .and_then(|u| u.name().ok().flatten().map(str::to_string));
        let counterpart = upstream.or_else(|| {
            let mut remotes: Vec<String> = self
                .repo
                .remotes()
                .ok()?
                .iter()
                .flatten()
                .map(str::to_string)
                .collect();
            remotes.sort_by_key(|r| r != "origin");
            remotes
                .into_iter()
                .map(|r| format!("{r}/{name}"))
                .find(|candidate| {
                    self.repo
                        .find_branch(candidate, git2::BranchType::Remote)
                        .is_ok()
                })
        });
        let Some(counterpart) = counterpart else {
            return (None, 0, 0);
        };
        let tips = branch.get().target().zip(
            self.repo
                .find_branch(&counterpart, git2::BranchType::Remote)
                .ok()
                .and_then(|b| b.get().target()),
        );
        let (ahead, behind) = tips
            .and_then(|(local, remote)| self.repo.graph_ahead_behind(local, remote).ok())
            .unwrap_or((0, 0));
        (Some(counterpart), ahead, behind)
    }

    /// The branch other branches are checked against for "already merged":
    /// the remote's default branch (`origin/HEAD`, e.g. `origin/main`), else
    /// local `main`, else local `master`. Returns its name and tip commit.
    pub fn default_branch(&self) -> Option<(String, git2::Oid)> {
        let remote_default = self
            .repo
            .find_reference("refs/remotes/origin/HEAD")
            .ok()
            .and_then(|r| r.symbolic_target().map(str::to_string))
            .and_then(|target| {
                let name = target.strip_prefix("refs/remotes/")?.to_string();
                let tip = self.repo.refname_to_id(&target).ok()?;
                Some((name, tip))
            });
        remote_default.or_else(|| {
            ["main", "master"].into_iter().find_map(|name| {
                let branch = self.repo.find_branch(name, git2::BranchType::Local).ok()?;
                Some((name.to_string(), branch.get().target()?))
            })
        })
    }

    fn is_remote_branch(&self, name: &str) -> bool {
        self.repo
            .find_branch(name, git2::BranchType::Remote)
            .is_ok()
    }

    /// Whether a local branch still points where it was created (its reflog
    /// holds only the "branch: Created from ..." entry), i.e. nothing was
    /// ever committed or pulled on it.
    fn never_moved(&self, name: &str) -> bool {
        match self.repo.reflog(&format!("refs/heads/{name}")) {
            Ok(log) => {
                log.len() == 1
                    && log
                        .get(0)
                        .and_then(|e| e.message().map(|m| m.starts_with("branch: Created")))
                        .unwrap_or(false)
            }
            Err(_) => false,
        }
    }

    /// Whether every commit of `tip` is already in `base_tip`. A branch that
    /// points at the same commit as the base (e.g. a new branch with no
    /// commits yet) doesn't count as merged.
    fn is_merged(&self, tip: git2::Oid, base_tip: git2::Oid) -> bool {
        tip != base_tip
            && self
                .repo
                .graph_descendant_of(base_tip, tip)
                .unwrap_or(false)
    }

    /// Stage a file (equivalent to `git add <path>`).
    pub fn stage(&self, path: impl AsRef<Path>) -> Result<()> {
        let mut index = self.repo.index()?;
        index.add_path(path.as_ref())?;
        index.write()?;
        Ok(())
    }

    /// Unstage a file (equivalent to `git reset <path>`), leaving the
    /// working tree unchanged.
    pub fn unstage(&self, path: impl AsRef<Path>) -> Result<()> {
        let head = self.repo.head()?.peel_to_commit()?;
        self.repo
            .reset_default(Some(head.as_object()), [path.as_ref()])?;
        Ok(())
    }

    /// Checks out an existing local branch: updates the working tree to
    /// match it and moves HEAD to point at it.
    pub fn checkout_branch(&self, name: &str) -> Result<()> {
        let branch = self
            .repo
            .find_branch(name, git2::BranchType::Local)
            .with_context(|| format!("local branch not found: {name}"))?;
        let refname = branch
            .get()
            .name()
            .context("branch reference has no name")?
            .to_string();

        let obj = self.repo.revparse_single(&refname)?;
        self.repo
            .checkout_tree(&obj, Some(git2::build::CheckoutBuilder::new().safe()))
            .with_context(|| format!("failed to checkout branch: {name}"))?;
        self.repo.set_head(&refname)?;
        Ok(())
    }

    /// Creates a new local branch named `name`. If `from` is `Some`, it must
    /// name an existing remote-tracking branch (e.g. `origin/feature`); the
    /// new branch starts at that branch's commit and tracks it. Otherwise
    /// the new branch starts at HEAD. Does not check out the new branch.
    pub fn create_branch(&self, name: &str, from: Option<&str>) -> Result<()> {
        let (target, upstream) = match from {
            Some(remote_branch) => {
                let branch = self
                    .repo
                    .find_branch(remote_branch, git2::BranchType::Remote)
                    .with_context(|| format!("remote branch not found: {remote_branch}"))?;
                let commit = branch.get().peel_to_commit()?;
                (commit, Some(remote_branch.to_string()))
            }
            None => {
                let commit = self.repo.head()?.peel_to_commit()?;
                (commit, None)
            }
        };

        let mut branch = self
            .repo
            .branch(name, &target, false)
            .with_context(|| format!("failed to create branch: {name}"))?;
        if let Some(upstream) = upstream {
            branch
                .set_upstream(Some(&upstream))
                .with_context(|| format!("failed to track {upstream} from {name}"))?;
        }
        Ok(())
    }

    /// Deletes a local or remote-tracking branch reference. For a remote
    /// branch this only removes the local tracking ref, mirroring `git
    /// branch -dr`; it does not push a deletion to the remote server.
    pub fn delete_branch(&self, name: &str, is_remote: bool) -> Result<()> {
        let branch_type = if is_remote {
            git2::BranchType::Remote
        } else {
            git2::BranchType::Local
        };
        let mut branch = self
            .repo
            .find_branch(name, branch_type)
            .with_context(|| format!("branch not found: {name}"))?;
        branch
            .delete()
            .with_context(|| format!("failed to delete branch: {name}"))?;
        Ok(())
    }

    /// Fetches the remote that owns `remote_branch` (e.g. `origin` for
    /// `origin/feature`), refreshing its remote-tracking branches.
    pub fn fetch_remote_for_branch(&self, remote_branch: &str) -> Result<()> {
        let remote_name = remote_branch
            .split('/')
            .next()
            .filter(|s| !s.is_empty())
            .with_context(|| format!("invalid remote branch name: {remote_branch}"))?;
        let mut remote = self
            .repo
            .find_remote(remote_name)
            .with_context(|| format!("remote not found: {remote_name}"))?;

        let mut callbacks = git2::RemoteCallbacks::new();
        callbacks.credentials(|url, username, allowed| {
            self.credentials_callback(url, username, allowed)
        });

        let mut fetch_options = git2::FetchOptions::new();
        fetch_options.remote_callbacks(callbacks);
        if prune_on_fetch() {
            // Drop remote-tracking branches deleted on the server.
            fetch_options.prune(git2::FetchPrune::On);
        }

        remote
            .fetch(&[] as &[&str], Some(&mut fetch_options), None)
            .with_context(|| format!("failed to fetch remote: {remote_name}"))?;
        Ok(())
    }

    /// Updates local branch `name` to its upstream: fetches the upstream's
    /// remote, then fast-forwards the branch (and, if it's the checked-out
    /// branch, the working tree) to match. Fails rather than merging if the
    /// branch has diverged from its upstream.
    pub fn update_branch(&self, name: &str) -> Result<()> {
        let upstream_name = {
            let branch = self
                .repo
                .find_branch(name, git2::BranchType::Local)
                .with_context(|| format!("local branch not found: {name}"))?;
            let upstream = branch
                .upstream()
                .with_context(|| format!("branch '{name}' has no upstream to update from"))?;
            upstream
                .name()?
                .context("upstream branch has no name")?
                .to_string()
        };

        self.fetch_remote_for_branch(&upstream_name)?;

        let mut branch = self.repo.find_branch(name, git2::BranchType::Local)?;
        let upstream = branch.upstream()?;
        let upstream_commit = upstream.get().peel_to_commit()?;

        let branch_refname = branch
            .get()
            .name()
            .context("branch has no name")?
            .to_string();
        let branch_oid = branch
            .get()
            .target()
            .context("branch has no direct target")?;

        if branch_oid != upstream_commit.id()
            && !self
                .repo
                .graph_descendant_of(upstream_commit.id(), branch_oid)?
        {
            anyhow::bail!(
                "branch '{name}' has diverged from its upstream; update requires a fast-forward"
            );
        }

        branch
            .get_mut()
            .set_target(upstream_commit.id(), "branchi: fast-forward update")?;

        if self.repo.head()?.name() == Some(branch_refname.as_str()) {
            let obj = self.repo.find_object(upstream_commit.id(), None)?;
            self.repo
                .checkout_tree(&obj, Some(git2::build::CheckoutBuilder::new().force()))?;
            self.repo.set_head(&branch_refname)?;
        }

        Ok(())
    }

    /// Discards working-tree changes to `path`, restoring it to the version
    /// in the index (equivalent to `git checkout -- <path>`). If `path` is
    /// untracked (not in the index), this removes the file instead.
    pub fn revert_file(&self, path: impl AsRef<Path>) -> Result<()> {
        let path = path.as_ref();
        let mut builder = git2::build::CheckoutBuilder::new();
        builder.force();
        builder.path(path);
        builder.remove_untracked(true);
        self.repo
            .checkout_index(None, Some(&mut builder))
            .with_context(|| format!("failed to revert file: {}", path.display()))?;
        Ok(())
    }

    /// Pushes local branch `name` to its upstream remote. Fails if the
    /// branch has no upstream configured.
    pub fn push(&self, name: &str) -> Result<()> {
        let branch = self
            .repo
            .find_branch(name, git2::BranchType::Local)
            .with_context(|| format!("local branch not found: {name}"))?;
        let upstream = branch
            .upstream()
            .with_context(|| format!("branch '{name}' has no upstream to push to"))?;
        let upstream_name = upstream
            .name()?
            .context("upstream branch has no name")?
            .to_string();
        let remote_name = upstream_name
            .split('/')
            .next()
            .filter(|s| !s.is_empty())
            .with_context(|| format!("invalid upstream branch name: {upstream_name}"))?
            .to_string();

        let refname = branch
            .get()
            .name()
            .context("branch reference has no name")?
            .to_string();

        let mut remote = self
            .repo
            .find_remote(&remote_name)
            .with_context(|| format!("remote not found: {remote_name}"))?;

        let mut callbacks = git2::RemoteCallbacks::new();
        callbacks.credentials(|url, username, allowed| {
            self.credentials_callback(url, username, allowed)
        });

        let mut push_options = git2::PushOptions::new();
        push_options.remote_callbacks(callbacks);

        let refspec = format!("{refname}:{refname}");
        remote
            .push(&[refspec.as_str()], Some(&mut push_options))
            .with_context(|| format!("failed to push branch: {name}"))?;
        Ok(())
    }

    /// Supplies credentials for a remote operation (fetch/push): an SSH key
    /// from a running ssh-agent for SSH remotes, the configured
    /// `credential.helper` for HTTPS remotes (e.g. Git Credential Manager,
    /// `osxkeychain`, `store`), or the platform's native default
    /// credentials (e.g. Windows SSPI) as a last resort.
    ///
    /// On Windows, the helper process is spawned with `CREATE_NO_WINDOW` so
    /// it doesn't flash a console window (this app has none of its own).
    /// Elsewhere it goes through `git2::Cred::credential_helper` directly,
    /// which has no such issue.
    fn credentials_callback(
        &self,
        url: &str,
        username_from_url: Option<&str>,
        allowed_types: git2::CredentialType,
    ) -> std::result::Result<git2::Cred, git2::Error> {
        if allowed_types.contains(git2::CredentialType::SSH_KEY) {
            if let Some(username) = username_from_url {
                if let Ok(cred) = git2::Cred::ssh_key_from_agent(username) {
                    return Ok(cred);
                }
            }
        }

        if allowed_types.contains(git2::CredentialType::USER_PASS_PLAINTEXT) {
            #[cfg(windows)]
            {
                if let Some((username, password)) =
                    windows_credential_helper(&self.repo, url, username_from_url)
                {
                    if let Ok(cred) = git2::Cred::userpass_plaintext(&username, &password) {
                        return Ok(cred);
                    }
                }
            }
            #[cfg(not(windows))]
            {
                if let Ok(config) = self.repo.config() {
                    if let Ok(cred) = git2::Cred::credential_helper(&config, url, username_from_url)
                    {
                        return Ok(cred);
                    }
                }
            }
        }

        git2::Cred::default()
    }

    /// The commit id `rev` resolves to, or `None` if it doesn't resolve
    /// (e.g. an unborn HEAD or a branch without an upstream).
    pub fn resolve_commit(&self, rev: &str) -> Option<String> {
        self.repo
            .revparse_single(rev)
            .and_then(|obj| obj.peel_to_commit())
            .ok()
            .map(|commit| commit.id().to_string())
    }

    /// What `to` adds on top of `from`: the commits reachable from `to`
    /// but not `from`, and the files and lines changed between their merge
    /// base and `to`. With no `from`, everything reachable from `to`
    /// counts (diffed against the empty tree).
    pub fn change_stats(&self, from: Option<&str>, to: &str) -> Result<ChangeStats> {
        let to_commit = self
            .repo
            .revparse_single(to)
            .and_then(|obj| obj.peel_to_commit())
            .with_context(|| format!("cannot resolve: {to}"))?;
        let from_commit = match from {
            Some(rev) => Some(
                self.repo
                    .revparse_single(rev)
                    .and_then(|obj| obj.peel_to_commit())
                    .with_context(|| format!("cannot resolve: {rev}"))?,
            ),
            None => None,
        };

        let mut walk = self.repo.revwalk()?;
        walk.push(to_commit.id())?;
        if let Some(from_commit) = &from_commit {
            walk.hide(from_commit.id())?;
        }
        let commits = walk.count();
        if commits == 0 {
            return Ok(ChangeStats::default());
        }

        let base_tree = match &from_commit {
            Some(from_commit) => {
                let base = self
                    .repo
                    .merge_base(from_commit.id(), to_commit.id())
                    .unwrap_or(from_commit.id());
                Some(self.repo.find_commit(base)?.tree()?)
            }
            None => None,
        };
        let diff =
            self.repo
                .diff_tree_to_tree(base_tree.as_ref(), Some(&to_commit.tree()?), None)?;
        let stats = diff.stats()?;
        Ok(ChangeStats {
            commits,
            files: stats.files_changed(),
            insertions: stats.insertions(),
            deletions: stats.deletions(),
        })
    }

    /// Commit the current index with the given message, using `name`/`email`
    /// as both author and committer. Returns the new commit's id.
    pub fn commit(&self, message: &str, name: &str, email: &str) -> Result<String> {
        let mut index = self.repo.index()?;
        let tree_id = index.write_tree()?;
        let tree = self.repo.find_tree(tree_id)?;
        let signature = git2::Signature::now(name, email)?;

        let parent = self.repo.head().ok().and_then(|h| h.peel_to_commit().ok());
        let parents: Vec<&git2::Commit> = parent.iter().collect();

        let oid = self.repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        )?;

        Ok(oid.to_string())
    }

    /// Commit the current index with the given message, using the
    /// repository's configured `user.name`/`user.email` (from local or
    /// global git config) as both author and committer. Returns the new
    /// commit's id.
    pub fn commit_with_configured_identity(&self, message: &str) -> Result<String> {
        let mut index = self.repo.index()?;
        let tree_id = index.write_tree()?;
        let tree = self.repo.find_tree(tree_id)?;
        let signature = self
            .repo
            .signature()
            .context("no user.name/user.email configured for this repository")?;

        let parent = self.repo.head().ok().and_then(|h| h.peel_to_commit().ok());
        let parents: Vec<&git2::Commit> = parent.iter().collect();

        let oid = self.repo.commit(
            Some("HEAD"),
            &signature,
            &signature,
            message,
            &tree,
            &parents,
        )?;

        Ok(oid.to_string())
    }

    /// Commits reachable from HEAD whose author date is in
    /// `[since, until]` (Unix seconds), with per-file line counts; plus the
    /// number of commits in `[previous_since, since)` and every author's
    /// span over all of history. An unborn HEAD gives an empty report.
    pub fn commit_stats(
        &self,
        since: i64,
        until: i64,
        previous_since: i64,
    ) -> Result<CommitStatsReport> {
        use std::collections::HashMap;

        let mut report = CommitStatsReport {
            commits: Vec::new(),
            previous_count: 0,
            authors: Vec::new(),
        };
        if self.repo.head().is_err() {
            return Ok(report);
        }

        let mut revwalk = self.repo.revwalk()?;
        revwalk.push_head()?;
        revwalk.set_sorting(git2::Sort::TIME)?;

        let mailmap = self.repo.mailmap().ok();
        let mut authors: HashMap<String, AuthorSpan> = HashMap::new();
        for oid in revwalk {
            let oid = oid?;
            let commit = self.repo.find_commit(oid)?;
            let author = Self::mapped_author(&commit, mailmap.as_ref())?;
            let seconds = author.when().seconds();
            let time = DateTime::<Utc>::from_timestamp(seconds, 0).unwrap_or_else(Utc::now);
            let name = author.name().unwrap_or("").to_string();
            let email = author.email().unwrap_or("").to_string();

            let span = authors
                .entry(email.to_lowercase())
                .or_insert_with(|| AuthorSpan {
                    name: name.clone(),
                    email: email.clone(),
                    first: time,
                    last: time,
                    commits: 0,
                });
            span.commits += 1;
            if time < span.first {
                span.first = time;
            }
            if time > span.last {
                span.last = time;
                span.name = name.clone();
            }

            if seconds >= since && seconds <= until {
                let offset = author.when().offset_minutes();
                report
                    .commits
                    .push(self.commit_stat(&commit, name, email, time, offset)?);
            } else if seconds >= previous_since && seconds < since {
                report.previous_count += 1;
            }
        }

        report.authors = authors.into_values().collect();
        report.authors.sort_by(|a, b| b.commits.cmp(&a.commits));
        Ok(report)
    }

    fn commit_stat(
        &self,
        commit: &git2::Commit,
        author: String,
        email: String,
        time: DateTime<Utc>,
        offset_minutes: i32,
    ) -> Result<CommitStat> {
        let is_merge = commit.parent_count() > 1;
        let mut files = Vec::new();
        if !is_merge {
            let tree = commit.tree()?;
            let parent_tree = commit.parents().next().map(|p| p.tree()).transpose()?;
            let diff = self
                .repo
                .diff_tree_to_tree(parent_tree.as_ref(), Some(&tree), None)?;
            for (index, delta) in diff.deltas().enumerate() {
                let path = delta
                    .new_file()
                    .path()
                    .or_else(|| delta.old_file().path())
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or_default();
                // Binary files have no patch, so no line counts.
                let (additions, deletions) = match git2::Patch::from_diff(&diff, index)? {
                    Some(patch) => {
                        let (_, additions, deletions) = patch.line_stats()?;
                        (additions, deletions)
                    }
                    None => (0, 0),
                };
                files.push(FileChangeStat {
                    path,
                    additions,
                    deletions,
                });
            }
        }
        Ok(CommitStat {
            id: commit.id().to_string(),
            summary: commit.summary().unwrap_or("").to_string(),
            author,
            email,
            time,
            offset_minutes,
            is_merge,
            additions: files.iter().map(|f| f.additions).sum(),
            deletions: files.iter().map(|f| f.deletions).sum(),
            files,
        })
    }

    /// Who last changed each line of `rel_path` (relative to the repo root,
    /// `/`-separated). With `contents`, blames that text instead of the
    /// committed file, so uncommitted edits show as uncommitted lines and
    /// the line numbers match what the editor shows.
    pub fn blame(&self, rel_path: &str, contents: Option<&str>) -> Result<Vec<BlameHunk>> {
        let line_count = |text: &str| text.lines().count().max(1);
        let uncommitted = |lines: usize| BlameHunk {
            start_line: 1,
            lines,
            commit_id: None,
            author: String::new(),
            email: String::new(),
            time: None,
            summary: String::new(),
        };

        // A new file (or an empty repository) has no history to blame.
        let tracked = self
            .repo
            .head()
            .ok()
            .and_then(|head| head.peel_to_tree().ok())
            .is_some_and(|tree| tree.get_path(Path::new(rel_path)).is_ok());
        if !tracked {
            let lines = match contents {
                Some(text) => line_count(text),
                None => {
                    let workdir = self.repo.workdir().context("bare repository")?;
                    line_count(&std::fs::read_to_string(workdir.join(rel_path))?)
                }
            };
            return Ok(vec![uncommitted(lines)]);
        }

        let mut options = git2::BlameOptions::new();
        options.use_mailmap(true);
        let blame = self
            .repo
            .blame_file(Path::new(rel_path), Some(&mut options))
            .with_context(|| format!("failed to blame {rel_path}"))?;
        let blame = match contents {
            Some(text) => blame.blame_buffer(text.as_bytes())?,
            None => blame,
        };

        // Author and summary come from the commit itself, not the hunk: after
        // `blame_buffer`, split hunks can carry no signature at all (git2
        // then dereferences a null pointer).
        let mailmap = self.repo.mailmap().ok();
        type CommitInfoParts = (String, String, Option<DateTime<Utc>>, String);
        let mut commits = std::collections::HashMap::<git2::Oid, CommitInfoParts>::new();
        let mut hunks = Vec::with_capacity(blame.len());
        for hunk in blame.iter() {
            let id = hunk.final_commit_id();
            let start_line = hunk.final_start_line();
            let lines = hunk.lines_in_hunk();
            if id.is_zero() {
                hunks.push(BlameHunk {
                    start_line,
                    lines,
                    ..uncommitted(lines)
                });
                continue;
            }
            let (author, email, time, summary) = commits
                .entry(id)
                .or_insert_with(|| {
                    let Ok(commit) = self.repo.find_commit(id) else {
                        return Default::default();
                    };
                    let summary = commit.summary().unwrap_or_default().to_string();
                    match Self::mapped_author(&commit, mailmap.as_ref()) {
                        Ok(sig) => (
                            sig.name().unwrap_or_default().to_string(),
                            sig.email().unwrap_or_default().to_string(),
                            DateTime::<Utc>::from_timestamp(sig.when().seconds(), 0),
                            summary,
                        ),
                        Err(_) => (String::new(), String::new(), None, summary),
                    }
                })
                .clone();
            hunks.push(BlameHunk {
                start_line,
                lines,
                commit_id: Some(id.to_string()),
                author,
                email,
                time,
                summary,
            });
        }
        Ok(hunks)
    }

    /// A commit's author with the repository's `.mailmap` applied (so one
    /// person's old names and emails count as one author).
    fn mapped_author(
        commit: &git2::Commit,
        mailmap: Option<&git2::Mailmap>,
    ) -> Result<git2::Signature<'static>> {
        Ok(match mailmap {
            Some(mailmap) => commit.author_with_mailmap(mailmap)?,
            None => commit.author().to_owned(),
        })
    }

    /// Every local branch's last commit and how it compares with the base
    /// branch (`main`, else `master`, else the current branch).
    pub fn branch_report(&self) -> Result<BranchReport> {
        let head_name = self
            .repo
            .head()
            .ok()
            .filter(|h| h.is_branch())
            .and_then(|h| h.shorthand().map(str::to_string));

        let base = ["main", "master"]
            .into_iter()
            .map(str::to_string)
            .find(|name| self.repo.find_branch(name, git2::BranchType::Local).is_ok())
            .or_else(|| head_name.clone());
        let base_tip = match &base {
            Some(name) => self
                .repo
                .find_branch(name, git2::BranchType::Local)?
                .get()
                .target(),
            None => None,
        };

        let mailmap = self.repo.mailmap().ok();
        let mut branches = Vec::new();
        for entry in self.repo.branches(Some(git2::BranchType::Local))? {
            let (branch, _) = entry?;
            let Some(name) = branch.name()?.map(str::to_string) else {
                continue;
            };
            let Some(tip) = branch.get().target() else {
                continue;
            };
            let commit = self.repo.find_commit(tip)?;
            let author = Self::mapped_author(&commit, mailmap.as_ref())?;

            let is_base = base.as_deref() == Some(name.as_str());
            let (ahead, behind, merged) = match base_tip {
                Some(base_tip) if !is_base => {
                    let (ahead, behind) = self.repo.graph_ahead_behind(tip, base_tip)?;
                    (ahead, behind, ahead == 0)
                }
                _ => (0, 0, false),
            };

            branches.push(BranchStat {
                is_head: head_name.as_deref() == Some(name.as_str()),
                name,
                last_commit_time: DateTime::<Utc>::from_timestamp(author.when().seconds(), 0)
                    .unwrap_or_else(Utc::now),
                last_author: author.name().unwrap_or("").to_string(),
                last_email: author.email().unwrap_or("").to_string(),
                ahead,
                behind,
                merged,
            });
        }
        branches.sort_by(|a, b| b.last_commit_time.cmp(&a.last_commit_time));

        Ok(BranchReport { base, branches })
    }

    /// Lists this repository's configured remotes (name and fetch URL).
    pub fn remotes(&self) -> Result<Vec<RemoteInfo>> {
        let names = self.repo.remotes()?;
        let mut remotes = Vec::new();
        for name in names.iter().flatten() {
            let remote = self.repo.find_remote(name)?;
            remotes.push(RemoteInfo {
                name: name.to_string(),
                url: remote.url().unwrap_or_default().to_string(),
            });
        }
        Ok(remotes)
    }

    /// Adds a new remote `name` pointing at `url`.
    pub fn add_remote(&self, name: &str, url: &str) -> Result<()> {
        self.repo.remote(name, url)?;
        Ok(())
    }

    /// Changes the fetch (and push) URL of existing remote `name`.
    pub fn set_remote_url(&self, name: &str, url: &str) -> Result<()> {
        self.repo.remote_set_url(name, url)?;
        self.repo.remote_set_pushurl(name, Some(url))?;
        Ok(())
    }

    /// Removes remote `name`.
    pub fn remove_remote(&self, name: &str) -> Result<()> {
        self.repo.remote_delete(name)?;
        Ok(())
    }
}

/// Reads the `user.name`/`user.email` identity from git's global config
/// (`~/.gitconfig` or equivalent), not tied to any specific repository.
pub fn global_identity() -> Result<GlobalIdentity> {
    let config = git2::Config::open_default()?;
    Ok(GlobalIdentity {
        name: config.get_string("user.name").ok(),
        email: config.get_string("user.email").ok(),
    })
}

/// Writes `name`/`email` into git's global config. Either may be empty to
/// leave that field unset (removed from the global config if present).
pub fn set_global_identity(name: &str, email: &str) -> Result<()> {
    let mut config = git2::Config::open_default()?;
    if name.is_empty() {
        let _ = config.remove("user.name");
    } else {
        config.set_str("user.name", name)?;
    }
    if email.is_empty() {
        let _ = config.remove("user.email");
    } else {
        config.set_str("user.email", email)?;
    }
    Ok(())
}

/// Runs the repository's configured `credential.helper` to obtain a
/// username/password for an HTTPS remote, the same protocol `git` itself
/// uses to talk to a helper (`<cmd> get`, `key=value` lines on stdin,
/// `username=`/`password=` lines read back from stdout).
///
/// Unlike `git2::Cred::credential_helper`, the helper process is spawned
/// with `CREATE_NO_WINDOW` so it doesn't flash a console window in this
/// GUI app, which has no console of its own.
#[cfg(windows)]
fn windows_credential_helper(
    repo: &git2::Repository,
    url: &str,
    username_from_url: Option<&str>,
) -> Option<(String, String)> {
    use std::io::Write;
    use std::os::windows::process::CommandExt;
    use std::process::{Command, Stdio};

    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    let config = repo.config().ok()?;
    let helper = config.get_string("credential.helper").ok()?;
    if helper.trim().is_empty() {
        return None;
    }

    let command_line = if let Some(script) = helper.strip_prefix('!') {
        script.to_string()
    } else if helper.contains('/') || helper.contains('\\') {
        helper
    } else {
        format!("git credential-{helper}")
    };

    let mut parts = command_line.split_whitespace();
    let program = parts.next()?;
    let mut child = Command::new(program)
        .args(parts)
        .arg("get")
        .creation_flags(CREATE_NO_WINDOW)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .ok()?;

    {
        let stdin = child.stdin.as_mut()?;
        if let Some(rest) = url.split("://").nth(1) {
            let protocol = url.split("://").next().unwrap_or("https");
            let host = rest.split('/').next().unwrap_or_default();
            writeln!(stdin, "protocol={protocol}").ok()?;
            writeln!(stdin, "host={host}").ok()?;
        }
        if let Some(username) = username_from_url {
            writeln!(stdin, "username={username}").ok()?;
        }
        writeln!(stdin).ok()?;
    }

    let output = child.wait_with_output().ok()?;
    if !output.status.success() {
        return None;
    }

    let mut username = username_from_url.map(str::to_string);
    let mut password = None;
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        if let Some(value) = line.strip_prefix("username=") {
            username = Some(value.to_string());
        } else if let Some(value) = line.strip_prefix("password=") {
            password = Some(value.to_string());
        }
    }

    match (username, password) {
        (Some(u), Some(p)) => Some((u, p)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn write_file(dir: &Path, name: &str, contents: &str) {
        fs::write(dir.join(name), contents).unwrap();
    }

    #[test]
    fn blame_reports_commits_and_uncommitted_lines() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        write_file(dir.path(), "a.txt", "one\ntwo\n");
        repo.stage("a.txt").unwrap();
        let first = repo.commit("first", "Alice", "alice@example.com").unwrap();
        write_file(dir.path(), "a.txt", "one\ntwo\nthree\n");
        repo.stage("a.txt").unwrap();
        let second = repo.commit("add three", "Bob", "bob@example.com").unwrap();

        let hunks = repo.blame("a.txt", None).unwrap();
        assert_eq!(hunks.len(), 2);
        assert_eq!(hunks[0].start_line, 1);
        assert_eq!(hunks[0].lines, 2);
        assert_eq!(hunks[0].commit_id.as_deref(), Some(first.as_str()));
        assert_eq!(hunks[0].author, "Alice");
        assert_eq!(hunks[0].summary, "first");
        assert_eq!(hunks[1].start_line, 3);
        assert_eq!(hunks[1].commit_id.as_deref(), Some(second.as_str()));

        // Unsaved/uncommitted edits: a new first line shifts the rest down.
        let hunks = repo
            .blame("a.txt", Some("zero\none\ntwo\nthree\n"))
            .unwrap();
        assert_eq!(hunks[0].start_line, 1);
        assert_eq!(hunks[0].commit_id, None);
        let line3 = hunks
            .iter()
            .find(|h| h.start_line <= 3 && 3 < h.start_line + h.lines)
            .unwrap();
        assert_eq!(line3.author, "Alice");

        // A line inserted in the middle splits a committed hunk; the split
        // parts must still report their commit (this used to crash).
        let hunks = repo
            .blame("a.txt", Some("one\ninserted\ntwo\nthree\n"))
            .unwrap();
        let authors: Vec<_> = hunks.iter().map(|h| h.author.as_str()).collect();
        assert_eq!(authors, vec!["Alice", "", "Alice", "Bob"]);

        // Untracked file: all uncommitted.
        write_file(dir.path(), "new.txt", "x\ny\n");
        let hunks = repo.blame("new.txt", None).unwrap();
        assert_eq!(hunks.len(), 1);
        assert_eq!(hunks[0].lines, 2);
        assert_eq!(hunks[0].commit_id, None);
    }

    #[test]
    fn init_stage_and_commit() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "hello.txt", "hello world");

        let status = repo.status().unwrap();
        assert_eq!(status.len(), 1);
        assert_eq!(status[0].path, "hello.txt");
        assert_eq!(status[0].unstaged, Some(FileStatus::New));

        repo.stage("hello.txt").unwrap();
        let status = repo.status().unwrap();
        assert_eq!(status[0].staged, Some(FileStatus::New));

        let commit_id = repo
            .commit("initial commit", "Test User", "test@example.com")
            .unwrap();
        assert!(!commit_id.is_empty());

        let log = repo.log(10).unwrap();
        assert_eq!(log.len(), 1);
        assert_eq!(log[0].summary, "initial commit");

        assert!(repo.status().unwrap().is_empty());
    }

    #[test]
    fn unstage_reverts_index_only() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("add a.txt", "Test User", "test@example.com")
            .unwrap();

        write_file(dir.path(), "a.txt", "two");
        repo.stage("a.txt").unwrap();
        repo.unstage("a.txt").unwrap();

        let status = repo.status().unwrap();
        assert_eq!(status[0].staged, None);
        assert_eq!(status[0].unstaged, Some(FileStatus::Modified));
    }

    #[test]
    fn change_stats_counts_commits_files_and_lines() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one\ntwo\n");
        repo.stage("a.txt").unwrap();
        let first = repo
            .commit("init", "Test User", "test@example.com")
            .unwrap();

        let stats = repo.change_stats(None, &first).unwrap();
        assert_eq!(
            stats,
            ChangeStats {
                commits: 1,
                files: 1,
                insertions: 2,
                deletions: 0
            }
        );

        write_file(dir.path(), "a.txt", "one\nthree\n");
        write_file(dir.path(), "b.txt", "new\n");
        repo.stage("a.txt").unwrap();
        repo.stage("b.txt").unwrap();
        repo.commit("second", "Test User", "test@example.com")
            .unwrap();
        write_file(dir.path(), "c.txt", "c\n");
        repo.stage("c.txt").unwrap();
        let third = repo
            .commit("third", "Test User", "test@example.com")
            .unwrap();

        let stats = repo.change_stats(Some(&first), "HEAD").unwrap();
        assert_eq!(
            stats,
            ChangeStats {
                commits: 2,
                files: 3,
                insertions: 3,
                deletions: 1
            }
        );
        assert_eq!(repo.resolve_commit("HEAD"), Some(third.clone()));
        assert_eq!(
            repo.change_stats(Some(&third), &third).unwrap(),
            ChangeStats::default()
        );
    }

    #[test]
    fn resolve_commit_on_unborn_head_is_none() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        assert_eq!(repo.resolve_commit("HEAD"), None);
    }

    #[test]
    fn commit_diff_reports_added_lines() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one\ntwo\n");
        repo.stage("a.txt").unwrap();
        let first = repo
            .commit("init", "Test User", "test@example.com")
            .unwrap();

        let diff = repo.commit_diff(&first).unwrap();
        assert_eq!(diff.len(), 1);
        assert_eq!(diff[0].path, "a.txt");
        assert_eq!(diff[0].status, FileStatus::New);
        assert_eq!(diff[0].additions, 2);
        assert_eq!(diff[0].deletions, 0);

        write_file(dir.path(), "a.txt", "one\ntwo\nthree\n");
        repo.stage("a.txt").unwrap();
        let second = repo
            .commit("add line", "Test User", "test@example.com")
            .unwrap();

        let diff = repo.commit_diff(&second).unwrap();
        assert_eq!(diff.len(), 1);
        assert_eq!(diff[0].status, FileStatus::Modified);
        assert_eq!(diff[0].additions, 1);
        assert_eq!(diff[0].deletions, 0);
    }

    #[test]
    fn log_includes_parent_ids() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        let first = repo
            .commit("init", "Test User", "test@example.com")
            .unwrap();

        write_file(dir.path(), "a.txt", "two");
        repo.stage("a.txt").unwrap();
        repo.commit("second", "Test User", "test@example.com")
            .unwrap();

        let log = repo.log(10).unwrap();
        assert_eq!(log.len(), 2);
        assert!(log[0].parent_ids.contains(&first));
        assert!(log[1].parent_ids.is_empty());
    }

    #[test]
    fn branches_lists_head() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Test User", "test@example.com")
            .unwrap();

        let branches = repo.branches().unwrap();
        assert_eq!(branches.len(), 1);
        assert!(branches[0].is_head);
        assert!(!branches[0].is_remote);
    }

    #[test]
    fn create_and_checkout_local_branch() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Test User", "test@example.com")
            .unwrap();

        repo.create_branch("feature", None).unwrap();
        repo.checkout_branch("feature").unwrap();

        let branches = repo.branches().unwrap();
        let feature = branches.iter().find(|b| b.name == "feature").unwrap();
        assert!(feature.is_head);
    }

    #[test]
    fn delete_local_branch() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Test User", "test@example.com")
            .unwrap();

        repo.create_branch("feature", None).unwrap();
        repo.delete_branch("feature", false).unwrap();

        let branches = repo.branches().unwrap();
        assert!(!branches.iter().any(|b| b.name == "feature"));
    }

    #[test]
    fn create_local_branch_from_remote_tracks_it() {
        let remote_dir = tempfile::tempdir().unwrap();
        let remote_repo = GitRepo::init(remote_dir.path()).unwrap();
        write_file(remote_dir.path(), "a.txt", "one");
        remote_repo.stage("a.txt").unwrap();
        remote_repo
            .commit("init", "Test User", "test@example.com")
            .unwrap();

        let local_dir = tempfile::tempdir().unwrap();
        let local_repo =
            GitRepo::clone(remote_dir.path().to_str().unwrap(), local_dir.path()).unwrap();

        local_repo
            .create_branch("feature", Some("origin/master"))
            .unwrap();

        let branches = local_repo.branches().unwrap();
        assert!(branches.iter().any(|b| b.name == "feature" && !b.is_remote));
    }

    #[test]
    fn commit_stats_counts_lines_and_periods() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one\ntwo\n");
        repo.stage("a.txt").unwrap();
        repo.commit("first", "Ann", "ann@example.com").unwrap();

        write_file(dir.path(), "a.txt", "one\nthree\nfour\n");
        write_file(dir.path(), "b.txt", "b\n");
        repo.stage("a.txt").unwrap();
        repo.stage("b.txt").unwrap();
        repo.commit("second", "Bob", "BOB@example.com").unwrap();

        let all = repo.commit_stats(0, i64::MAX, 0).unwrap();
        assert_eq!(all.commits.len(), 2);
        assert_eq!(all.previous_count, 0);
        let second = all.commits.iter().find(|c| c.summary == "second").unwrap();
        assert!(!second.is_merge);
        assert_eq!(second.additions, 3);
        assert_eq!(second.deletions, 1);
        assert_eq!(second.files.len(), 2);
        let first = all.commits.iter().find(|c| c.summary == "first").unwrap();
        assert_eq!(first.additions, 2);
        assert_eq!(all.authors.len(), 2);

        // A period that ends before the commits counts them as "previous".
        let future = Utc::now().timestamp() + 1000;
        let later = repo.commit_stats(future, future + 10, 0).unwrap();
        assert!(later.commits.is_empty());
        assert_eq!(later.previous_count, 2);
    }

    #[test]
    fn commit_stats_applies_mailmap() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("old identity", "annie", "ann@old.example")
            .unwrap();
        write_file(dir.path(), "a.txt", "two");
        repo.stage("a.txt").unwrap();
        repo.commit("new identity", "Ann Lee", "ann@new.example")
            .unwrap();

        write_file(
            dir.path(),
            ".mailmap",
            "Ann Lee <ann@new.example> annie <ann@old.example>\n",
        );

        let report = repo.commit_stats(0, i64::MAX, 0).unwrap();
        assert_eq!(report.authors.len(), 1);
        assert_eq!(report.authors[0].email, "ann@new.example");
        assert_eq!(report.authors[0].commits, 2);
        assert!(report
            .commits
            .iter()
            .all(|c| c.email == "ann@new.example" && c.author == "Ann Lee"));
    }

    #[test]
    fn commit_stats_keeps_author_utc_offset() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();

        // 2026-01-01 09:00 in Tehran (+03:30).
        let when = git2::Time::new(1_767_245_400, 210);
        let sig = git2::Signature::new("Sara", "sara@example.com", &when).unwrap();
        let tree_id = repo.repo.index().unwrap().write_tree().unwrap();
        let tree = repo.repo.find_tree(tree_id).unwrap();
        repo.repo
            .commit(Some("HEAD"), &sig, &sig, "init", &tree, &[])
            .unwrap();

        let report = repo.commit_stats(0, i64::MAX, 0).unwrap();
        assert_eq!(report.commits[0].offset_minutes, 210);
    }

    #[test]
    fn commit_stats_on_empty_repo_is_empty() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        let report = repo.commit_stats(0, i64::MAX, 0).unwrap();
        assert!(report.commits.is_empty());
        assert!(report.authors.is_empty());
    }

    #[test]
    fn branch_report_compares_with_base() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Ann", "ann@example.com").unwrap();
        let base = repo.repo.head().unwrap().shorthand().unwrap().to_string();

        repo.create_branch("merged", None).unwrap();
        repo.create_branch("feature", None).unwrap();
        repo.checkout_branch("feature").unwrap();
        write_file(dir.path(), "b.txt", "b");
        repo.stage("b.txt").unwrap();
        repo.commit("feature work", "Bob", "bob@example.com")
            .unwrap();

        let report = repo.branch_report().unwrap();
        assert_eq!(report.base.as_deref(), Some(base.as_str()));
        let feature = report
            .branches
            .iter()
            .find(|b| b.name == "feature")
            .unwrap();
        assert_eq!(
            (feature.ahead, feature.behind, feature.merged),
            (1, 0, false)
        );
        assert!(feature.is_head);
        assert_eq!(feature.last_email, "bob@example.com");
        let merged = report.branches.iter().find(|b| b.name == "merged").unwrap();
        assert!(merged.merged);
        let base_stat = report.branches.iter().find(|b| b.name == base).unwrap();
        assert!(!base_stat.merged);
    }

    #[test]
    fn branches_count_ahead_behind_against_base() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Ann", "ann@example.com").unwrap();
        let base = repo.repo.head().unwrap().shorthand().unwrap().to_string();

        repo.create_branch("develop", None).unwrap();
        repo.create_branch("feature", None).unwrap();
        repo.checkout_branch("feature").unwrap();
        for f in ["b.txt", "c.txt"] {
            write_file(dir.path(), f, f);
            repo.stage(f).unwrap();
            repo.commit(f, "Bob", "bob@example.com").unwrap();
        }
        repo.checkout_branch(&base).unwrap();
        write_file(dir.path(), "m.txt", "m");
        repo.stage("m.txt").unwrap();
        repo.commit("main work", "Ann", "ann@example.com").unwrap();

        let find = |list: &[BranchInfo], name: &str| {
            list.iter().find(|b| b.name == name).cloned().unwrap()
        };
        let list = repo.branches().unwrap();
        let feature = find(&list, "feature");
        assert_eq!(feature.base.as_deref(), Some(base.as_str()));
        assert_eq!((feature.base_ahead, feature.base_behind), (2, 1));
        let main = find(&list, &base);
        assert_eq!(main.base, None);

        // Against "develop" instead: it has none of main's or feature's work.
        let list = repo.branches_compared_with(Some("develop")).unwrap();
        let feature = find(&list, "feature");
        assert_eq!(feature.base.as_deref(), Some("develop"));
        assert_eq!((feature.base_ahead, feature.base_behind), (2, 0));
        assert_eq!(find(&list, "develop").base, None);
        assert_eq!(find(&list, &base).base_ahead, 1);

        // An unknown base falls back to the default branch.
        let list = repo.branches_compared_with(Some("nope")).unwrap();
        assert_eq!(find(&list, "feature").base.as_deref(), Some(base.as_str()));
    }

    #[test]
    fn branches_marks_merged_into_local_default() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Ann", "ann@example.com").unwrap();
        let base = repo.repo.head().unwrap().shorthand().unwrap().to_string();
        assert!(base == "main" || base == "master");

        // "fresh" has no commits of its own yet: not marked as merged.
        repo.create_branch("fresh", None).unwrap();

        // "done" gets a commit that the base then takes in, and the base
        // moves on.
        repo.create_branch("done", None).unwrap();
        repo.checkout_branch("done").unwrap();
        write_file(dir.path(), "d.txt", "d");
        repo.stage("d.txt").unwrap();
        repo.commit("done work", "Bob", "bob@example.com").unwrap();
        let done_tip = repo.repo.head().unwrap().target().unwrap();
        repo.checkout_branch(&base).unwrap();
        repo.repo
            .find_reference(&format!("refs/heads/{base}"))
            .unwrap()
            .set_target(done_tip, "test")
            .unwrap();
        repo.repo
            .checkout_head(Some(git2::build::CheckoutBuilder::new().force()))
            .unwrap();
        write_file(dir.path(), "c.txt", "c");
        repo.stage("c.txt").unwrap();
        repo.commit("more base work", "Ann", "ann@example.com")
            .unwrap();

        repo.create_branch("feature", None).unwrap();
        repo.checkout_branch("feature").unwrap();
        write_file(dir.path(), "b.txt", "b");
        repo.stage("b.txt").unwrap();
        repo.commit("feature work", "Bob", "bob@example.com")
            .unwrap();

        let branches = repo.branches().unwrap();
        let merged_into = |name: &str| {
            branches
                .iter()
                .find(|b| b.name == name)
                .unwrap()
                .merged_into
                .clone()
        };
        assert_eq!(merged_into("done"), Some(base.clone()));
        assert_eq!(merged_into("fresh"), None);
        assert_eq!(merged_into("feature"), None);
        assert_eq!(merged_into(&base), None);
    }

    #[test]
    fn branches_prefers_remote_default_branch() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Ann", "ann@example.com").unwrap();
        let base = repo.repo.head().unwrap().shorthand().unwrap().to_string();

        // A branch with work that only the remote's default branch has
        // merged (local `main`/`master` is behind).
        repo.create_branch("shipped", None).unwrap();
        repo.checkout_branch("shipped").unwrap();
        write_file(dir.path(), "b.txt", "b");
        repo.stage("b.txt").unwrap();
        repo.commit("shipped work", "Bob", "bob@example.com")
            .unwrap();
        // The remote's default branch has the shipped work plus more.
        repo.create_branch("tmp", None).unwrap();
        repo.checkout_branch("tmp").unwrap();
        write_file(dir.path(), "c.txt", "c");
        repo.stage("c.txt").unwrap();
        repo.commit("more work", "Ann", "ann@example.com").unwrap();
        let develop_tip = repo.repo.head().unwrap().target().unwrap();
        repo.checkout_branch("shipped").unwrap();
        repo.delete_branch("tmp", false).unwrap();
        repo.repo
            .reference("refs/remotes/origin/develop", develop_tip, true, "test")
            .unwrap();
        repo.repo
            .reference_symbolic(
                "refs/remotes/origin/HEAD",
                "refs/remotes/origin/develop",
                true,
                "test",
            )
            .unwrap();
        repo.checkout_branch(&base).unwrap();

        let branches = repo.branches().unwrap();
        let find = |name: &str| branches.iter().find(|b| b.name == name).unwrap();
        assert_eq!(
            find("shipped").merged_into.as_deref(),
            Some("origin/develop")
        );
        assert_eq!(find(&base).merged_into.as_deref(), Some("origin/develop"));
        assert_eq!(find("origin/develop").merged_into, None);
        assert!(branches
            .iter()
            .filter(|b| b.name.ends_with("/HEAD"))
            .all(|b| b.merged_into.is_none()));
    }

    #[test]
    fn revert_file_discards_working_tree_changes() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Test User", "test@example.com")
            .unwrap();

        write_file(dir.path(), "a.txt", "two");
        assert_eq!(
            repo.status().unwrap()[0].unstaged,
            Some(FileStatus::Modified)
        );

        repo.revert_file("a.txt").unwrap();

        assert!(repo.status().unwrap().is_empty());
        assert_eq!(fs::read_to_string(dir.path().join("a.txt")).unwrap(), "one");
    }

    #[test]
    fn working_file_diff_reports_staged_and_unstaged_changes() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one\n");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Test User", "test@example.com")
            .unwrap();

        write_file(dir.path(), "a.txt", "two\n");
        repo.stage("a.txt").unwrap();
        write_file(dir.path(), "a.txt", "three\n");
        write_file(dir.path(), "new.txt", "fresh\n");

        let staged = repo.working_file_diff("a.txt", true).unwrap();
        assert!(staged.contains("@@ -1 +1 @@"), "{staged}");
        assert!(staged.contains("-one\n") && staged.contains("+two\n"));

        let unstaged = repo.working_file_diff("a.txt", false).unwrap();
        assert!(unstaged.contains("-two\n") && unstaged.contains("+three\n"));

        let untracked = repo.working_file_diff("new.txt", false).unwrap();
        assert!(untracked.contains("+fresh\n"), "{untracked}");
        assert!(!untracked.contains("a.txt"));
    }

    #[test]
    fn working_file_diff_handles_unborn_head() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one\n");
        repo.stage("a.txt").unwrap();

        let staged = repo.working_file_diff("a.txt", true).unwrap();
        assert!(staged.contains("+one\n"), "{staged}");
    }

    #[test]
    fn commit_with_configured_identity_uses_repo_config() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        {
            let mut config = repo.repo.config().unwrap();
            config.set_str("user.name", "Configured User").unwrap();
            config
                .set_str("user.email", "configured@example.com")
                .unwrap();
        }

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        let commit_id = repo.commit_with_configured_identity("init").unwrap();
        assert!(!commit_id.is_empty());

        let log = repo.log(10).unwrap();
        assert_eq!(log[0].author, "Configured User");
        assert_eq!(log[0].email, "configured@example.com");
    }

    #[test]
    fn update_branch_fast_forwards_to_upstream() {
        let remote_dir = tempfile::tempdir().unwrap();
        let remote_repo = GitRepo::init(remote_dir.path()).unwrap();
        write_file(remote_dir.path(), "a.txt", "one");
        remote_repo.stage("a.txt").unwrap();
        remote_repo
            .commit("init", "Test User", "test@example.com")
            .unwrap();

        let local_dir = tempfile::tempdir().unwrap();
        let local_repo =
            GitRepo::clone(remote_dir.path().to_str().unwrap(), local_dir.path()).unwrap();
        let local_branch = local_repo.branches().unwrap()[0].name.clone();

        write_file(remote_dir.path(), "a.txt", "two");
        remote_repo.stage("a.txt").unwrap();
        remote_repo
            .commit("second", "Test User", "test@example.com")
            .unwrap();

        local_repo.update_branch(&local_branch).unwrap();

        let log = local_repo.log(10).unwrap();
        assert_eq!(log.len(), 2);
        assert_eq!(log[0].summary, "second");
    }

    #[test]
    fn fetch_prunes_branches_deleted_on_the_remote() {
        let remote_dir = tempfile::tempdir().unwrap();
        let remote_repo = GitRepo::init(remote_dir.path()).unwrap();
        write_file(remote_dir.path(), "a.txt", "one");
        remote_repo.stage("a.txt").unwrap();
        remote_repo
            .commit("init", "Test User", "test@example.com")
            .unwrap();
        let head = remote_repo.repo.head().unwrap().peel_to_commit().unwrap();
        remote_repo.repo.branch("feature", &head, false).unwrap();

        let local_dir = tempfile::tempdir().unwrap();
        let local_repo =
            GitRepo::clone(remote_dir.path().to_str().unwrap(), local_dir.path()).unwrap();
        let remote_names = |repo: &GitRepo| -> Vec<String> {
            repo.branches()
                .unwrap()
                .into_iter()
                .filter(|b| b.is_remote)
                .map(|b| b.name)
                .collect()
        };
        assert!(remote_names(&local_repo).contains(&"origin/feature".to_string()));
        let main = local_repo
            .branches()
            .unwrap()
            .into_iter()
            .find(|b| !b.is_remote)
            .unwrap();
        assert!(main.last_commit_time.is_some());
        assert_eq!(
            main.remote_counterpart.as_deref(),
            Some(format!("origin/{}", main.name).as_str())
        );
        assert_eq!((main.ahead, main.behind), (0, 0));
        write_file(local_dir.path(), "b.txt", "local");
        local_repo.stage("b.txt").unwrap();
        local_repo
            .commit("local", "Test User", "t@example.com")
            .unwrap();
        let main = local_repo
            .branches()
            .unwrap()
            .into_iter()
            .find(|b| !b.is_remote)
            .unwrap();
        assert_eq!((main.ahead, main.behind), (1, 0));

        remote_repo
            .repo
            .find_branch("feature", git2::BranchType::Local)
            .unwrap()
            .delete()
            .unwrap();
        local_repo.fetch_remote_for_branch("origin/HEAD").unwrap();
        assert!(!remote_names(&local_repo).contains(&"origin/feature".to_string()));
    }

    #[test]
    fn add_list_set_and_remove_remote() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        assert!(repo.remotes().unwrap().is_empty());

        repo.add_remote("origin", "https://example.com/repo.git")
            .unwrap();
        let remotes = repo.remotes().unwrap();
        assert_eq!(remotes.len(), 1);
        assert_eq!(remotes[0].name, "origin");
        assert_eq!(remotes[0].url, "https://example.com/repo.git");

        repo.set_remote_url("origin", "https://example.com/other.git")
            .unwrap();
        let remotes = repo.remotes().unwrap();
        assert_eq!(remotes[0].url, "https://example.com/other.git");

        repo.remove_remote("origin").unwrap();
        assert!(repo.remotes().unwrap().is_empty());
    }
}
