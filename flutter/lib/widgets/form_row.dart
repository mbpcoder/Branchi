import 'package:flutter/material.dart';

/// A label + input row used by the clone-repository form.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 140, child: Text(label)),
        Expanded(child: child),
      ],
    );
  }
}
