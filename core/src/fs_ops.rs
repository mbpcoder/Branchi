//! Filesystem helpers for the file explorer that Dart can't do portably on
//! its own, such as moving a path to the OS trash / Recycle Bin.

use anyhow::{Context, Result};
use std::path::Path;

/// Moves `path` (a file or a whole directory) to the OS trash: the Recycle
/// Bin on Windows, the Trash on macOS, and the freedesktop.org trash on
/// Linux. The item can be restored from there.
pub fn move_to_trash(path: &str) -> Result<()> {
    let target = Path::new(path);
    if !target.exists() && target.symlink_metadata().is_err() {
        anyhow::bail!("{path} does not exist");
    }
    trash::delete(target).with_context(|| format!("failed to move {path} to the trash"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_path_is_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("nope");
        assert!(move_to_trash(missing.to_str().unwrap()).is_err());
    }
}
