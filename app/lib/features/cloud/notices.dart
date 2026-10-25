import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../cloud/access_controller.dart';
import '../../cloud/cloud_gateway.dart';
import '../../data/queries.dart';
import '../../data/receipt_loader.dart' show formatDateTime;

/// Notices from Digital Target for this restaurant. Empty without internet or sign-in; they arrive live while online.
final noticesProvider = StreamProvider.autoDispose<List<AppNotice>>((ref) {
  final gw = ref.watch(cloudGatewayProvider);
  final user = gw?.currentUser;
  if (gw == null || user == null) return const Stream.empty();
  return gw.watchNotices(user.uid);
});

/// When the owner last opened the bell (milliseconds): anything newer is "unread".
class NoticeSeenNotifier extends AsyncNotifier<int> {
  static const key = 'notice.seen';
  @override
  Future<int> build() async => int.tryParse(await getSetting(ref.read(databaseProvider), key) ?? '') ?? 0;

  Future<void> markSeen(int at) async {
    if (at <= (state.value ?? 0)) return;
    await setSetting(ref.read(databaseProvider), key, '$at', ref.read(clockProvider)().millisecondsSinceEpoch);
    state = AsyncData(at);
  }
}

final noticeSeenProvider = AsyncNotifierProvider<NoticeSeenNotifier, int>(NoticeSeenNotifier.new);

final unreadNoticesProvider = Provider.autoDispose<int>((ref) {
  final seen = ref.watch(noticeSeenProvider).value ?? 0;
  final list = ref.watch(noticesProvider).value ?? const [];
  return list.where((n) => (n.at?.millisecondsSinceEpoch ?? 0) > seen).length;
});

IconData noticeIcon(String kind) => switch (kind) {
      'payment' => Icons.payments_outlined,
      'update' => Icons.system_update_alt,
      'warning' => Icons.warning_amber_rounded,
      'offer' => Icons.local_offer_outlined,
      _ => Icons.notifications_none,
    };

/// The bell with the number of unread notices; opens the list.
class NoticeBell extends ConsumerWidget {
  const NoticeBell({super.key, this.onDark = false});

  /// true on the coloured drawer header, where the icon must be light.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(cloudGatewayProvider) == null) return const SizedBox.shrink();
    final n = ref.watch(unreadNoticesProvider);
    return IconButton(
      key: ValueKey(onDark ? 'bell-drawer' : 'bell'),
      tooltip: Strings.of(context)['notifications'],
      icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(n > 0 ? Icons.notifications_active : Icons.notifications_none, color: onDark ? BrandBanner(Theme.of(context).colorScheme.primary).on : null)),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NoticesScreen())),
    );
  }
}

class NoticesScreen extends ConsumerStatefulWidget {
  const NoticesScreen({super.key});
  @override
  ConsumerState<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends ConsumerState<NoticesScreen> {
  int _openedWithSeen = 0;

  @override
  void initState() {
    super.initState();
    // what was unread when the screen opened stays highlighted; then it counts as read
    _openedWithSeen = ref.read(noticeSeenProvider).value ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = Strings.of(context);
    final cs = Theme.of(context).colorScheme;
    final list = ref.watch(noticesProvider);
    final newest = list.value?.fold<int>(0, (m, n) => (n.at?.millisecondsSinceEpoch ?? 0) > m ? (n.at?.millisecondsSinceEpoch ?? 0) : m) ?? 0;
    if (newest > 0) Future.microtask(() => ref.read(noticeSeenProvider.notifier).markSeen(newest));
    return Scaffold(
      appBar: DtAppBar(title: Text(t['notifications'])),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (items) => items.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(t['notices_none'], key: const ValueKey('notices-empty'), textAlign: TextAlign.center)))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final n = items[i];
                  final isNew = (n.at?.millisecondsSinceEpoch ?? 0) > _openedWithSeen;
                  return Card(
                    key: ValueKey('notice-${n.title}'),
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isNew ? cs.primary : cs.outlineVariant, width: isNew ? 1.6 : 1)),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(noticeIcon(n.kind), color: cs.primary)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                            if (n.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(n.body)),
                            if (n.at != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(formatDateTime(n.at!), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
