import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/strings.dart';

class FieldSpec {
  const FieldSpec(this.key, this.label, {this.initial = '', this.number = false, this.obscure = false, this.required = true, this.lines = 1});
  final String key;
  final String label;
  final String initial;
  final bool number;
  final bool obscure;
  final bool required;
  final int lines;
}

/// One reusable form dialog: labelled text fields, required-field checks, optional extra widgets (dropdowns).
/// Returns the entered values, or null if cancelled. [validate] may return an error to keep the dialog open.
Future<Map<String, String>?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  Widget Function(StateSetter setState)? extra,
  Future<String?> Function(Map<String, String> values)? validate,
  String? okLabel,
}) {
  final controllers = {for (final f in fields) f.key: TextEditingController(text: f.initial)};
  final t = Strings.of(context);
  String? error;
  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in fields) ...[
              TextField(
                key: ValueKey('f-${f.key}'),
                controller: controllers[f.key],
                keyboardType: f.number ? const TextInputType.numberWithOptions(decimal: true) : (f.lines > 1 ? TextInputType.multiline : null),
                inputFormatters: f.number ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))] : null,
                obscureText: f.obscure,
                minLines: f.lines,
                maxLines: f.lines,
                decoration: InputDecoration(labelText: f.label),
              ),
              const SizedBox(height: 10),
            ],
            if (extra != null) extra(setState),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, key: const ValueKey('form-error'), style: TextStyle(color: Theme.of(ctx).colorScheme.error, fontWeight: FontWeight.w600))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t['cancel'])),
          FilledButton(
            key: const ValueKey('form-ok'),
            onPressed: () async {
              final values = {for (final f in fields) f.key: controllers[f.key]!.text.trim()};
              for (final f in fields) {
                if (f.required && values[f.key]!.isEmpty) {
                  setState(() => error = '${f.label}: ${t['required']}');
                  return;
                }
              }
              final problem = validate == null ? null : await validate(values);
              if (problem != null) {
                setState(() => error = problem);
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx, values);
            },
            child: Text(okLabel ?? t['save']),
          ),
        ],
      ),
    ),
  );
}

Future<bool> confirmDialog(BuildContext context, String message, {String? okLabel}) async {
  final t = Strings.of(context);
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t['cancel'])), FilledButton(key: const ValueKey('confirm-ok'), onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel ?? t['ok']))],
        ),
      ) ??
      false;
}

void showMessage(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
