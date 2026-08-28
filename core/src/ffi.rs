//! C ABI surface for the core crate, so the Flutter UI can call straight
//! into `git2`-backed logic via `dart:ffi` instead of shelling out to a
//! `git` binary.
//!
//! Every fallible entry point returns a heap-allocated, NUL-terminated
//! UTF-8 error string on failure, or a null pointer on success. Callers
//! MUST pass any non-null returned string to [`rustgit_free_string`]
//! exactly once to release it.

use crate::git::GitRepo;
use std::ffi::{c_char, CStr, CString};

/// Converts a `Result` into the null-on-success / error-string-on-failure
/// convention used across this FFI surface.
fn result_to_c_string<T>(result: anyhow::Result<T>) -> *mut c_char {
    match result {
        Ok(_) => std::ptr::null_mut(),
        Err(err) => CString::new(err.to_string())
            .unwrap_or_else(|_| CString::new("unknown error").unwrap())
            .into_raw(),
    }
}

/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string.
unsafe fn c_str_to_string(ptr: *const c_char) -> String {
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

/// Initializes a new git repository at `path`.
///
/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string that outlives the
/// call.
#[no_mangle]
pub unsafe extern "C" fn rustgit_init(path: *const c_char) -> *mut c_char {
    let path = c_str_to_string(path);
    result_to_c_string(GitRepo::init(&path))
}

/// Clones `url` into `path`.
///
/// # Safety
/// `url` and `path` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn rustgit_clone(url: *const c_char, path: *const c_char) -> *mut c_char {
    let url = c_str_to_string(url);
    let path = c_str_to_string(path);
    result_to_c_string(GitRepo::clone(&url, &path))
}

/// Returns `true` if `path` is the root of a git repository that can be
/// opened.
///
/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string that outlives the
/// call.
#[no_mangle]
pub unsafe extern "C" fn rustgit_is_repository(path: *const c_char) -> bool {
    let path = c_str_to_string(path);
    GitRepo::open(&path).is_ok()
}

/// Releases a string previously returned by one of this module's
/// functions. Safe to call with a null pointer (no-op).
///
/// # Safety
/// `ptr` must either be null or a pointer previously returned by a
/// function in this module, not already freed.
#[no_mangle]
pub unsafe extern "C" fn rustgit_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    drop(CString::from_raw(ptr));
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn init_reports_success_as_null() {
        let dir = tempfile::tempdir().unwrap();
        let path = CString::new(dir.path().to_str().unwrap()).unwrap();

        let err = unsafe { rustgit_init(path.as_ptr()) };
        assert!(err.is_null());

        let is_repo = unsafe { rustgit_is_repository(path.as_ptr()) };
        assert!(is_repo);
    }

    #[test]
    fn init_reports_failure_as_error_string() {
        // A file, not a directory, is not a valid repo root.
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("not-a-dir");
        std::fs::write(&file_path, "x").unwrap();
        let path = CString::new(file_path.to_str().unwrap()).unwrap();

        let err = unsafe { rustgit_init(path.as_ptr()) };
        assert!(!err.is_null());
        unsafe { rustgit_free_string(err) };
    }
}
