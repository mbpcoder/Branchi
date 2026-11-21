//! File logging for the core crate.
//!
//! Writes to `logs/branchi-core.log` next to the running executable
//! (`~/Library/Logs/Branchi` on macOS, where the app bundle must stay
//! unmodified), rotating daily and keeping 30 days of history, so exceptions/errors
//! can be inspected after the fact (e.g. pasted back for debugging).

use flexi_logger::{Age, Cleanup, Criterion, FileSpec, Logger, Naming};
use std::sync::Once;

static INIT: Once = Once::new();

fn logs_dir() -> std::path::PathBuf {
    #[cfg(target_os = "macos")]
    if let Some(home) = std::env::var_os("HOME") {
        return std::path::PathBuf::from(home).join("Library/Logs/Branchi");
    }
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("logs")
}

/// Initializes the rotating file logger. Safe to call more than once;
/// only the first call takes effect.
pub fn init() {
    INIT.call_once(|| {
        let dir = logs_dir();
        if let Err(err) = std::fs::create_dir_all(&dir) {
            eprintln!(
                "branchi-core: failed to create log directory {}: {err}",
                dir.display()
            );
            return;
        }

        let file_spec = FileSpec::default().directory(dir).basename("branchi-core");

        let logger = Logger::try_with_str("info").and_then(|logger| {
            logger
                .log_to_file(file_spec)
                .rotate(
                    Criterion::Age(Age::Day),
                    Naming::Timestamps,
                    Cleanup::KeepLogFiles(30),
                )
                .start()
        });

        if let Err(err) = logger {
            eprintln!("branchi-core: failed to initialize file logger: {err}");
            return;
        }

        std::panic::set_hook(Box::new(|info| {
            log::error!("panic: {info}");
        }));
    });
}
