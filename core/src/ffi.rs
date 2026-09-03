//! C ABI surface for the core crate, so the Flutter UI can call straight
//! into `git2`-backed logic via `dart:ffi` instead of shelling out to a
//! `git` binary.
//!
//! Every fallible entry point returns a heap-allocated, NUL-terminated
//! UTF-8 error string on failure, or a null pointer on success. Callers
//! MUST pass any non-null returned string to [`branchi_free_string`]
//! exactly once to release it.

use crate::git::{self, GitRepo};
use serde::Serialize;
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

/// Converts a `Result` into a JSON string of the shape
/// `{"ok": <value>}` or `{"error": "<message>"}`. Unlike
/// [`result_to_c_string`] this always returns a non-null pointer, which
/// callers must still free with [`branchi_free_string`].
fn result_to_json_c_string<T: Serialize>(result: anyhow::Result<T>) -> *mut c_char {
    let payload = match result {
        Ok(value) => serde_json::json!({ "ok": value }),
        Err(err) => serde_json::json!({ "error": err.to_string() }),
    };
    let text = serde_json::to_string(&payload)
        .unwrap_or_else(|_| "{\"error\":\"failed to serialize response\"}".to_string());
    CString::new(text)
        .unwrap_or_else(|_| CString::new("{\"error\":\"invalid utf8 in response\"}").unwrap())
        .into_raw()
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
pub unsafe extern "C" fn branchi_init(path: *const c_char) -> *mut c_char {
    let path = c_str_to_string(path);
    result_to_c_string(GitRepo::init(&path))
}

/// Clones `url` into `path`.
///
/// # Safety
/// `url` and `path` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_clone(url: *const c_char, path: *const c_char) -> *mut c_char {
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
pub unsafe extern "C" fn branchi_is_repository(path: *const c_char) -> bool {
    let path = c_str_to_string(path);
    GitRepo::open(&path).is_ok()
}

/// Returns the commit history reachable from HEAD (newest first, at most
/// `limit` entries) as a JSON string: `{"ok": [CommitInfo, ...]}` or
/// `{"error": "..."}`.
///
/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string that outlives the
/// call.
#[no_mangle]
pub unsafe extern "C" fn branchi_log(path: *const c_char, limit: usize) -> *mut c_char {
    let path = c_str_to_string(path);
    let result = GitRepo::open(&path).and_then(|repo| repo.log(limit));
    result_to_json_c_string(result)
}

/// Returns local and remote-tracking branches as a JSON string:
/// `{"ok": [BranchInfo, ...]}` or `{"error": "..."}`.
///
/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string that outlives the
/// call.
#[no_mangle]
pub unsafe extern "C" fn branchi_branches(path: *const c_char) -> *mut c_char {
    let path = c_str_to_string(path);
    let result = GitRepo::open(&path).and_then(|repo| repo.branches());
    result_to_json_c_string(result)
}

/// Returns the file-level diff of `commit_id` against its first parent (or
/// the empty tree, for a root commit) as a JSON string:
/// `{"ok": [DiffFileEntry, ...]}` or `{"error": "..."}`.
///
/// # Safety
/// `path` and `commit_id` must be valid, NUL-terminated UTF-8 C strings
/// that outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_commit_diff(
    path: *const c_char,
    commit_id: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let commit_id = c_str_to_string(commit_id);
    let result = GitRepo::open(&path).and_then(|repo| repo.commit_diff(&commit_id));
    result_to_json_c_string(result)
}

/// Checks out an existing local branch `name` in the repository at `path`.
///
/// # Safety
/// `path` and `name` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_checkout_branch(
    path: *const c_char,
    name: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let name = c_str_to_string(name);
    let result = GitRepo::open(&path).and_then(|repo| repo.checkout_branch(&name));
    result_to_c_string(result)
}

/// Creates a new local branch `name` in the repository at `path`. If `from`
/// is a non-empty string, it must name an existing remote-tracking branch
/// (e.g. `origin/feature`) that the new branch starts at and tracks;
/// otherwise the new branch starts at HEAD. Does not check out the branch.
///
/// # Safety
/// `path`, `name`, and `from` must be valid, NUL-terminated UTF-8 C strings
/// that outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_create_branch(
    path: *const c_char,
    name: *const c_char,
    from: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let name = c_str_to_string(name);
    let from = c_str_to_string(from);
    let from = if from.is_empty() { None } else { Some(from.as_str()) };
    let result = GitRepo::open(&path).and_then(|repo| repo.create_branch(&name, from));
    result_to_c_string(result)
}

/// Deletes branch `name` in the repository at `path`. When `is_remote` is
/// true, `name` must be a remote-tracking branch (e.g. `origin/feature`) and
/// only the local tracking ref is removed, not the branch on the server.
///
/// # Safety
/// `path` and `name` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_delete_branch(
    path: *const c_char,
    name: *const c_char,
    is_remote: bool,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let name = c_str_to_string(name);
    let result = GitRepo::open(&path).and_then(|repo| repo.delete_branch(&name, is_remote));
    result_to_c_string(result)
}

/// Updates branch `name` in the repository at `path`. When `is_remote` is
/// true, `name` must be a remote-tracking branch (e.g. `origin/feature`) and
/// this just fetches its remote. Otherwise `name` is a local branch that is
/// fast-forwarded to its upstream (fetching first); it fails rather than
/// merging if the branch has diverged from its upstream.
///
/// # Safety
/// `path` and `name` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_update_branch(
    path: *const c_char,
    name: *const c_char,
    is_remote: bool,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let name = c_str_to_string(name);
    let result = GitRepo::open(&path).and_then(|repo| {
        if is_remote {
            repo.fetch_remote_for_branch(&name)
        } else {
            repo.update_branch(&name)
        }
    });
    result_to_c_string(result)
}

/// Returns the working-tree/index status of every changed file as a JSON
/// string: `{"ok": [StatusEntry, ...]}` or `{"error": "..."}`.
///
/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string that outlives the
/// call.
#[no_mangle]
pub unsafe extern "C" fn branchi_status(path: *const c_char) -> *mut c_char {
    let path = c_str_to_string(path);
    let result = GitRepo::open(&path).and_then(|repo| repo.status());
    result_to_json_c_string(result)
}

/// Stages `file_path` (equivalent to `git add <file_path>`) in the
/// repository at `path`.
///
/// # Safety
/// `path` and `file_path` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_stage(
    path: *const c_char,
    file_path: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let file_path = c_str_to_string(file_path);
    let result = GitRepo::open(&path).and_then(|repo| repo.stage(&file_path));
    result_to_c_string(result)
}

/// Unstages `file_path` (equivalent to `git reset <file_path>`) in the
/// repository at `path`, leaving the working tree unchanged.
///
/// # Safety
/// `path` and `file_path` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_unstage(
    path: *const c_char,
    file_path: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let file_path = c_str_to_string(file_path);
    let result = GitRepo::open(&path).and_then(|repo| repo.unstage(&file_path));
    result_to_c_string(result)
}

/// Discards working-tree changes to `file_path` in the repository at
/// `path`, restoring it to the version in the index.
///
/// # Safety
/// `path` and `file_path` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_revert_file(
    path: *const c_char,
    file_path: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let file_path = c_str_to_string(file_path);
    let result = GitRepo::open(&path).and_then(|repo| repo.revert_file(&file_path));
    result_to_c_string(result)
}

/// Commits the current index in the repository at `path` with `message`,
/// using the repository's configured `user.name`/`user.email` as both
/// author and committer. Returns the new commit's id as a JSON string:
/// `{"ok": "<commit id>"}` or `{"error": "..."}`.
///
/// # Safety
/// `path` and `message` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_commit(
    path: *const c_char,
    message: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let message = c_str_to_string(message);
    let result =
        GitRepo::open(&path).and_then(|repo| repo.commit_with_configured_identity(&message));
    result_to_json_c_string(result)
}

/// Pushes local branch `name` to its upstream remote in the repository at
/// `path`.
///
/// # Safety
/// `path` and `name` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_push(path: *const c_char, name: *const c_char) -> *mut c_char {
    let path = c_str_to_string(path);
    let name = c_str_to_string(name);
    let result = GitRepo::open(&path).and_then(|repo| repo.push(&name));
    result_to_c_string(result)
}

/// Returns the repository's configured remotes as a JSON string:
/// `{"ok": [RemoteInfo, ...]}` or `{"error": "..."}`.
///
/// # Safety
/// `path` must be a valid, NUL-terminated UTF-8 C string that outlives the
/// call.
#[no_mangle]
pub unsafe extern "C" fn branchi_remotes(path: *const c_char) -> *mut c_char {
    let path = c_str_to_string(path);
    let result = GitRepo::open(&path).and_then(|repo| repo.remotes());
    result_to_json_c_string(result)
}

/// Adds a new remote `name` pointing at `url` in the repository at `path`.
///
/// # Safety
/// `path`, `name`, and `url` must be valid, NUL-terminated UTF-8 C strings
/// that outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_add_remote(
    path: *const c_char,
    name: *const c_char,
    url: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let name = c_str_to_string(name);
    let url = c_str_to_string(url);
    let result = GitRepo::open(&path).and_then(|repo| repo.add_remote(&name, &url));
    result_to_c_string(result)
}

/// Changes the URL of existing remote `name` in the repository at `path`.
///
/// # Safety
/// `path`, `name`, and `url` must be valid, NUL-terminated UTF-8 C strings
/// that outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_set_remote_url(
    path: *const c_char,
    name: *const c_char,
    url: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let name = c_str_to_string(name);
    let url = c_str_to_string(url);
    let result = GitRepo::open(&path).and_then(|repo| repo.set_remote_url(&name, &url));
    result_to_c_string(result)
}

/// Removes remote `name` from the repository at `path`.
///
/// # Safety
/// `path` and `name` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_remove_remote(
    path: *const c_char,
    name: *const c_char,
) -> *mut c_char {
    let path = c_str_to_string(path);
    let name = c_str_to_string(name);
    let result = GitRepo::open(&path).and_then(|repo| repo.remove_remote(&name));
    result_to_c_string(result)
}

/// Returns the `user.name`/`user.email` identity from git's global config
/// as a JSON string: `{"ok": GlobalIdentity}` or `{"error": "..."}`.
#[no_mangle]
pub extern "C" fn branchi_global_config_get() -> *mut c_char {
    result_to_json_c_string(git::global_identity())
}

/// Writes `name`/`email` into git's global config. Either may be an empty
/// string to leave that field unset.
///
/// # Safety
/// `name` and `email` must be valid, NUL-terminated UTF-8 C strings that
/// outlive the call.
#[no_mangle]
pub unsafe extern "C" fn branchi_global_config_set(
    name: *const c_char,
    email: *const c_char,
) -> *mut c_char {
    let name = c_str_to_string(name);
    let email = c_str_to_string(email);
    result_to_c_string(git::set_global_identity(&name, &email))
}

/// Releases a string previously returned by one of this module's
/// functions. Safe to call with a null pointer (no-op).
///
/// # Safety
/// `ptr` must either be null or a pointer previously returned by a
/// function in this module, not already freed.
#[no_mangle]
pub unsafe extern "C" fn branchi_free_string(ptr: *mut c_char) {
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

        let err = unsafe { branchi_init(path.as_ptr()) };
        assert!(err.is_null());

        let is_repo = unsafe { branchi_is_repository(path.as_ptr()) };
        assert!(is_repo);
    }

    #[test]
    fn init_reports_failure_as_error_string() {
        // A file, not a directory, is not a valid repo root.
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("not-a-dir");
        std::fs::write(&file_path, "x").unwrap();
        let path = CString::new(file_path.to_str().unwrap()).unwrap();

        let err = unsafe { branchi_init(path.as_ptr()) };
        assert!(!err.is_null());
        unsafe { branchi_free_string(err) };
    }
}
