import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

/// Thrown by [GitFfi]'s JSON-returning calls (log/branches/commitDiff) when
/// the underlying git operation fails.
class GitFfiException implements Exception {
  GitFfiException(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef _InitLoggingNative = Void Function();
typedef _InitLoggingDart = void Function();

typedef _InitNative = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef _InitDart = Pointer<Utf8> Function(Pointer<Utf8> path);

typedef _CloneNative = Pointer<Utf8> Function(
  Pointer<Utf8> url,
  Pointer<Utf8> path,
);
typedef _CloneDart = Pointer<Utf8> Function(
  Pointer<Utf8> url,
  Pointer<Utf8> path,
);

typedef _IsRepositoryNative = Bool Function(Pointer<Utf8> path);
typedef _IsRepositoryDart = bool Function(Pointer<Utf8> path);

typedef _LogNative = Pointer<Utf8> Function(Pointer<Utf8> path, IntPtr limit);
typedef _LogDart = Pointer<Utf8> Function(Pointer<Utf8> path, int limit);

typedef _BranchesNative = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef _BranchesDart = Pointer<Utf8> Function(Pointer<Utf8> path);

typedef _CommitDiffNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> commitId,
);
typedef _CommitDiffDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> commitId,
);

typedef _CheckoutBranchNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
);
typedef _CheckoutBranchDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
);

typedef _CreateBranchNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  Pointer<Utf8> from,
);
typedef _CreateBranchDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  Pointer<Utf8> from,
);

typedef _DeleteBranchNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  Bool isRemote,
);
typedef _DeleteBranchDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  bool isRemote,
);

typedef _UpdateBranchNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  Bool isRemote,
);
typedef _UpdateBranchDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  bool isRemote,
);

typedef _StatusNative = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef _StatusDart = Pointer<Utf8> Function(Pointer<Utf8> path);

typedef _StageNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> filePath,
);
typedef _StageDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> filePath,
);

typedef _UnstageNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> filePath,
);
typedef _UnstageDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> filePath,
);

typedef _RevertFileNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> filePath,
);
typedef _RevertFileDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> filePath,
);

typedef _CommitNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> message,
);
typedef _CommitDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> message,
);

typedef _PushNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
);
typedef _PushDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
);

typedef _RemotesNative = Pointer<Utf8> Function(Pointer<Utf8> path);
typedef _RemotesDart = Pointer<Utf8> Function(Pointer<Utf8> path);

typedef _AddRemoteNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  Pointer<Utf8> url,
);
typedef _AddRemoteDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  Pointer<Utf8> url,
);

typedef _SetRemoteUrlNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  Pointer<Utf8> url,
);
typedef _SetRemoteUrlDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
  Pointer<Utf8> url,
);

typedef _RemoveRemoteNative = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
);
typedef _RemoveRemoteDart = Pointer<Utf8> Function(
  Pointer<Utf8> path,
  Pointer<Utf8> name,
);

typedef _GlobalConfigGetNative = Pointer<Utf8> Function();
typedef _GlobalConfigGetDart = Pointer<Utf8> Function();

typedef _GlobalConfigSetNative = Pointer<Utf8> Function(
  Pointer<Utf8> name,
  Pointer<Utf8> email,
);
typedef _GlobalConfigSetDart = Pointer<Utf8> Function(
  Pointer<Utf8> name,
  Pointer<Utf8> email,
);

typedef _FreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeStringDart = void Function(Pointer<Utf8> ptr);

/// Loads the `branchi_core` cdylib and exposes its C ABI (see
/// `core/src/ffi.rs`) as typed Dart functions.
///
/// This is a hand-written binding rather than a generated one (e.g. via
/// `flutter_rust_bridge`) to keep the surface small and explicit; if the
/// bridged surface grows much beyond init/clone/open, switch to codegen.
class GitFfi {
  GitFfi._(DynamicLibrary lib)
      : _initLogging = lib.lookupFunction<_InitLoggingNative,
            _InitLoggingDart>('branchi_init_logging'),
        _init = lib.lookupFunction<_InitNative, _InitDart>('branchi_init'),
        _clone =
            lib.lookupFunction<_CloneNative, _CloneDart>('branchi_clone'),
        _isRepository = lib.lookupFunction<_IsRepositoryNative,
            _IsRepositoryDart>('branchi_is_repository'),
        _log = lib.lookupFunction<_LogNative, _LogDart>('branchi_log'),
        _branches = lib.lookupFunction<_BranchesNative, _BranchesDart>(
          'branchi_branches',
        ),
        _commitDiff =
            lib.lookupFunction<_CommitDiffNative, _CommitDiffDart>(
          'branchi_commit_diff',
        ),
        _checkoutBranch =
            lib.lookupFunction<_CheckoutBranchNative, _CheckoutBranchDart>(
          'branchi_checkout_branch',
        ),
        _createBranch =
            lib.lookupFunction<_CreateBranchNative, _CreateBranchDart>(
          'branchi_create_branch',
        ),
        _deleteBranch =
            lib.lookupFunction<_DeleteBranchNative, _DeleteBranchDart>(
          'branchi_delete_branch',
        ),
        _updateBranch =
            lib.lookupFunction<_UpdateBranchNative, _UpdateBranchDart>(
          'branchi_update_branch',
        ),
        _status =
            lib.lookupFunction<_StatusNative, _StatusDart>('branchi_status'),
        _stage =
            lib.lookupFunction<_StageNative, _StageDart>('branchi_stage'),
        _unstage = lib.lookupFunction<_UnstageNative, _UnstageDart>(
          'branchi_unstage',
        ),
        _revertFile =
            lib.lookupFunction<_RevertFileNative, _RevertFileDart>(
          'branchi_revert_file',
        ),
        _commit =
            lib.lookupFunction<_CommitNative, _CommitDart>('branchi_commit'),
        _push = lib.lookupFunction<_PushNative, _PushDart>('branchi_push'),
        _remotes = lib.lookupFunction<_RemotesNative, _RemotesDart>(
          'branchi_remotes',
        ),
        _addRemote = lib.lookupFunction<_AddRemoteNative, _AddRemoteDart>(
          'branchi_add_remote',
        ),
        _setRemoteUrl =
            lib.lookupFunction<_SetRemoteUrlNative, _SetRemoteUrlDart>(
          'branchi_set_remote_url',
        ),
        _removeRemote =
            lib.lookupFunction<_RemoveRemoteNative, _RemoveRemoteDart>(
          'branchi_remove_remote',
        ),
        _globalConfigGet = lib.lookupFunction<_GlobalConfigGetNative,
            _GlobalConfigGetDart>('branchi_global_config_get'),
        _globalConfigSet = lib.lookupFunction<_GlobalConfigSetNative,
            _GlobalConfigSetDart>('branchi_global_config_set'),
        _freeString = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'branchi_free_string',
        );

  static GitFfi? _instance;

  /// Paths tried by the most recent [instanceOrNull] lookup that didn't
  /// already have a cached instance. Populated even on success, so a
  /// caller can report exactly where it looked when diagnosing a failure.
  static List<String> lastAttemptedPaths = const [];

  /// The loaded binding, or null if the native library couldn't be found
  /// (e.g. it hasn't been built yet during development).
  static GitFfi? get instanceOrNull {
    if (_instance != null) return _instance;
    final lib = _tryLoadLibrary();
    if (lib == null) return null;
    final instance = GitFfi._(lib);
    instance._initLogging();
    return _instance = instance;
  }

  final _InitLoggingDart _initLogging;
  final _InitDart _init;
  final _CloneDart _clone;
  final _IsRepositoryDart _isRepository;
  final _LogDart _log;
  final _BranchesDart _branches;
  final _CommitDiffDart _commitDiff;
  final _CheckoutBranchDart _checkoutBranch;
  final _CreateBranchDart _createBranch;
  final _DeleteBranchDart _deleteBranch;
  final _UpdateBranchDart _updateBranch;
  final _StatusDart _status;
  final _StageDart _stage;
  final _UnstageDart _unstage;
  final _RevertFileDart _revertFile;
  final _CommitDart _commit;
  final _PushDart _push;
  final _RemotesDart _remotes;
  final _AddRemoteDart _addRemote;
  final _SetRemoteUrlDart _setRemoteUrl;
  final _RemoveRemoteDart _removeRemote;
  final _GlobalConfigGetDart _globalConfigGet;
  final _GlobalConfigSetDart _globalConfigSet;
  final _FreeStringDart _freeString;

  /// Runs `git init` at [path] via the Rust core. Returns null on success,
  /// or an error message on failure.
  String? init(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      final errPtr = _init(pathPtr);
      return _consumeError(errPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Clones [url] into [path] via the Rust core. Returns null on success,
  /// or an error message on failure.
  String? clone(String url, String path) {
    final urlPtr = url.toNativeUtf8();
    final pathPtr = path.toNativeUtf8();
    try {
      final errPtr = _clone(urlPtr, pathPtr);
      return _consumeError(errPtr);
    } finally {
      malloc.free(urlPtr);
      malloc.free(pathPtr);
    }
  }

  /// Whether [path] is the root of an openable git repository.
  bool isRepository(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _isRepository(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  String? _consumeError(Pointer<Utf8> errPtr) {
    if (errPtr == nullptr) return null;
    final message = errPtr.toDartString();
    _freeString(errPtr);
    return message;
  }

  /// Commit history reachable from HEAD (newest first, at most [limit]
  /// entries), as raw decoded JSON list entries. Throws a [GitFfiException]
  /// on failure.
  List<dynamic> log(String path, int limit) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _consumeJsonList(_log(pathPtr, limit));
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Local and remote-tracking branches, as raw decoded JSON list entries.
  /// Throws a [GitFfiException] on failure.
  List<dynamic> branches(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _consumeJsonList(_branches(pathPtr));
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// The file-level diff of [commitId] against its first parent, as raw
  /// decoded JSON list entries. Throws a [GitFfiException] on failure.
  List<dynamic> commitDiff(String path, String commitId) {
    final pathPtr = path.toNativeUtf8();
    final commitIdPtr = commitId.toNativeUtf8();
    try {
      return _consumeJsonList(_commitDiff(pathPtr, commitIdPtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(commitIdPtr);
    }
  }

  /// Checks out local branch [name]. Returns null on success, or an error
  /// message on failure.
  String? checkoutBranch(String path, String name) {
    final pathPtr = path.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      return _consumeError(_checkoutBranch(pathPtr, namePtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(namePtr);
    }
  }

  /// Creates local branch [name], starting from and tracking [from] (a
  /// remote-tracking branch like `origin/feature`) if given, or from HEAD
  /// otherwise. Returns null on success, or an error message on failure.
  String? createBranch(String path, String name, {String? from}) {
    final pathPtr = path.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    final fromPtr = (from ?? '').toNativeUtf8();
    try {
      return _consumeError(_createBranch(pathPtr, namePtr, fromPtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(namePtr);
      malloc.free(fromPtr);
    }
  }

  /// Deletes branch [name] ([isRemote] selects a remote-tracking branch, in
  /// which case only the local tracking ref is removed). Returns null on
  /// success, or an error message on failure.
  String? deleteBranch(String path, String name, {required bool isRemote}) {
    final pathPtr = path.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      return _consumeError(_deleteBranch(pathPtr, namePtr, isRemote));
    } finally {
      malloc.free(pathPtr);
      malloc.free(namePtr);
    }
  }

  /// Updates branch [name]: fetches its remote, and if it's a local branch,
  /// fast-forwards it to the fetched upstream. Returns null on success, or
  /// an error message on failure.
  String? updateBranch(String path, String name, {required bool isRemote}) {
    final pathPtr = path.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      return _consumeError(_updateBranch(pathPtr, namePtr, isRemote));
    } finally {
      malloc.free(pathPtr);
      malloc.free(namePtr);
    }
  }

  /// Working-tree/index status of every changed file, as raw decoded JSON
  /// list entries. Throws a [GitFfiException] on failure.
  List<dynamic> status(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _consumeJsonList(_status(pathPtr));
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Stages [filePath]. Returns null on success, or an error message on
  /// failure.
  String? stage(String path, String filePath) {
    final pathPtr = path.toNativeUtf8();
    final filePathPtr = filePath.toNativeUtf8();
    try {
      return _consumeError(_stage(pathPtr, filePathPtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(filePathPtr);
    }
  }

  /// Unstages [filePath], leaving the working tree unchanged. Returns null
  /// on success, or an error message on failure.
  String? unstage(String path, String filePath) {
    final pathPtr = path.toNativeUtf8();
    final filePathPtr = filePath.toNativeUtf8();
    try {
      return _consumeError(_unstage(pathPtr, filePathPtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(filePathPtr);
    }
  }

  /// Discards working-tree changes to [filePath]. Returns null on success,
  /// or an error message on failure.
  String? revertFile(String path, String filePath) {
    final pathPtr = path.toNativeUtf8();
    final filePathPtr = filePath.toNativeUtf8();
    try {
      return _consumeError(_revertFile(pathPtr, filePathPtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(filePathPtr);
    }
  }

  /// Commits the current index with [message], using the repository's
  /// configured `user.name`/`user.email`. Returns the new commit id. Throws
  /// a [GitFfiException] on failure.
  String commit(String path, String message) {
    final pathPtr = path.toNativeUtf8();
    final messagePtr = message.toNativeUtf8();
    try {
      return _consumeJsonString(_commit(pathPtr, messagePtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(messagePtr);
    }
  }

  /// Pushes local branch [name] to its upstream remote. Returns null on
  /// success, or an error message on failure.
  String? push(String path, String name) {
    final pathPtr = path.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      return _consumeError(_push(pathPtr, namePtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(namePtr);
    }
  }

  /// This repository's configured remotes, as raw decoded JSON list
  /// entries. Throws a [GitFfiException] on failure.
  List<dynamic> remotes(String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _consumeJsonList(_remotes(pathPtr));
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Adds a new remote [name] pointing at [url]. Returns null on success,
  /// or an error message on failure.
  String? addRemote(String path, String name, String url) {
    final pathPtr = path.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    final urlPtr = url.toNativeUtf8();
    try {
      return _consumeError(_addRemote(pathPtr, namePtr, urlPtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(namePtr);
      malloc.free(urlPtr);
    }
  }

  /// Changes the URL of existing remote [name]. Returns null on success, or
  /// an error message on failure.
  String? setRemoteUrl(String path, String name, String url) {
    final pathPtr = path.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    final urlPtr = url.toNativeUtf8();
    try {
      return _consumeError(_setRemoteUrl(pathPtr, namePtr, urlPtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(namePtr);
      malloc.free(urlPtr);
    }
  }

  /// Removes remote [name]. Returns null on success, or an error message on
  /// failure.
  String? removeRemote(String path, String name) {
    final pathPtr = path.toNativeUtf8();
    final namePtr = name.toNativeUtf8();
    try {
      return _consumeError(_removeRemote(pathPtr, namePtr));
    } finally {
      malloc.free(pathPtr);
      malloc.free(namePtr);
    }
  }

  /// The `user.name`/`user.email` identity from git's global config, as a
  /// raw decoded JSON map (`name`/`email` may be null). Throws a
  /// [GitFfiException] on failure.
  Map<String, dynamic> globalConfigGet() {
    return _consumeJsonMap(_globalConfigGet());
  }

  /// Writes [name]/[email] into git's global config. Pass an empty string
  /// to leave a field unset. Returns null on success, or an error message
  /// on failure.
  String? globalConfigSet(String name, String email) {
    final namePtr = name.toNativeUtf8();
    final emailPtr = email.toNativeUtf8();
    try {
      return _consumeError(_globalConfigSet(namePtr, emailPtr));
    } finally {
      malloc.free(namePtr);
      malloc.free(emailPtr);
    }
  }

  /// Decodes a `{"ok": [...]}` / `{"error": "..."}` response, freeing the
  /// native string in the process.
  List<dynamic> _consumeJsonList(Pointer<Utf8> resultPtr) {
    final text = resultPtr.toDartString();
    _freeString(resultPtr);

    final decoded = jsonDecode(text) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      throw GitFfiException(decoded['error'] as String);
    }
    return decoded['ok'] as List<dynamic>;
  }

  /// Decodes a `{"ok": <string>}` / `{"error": "..."}` response, freeing the
  /// native string in the process.
  String _consumeJsonString(Pointer<Utf8> resultPtr) {
    final text = resultPtr.toDartString();
    _freeString(resultPtr);

    final decoded = jsonDecode(text) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      throw GitFfiException(decoded['error'] as String);
    }
    return decoded['ok'] as String;
  }

  /// Decodes a `{"ok": {...}}` / `{"error": "..."}` response, freeing the
  /// native string in the process.
  Map<String, dynamic> _consumeJsonMap(Pointer<Utf8> resultPtr) {
    final text = resultPtr.toDartString();
    _freeString(resultPtr);

    final decoded = jsonDecode(text) as Map<String, dynamic>;
    if (decoded.containsKey('error')) {
      throw GitFfiException(decoded['error'] as String);
    }
    return decoded['ok'] as Map<String, dynamic>;
  }

  static DynamicLibrary? _tryLoadLibrary() {
    final tried = <String>[];
    for (final candidate in _candidatePaths()) {
      tried.add(candidate);
      try {
        final lib = DynamicLibrary.open(candidate);
        lastAttemptedPaths = tried;
        return lib;
      } on ArgumentError {
        continue;
      }
    }
    lastAttemptedPaths = tried;
    return null;
  }

  /// Library names/locations to try, in order. In a packaged app the
  /// native library ships alongside the executable (wired up by the
  /// platform build, e.g. CMakeLists.txt / Podfile); during `flutter run`
  /// from this repo it instead lives in the cargo workspace's shared
  /// `target/<profile>/` directory (this crate is a workspace member, not
  /// a standalone one, so the output isn't under `core/target/`).
  ///
  /// The process's working directory during `flutter run` is not
  /// necessarily the `flutter/` source directory: on Windows/Linux desktop
  /// it's typically the build output directory (e.g.
  /// `build/windows/x64/runner/Debug`), an unpredictable number of levels
  /// below the repo root. So rather than guessing a fixed number of `..`
  /// segments, walk upward from both the current directory and the
  /// executable's directory looking for `target/<profile>/<libName>`.
  static Iterable<String> _candidatePaths() sync* {
    final libName = Platform.isWindows
        ? 'branchi_core.dll'
        : Platform.isMacOS
            ? 'libbranchi_core.dylib'
            : 'libbranchi_core.so';

    yield libName;

    final searchRoots = <String>{
      Directory.current.path,
      p.dirname(Platform.resolvedExecutable),
    };

    for (final root in searchRoots) {
      for (final profile in ['debug', 'release']) {
        yield* _ancestorCandidates(root, profile, libName);
      }
    }
  }

  /// `root`, `root/..`, `root/../..`, ... up to a reasonable depth, each
  /// joined with `target/<profile>/<libName>`.
  static Iterable<String> _ancestorCandidates(
    String root,
    String profile,
    String libName,
  ) sync* {
    var dir = p.normalize(root);
    for (var i = 0; i < 10; i++) {
      yield p.join(dir, 'target', profile, libName);
      final parent = p.dirname(dir);
      if (parent == dir) break;
      dir = parent;
    }
  }
}
