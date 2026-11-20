import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A small muted label stacked above its input, as used by the clone dialog
/// and the settings forms.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final b = context.branchi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: b.muted)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
