//! RustGit core library.
//!
//! This crate holds the Rust logic for the RustGit client. It is kept
//! separate from the Flutter UI so the same core can later be bridged
//! into the app (e.g. via `flutter_rust_bridge`), the same way RustDesk
//! splits its `libs/` core from its `flutter/` UI.

pub mod db;
pub mod git;

pub fn welcome_message() -> String {
    "Welcome to RustGit".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn welcome_message_is_correct() {
        assert_eq!(welcome_message(), "Welcome to RustGit");
    }
}
