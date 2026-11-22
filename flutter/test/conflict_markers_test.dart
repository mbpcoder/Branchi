import 'package:branchi/code/conflict_markers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lines = [
    'a',
    '<<<<<<< HEAD',
    'mine',
    '=======',
    'theirs 1',
    'theirs 2',
    '>>>>>>> feature',
    'b',
    '<<<<<<< HEAD',
    'x',
    '||||||| base',
    'old',
    '=======',
    '>>>>>>> feature',
    '<<<<<<< unfinished',
  ];

  test('finds complete blocks, with or without a base section', () {
    final blocks = findConflicts(lines);
    expect(blocks.length, 2);
    expect(blocks[0].mine(lines), ['mine']);
    expect(blocks[0].theirs(lines), ['theirs 1', 'theirs 2']);
    expect(blocks[1].mine(lines), ['x']);
    expect(blocks[1].theirs(lines), isEmpty);
  });

  test('resolves a block to either side or both', () {
    final block = findConflicts(lines).first;
    expect(resolveBlock(lines, block, ConflictChoice.mine), ['mine']);
    expect(resolveBlock(lines, block, ConflictChoice.both),
        ['mine', 'theirs 1', 'theirs 2']);
  });
}
