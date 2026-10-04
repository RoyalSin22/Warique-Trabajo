import 'package:flutter/widgets.dart';

/// Owns the [TextEditingController]s of a dialog and disposes them when the dialog's route is
/// really gone. Disposing them right after `showDialog` returns is a bug: the closing animation
/// still rebuilds the text fields.
class WithTextControllers extends StatefulWidget {
  const WithTextControllers({super.key, required this.initialTexts, required this.builder});

  final List<String?> initialTexts;
  final Widget Function(BuildContext context, List<TextEditingController> controllers) builder;

  @override
  State<WithTextControllers> createState() => _WithTextControllersState();
}

class _WithTextControllersState extends State<WithTextControllers> {
  late final List<TextEditingController> _controllers = [
    for (final text in widget.initialTexts) TextEditingController(text: text),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controllers);
}
