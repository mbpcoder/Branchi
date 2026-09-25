//! Branchi core library.
//!
//! This crate holds the Rust logic for the Branchi client. It is kept
//! separate from the Flutter UI so the same core can later be bridged
//! into the app (e.g. via `flutter_rust_bridge`), the same way RustDesk
//! splits its `libs/` core from its `flutter/` UI.

pub mod db;
pub mod ffi;
pub mod git;
pub mod logging;

pub fn welcome_message() -> String {
    "Welcome to Branchi".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn welcome_message_is_correct() {
        assert_eq!(welcome_message(), "Welcome to Branchi");
    }
}
