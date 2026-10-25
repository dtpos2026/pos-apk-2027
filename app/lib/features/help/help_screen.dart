import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../domain/tutorials.dart';

/// How the guides are shown: the language and, for Urdu, the lettering style (Nastaliq like a printed Urdu book, or the plainer Naskh).
enum HelpStyle { en, urNastaliq, urNaskh, ro }

const _icons = <String, IconData>{
  'rocket': Icons.rocket_launch_outlined,
  'cart': Icons.shopping_cart_outlined,
  'kitchen': Icons.soup_kitchen_outlined,
  'tables': Icons.table_restaurant_outlined,
  'delivery': Icons.delivery_dining_outlined,
  'book': Icons.menu_book_outlined,
  'menu': Icons.restaurant_menu,
  'print': Icons.print_outlined,
  'chart': Icons.bar_chart_rounded,
  'people': Icons.badge_outlined,
  'backup': Icons.backup_outlined,
  'support': Icons.support_agent,
};

/// Help & Tutorials: every part of the app explained step by step, in English, Urdu (two styles) and Roman Urdu. Works without internet.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});
  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  HelpStyle? _style;
  String _q = '';

  TutorialLang _lang(HelpStyle s) => switch (s) { HelpStyle.en => TutorialLang.en, HelpStyle.ro => TutorialLang.ro, _ => TutorialLang.ur };

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final style = _style ?? (ref.watch(localeProvider).languageCode == 'ur' ? HelpStyle.urNastaliq : HelpStyle.en);
    final lang = _lang(style);
    final rtl = lang == TutorialLang.ur;
    final font = switch (style) { HelpStyle.urNastaliq => 'NotoNastaliqUrdu', HelpStyle.urNaskh => 'NotoNaskhArabic', _ => null };
    final q = _q.trim().toLowerCase();
    final shown = [for (final x in tutorials) if (q.isEmpty || tutorialText(x, lang).toLowerCase().contains(q)) x];
    final bodyStyle = TextStyle(fontFamily: font, fontSize: rtl ? 17 : 15, height: style == HelpStyle.urNastaliq ? 2.0 : 1.5);
    return Scaffold(
      appBar: DtAppBar(title: Text(t['help_title'])),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: SizedBox(
            height: 44,
            child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              for (final e in {HelpStyle.en: 'English', HelpStyle.urNastaliq: 'اردو (نستعلیق)', HelpStyle.urNaskh: 'اردو (نسخ)', HelpStyle.ro: 'Roman Urdu'}.entries)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: ChoiceChip(key: ValueKey('help-${e.key.name}'), label: Text(e.value), selected: style == e.key, showCheckmark: false, onSelected: (_) => setState(() => _style = e.key)),
                ),
            ])),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(key: const ValueKey('help-search'), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: t['help_search'], isDense: true), onChanged: (v) => setState(() => _q = v)),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(t['help_none']))
              : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                  for (final x in shown)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      clipBehavior: Clip.antiAlias,
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: ValueKey('help-topic-${x.id}'),
                          initiallyExpanded: q.isNotEmpty,
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
                            child: Icon(_icons[x.icon] ?? Icons.help_outline, color: cs.primary),
                          ),
                          title: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: Text(x.title[lang]!, style: TextStyle(fontFamily: font, fontWeight: FontWeight.w800, fontSize: rtl ? 18 : 16, height: style == HelpStyle.urNastaliq ? 1.9 : 1.3))),
                          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          expandedCrossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Directionality(
                              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                for (var i = 0; i < x.steps[lang]!.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Container(
                                        margin: const EdgeInsetsDirectional.only(end: 10, top: 4),
                                        width: 24,
                                        height: 24,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
                                        child: Text('${i + 1}', style: TextStyle(color: cs.onPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
                                      ),
                                      Expanded(child: Text(x.steps[lang]![i], style: bodyStyle)),
                                    ]),
                                  ),
                              ]),
                            ),
                          ],
                        ),
                      ),
                    ),
                ]),
        ),
      ]),
    );
  }
}
