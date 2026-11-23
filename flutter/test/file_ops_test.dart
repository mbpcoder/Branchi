import 'dart:io';

import 'package:branchi/code/file_languages.dart';
import 'package:branchi/code/file_search_dialog.dart';
import 'package:branchi/code/file_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('branchi_ops_'));
  tearDown(() => root.deleteSync(recursive: true));

  String path(String rel) => p.join(root.path, rel);
  void write(String rel, [String text = 'x']) {
    File(path(rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  group('uniqueDestination', () {
    test('keeps the name when free, else adds " copy", " copy 2"', () {
      expect(FileOps.uniqueDestination(root.path, 'a.txt'), path('a.txt'));
      write('a.txt');
      expect(FileOps.uniqueDestination(root.path, 'a.txt'), path('a copy.txt'));
      write('a copy.txt');
      expect(
        FileOps.uniqueDestination(root.path, 'a.txt'),
        path('a copy 2.txt'),
      );
    });

    test('dotfiles and folders keep the suffix at the end', () {
      write('.env');
      expect(FileOps.uniqueDestination(root.path, '.env'), path('.env copy'));
      Directory(path('src.v1')).createSync();
      expect(
        FileOps.uniqueDestination(root.path, 'src.v1', isDir: true),
        path('src.v1 copy'),
      );
    });
  });

  group('paste', () {
    test('copies a folder recursively into another folder', () async {
      write('src/a.txt', 'A');
      write('src/sub/b.txt', 'B');
      Directory(path('dest')).createSync();
      final result = await FileOps.paste(
        FileClipboardEntry(path('src'), isCut: false),
        path('dest'),
      );
      expect(result, path('dest/src'));
      expect(File(path('dest/src/sub/b.txt')).readAsStringSync(), 'B');
      expect(File(path('src/a.txt')).existsSync(), isTrue);
    });

    test('copying into the same folder makes a copy', () async {
      write('a.txt');
      final result = await FileOps.paste(
        FileClipboardEntry(path('a.txt'), isCut: false),
        root.path,
      );
      expect(result, path('a copy.txt'));
    });

    test('cut moves the item', () async {
      write('a.txt', 'A');
      Directory(path('dest')).createSync();
      final result = await FileOps.paste(
        FileClipboardEntry(path('a.txt'), isCut: true),
        path('dest'),
      );
      expect(result, path('dest/a.txt'));
      expect(File(path('a.txt')).existsSync(), isFalse);
      expect(File(result).readAsStringSync(), 'A');
    });

    test('cut into its own folder is a no-op', () async {
      write('a.txt');
      final result = await FileOps.paste(
        FileClipboardEntry(path('a.txt'), isCut: true),
        root.path,
      );
      expect(result, path('a.txt'));
      expect(File(path('a.txt')).existsSync(), isTrue);
    });

    test('refuses to paste a folder into itself', () async {
      write('src/a.txt');
      expect(
        () => FileOps.paste(
          FileClipboardEntry(path('src'), isCut: false),
          path('src'),
        ),
        throwsA(isA<FileOpException>()),
      );
    });
  });

  group('rename', () {
    test('renames and rejects bad or taken names', () async {
      write('a.txt');
      write('b.txt');
      expect(FileOps.validateNewName(path('a.txt'), ''), isNotNull);
      expect(FileOps.validateNewName(path('a.txt'), 'x/y'), isNotNull);
      expect(FileOps.validateNewName(path('a.txt'), 'b.txt'), isNotNull);
      expect(FileOps.validateNewName(path('a.txt'), 'A.txt'), isNull);
      final result = await FileOps.rename(path('a.txt'), 'c.txt');
      expect(result, path('c.txt'));
      expect(File(path('c.txt')).existsSync(), isTrue);
    });
  });

  group('detectFileLanguage', () {
    test('uses exact file names before extensions', () {
      expect(detectFileLanguage('/x/composer.lock')?.grammar, 'json');
      expect(detectFileLanguage('/x/yarn.lock'), isNull);
      expect(detectFileLanguage('/x/Dockerfile')?.grammar, 'dockerfile');
      expect(detectFileLanguage('/x/artisan')?.grammar, 'php');
      expect(detectFileLanguage('/x/a.blade.php')?.label, 'Blade');
      expect(detectFileLanguage('/x/.env.local')?.label, 'Env');
      expect(detectFileLanguage('/x/main.PHP')?.grammar, 'php');
    });

    test('every grammar used exists in re_highlight', () {
      final keys = allPickableLanguages().map((l) => l.grammar).toSet();
      for (final name in [
        'composer.lock', 'Dockerfile', 'Makefile', 'a.toml', 'a.ps1',
        'a.bat', 'a.go', 'a.kt', 'a.sql', 'a.proto', 'a.twig', 'a.vue',
        'a.graphql', 'a.diff', 'a.cpp', 'Gemfile', 'CMakeLists.txt',
      ]) {
        final lang = detectFileLanguage('/x/$name');
        expect(lang, isNotNull, reason: name);
        expect(keys, contains(lang!.grammar), reason: name);
      }
    });
  });

  group('create', () {
    test('creates files, folders and nested paths', () async {
      final file = await FileOps.create(root.path, 'a.txt', isDir: false);
      expect(File(file).existsSync(), isTrue);
      final nested =
          await FileOps.create(root.path, 'src/util/b.dart', isDir: false);
      expect(nested, path('src/util/b.dart'));
      expect(File(nested).existsSync(), isTrue);
      final dir = await FileOps.create(root.path, 'docs', isDir: true);
      expect(Directory(dir).existsSync(), isTrue);
    });

    test('rejects empty, dot and existing names', () {
      write('a.txt');
      expect(FileOps.validateNewEntry(root.path, '  '), isNotNull);
      expect(FileOps.validateNewEntry(root.path, '../x'), isNotNull);
      expect(FileOps.validateNewEntry(root.path, 'a.txt'), isNotNull);
      expect(FileOps.validateNewEntry(root.path, 'b.txt'), isNull);
    });
  });

  group('RecentFiles', () {
    test('keeps newest first, follows moves and drops missing files',
        () async {
      SharedPreferences.setMockInitialValues({});
      write('a.txt');
      write('b.txt');
      await RecentFiles.record(root.path, path('a.txt'));
      await RecentFiles.record(root.path, path('b.txt'));
      await RecentFiles.record(root.path, path('a.txt'));
      expect(await RecentFiles.forRoot(root.path), ['a.txt', 'b.txt']);

      File(path('a.txt')).renameSync(path('c.txt'));
      await RecentFiles.movePath(root.path, path('a.txt'), path('c.txt'));
      expect(await RecentFiles.forRoot(root.path), ['c.txt', 'b.txt']);

      File(path('b.txt')).deleteSync();
      expect(await RecentFiles.forRoot(root.path), ['c.txt']);
    });
  });
}
