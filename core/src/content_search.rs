//! "Search in files": finds text or a regex in every file of a working
//! tree, using ripgrep's own search crates and its `.gitignore`-aware
//! parallel walker.

use anyhow::{Context, Result};
use grep_matcher::Matcher;
use grep_regex::{RegexMatcher, RegexMatcherBuilder};
use grep_searcher::{sinks::UTF8, BinaryDetection, SearcherBuilder};
use ignore::{WalkBuilder, WalkState};
use serde::Serialize;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

/// Files larger than this are skipped (minified bundles, data dumps).
const MAX_FILE_SIZE: u64 = 4 * 1024 * 1024;

/// Lines longer than this are shown as a window around the first match.
const MAX_PREVIEW_CHARS: usize = 300;

#[derive(Debug, Clone, Default)]
pub struct ContentSearchOptions {
    pub regex: bool,
    pub case_sensitive: bool,
    pub whole_word: bool,
    pub max_matches: usize,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ContentMatch {
    /// Path relative to the searched root, with `/` separators.
    pub path: String,
    /// 1-based line number.
    pub line: u64,
    /// 0-based character column of the first match in the full line.
    pub column: usize,
    /// The line (or a window of a long line), leading whitespace trimmed.
    pub text: String,
    /// `[start, end)` character ranges of the matches within `text`.
    pub ranges: Vec<(usize, usize)>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ContentSearchResult {
    pub matches: Vec<ContentMatch>,
    /// True when the search stopped at `max_matches`.
    pub truncated: bool,
}

fn build_matcher(query: &str, options: &ContentSearchOptions) -> Result<RegexMatcher> {
    let mut builder = RegexMatcherBuilder::new();
    builder
        .case_insensitive(!options.case_sensitive)
        .word(options.whole_word)
        .fixed_strings(!options.regex)
        .line_terminator(Some(b'\n'));
    builder
        .build(query)
        .with_context(|| format!("invalid search pattern: {query}"))
}

/// Searches every non-ignored text file under `root` for `query`.
pub fn search_content(
    root: &str,
    query: &str,
    options: &ContentSearchOptions,
) -> Result<ContentSearchResult> {
    if query.is_empty() {
        return Ok(ContentSearchResult {
            matches: Vec::new(),
            truncated: false,
        });
    }
    if !Path::new(root).is_dir() {
        anyhow::bail!("{root} is not a folder");
    }
    let matcher = build_matcher(query, options)?;
    let max = options.max_matches.max(1);
    let root_path = Path::new(root).to_path_buf();
    let found = Arc::new(Mutex::new(Vec::<ContentMatch>::new()));
    let count = Arc::new(AtomicUsize::new(0));
    let truncated = Arc::new(AtomicBool::new(false));

    WalkBuilder::new(&root_path)
        .hidden(false)
        .git_ignore(true)
        .git_global(true)
        .git_exclude(true)
        .require_git(false)
        .max_filesize(Some(MAX_FILE_SIZE))
        .filter_entry(|entry| entry.file_name() != ".git")
        .build_parallel()
        .run(|| {
            let matcher = matcher.clone();
            let root_path = root_path.clone();
            let found = Arc::clone(&found);
            let count = Arc::clone(&count);
            let truncated = Arc::clone(&truncated);
            let mut searcher = SearcherBuilder::new()
                .binary_detection(BinaryDetection::quit(b'\x00'))
                .line_number(true)
                .build();
            Box::new(move |entry| {
                if truncated.load(Ordering::Relaxed) {
                    return WalkState::Quit;
                }
                let Ok(entry) = entry else {
                    return WalkState::Continue;
                };
                if !entry.file_type().is_some_and(|t| t.is_file()) {
                    return WalkState::Continue;
                }
                let Ok(rel) = entry.path().strip_prefix(&root_path) else {
                    return WalkState::Continue;
                };
                let rel = rel.to_string_lossy().replace('\\', "/");
                let mut local = Vec::new();
                // Unreadable or non-UTF-8 files are just skipped.
                let _ = searcher.search_path(
                    &matcher,
                    entry.path(),
                    UTF8(|line_number, line| {
                        if count.fetch_add(1, Ordering::Relaxed) >= max {
                            truncated.store(true, Ordering::Relaxed);
                            return Ok(false);
                        }
                        if let Some(m) = make_match(&matcher, &rel, line_number, line) {
                            local.push(m);
                        }
                        Ok(true)
                    }),
                );
                if !local.is_empty() {
                    found.lock().unwrap().append(&mut local);
                }
                if truncated.load(Ordering::Relaxed) {
                    WalkState::Quit
                } else {
                    WalkState::Continue
                }
            })
        });

    let mut matches = std::mem::take(&mut *found.lock().unwrap());
    matches.sort_by(|a, b| a.path.cmp(&b.path).then(a.line.cmp(&b.line)));
    matches.truncate(max);
    Ok(ContentSearchResult {
        matches,
        truncated: truncated.load(Ordering::Relaxed),
    })
}

/// Builds the preview for one matching line: match ranges in characters,
/// leading whitespace trimmed, and long lines cut down around the match.
fn make_match(
    matcher: &RegexMatcher,
    path: &str,
    line_number: u64,
    line: &str,
) -> Option<ContentMatch> {
    let line = line.trim_end_matches(['\n', '\r']);
    let mut byte_ranges = Vec::new();
    let _ = matcher.find_iter(line.as_bytes(), |m| {
        if m.start() < m.end() {
            byte_ranges.push((m.start(), m.end()));
        }
        true
    });
    let first = *byte_ranges.first()?;

    let to_char = |byte: usize| line[..byte].chars().count();
    let column = to_char(first.0);
    let mut ranges: Vec<(usize, usize)> = byte_ranges
        .iter()
        .map(|&(s, e)| (to_char(s), to_char(e)))
        .collect();
    let chars: Vec<char> = line.chars().collect();

    // Trim leading whitespace, or cut a long line to a window that starts a
    // little before the first match.
    let indent = chars.iter().take_while(|c| c.is_whitespace()).count();
    let (start, prefix) = if chars.len() - indent > MAX_PREVIEW_CHARS {
        let start = column.saturating_sub(40).max(indent);
        (start, if start > indent { "…" } else { "" })
    } else {
        (indent, "")
    };
    let end = (start + MAX_PREVIEW_CHARS).min(chars.len());
    let suffix = if end < chars.len() { "…" } else { "" };
    let shift = prefix.chars().count();
    let text = format!(
        "{prefix}{}{suffix}",
        chars[start..end].iter().collect::<String>()
    );
    ranges = ranges
        .into_iter()
        .filter(|&(s, _)| s >= start && s < end)
        .map(|(s, e)| (s - start + shift, e.min(end) - start + shift))
        .collect();

    Some(ContentMatch {
        path: path.to_string(),
        line: line_number,
        column,
        text,
        ranges,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn opts() -> ContentSearchOptions {
        ContentSearchOptions {
            max_matches: 100,
            ..Default::default()
        }
    }

    fn tree() -> tempfile::TempDir {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        fs::create_dir_all(root.join("src")).unwrap();
        fs::create_dir_all(root.join("vendor")).unwrap();
        fs::write(root.join(".gitignore"), "vendor/\n").unwrap();
        fs::write(
            root.join("src/a.php"),
            "<?php\n    $user = new User();\n// user\n",
        )
        .unwrap();
        fs::write(root.join("src/b.txt"), "nothing here\nUSER upper\n").unwrap();
        fs::write(root.join("vendor/c.php"), "User\n").unwrap();
        fs::write(root.join("bin.dat"), b"User\x00\x01\x02").unwrap();
        dir
    }

    #[test]
    fn finds_case_insensitive_and_skips_ignored_and_binary() {
        let dir = tree();
        let r = search_content(dir.path().to_str().unwrap(), "user", &opts()).unwrap();
        let hits: Vec<_> = r
            .matches
            .iter()
            .map(|m| (m.path.as_str(), m.line))
            .collect();
        assert_eq!(
            hits,
            vec![("src/a.php", 2), ("src/a.php", 3), ("src/b.txt", 2)]
        );
        let first = &r.matches[0];
        assert_eq!(first.text, "$user = new User();");
        assert_eq!(first.ranges, vec![(1, 5), (12, 16)]);
        assert_eq!(first.column, 5);
        assert!(!r.truncated);
    }

    #[test]
    fn case_sensitive_whole_word_and_regex() {
        let dir = tree();
        let root = dir.path().to_str().unwrap();
        let mut o = opts();
        o.case_sensitive = true;
        let r = search_content(root, "User", &o).unwrap();
        assert_eq!(r.matches.len(), 1);

        let mut o = opts();
        o.regex = true;
        let r = search_content(root, r"new \w+\(", &o).unwrap();
        assert_eq!(r.matches.len(), 1);
        assert_eq!(r.matches[0].ranges, vec![(8, 17)]);

        assert!(search_content(root, "(", &o).is_err());
    }

    #[test]
    fn stops_at_max_matches() {
        let dir = tree();
        let mut o = opts();
        o.max_matches = 2;
        let r = search_content(dir.path().to_str().unwrap(), "user", &o).unwrap();
        assert_eq!(r.matches.len(), 2);
        assert!(r.truncated);
    }

    #[test]
    fn long_lines_are_windowed_around_the_match() {
        let dir = tempfile::tempdir().unwrap();
        let line = format!("{}needle{}", "a".repeat(1000), "b".repeat(1000));
        fs::write(dir.path().join("min.js"), &line).unwrap();
        let r = search_content(dir.path().to_str().unwrap(), "needle", &opts()).unwrap();
        let m = &r.matches[0];
        assert!(m.text.starts_with('…') && m.text.ends_with('…'));
        let (s, e) = m.ranges[0];
        let chars: Vec<char> = m.text.chars().collect();
        assert_eq!(chars[s..e].iter().collect::<String>(), "needle");
        assert_eq!(m.column, 1000);
    }
}
