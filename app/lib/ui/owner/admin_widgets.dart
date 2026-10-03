import 'package:flutter/material.dart';

import '../widgets/common.dart';

/// Runs a save action with a spinner-free busy flag, error snack and success message.
/// Returns true on success.
Future<bool> runSaving(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (context.mounted && success != null) showInfoSnack(context, success);
    return true;
  } catch (error) {
    if (context.mounted) showErrorSnack(context, error);
    return false;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Aceptar',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
      ],
    ),
  );
  return result ?? false;
}

/// Dialog with a form; [onSave] returns true to close it (false keeps it open, e.g. on error).
class FormDialog extends StatefulWidget {
  const FormDialog({super.key, required this.title, required this.children, required this.onSave});

  final String title;
  final List<Widget> children;
  final Future<bool> Function() onSave;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final close = await widget.onSave();
    if (!mounted) return;
    if (close) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: widget.children),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Guardar'),
      ),
    ],
  );
}

String? requiredText(String? value, {int max = 100}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Obligatorio';
  if (text.length > max) return 'Máximo $max caracteres';
  return null;
}

/// Small grey tag for inactive records.
class InactiveTag extends StatelessWidget {
  const InactiveTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
  );
}
