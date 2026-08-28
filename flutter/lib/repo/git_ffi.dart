import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

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
        _freeString = lib.lookupFunction<_FreeStringNative, _FreeStringDart>(
          'rustgit_free_string',
        );

  static GitFfi? _instance;

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

  static DynamicLibrary? _tryLoadLibrary() {
    for (final candidate in _candidatePaths()) {
      try {
        return DynamicLibrary.open(candidate);
      } on ArgumentError {
        continue;
      }
    }
    return null;
  }

  /// Library names/locations to try, in order. In a packaged app the
  /// native library ships alongside the executable (wired up by the
  /// platform build, e.g. CMakeLists.txt / Podfile); during `flutter run`
  /// from this repo it instead lives in the cargo workspace's shared
  /// `target/<profile>/` directory (this crate is a workspace member, not
  /// a standalone one, so the output isn't under `core/target/`).
  static Iterable<String> _candidatePaths() sync* {
    final libName = Platform.isWindows
        ? 'rustgit_core.dll'
        : Platform.isMacOS
            ? 'librustgit_core.dylib'
            : 'librustgit_core.so';

    yield libName;

    for (final profile in ['debug', 'release']) {
      yield p.normalize(
        p.join(Directory.current.path, '..', 'target', profile, libName),
      );
      yield p.normalize(
        p.join(
          p.dirname(Platform.script.toFilePath()),
          '..',
          '..',
          'target',
          profile,
          libName,
        ),
      );
    }
  }
}
