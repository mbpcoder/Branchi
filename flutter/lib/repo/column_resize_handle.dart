import 'package:flutter/material.dart';

/// A thin draggable divider between two columns: shows a resize cursor on
/// hover and reports horizontal drag deltas so the caller can adjust the
/// adjacent column's width.
class ColumnResizeHandle extends StatelessWidget {
  const ColumnResizeHandle({
    super.key,
    required this.onDrag,
    this.onDragEnd,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd?.call(),
        child: SizedBox(
          width: 6,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).dividerColor,
            ),
          ),
        ),
      ),
    );
  }
}
