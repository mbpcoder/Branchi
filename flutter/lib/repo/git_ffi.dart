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

typedef _FreeStringNative = Void Function(Pointer<Utf8> ptr);
typedef _FreeStringDart = void Function(Pointer<Utf8> ptr);

/// Loads the `rustgit_core` cdylib and exposes its C ABI (see
/// `core/src/ffi.rs`) as typed Dart functions.
///
/// This is a hand-written binding rather than a generated one (e.g. via
/// `flutter_rust_bridge`) to keep the surface small and explicit; if the
/// bridged surface grows much beyond init/clone/open, switch to codegen.
class GitFfi {
  GitFfi._(DynamicLibrary lib)
      : _init = lib.lookupFunction<_InitNative, _InitDart>('rustgit_init'),
        _clone =
            lib.lookupFunction<_CloneNative, _CloneDart>('rustgit_clone'),
        _isRepository = lib.lookupFunction<_IsRepositoryNative,
            _IsRepositoryDart>('rustgit_is_repository'),
        _log = lib.lookupFunction<_LogNative, _LogDart>('rustgit_log'),
        _branches = lib.lookupFunction<_BranchesNative, _BranchesDart>(
          'rustgit_branches',
        ),
        _commitDiff =
            lib.lookupFunction<_CommitDiffNative, _CommitDiffDart>(
          'rustgit_commit_diff',
        ),
        _freeString = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'rustgit_free_string',
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
    return _instance = GitFfi._(lib);
  }

  final _InitDart _init;
  final _CloneDart _clone;
  final _IsRepositoryDart _isRepository;
  final _LogDart _log;
  final _BranchesDart _branches;
  final _CommitDiffDart _commitDiff;
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
        ? 'rustgit_core.dll'
        : Platform.isMacOS
            ? 'librustgit_core.dylib'
            : 'librustgit_core.so';

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
