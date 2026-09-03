/// Data models mirroring `core/src/git.rs`'s JSON-serialized types, as
/// returned by the `branchi_log`, `branchi_branches`, and
/// `branchi_commit_diff` FFI calls.

enum FileChangeStatus { new_, modified, deleted, renamed, typechange, conflicted }

FileChangeStatus _statusFromJson(String value) {
  switch (value) {
    case 'new':
      return FileChangeStatus.new_;
    case 'modified':
      return FileChangeStatus.modified;
    case 'deleted':
      return FileChangeStatus.deleted;
    case 'renamed':
      return FileChangeStatus.renamed;
    case 'typechange':
      return FileChangeStatus.typechange;
    case 'conflicted':
      return FileChangeStatus.conflicted;
    default:
      return FileChangeStatus.modified;
  }
}

class CommitEntry {
  const CommitEntry({
    required this.id,
    required this.summary,
    required this.author,
    required this.email,
    required this.time,
    required this.parentIds,
  });

  factory CommitEntry.fromJson(Map<String, dynamic> json) {
    return CommitEntry(
      id: json['id'] as String,
      summary: json['summary'] as String,
      author: json['author'] as String,
      email: json['email'] as String,
      time: DateTime.parse(json['time'] as String),
      parentIds: (json['parent_ids'] as List).cast<String>(),
    );
  }

  final String id;
  final String summary;
  final String author;
  final String email;
  final DateTime time;
  final List<String> parentIds;

  bool get isMergeCommit => parentIds.length > 1;

  String get shortId => id.length > 7 ? id.substring(0, 7) : id;
}

class BranchEntry {
  const BranchEntry({
    required this.name,
    required this.isHead,
    required this.isRemote,
  });

  factory BranchEntry.fromJson(Map<String, dynamic> json) {
    return BranchEntry(
      name: json['name'] as String,
      isHead: json['is_head'] as bool,
      isRemote: json['is_remote'] as bool,
    );
  }

  final String name;
  final bool isHead;
  final bool isRemote;
}

/// A single configured remote, as returned by `branchi_remotes`.
class RemoteEntry {
  const RemoteEntry({required this.name, required this.url});

  factory RemoteEntry.fromJson(Map<String, dynamic> json) {
    return RemoteEntry(
      name: json['name'] as String,
      url: json['url'] as String,
    );
  }

  final String name;
  final String url;
}

/// The `user.name`/`user.email` identity read from git's global config, as
/// returned by `branchi_global_config_get`.
class GlobalGitIdentity {
  const GlobalGitIdentity({this.name, this.email});

  final String? name;
  final String? email;
}

/// A single file's working-tree/index status, as returned by
/// `branchi_status`.
class StatusEntry {
  const StatusEntry({
    required this.path,
    required this.staged,
    required this.unstaged,
  });

  factory StatusEntry.fromJson(Map<String, dynamic> json) {
    return StatusEntry(
      path: json['path'] as String,
      staged: json['staged'] == null
          ? null
          : _statusFromJson(json['staged'] as String),
      unstaged: json['unstaged'] == null
          ? null
          : _statusFromJson(json['unstaged'] as String),
    );
  }

  final String path;
  final FileChangeStatus? staged;
  final FileChangeStatus? unstaged;

  bool get isStaged => staged != null;
}

class DiffFileEntry {
  const DiffFileEntry({
    required this.path,
    required this.status,
    required this.additions,
    required this.deletions,
    required this.patch,
  });

  factory DiffFileEntry.fromJson(Map<String, dynamic> json) {
    return DiffFileEntry(
      path: json['path'] as String,
      status: _statusFromJson(json['status'] as String),
      additions: json['additions'] as int,
      deletions: json['deletions'] as int,
      patch: json['patch'] as String,
    );
  }

  final String path;
  final FileChangeStatus status;
  final int additions;
  final int deletions;
  final String patch;
}
