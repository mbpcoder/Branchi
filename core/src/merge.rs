//! Merging a branch into the current one (normal, no-fast-forward or
//! squash), the in-progress state after a merge stops on conflicts, and
//! resolving or aborting it.

use anyhow::{bail, Context, Result};
use chrono::{DateTime, Utc};
use serde::Serialize;

use crate::git::{CommitInfo, GitRepo};

/// How [`GitRepo::merge`] combines the branches.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MergeMode {
    /// Fast-forward when possible, else a merge commit.
    Merge,
    /// Always a merge commit.
    NoFastForward,
    /// One new commit with all the branch's changes and a single parent.
    Squash,
}

impl MergeMode {
    pub fn parse(mode: &str) -> Result<Self> {
        Ok(match mode {
            "merge" => Self::Merge,
            "no_ff" => Self::NoFastForward,
            "squash" => Self::Squash,
            other => bail!("unknown merge mode: {other}"),
        })
    }
}

/// What merging `source` into the current branch would bring in.
#[derive(Debug, Clone, Serialize)]
pub struct MergePreview {
    pub source: String,
    /// The current branch, or `None` when HEAD is detached.
    pub target: Option<String>,
    /// Newest first, at most [`PREVIEW_LIMIT`].
    pub incoming: Vec<CommitInfo>,
    pub incoming_count: usize,
    pub up_to_date: bool,
    pub can_fast_forward: bool,
    /// Whether there are uncommitted changes (merging is refused then).
    pub dirty: bool,
    /// Commits on the current branch that `source` doesn't have: what a
    /// rebase would replay.
    pub outgoing_count: usize,
    /// Whether some of those are already pushed (a rebase rewrites them,
    /// so the branch then needs a force push).
    pub rewrites_pushed: bool,
}

const PREVIEW_LIMIT: usize = 50;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum MergeResult {
    UpToDate,
    FastForward,
    Committed,
    Conflicts,
}

#[derive(Debug, Clone, Serialize)]
pub struct MergeOutcome {
    pub result: MergeResult,
    pub commit_id: Option<String>,
    /// Paths still in conflict, when `result` is `conflicts`.
    pub conflicts: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum MergeKind {
    Merge,
    Squash,
    Rebase,
}

/// A merge that stopped on conflicts and waits to be finished or aborted.
#[derive(Debug, Clone, Serialize)]
pub struct MergeState {
    pub kind: MergeKind,
    /// The commit message the merge will be finished with.
    pub message: String,
    pub conflicts: Vec<String>,
    /// For a rebase: the branch being rebased, what it's rebased onto, and
    /// which of its commits is being replayed (1-based) out of how many.
    pub branch: Option<String>,
    pub onto: Option<String>,
    pub step: usize,
    pub total: usize,
}

const SQUASH_MSG: &str = "SQUASH_MSG";
const MERGE_MSG: &str = "MERGE_MSG";

impl GitRepo {
    fn find_any_branch(&self, name: &str) -> Result<git2::Branch<'_>> {
        self.repo
            .find_branch(name, git2::BranchType::Local)
            .or_else(|_| self.repo.find_branch(name, git2::BranchType::Remote))
            .with_context(|| format!("branch not found: {name}"))
    }

    fn has_uncommitted_changes(&self) -> Result<bool> {
        let mut options = git2::StatusOptions::new();
        options.include_untracked(false).include_ignored(false);
        Ok(!self.repo.statuses(Some(&mut options))?.is_empty())
    }

    fn current_branch_name(&self) -> Option<String> {
        self.repo
            .head()
            .ok()
            .filter(|h| h.is_branch())
            .and_then(|h| h.shorthand().map(str::to_string))
    }

    /// What merging `source` into the current branch would bring in.
    pub fn merge_preview(&self, source: &str) -> Result<MergePreview> {
        let branch = self.find_any_branch(source)?;
        let annotated = self.repo.reference_to_annotated_commit(branch.get())?;
        let (analysis, _) = self.repo.merge_analysis(&[&annotated])?;
        let head = self.repo.head()?.peel_to_commit()?;

        let mut walk = self.repo.revwalk()?;
        walk.push(annotated.id())?;
        walk.hide(head.id())?;
        let ids: Vec<git2::Oid> = walk.collect::<std::result::Result<_, _>>()?;
        let incoming = ids
            .iter()
            .take(PREVIEW_LIMIT)
            .map(|id| -> Result<CommitInfo> {
                let commit = self.repo.find_commit(*id)?;
                let author = commit.author();
                Ok(CommitInfo {
                    id: id.to_string(),
                    summary: commit.summary().unwrap_or_default().to_string(),
                    author: author.name().unwrap_or_default().to_string(),
                    email: author.email().unwrap_or_default().to_string(),
                    time: DateTime::<Utc>::from_timestamp(commit.time().seconds(), 0)
                        .unwrap_or_default(),
                    parent_ids: commit.parent_ids().map(|p| p.to_string()).collect(),
                })
            })
            .collect::<Result<Vec<_>>>()?;

        let mut walk = self.repo.revwalk()?;
        walk.push(head.id())?;
        walk.hide(annotated.id())?;
        let outgoing: Vec<git2::Oid> = walk.collect::<std::result::Result<_, _>>()?;
        let upstream = self
            .repo
            .head()
            .ok()
            .filter(|h| h.is_branch())
            .and_then(|h| h.shorthand().map(str::to_string))
            .and_then(|name| self.repo.find_branch(&name, git2::BranchType::Local).ok())
            .and_then(|b| b.upstream().ok())
            .and_then(|u| u.get().target());
        let rewrites_pushed = upstream.is_some_and(|up| {
            outgoing
                .iter()
                .any(|c| *c == up || self.repo.graph_descendant_of(up, *c).unwrap_or(false))
        });

        Ok(MergePreview {
            outgoing_count: outgoing.len(),
            rewrites_pushed,
            source: source.to_string(),
            target: self.current_branch_name(),
            incoming_count: ids.len(),
            incoming,
            up_to_date: analysis.is_up_to_date(),
            can_fast_forward: analysis.is_fast_forward(),
            dirty: self.has_uncommitted_changes()?,
        })
    }

    /// Merges branch `source` (local or remote) into the current branch.
    /// With conflicts, the merge is left in progress (see
    /// [`merge_state`](Self::merge_state)) and finished by committing.
    pub fn merge(&self, source: &str, mode: MergeMode, message: &str) -> Result<MergeOutcome> {
        if self.merge_state()?.is_some() {
            bail!("A merge is already in progress. Finish or abort it first.");
        }
        if self.has_uncommitted_changes()? {
            bail!("Commit or discard your changes before merging.");
        }
        let branch = self.find_any_branch(source)?;
        let annotated = self.repo.reference_to_annotated_commit(branch.get())?;
        let (analysis, _) = self.repo.merge_analysis(&[&annotated])?;

        if analysis.is_up_to_date() {
            return Ok(MergeOutcome {
                result: MergeResult::UpToDate,
                commit_id: None,
                conflicts: Vec::new(),
            });
        }

        if analysis.is_fast_forward() && mode == MergeMode::Merge {
            let target = self.repo.find_commit(annotated.id())?;
            self.repo.checkout_tree(
                target.as_object(),
                Some(git2::build::CheckoutBuilder::new().safe()),
            )?;
            let mut head = self.repo.head()?;
            if !head.is_branch() {
                bail!("HEAD is detached; check out a branch first.");
            }
            head.set_target(target.id(), &format!("merge {source}: Fast-forward"))?;
            return Ok(MergeOutcome {
                result: MergeResult::FastForward,
                commit_id: Some(target.id().to_string()),
                conflicts: Vec::new(),
            });
        }

        let mut checkout = git2::build::CheckoutBuilder::new();
        checkout.allow_conflicts(true).conflict_style_merge(true);
        self.repo
            .merge(&[&annotated], None, Some(&mut checkout))
            .with_context(|| format!("failed to merge {source}"))?;

        let squash = mode == MergeMode::Squash;
        if squash {
            // A squash isn't a merge in git's eyes: no MERGE_HEAD, so the
            // final commit has one parent.
            self.repo.cleanup_state()?;
            std::fs::write(self.repo.path().join(SQUASH_MSG), message)?;
        } else {
            std::fs::write(self.repo.path().join(MERGE_MSG), message)?;
        }

        let conflicts = self.conflicted_paths()?;
        if !conflicts.is_empty() {
            return Ok(MergeOutcome {
                result: MergeResult::Conflicts,
                commit_id: None,
                conflicts,
            });
        }

        let id = self.commit_with_configured_identity(message)?;
        Ok(MergeOutcome {
            result: MergeResult::Committed,
            commit_id: Some(id),
            conflicts: Vec::new(),
        })
    }

    /// The merge waiting to be finished, if any.
    pub fn merge_state(&self) -> Result<Option<MergeState>> {
        if let Some(state) = self.rebase_state()? {
            return Ok(Some(state));
        }
        let dir = self.repo.path();
        let kind = if self.repo.state() == git2::RepositoryState::Merge {
            MergeKind::Merge
        } else if dir.join(SQUASH_MSG).exists() {
            MergeKind::Squash
        } else {
            return Ok(None);
        };
        let file = match kind {
            MergeKind::Squash => SQUASH_MSG,
            _ => MERGE_MSG,
        };
        let message = std::fs::read_to_string(dir.join(file)).unwrap_or_default();
        Ok(Some(MergeState {
            kind,
            message: message.trim_end().to_string(),
            conflicts: self.conflicted_paths()?,
            branch: None,
            onto: None,
            step: 0,
            total: 0,
        }))
    }

    /// The commit being merged in, while a merge is in progress.
    pub(crate) fn merge_head(&self) -> Result<Option<git2::Commit<'_>>> {
        if self.repo.state() != git2::RepositoryState::Merge {
            return Ok(None);
        }
        // The first line of .git/MERGE_HEAD (one line per merged commit).
        let text = std::fs::read_to_string(self.repo.path().join("MERGE_HEAD")).unwrap_or_default();
        let found = text
            .lines()
            .next()
            .and_then(|line| git2::Oid::from_str(line.trim()).ok());
        Ok(match found {
            Some(id) => Some(self.repo.find_commit(id)?),
            None => None,
        })
    }

    /// Forgets an in-progress merge or squash (after it was committed).
    pub(crate) fn clear_merge_state(&self) -> Result<()> {
        if self.repo.state() == git2::RepositoryState::Merge {
            self.repo.cleanup_state()?;
        }
        let squash = self.repo.path().join(SQUASH_MSG);
        if squash.exists() {
            std::fs::remove_file(squash)?;
        }
        Ok(())
    }

    /// Cancels an in-progress merge, putting the branch and files back as
    /// they were before it started.
    pub fn abort_merge(&self) -> Result<()> {
        if self.is_rebasing() {
            return self.abort_rebase();
        }
        if self.merge_state()?.is_none() {
            bail!("No merge in progress.");
        }
        let head = self.repo.head()?.peel_to_commit()?;
        self.repo
            .reset(head.as_object(), git2::ResetType::Hard, None)?;
        self.clear_merge_state()
    }

    /// Resolves the conflict in `path` by taking one side whole: `ours`
    /// (the current branch) or `theirs` (the merged branch). A side that
    /// deleted the file deletes it.
    pub fn resolve_conflict(&self, path: &str, side: &str) -> Result<()> {
        let mut index = self.repo.index()?;
        let conflict = index
            .conflicts()?
            .filter_map(|c| c.ok())
            .find(|c| {
                [&c.our, &c.their, &c.ancestor]
                    .into_iter()
                    .flatten()
                    .any(|e| e.path == path.as_bytes())
            })
            .with_context(|| format!("{path} has no conflict"))?;
        let entry = match side {
            "ours" => conflict.our,
            "theirs" => conflict.their,
            other => bail!("unknown side: {other}"),
        };
        let workdir = self.repo.workdir().context("bare repository")?;
        let file = workdir.join(path);
        match entry {
            Some(entry) => {
                let blob = self.repo.find_blob(entry.id)?;
                if let Some(parent) = file.parent() {
                    std::fs::create_dir_all(parent)?;
                }
                std::fs::write(&file, blob.content())?;
                index.add_path(std::path::Path::new(path))?;
            }
            None => {
                if file.exists() {
                    std::fs::remove_file(&file)?;
                }
                index.remove_path(std::path::Path::new(path))?;
            }
        }
        index.write()?;
        Ok(())
    }

    fn is_rebasing(&self) -> bool {
        matches!(
            self.repo.state(),
            git2::RepositoryState::Rebase
                | git2::RepositoryState::RebaseMerge
                | git2::RepositoryState::RebaseInteractive
        )
    }

    /// Replays the current branch's own commits on top of branch `onto`.
    /// Stops on the first commit that conflicts, leaving the rebase in
    /// progress (see [`continue_rebase`](Self::continue_rebase)).
    pub fn rebase(&self, onto: &str) -> Result<MergeOutcome> {
        if self.merge_state()?.is_some() {
            bail!("A merge or rebase is already in progress. Finish or abort it first.");
        }
        if self.has_uncommitted_changes()? {
            bail!("Commit or discard your changes before rebasing.");
        }
        if self.current_branch_name().is_none() {
            bail!("HEAD is detached; check out a branch first.");
        }
        let branch = self.find_any_branch(onto)?;
        let upstream = self.repo.reference_to_annotated_commit(branch.get())?;
        let head = self.repo.head()?.peel_to_commit()?;
        if head.id() == upstream.id() || self.repo.graph_descendant_of(head.id(), upstream.id())? {
            return Ok(MergeOutcome {
                result: MergeResult::UpToDate,
                commit_id: None,
                conflicts: Vec::new(),
            });
        }
        let mut rebase = self
            .repo
            .rebase(None, Some(&upstream), None, None)
            .with_context(|| format!("failed to start rebasing onto {onto}"))?;
        self.run_rebase(&mut rebase, None)
    }

    /// Continues a rebase stopped on conflicts: commits the resolved commit
    /// (with `message`, or its original message) and replays the rest.
    pub fn continue_rebase(&self, message: Option<&str>) -> Result<MergeOutcome> {
        let mut rebase = self
            .repo
            .open_rebase(None)
            .context("No rebase in progress.")?;
        if !self.conflicted_paths()?.is_empty() {
            bail!("Resolve all conflicts before continuing.");
        }
        if rebase.operation_current().is_some() {
            self.commit_rebase_step(&mut rebase, message)?;
        }
        self.run_rebase(&mut rebase, None)
    }

    /// Drops the commit the rebase stopped on and goes on with the rest.
    pub fn skip_rebase_commit(&self) -> Result<MergeOutcome> {
        let mut rebase = self
            .repo
            .open_rebase(None)
            .context("No rebase in progress.")?;
        // Drop the step's changes. Not a hard reset: that would also end
        // the rebase.
        let tree = self.repo.head()?.peel_to_tree()?;
        let mut index = self.repo.index()?;
        index.read_tree(&tree)?;
        index.write()?;
        self.repo.checkout_index(
            Some(&mut index),
            Some(git2::build::CheckoutBuilder::new().force()),
        )?;
        self.run_rebase(&mut rebase, None)
    }

    fn abort_rebase(&self) -> Result<()> {
        let mut rebase = self
            .repo
            .open_rebase(None)
            .context("No rebase in progress.")?;
        rebase.abort()?;
        Ok(())
    }

    fn commit_rebase_step(
        &self,
        rebase: &mut git2::Rebase<'_>,
        message: Option<&str>,
    ) -> Result<()> {
        let committer = self
            .repo
            .signature()
            .context("no user.name/user.email configured for this repository")?;
        match rebase.commit(None, &committer, message) {
            Ok(_) => Ok(()),
            // The change is already on the new base: nothing to commit.
            Err(e) if e.code() == git2::ErrorCode::Applied => Ok(()),
            Err(e) => Err(e.into()),
        }
    }

    /// Applies the remaining operations, committing each; stops on
    /// conflicts, else finishes.
    fn run_rebase(
        &self,
        rebase: &mut git2::Rebase<'_>,
        message: Option<&str>,
    ) -> Result<MergeOutcome> {
        while let Some(op) = rebase.next() {
            op?;
            let conflicts = self.conflicted_paths()?;
            if !conflicts.is_empty() {
                return Ok(MergeOutcome {
                    result: MergeResult::Conflicts,
                    commit_id: None,
                    conflicts,
                });
            }
            self.commit_rebase_step(rebase, message)?;
        }
        let committer = self
            .repo
            .signature()
            .context("no user.name/user.email configured for this repository")?;
        rebase.finish(Some(&committer))?;
        let head = self.repo.head()?.peel_to_commit()?;
        Ok(MergeOutcome {
            result: MergeResult::Committed,
            commit_id: Some(head.id().to_string()),
            conflicts: Vec::new(),
        })
    }

    fn rebase_state(&self) -> Result<Option<MergeState>> {
        if !self.is_rebasing() {
            return Ok(None);
        }
        let dir = self.repo.path().join("rebase-merge");
        let read = |name: &str| {
            std::fs::read_to_string(dir.join(name))
                .ok()
                .map(|s| s.trim().to_string())
        };
        let branch =
            read("head-name").map(|n| n.strip_prefix("refs/heads/").unwrap_or(&n).to_string());
        let onto = read("onto").and_then(|id| {
            let oid = git2::Oid::from_str(&id).ok()?;
            self.branch_name_at(oid)
                .or_else(|| Some(id.chars().take(7).collect()))
        });
        let mut rebase = self.repo.open_rebase(None)?;
        let total = rebase.len();
        let current = rebase.operation_current();
        let message = current
            .and_then(|i| rebase.nth(i))
            .and_then(|op| self.repo.find_commit(op.id()).ok())
            .and_then(|c| c.message().map(|m| m.trim_end().to_string()))
            .unwrap_or_default();
        Ok(Some(MergeState {
            kind: MergeKind::Rebase,
            message,
            conflicts: self.conflicted_paths()?,
            branch,
            onto,
            step: current.map_or(0, |i| i + 1),
            total,
        }))
    }

    /// A branch (local first) pointing at `oid`, for naming a commit.
    fn branch_name_at(&self, oid: git2::Oid) -> Option<String> {
        for kind in [git2::BranchType::Local, git2::BranchType::Remote] {
            for entry in self.repo.branches(Some(kind)).ok()?.flatten() {
                let (branch, _) = entry;
                if branch.get().target() == Some(oid) {
                    if let Ok(Some(name)) = branch.name() {
                        if !name.ends_with("/HEAD") {
                            return Some(name.to_string());
                        }
                    }
                }
            }
        }
        None
    }

    fn conflicted_paths(&self) -> Result<Vec<String>> {
        let index = self.repo.index()?;
        let mut paths: Vec<String> = index
            .conflicts()?
            .filter_map(|c| c.ok())
            .filter_map(|c| {
                c.our
                    .or(c.their)
                    .or(c.ancestor)
                    .map(|e| String::from_utf8_lossy(&e.path).into_owned())
            })
            .collect();
        paths.sort();
        paths.dedup();
        Ok(paths)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;

    fn write(dir: &Path, name: &str, text: &str) {
        std::fs::write(dir.join(name), text).unwrap();
    }

    fn commit(repo: &GitRepo, dir: &Path, name: &str, text: &str) {
        write(dir, name, text);
        repo.stage(name).unwrap();
        repo.commit(name, "T", "t@example.com").unwrap();
    }

    /// A repo whose default branch and "feature" both changed a.txt.
    fn diverged(conflicting: bool) -> (tempfile::TempDir, GitRepo, String) {
        let dir = tempfile::tempdir().unwrap();
        let repo = GitRepo::init(dir.path()).unwrap();
        let mut config = repo.repo.config().unwrap();
        config.set_str("user.name", "T").unwrap();
        config.set_str("user.email", "t@example.com").unwrap();
        commit(&repo, dir.path(), "a.txt", "one\ntwo\nthree\n");
        let main = repo.repo.head().unwrap().shorthand().unwrap().to_string();
        repo.create_branch("feature", None).unwrap();
        repo.checkout_branch("feature").unwrap();
        commit(&repo, dir.path(), "a.txt", "one\nFEATURE\nthree\n");
        commit(&repo, dir.path(), "f.txt", "f");
        repo.checkout_branch(&main).unwrap();
        if conflicting {
            commit(&repo, dir.path(), "a.txt", "one\nMAIN\nthree\n");
        } else {
            commit(&repo, dir.path(), "m.txt", "m");
        }
        (dir, repo, main)
    }

    fn head(repo: &GitRepo) -> git2::Commit<'_> {
        repo.repo.head().unwrap().peel_to_commit().unwrap()
    }

    #[test]
    fn preview_lists_incoming_commits() {
        let (_dir, repo, main) = diverged(false);
        let preview = repo.merge_preview("feature").unwrap();
        assert_eq!(preview.target.as_deref(), Some(main.as_str()));
        assert_eq!(preview.incoming_count, 2);
        assert_eq!(preview.incoming[0].summary, "f.txt");
        assert!(!preview.can_fast_forward && !preview.up_to_date && !preview.dirty);
    }

    #[test]
    fn fast_forward_and_up_to_date() {
        let (dir, repo, main) = diverged(false);
        repo.create_branch("old", None).unwrap();
        commit(&repo, dir.path(), "n.txt", "n");
        repo.checkout_branch("old").unwrap();
        assert!(repo.merge_preview(&main).unwrap().can_fast_forward);
        let out = repo.merge(&main, MergeMode::Merge, "msg").unwrap();
        assert!(matches!(out.result, MergeResult::FastForward));
        assert!(dir.path().join("n.txt").exists());
        assert_eq!(head(&repo).message(), Some("n.txt"));
        let out = repo.merge(&main, MergeMode::Merge, "msg").unwrap();
        assert!(matches!(out.result, MergeResult::UpToDate));
    }

    #[test]
    fn clean_merge_commits_with_two_parents() {
        let (_dir, repo, _) = diverged(false);
        let out = repo
            .merge("feature", MergeMode::Merge, "Merge feature")
            .unwrap();
        assert!(matches!(out.result, MergeResult::Committed));
        let commit = head(&repo);
        assert_eq!(commit.parent_count(), 2);
        assert_eq!(commit.message(), Some("Merge feature"));
        assert!(repo.merge_state().unwrap().is_none());
    }

    #[test]
    fn squash_commits_with_one_parent() {
        let (dir, repo, _) = diverged(false);
        let out = repo
            .merge("feature", MergeMode::Squash, "Squashed feature")
            .unwrap();
        assert!(matches!(out.result, MergeResult::Committed));
        let commit = head(&repo);
        assert_eq!(commit.parent_count(), 1);
        assert!(dir.path().join("f.txt").exists());
        assert!(repo.merge_state().unwrap().is_none());
    }

    #[test]
    fn conflicts_then_resolve_and_finish() {
        let (dir, repo, _) = diverged(true);
        let out = repo.merge("feature", MergeMode::Merge, "Merge it").unwrap();
        assert!(matches!(out.result, MergeResult::Conflicts));
        assert_eq!(out.conflicts, vec!["a.txt".to_string()]);
        let state = repo.merge_state().unwrap().unwrap();
        assert!(matches!(state.kind, MergeKind::Merge));
        assert_eq!(state.message, "Merge it");
        let text = std::fs::read_to_string(dir.path().join("a.txt")).unwrap();
        assert!(text.contains("<<<<<<<") && text.contains("FEATURE"));
        assert!(repo.commit_with_configured_identity("x").is_err());

        repo.resolve_conflict("a.txt", "theirs").unwrap();
        assert_eq!(
            std::fs::read_to_string(dir.path().join("a.txt")).unwrap(),
            "one\nFEATURE\nthree\n"
        );
        assert!(repo.merge_state().unwrap().unwrap().conflicts.is_empty());
        repo.commit_with_configured_identity("Merge it").unwrap();
        assert_eq!(head(&repo).parent_count(), 2);
        assert!(repo.merge_state().unwrap().is_none());
    }

    #[test]
    fn squash_conflict_can_be_aborted() {
        let (dir, repo, _) = diverged(true);
        let before = head(&repo).id();
        let out = repo.merge("feature", MergeMode::Squash, "Squash").unwrap();
        assert!(matches!(out.result, MergeResult::Conflicts));
        let state = repo.merge_state().unwrap().unwrap();
        assert!(matches!(state.kind, MergeKind::Squash));
        repo.abort_merge().unwrap();
        assert!(repo.merge_state().unwrap().is_none());
        assert_eq!(head(&repo).id(), before);
        assert_eq!(
            std::fs::read_to_string(dir.path().join("a.txt")).unwrap(),
            "one\nMAIN\nthree\n"
        );
        assert!(!dir.path().join("f.txt").exists());
    }

    #[test]
    fn clean_rebase_replays_commits() {
        let (dir, repo, main) = diverged(false);
        repo.checkout_branch("feature").unwrap();
        let preview = repo.merge_preview(&main).unwrap();
        assert_eq!(preview.outgoing_count, 2);
        assert!(!preview.rewrites_pushed);
        let out = repo.rebase(&main).unwrap();
        assert!(matches!(out.result, MergeResult::Committed));
        // feature's two commits now sit on top of main's.
        let head = head(&repo);
        assert_eq!(head.message(), Some("f.txt"));
        assert_eq!(head.parent_count(), 1);
        assert!(dir.path().join("m.txt").exists());
        assert!(repo.merge_state().unwrap().is_none());
        assert_eq!(repo.repo.head().unwrap().shorthand(), Some("feature"));
        assert!(matches!(
            repo.rebase(&main).unwrap().result,
            MergeResult::UpToDate
        ));
    }

    #[test]
    fn rebase_conflict_continue_and_abort() {
        let (dir, repo, main) = diverged(true);
        repo.checkout_branch("feature").unwrap();
        let before = head(&repo).id();
        let out = repo.rebase(&main).unwrap();
        assert!(matches!(out.result, MergeResult::Conflicts));
        let state = repo.merge_state().unwrap().unwrap();
        assert!(matches!(state.kind, MergeKind::Rebase));
        assert_eq!(state.branch.as_deref(), Some("feature"));
        assert_eq!(state.onto.as_deref(), Some(main.as_str()));
        assert_eq!((state.step, state.total), (1, 2));
        assert_eq!(state.message, "a.txt");

        // Abort puts feature back.
        repo.abort_merge().unwrap();
        assert!(repo.merge_state().unwrap().is_none());
        assert_eq!(head(&repo).id(), before);

        // Again, resolving this time.
        repo.rebase(&main).unwrap();
        repo.resolve_conflict("a.txt", "theirs").unwrap();
        let out = repo.continue_rebase(None).unwrap();
        assert!(matches!(out.result, MergeResult::Committed));
        assert!(repo.merge_state().unwrap().is_none());
        assert_eq!(head(&repo).message(), Some("f.txt"));
        assert_eq!(
            std::fs::read_to_string(dir.path().join("a.txt")).unwrap(),
            "one\nFEATURE\nthree\n"
        );
    }

    #[test]
    fn rebase_skip_drops_the_conflicting_commit() {
        let (dir, repo, main) = diverged(true);
        repo.checkout_branch("feature").unwrap();
        repo.rebase(&main).unwrap();
        let out = repo.skip_rebase_commit().unwrap();
        assert!(matches!(out.result, MergeResult::Committed));
        assert_eq!(
            std::fs::read_to_string(dir.path().join("a.txt")).unwrap(),
            "one\nMAIN\nthree\n"
        );
        assert!(dir.path().join("f.txt").exists());
    }

    #[test]
    fn refuses_with_uncommitted_changes() {
        let (dir, repo, _) = diverged(false);
        write(dir.path(), "a.txt", "dirty");
        assert!(repo.merge_preview("feature").unwrap().dirty);
        assert!(repo.merge("feature", MergeMode::Merge, "m").is_err());
    }
}
