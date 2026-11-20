import 'package:flutter/widgets.dart';

import '../repo/repo_controller.dart';
import '../repo/repository_view.dart';

/// Finds the [RepoController] of the repository shown in the main window
/// (the active tab's [RepositoryView]) by walking the root navigator's
/// element tree; the window's route stays mounted below the settings route.
///
/// Returns `null` when the active tab is a start page. Must not be called
/// during build (call it from a post-frame callback).
RepoController? findOpenRepoController(BuildContext context) {
  final navigator = Navigator.maybeOf(context, rootNavigator: true);
  if (navigator == null) return null;
  RepoController? found;
  void visit(Element element) {
    if (found != null) return;
    final widget = element.widget;
    if (widget is RepositoryView) {
      found = widget.controller;
      return;
    }
    element.visitChildren(visit);
  }

  navigator.context.visitChildElements(visit);
  return found;
}
