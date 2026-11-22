import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../logs/action_log.dart';
import '../repo/git_ffi.dart';

/// Thrown when a file explorer operation can't be done; [message] is
/// meant for the user.
class FileOpException implements Exception {
  FileOpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What was last cut or copied in the file explorer.
class FileClipboardEntry {
  const FileClipboardEntry(this.path, {required this.isCut});

  final String path;
  final bool isCut;
}

/// The file explorer's own clipboard (separate from the system clipboard),
/// shared by every open repository tab.
final ValueNotifier<FileClipboardEntry?> fileClipboard = ValueNotifier(null);

/// Copy, move, rename and trash for the file explorer.
class FileOps {
  FileOps._();

  /// Whether [path] is [parent] itself or somewhere inside it.
  static bool isSameOrWithin(String parent, String path) =>
      p.equals(parent, path) || p.isWithin(parent, path);

  /// A path in [dir] named like [name] that doesn't exist yet: [name]
  /// itself, else "name copy.ext", "name copy 2.ext", ...
  static String uniqueDestination(String dir, String name, {bool isDir = false}) {
    String candidate(String n) => p.join(dir, n);
    if (!_exists(candidate(name))) return candidate(name);

    // Dotfiles like ".env" have no extension to keep at the end.
    final ext = isDir || name.startsWith('.') && !name.substring(1).contains('.')
        ? ''
        : p.extension(name);
    final stem = name.substring(0, name.length - ext.length);
    for (var i = 1;; i++) {
      final suffix = i == 1 ? ' copy' : ' copy $i';
      final path = candidate('$stem$suffix$ext');
      if (!_exists(path)) return path;
    }
  }

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  /// Pastes [entry] into [targetDir]: copies it, or moves it for a cut.
  /// Returns the new path.
  static Future<String> paste(FileClipboardEntry entry, String targetDir) async {
    final src = p.normalize(entry.path);
    final type = FileSystemEntity.typeSync(src, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileOpException('${p.basename(src)} no longer exists.');
    }
    final isDir = type == FileSystemEntityType.directory;
    if (isDir && isSameOrWithin(src, targetDir)) {
      throw FileOpException(
        "Can't paste ${p.basename(src)} into itself.",
      );
    }

    // Cutting and pasting into the same folder changes nothing.
    if (entry.isCut && p.equals(p.dirname(src), targetDir)) return src;

    final dest = uniqueDestination(targetDir, p.basename(src), isDir: isDir);
    try {
      if (entry.isCut) {
        await _move(src, dest, type);
      } else {
        await _copy(src, dest, type);
      }
      ActionLog.instance.record(
        '${entry.isCut ? 'move' : 'copy'} $src -> $dest',
        success: true,
      );
      return dest;
    } on FileSystemException catch (error) {
      ActionLog.instance.record(
        '${entry.isCut ? 'move' : 'copy'} $src -> $dest',
        success: false,
        detail: error.toString(),
      );
      throw FileOpException(
        'Failed to ${entry.isCut ? 'move' : 'copy'} ${p.basename(src)}: '
        '${error.osError?.message ?? error.message}',
      );
    }
  }

  static Future<void> _move(
    String src,
    String dest,
    FileSystemEntityType type,
  ) async {
    try {
      // Same drive: an instant rename.
      await _entity(src, type).rename(dest);
    } on FileSystemException {
      // Across drives a rename fails; copy, then remove the original.
      await _copy(src, dest, type);
      await _entity(src, type).delete(recursive: true);
    }
  }

  static FileSystemEntity _entity(String path, FileSystemEntityType type) =>
      switch (type) {
        FileSystemEntityType.directory => Directory(path),
        FileSystemEntityType.link => Link(path),
        _ => File(path),
      };

  /// Copies a file, link or whole folder. Uses async IO throughout so a
  /// large folder doesn't freeze the UI.
  static Future<void> _copy(
    String src,
    String dest,
    FileSystemEntityType type,
  ) async {
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(dest).create();
        await for (final child in Directory(src).list(followLinks: false)) {
          final childType =
              await FileSystemEntity.type(child.path, followLinks: false);
          await _copy(
            child.path,
            p.join(dest, p.basename(child.path)),
            childType,
          );
        }
      case FileSystemEntityType.link:
        await Link(dest).create(await Link(src).target());
      default:
        await File(src).copy(dest);
    }
  }

  /// Checks [newName] as a new name for [path]; returns an error message,
  /// or null when it's fine.
  static String? validateNewName(String path, String newName) {
    final name = newName.trim();
    if (name.isEmpty) return 'A name is required.';
    if (name == '.' || name == '..') return 'That name is not allowed.';
    if (name.contains('/') || name.contains(r'\')) {
      return 'A name cannot contain / or \\.';
    }
    if (Platform.isWindows && RegExp(r'[<>:"|?*]').hasMatch(name)) {
      return r'A name cannot contain < > : " | ? *';
    }
    final dest = p.join(p.dirname(path), name);
    // Changing only the letter case is a valid rename even on
    // case-insensitive filesystems, where `dest` "exists" already.
    final caseOnly = dest.toLowerCase() == path.toLowerCase();
    if (!caseOnly && _exists(dest)) return '$name already exists here.';
    return null;
  }

  /// Renames [path] to [newName] in the same folder. Returns the new path.
  static Future<String> rename(String path, String newName) async {
    final name = newName.trim();
    final error = validateNewName(path, name);
    if (error != null) throw FileOpException(error);
    final dest = p.join(p.dirname(path), name);
    if (dest == path) return path;
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    try {
      await _entity(path, type).rename(dest);
      ActionLog.instance.record('rename $path -> $dest', success: true);
      return dest;
    } on FileSystemException catch (error) {
      ActionLog.instance.record(
        'rename $path -> $dest',
        success: false,
        detail: error.toString(),
      );
      throw FileOpException(
        'Failed to rename ${p.basename(path)}: '
        '${error.osError?.message ?? error.message}',
      );
    }
  }

  /// Moves [path] to the OS trash / Recycle Bin.
  static Future<void> moveToTrash(String path) async {
    final ffi = GitFfi.instanceOrNull;
    if (ffi == null) {
      throw FileOpException(
        'Moving to the trash needs the Branchi core library, which was not found.',
      );
    }
    final error = await Isolate.run(() => ffi.moveToTrash(path));
    ActionLog.instance.record(
      'move to trash $path',
      success: error == null,
      detail: error,
    );
    if (error != null) throw FileOpException(error);
  }
}
