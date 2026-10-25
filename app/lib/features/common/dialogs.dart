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

/// Buttons at the bottom of a dialog: one tidy, wrapping, right-aligned group where every button has the same height and the
/// same gap, however many there are or however long the (translated) labels are. Use as `actions: [DialogActions([...])]`.
class DialogActions extends StatelessWidget {
  const DialogActions(this.children, {super.key, this.grid = false});
  final List<Widget> children;

  /// Many actions (a bill has a dozen): lay them out as an even two- or three-column grid instead of a ragged wrap.
  final bool grid;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const size = WidgetStatePropertyAll(Size(64, 46));
    return Theme(
      data: t.copyWith(
        filledButtonTheme: FilledButtonThemeData(style: (t.filledButtonTheme.style ?? const ButtonStyle()).copyWith(minimumSize: size)),
        outlinedButtonTheme: OutlinedButtonThemeData(style: (t.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(minimumSize: size)),
        textButtonTheme: TextButtonThemeData(style: (t.textButtonTheme.style ?? const ButtonStyle()).copyWith(minimumSize: size)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: grid
            ? Builder(builder: (context) {
                // AlertDialog measures its actions with intrinsic sizes, so no LayoutBuilder here: work the dialog width out from the screen
                final screen = MediaQuery.sizeOf(context).width;
                final inner = (screen - 80).clamp(240.0, 560.0) - 48;
                final cols = inner >= 430 ? 3 : 2;
                final w = (inner - (cols - 1) * 8) / cols;
                return Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final x in children) SizedBox(width: w, height: 46, child: FittedBox(fit: BoxFit.scaleDown, child: x))],
                );
              })
            : Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: children),
      ),
    );
  }
}
