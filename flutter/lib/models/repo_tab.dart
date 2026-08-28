/// A single tab in the top tab bar: either an unattached "start page" tab
/// or one bound to an opened/created/cloned repository.
class RepoTab {
  RepoTab({required this.id, required this.title, this.path});

  final int id;
  String title;
  String? path;
}
