//! Git operations, built on `git2` (libgit2 bindings) — the same library
//! Cargo itself uses. This wraps the subset of git a client UI needs:
//! opening/cloning repos, status, history, diffs, branches, staging and
//! committing.

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use git2::{Repository, StatusOptions};
use std::path::Path;

pub struct GitRepo {
    repo: Repository,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileStatus {
    New,
    Modified,
    Deleted,
    Renamed,
    Typechange,
    Conflicted,
}

#[derive(Debug, Clone)]
pub struct StatusEntry {
    pub path: String,
    pub staged: Option<FileStatus>,
    pub unstaged: Option<FileStatus>,
}

#[derive(Debug, Clone)]
pub struct CommitInfo {
    pub id: String,
    pub summary: String,
    pub author: String,
    pub email: String,
    pub time: DateTime<Utc>,
}

#[derive(Debug, Clone)]
pub struct BranchInfo {
    pub name: String,
    pub is_head: bool,
    pub is_remote: bool,
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
            });
        }

        Ok(commits)
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
}
