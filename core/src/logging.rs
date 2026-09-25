//! File logging for the core crate.
//!
//! Writes to `logs/branchi-core.log` next to the running executable,
//! rotating daily and keeping 30 days of history, so exceptions/errors
//! can be inspected after the fact (e.g. pasted back for debugging).

use flexi_logger::{Age, Cleanup, Criterion, FileSpec, Logger, Naming};
use std::sync::Once;

static INIT: Once = Once::new();

fn logs_dir() -> std::path::PathBuf {
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
        let file_spec = FileSpec::default()
            .directory(logs_dir())
            .basename("branchi-core");

        let logger = Logger::try_with_str("info")
            .and_then(|logger| {
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
