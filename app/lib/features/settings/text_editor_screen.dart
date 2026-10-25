import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';

/// Change any label in the app (button names, tab names, headings...) for the current language. The built-in text is shown
/// under each label, and an edit can be undone by clearing the field. Saved on the phone; no code or update needed.
class TextEditorScreen extends ConsumerStatefulWidget {
  const TextEditorScreen({super.key});
  @override
  ConsumerState<TextEditorScreen> createState() => _TextEditorState();
}

class _TextEditorState extends ConsumerState<TextEditorScreen> {
  String _q = '';

  Future<void> _edit(String lang, String key) async {
    final t = Strings.of(context);
    final c = TextEditingController(text: Strings.overrides[lang]?[key] ?? Strings.builtIn(lang, key));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(scrollable: true, 
        title: Text(key),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${t['text_original']}: ${Strings.builtIn(lang, key)}', style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 10),
          TextField(key: const ValueKey('text-field'), controller: c, autofocus: true, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: t['text_new'])),
        ]),
        actions: [
          TextButton(key: const ValueKey('text-reset'), onPressed: () { c.text = ''; Navigator.pop(ctx, true); }, child: Text(t['text_reset_one'])),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t['cancel'])),
          FilledButton(key: const ValueKey('text-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(t['save'])),
        ],
      ),
    );
    if (ok == true) await ref.read(textOverridesProvider.notifier).setText(lang, key, c.text);
    c.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    ref.watch(textOverridesProvider);
    final cs = Theme.of(context).colorScheme;
    final q = _q.trim().toLowerCase();
    final keys = Strings.keys.where((k) => q.isEmpty || k.toLowerCase().contains(q) || Strings.builtIn(lang, k).toLowerCase().contains(q) || (Strings.overrides[lang]?[k] ?? '').toLowerCase().contains(q)).toList();
    final changed = Strings.overrides[lang]?.length ?? 0;
    return Scaffold(
      appBar: DtAppBar(
        title: Text(t['text_editor']),
        actions: [if (changed > 0) TextButton(key: const ValueKey('text-reset-all'), onPressed: () => ref.read(textOverridesProvider.notifier).resetAll(), child: Text(t['text_reset_all'], style: TextStyle(color: Theme.of(context).appBarTheme.foregroundColor)))],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(key: const ValueKey('text-search'), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['search']), onChanged: (v) => setState(() => _q = v))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Align(alignment: AlignmentDirectional.centerStart, child: Text('${Strings.languageNames[lang]} · ${t['text_changed']}: $changed', style: TextStyle(color: cs.onSurfaceVariant)))),
        Expanded(
          child: ListView.builder(
            itemCount: keys.length,
            itemBuilder: (_, i) {
              final k = keys[i];
              final mine = Strings.overrides[lang]?[k];
              return ListTile(
                key: ValueKey('text-$k'),
                dense: true,
                title: Text(mine ?? Strings.builtIn(lang, k), style: TextStyle(fontWeight: mine != null ? FontWeight.w800 : FontWeight.w500, color: mine != null ? context.accent : null)),
                subtitle: Text(k, style: const TextStyle(fontSize: 11)),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _edit(lang, k),
              );
            },
          ),
        ),
      ]),
    );
  }
}
