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

#[derive(Debug, Clone, Serialize)]
pub struct BranchInfo {
    pub name: String,
    pub is_head: bool,
    pub is_remote: bool,
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
                    entry.patch.push_str(&String::from_utf8_lossy(line.content()));
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

    /// Local and remote-tracking branches.
    pub fn branches(&self) -> Result<Vec<BranchInfo>> {
        let head_name = self
            .repo
            .head()
            .ok()
            .and_then(|h| h.shorthand().map(str::to_string));

        let mut result = Vec::new();
        for entry in self.repo.branches(None)? {
            let (branch, branch_type) = entry?;
            let name = match branch.name()? {
                Some(name) => name.to_string(),
                None => continue,
            };
            let is_remote = branch_type == git2::BranchType::Remote;
            let is_head = !is_remote && head_name.as_deref() == Some(name.as_str());

            result.push(BranchInfo {
                name,
                is_head,
                is_remote,
            });
        }

        Ok(result)
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
                    if let Ok(cred) =
                        git2::Cred::credential_helper(&config, url, username_from_url)
                    {
                        return Ok(cred);
                    }
                }
            }
        }

        git2::Cred::default()
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
    fn commit_diff_reports_added_lines() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one\ntwo\n");
        repo.stage("a.txt").unwrap();
        let first = repo.commit("init", "Test User", "test@example.com").unwrap();

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
        let first = repo.commit("init", "Test User", "test@example.com").unwrap();

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
        repo.commit("init", "Test User", "test@example.com").unwrap();

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
        repo.commit("init", "Test User", "test@example.com").unwrap();

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
        repo.commit("init", "Test User", "test@example.com").unwrap();

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
    fn revert_file_discards_working_tree_changes() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();

        write_file(dir.path(), "a.txt", "one");
        repo.stage("a.txt").unwrap();
        repo.commit("init", "Test User", "test@example.com").unwrap();

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
    fn commit_with_configured_identity_uses_repo_config() {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        {
            let mut config = repo.repo.config().unwrap();
            config.set_str("user.name", "Configured User").unwrap();
            config.set_str("user.email", "configured@example.com").unwrap();
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
