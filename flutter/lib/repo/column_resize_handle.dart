import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A thin, invisible draggable strip between two columns: shows a resize
/// cursor on hover and reports horizontal drag deltas so the caller can
/// adjust the adjacent column's width.
///
/// The columns draw their own 1px hairline borders, so the handle itself is
/// transparent until hovered or dragged, when it shows a faint guide line.
class ColumnResizeHandle extends StatefulWidget {
  const ColumnResizeHandle({
    super.key,
    required this.onDrag,
    this.onDragEnd,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  State<ColumnResizeHandle> createState() => _ColumnResizeHandleState();
}

class _ColumnResizeHandleState extends State<ColumnResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 1,
              color: active ? context.branchi.line : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}
