//! Fast fuzzy "go to file" search over a working tree.
//!
//! The file list is gathered once with a parallel walk that honours
//! `.gitignore` (the same walker ripgrep uses) and cached per root, so each
//! keystroke only runs the in-memory fuzzy match.

use anyhow::Result;
use ignore::{WalkBuilder, WalkState};
use serde::Serialize;
use std::collections::HashMap;
use std::path::Path;
use std::sync::{Arc, Mutex, OnceLock};

/// Walking stops after this many files, so a huge tree can't stall search.
const MAX_INDEXED_FILES: usize = 500_000;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct FileMatch {
    /// Path relative to the searched root, always with `/` separators.
    pub path: String,
    pub score: i64,
    /// Character (not byte) indices into `path` that matched the query,
    /// for highlighting.
    pub positions: Vec<usize>,
}

/// An indexed path plus its lowercase form, computed once per index so
/// each keystroke doesn't redo it. `lower` has exactly one char per char of
/// `path`, so positions line up.
struct Indexed {
    path: String,
    lower: String,
}

impl Indexed {
    fn new(path: String) -> Self {
        let lower = path
            .chars()
            .map(|c| c.to_lowercase().next().unwrap_or(c))
            .collect();
        Self { path, lower }
    }
}

type Index = Arc<Vec<Indexed>>;

fn cache() -> &'static Mutex<HashMap<String, Index>> {
    static CACHE: OnceLock<Mutex<HashMap<String, Index>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Lists every file under `root` (relative, `/`-separated, sorted),
/// skipping `.git` and anything `.gitignore`d. Hidden files like `.env`
/// are included.
pub fn index_files(root: &str) -> Vec<String> {
    let root_path = Path::new(root).to_path_buf();
    let found = Arc::new(Mutex::new(Vec::<String>::new()));
    WalkBuilder::new(&root_path)
        .hidden(false)
        .git_ignore(true)
        .git_global(true)
        .git_exclude(true)
        .require_git(false)
        .filter_entry(|entry| entry.file_name() != ".git")
        .build_parallel()
        .run(|| {
            let mut batch = Batch {
                local: Vec::new(),
                shared: Arc::clone(&found),
            };
            let root_path = root_path.clone();
            Box::new(move |entry| {
                let Ok(entry) = entry else {
                    return WalkState::Continue;
                };
                if entry.file_type().is_some_and(|t| t.is_file()) {
                    if let Ok(rel) = entry.path().strip_prefix(&root_path) {
                        batch.local.push(rel.to_string_lossy().replace('\\', "/"));
                    }
                }
                if batch.local.len() >= 256 && batch.flush() >= MAX_INDEXED_FILES {
                    return WalkState::Quit;
                }
                WalkState::Continue
            })
        });
    let mut files = std::mem::take(&mut *found.lock().unwrap());
    files.sort_unstable();
    files.truncate(MAX_INDEXED_FILES);
    files
}

/// One walker thread's pending paths; flushed to the shared list in
/// batches to keep lock traffic low, and once more when the thread ends.
struct Batch {
    local: Vec<String>,
    shared: Arc<Mutex<Vec<String>>>,
}

impl Batch {
    /// Moves pending paths to the shared list; returns its new length.
    fn flush(&mut self) -> usize {
        let mut all = self.shared.lock().unwrap();
        all.append(&mut self.local);
        all.len()
    }
}

impl Drop for Batch {
    fn drop(&mut self) {
        self.flush();
    }
}

/// Fuzzy-matches `query` against the files under `root` and returns the
/// best `limit` matches, best first. With `refresh` (or on first use for
/// this root) the file list is rebuilt from disk; otherwise the cached list
/// is reused.
pub fn find_files(root: &str, query: &str, limit: usize, refresh: bool) -> Result<Vec<FileMatch>> {
    let files = {
        let cached = if refresh {
            None
        } else {
            cache().lock().unwrap().get(root).cloned()
        };
        match cached {
            Some(files) => files,
            None => {
                if !Path::new(root).is_dir() {
                    anyhow::bail!("{root} is not a folder");
                }
                let files: Index =
                    Arc::new(index_files(root).into_iter().map(Indexed::new).collect());
                cache()
                    .lock()
                    .unwrap()
                    .insert(root.to_string(), Arc::clone(&files));
                files
            }
        }
    };

    let needle: Vec<char> = query
        .chars()
        .filter(|c| !c.is_whitespace())
        .map(|c| if c == '\\' { '/' } else { c })
        .map(|c| c.to_lowercase().next().unwrap_or(c))
        .collect();
    let needle_str: String = needle.iter().collect();

    if needle.is_empty() {
        return Ok(files
            .iter()
            .take(limit)
            .map(|file| FileMatch {
                path: file.path.clone(),
                score: 0,
                positions: Vec::new(),
            })
            .collect());
    }

    let mut matches: Vec<FileMatch> = files
        .iter()
        .filter_map(|file| {
            if !is_subsequence(file.lower.as_bytes(), needle_str.as_bytes()) {
                return None;
            }
            score(&file.path, &file.lower, &needle).map(|(score, positions)| FileMatch {
                path: file.path.clone(),
                score,
                positions,
            })
        })
        .collect();
    matches.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then(a.path.len().cmp(&b.path.len()))
            .then_with(|| a.path.cmp(&b.path))
    });
    matches.truncate(limit);
    Ok(matches)
}

/// Scores `path` against the lowercase `needle` as a subsequence match.
/// Matching in the file name, at word starts and in runs scores higher.
/// Returns None if not every needle character appears in order.
/// Fast byte-level pre-filter. If the needle's chars appear in order, so do
/// their UTF-8 bytes, so this never drops a real match; the rare false
/// positive with non-ASCII text is dropped by [score].
fn is_subsequence(hay: &[u8], needle: &[u8]) -> bool {
    let mut rest = hay;
    for &b in needle {
        match rest.iter().position(|&h| h == b) {
            Some(i) => rest = &rest[i + 1..],
            None => return false,
        }
    }
    true
}

fn score(path: &str, lower: &str, needle: &[char]) -> Option<(i64, Vec<usize>)> {
    let hay: Vec<char> = path.chars().collect();
    let lower: Vec<char> = lower.chars().collect();
    let name_start = hay.iter().rposition(|&c| c == '/').map_or(0, |i| i + 1);

    // Prefer matching inside the file name: try aligning the needle there
    // first, falling back to a greedy match over the whole path.
    let positions = match_from(&lower, needle, name_start)
        .or_else(|| match_name_suffix(&lower, needle, name_start))
        .or_else(|| match_from(&lower, needle, 0))?;

    let mut total: i64 = 0;
    let mut prev: Option<usize> = None;
    for &pos in &positions {
        let mut s = 1;
        let boundary = pos == 0
            || matches!(hay[pos - 1], '/' | '_' | '-' | '.' | ' ')
            || (hay[pos].is_uppercase() && hay[pos - 1].is_lowercase());
        if boundary {
            s += 8;
        }
        if pos >= name_start {
            s += 4;
        }
        if prev.is_some_and(|p| p + 1 == pos) {
            s += 6;
        }
        total += s;
        prev = Some(pos);
    }
    // Whole file name typed exactly, or as a prefix.
    let name: String = lower[name_start..].iter().collect();
    let typed: String = needle.iter().collect();
    if name == typed {
        total += 100;
    } else if name.starts_with(&typed) {
        total += 40;
    }
    Some((total, positions))
}

/// Greedy subsequence match of the whole needle starting at `from`.
fn match_from(lower: &[char], needle: &[char], from: usize) -> Option<Vec<usize>> {
    let mut positions = Vec::with_capacity(needle.len());
    let mut i = from;
    for n in needle {
        while i < lower.len() && lower[i] != *n {
            i += 1;
        }
        if i == lower.len() {
            return None;
        }
        positions.push(i);
        i += 1;
    }
    Some(positions)
}

/// Matches a leading part of the needle in the directories and the rest
/// in the file name (e.g. "ctrluser" -> `Controllers/UserController.php`),
/// putting as much as possible in the file name.
fn match_name_suffix(lower: &[char], needle: &[char], name_start: usize) -> Option<Vec<usize>> {
    for split in 1..needle.len() {
        let (dir_part, name_part) = needle.split_at(split);
        let Some(name_pos) = match_from(lower, name_part, name_start) else {
            continue;
        };
        let dir_slice = &lower[..name_start];
        if let Some(mut dir_pos) = match_from(dir_slice, dir_part, 0) {
            dir_pos.extend(name_pos);
            return Some(dir_pos);
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn tree() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join("app/Http/Controllers")).unwrap();
        fs::create_dir_all(root.join("vendor/pkg")).unwrap();
        fs::create_dir_all(root.join(".git")).unwrap();
        fs::write(root.join(".gitignore"), "vendor/\n").unwrap();
        fs::write(root.join(".env"), "").unwrap();
        fs::write(root.join("composer.lock"), "{}").unwrap();
        fs::write(root.join("app/Http/Controllers/UserController.php"), "").unwrap();
        fs::write(root.join("app/User.php"), "").unwrap();
        fs::write(root.join("vendor/pkg/User.php"), "").unwrap();
        fs::write(root.join(".git/HEAD"), "").unwrap();
        dir
    }

    #[test]
    fn index_skips_git_and_ignored_but_keeps_dotfiles() {
        let dir = tree();
        let files = index_files(dir.path().to_str().unwrap());
        assert!(files.contains(&".env".to_string()));
        assert!(files.contains(&"composer.lock".to_string()));
        assert!(files.contains(&"app/User.php".to_string()));
        assert!(!files.iter().any(|f| f.starts_with("vendor/")));
        assert!(!files.iter().any(|f| f.starts_with(".git/")));
    }

    #[test]
    fn exact_file_name_ranks_first() {
        let dir = tree();
        let root = dir.path().to_str().unwrap();
        let found = find_files(root, "user.php", 10, true).unwrap();
        assert_eq!(found[0].path, "app/User.php");
        assert!(found.iter().any(|m| m.path.ends_with("UserController.php")));
    }

    #[test]
    fn fuzzy_across_directories() {
        let dir = tree();
        let root = dir.path().to_str().unwrap();
        let found = find_files(root, "ctrlusr", 10, true).unwrap();
        assert_eq!(found[0].path, "app/Http/Controllers/UserController.php");
        assert_eq!(found[0].positions.len(), 7);
    }

    #[test]
    fn no_match_is_empty() {
        let dir = tree();
        let root = dir.path().to_str().unwrap();
        assert!(find_files(root, "zzzq", 10, true).unwrap().is_empty());
    }
}
