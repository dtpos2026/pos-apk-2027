import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/feedback.dart';
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
  final cleared = ref.watch(noticeClearedProvider).value ?? 0;
  // "Clear" hides what has arrived so far on this phone; later notices still show
  return gw.watchNotices(user.uid).map((l) => [for (final n in l) if ((n.at?.millisecondsSinceEpoch ?? 0) > cleared) n]);
});

/// When the owner pressed "Clear all" in the notifications list (milliseconds).
class NoticeClearedNotifier extends AsyncNotifier<int> {
  static const key = 'notice.cleared';
  @override
  Future<int> build() async => int.tryParse(await getSetting(ref.read(databaseProvider), key) ?? '') ?? 0;

  /// [newest] = the newest notice on screen, so one stamped a moment after this phone's clock is cleared as well.
  Future<void> clearAll({int newest = 0}) async {
    final now = ref.read(clockProvider)().millisecondsSinceEpoch;
    final at = newest > now ? newest : now;
    await setSetting(ref.read(databaseProvider), key, '$at', now);
    state = AsyncData(at);
    await ref.read(feedbackPlayerProvider).clearNotifications();
  }
}

final noticeClearedProvider = AsyncNotifierProvider<NoticeClearedNotifier, int>(NoticeClearedNotifier.new);

/// Shows each new notice in the phone's status bar (once), when the owner allowed it. Renders nothing.
/// Notices arrive live while the app is running; this build has no push service for a fully closed app.
class NoticePusher extends ConsumerStatefulWidget {
  const NoticePusher({super.key});
  @override
  ConsumerState<NoticePusher> createState() => _NoticePusherState();
}

class _NoticePusherState extends ConsumerState<NoticePusher> {
  static const _pushedKey = 'notice.pushed';
  bool _busy = false;

  Future<void> _push(List<AppNotice> list) async {
    if (_busy) return;
    _busy = true;
    try {
      final db = ref.read(databaseProvider);
      final stored = await getSetting(db, _pushedKey);
      final newest = list.fold<int>(0, (m, n) => (n.at?.millisecondsSinceEpoch ?? 0) > m ? (n.at?.millisecondsSinceEpoch ?? 0) : m);
      final pushed = int.tryParse(stored ?? '');
      final prefs = await ref.read(feedbackPrefsProvider.future);
      if (pushed != null && prefs.notices) {
        final fresh = [for (final n in list) if ((n.at?.millisecondsSinceEpoch ?? 0) > pushed) n]..sort((a, b) => a.at!.compareTo(b.at!));
        for (final n in fresh) {
          await ref.read(feedbackPlayerProvider).notify(n.title, n.body, n.at!.millisecondsSinceEpoch & 0x7fffffff);
        }
      }
      // the very first reading is only a baseline: notices that already exist are not announced again
      if (pushed == null || newest > pushed) await setSetting(db, _pushedKey, '$newest', ref.read(clockProvider)().millisecondsSinceEpoch);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(noticesProvider, (_, next) {
      final v = next.value;
      if (v != null) _push(v);
    });
    return const SizedBox.shrink();
  }
}

/// Asks once whether DT Food POS may show notices in the phone's status bar.
class NoticePermissionAsk extends ConsumerStatefulWidget {
  const NoticePermissionAsk({super.key});
  @override
  ConsumerState<NoticePermissionAsk> createState() => _NoticePermissionAskState();
}

class _NoticePermissionAskState extends ConsumerState<NoticePermissionAsk> {
  static const _askedKey = 'ui.notices_asked';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  Future<void> _ask() async {
    if (_started || !mounted) return;
    _started = true;
    final db = ref.read(databaseProvider);
    if (ref.read(cloudGatewayProvider) == null || !ref.read(feedbackPlayerProvider).supportsNotices || await getSetting(db, _askedKey) != null) return;
    if (!mounted) return;
    final t = Strings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: Text(t['notices_ask_title']),
        content: Text(t['notices_ask_body']),
        actions: [
          TextButton(key: const ValueKey('notices-no'), onPressed: () => Navigator.pop(c, false), child: Text(t['not_now'])),
          FilledButton(key: const ValueKey('notices-yes'), onPressed: () => Navigator.pop(c, true), child: Text(t['allow'])),
        ],
      ),
    );
    await setSetting(db, _askedKey, '1', ref.read(clockProvider)().millisecondsSinceEpoch);
    await ref.read(feedbackPrefsProvider.notifier).setNotices(yes == true);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

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
      appBar: DtAppBar(title: Text(t['notifications']), actions: [
        if ((list.value ?? const []).isNotEmpty)
          IconButton(key: const ValueKey('notices-clear'), tooltip: t['notices_clear'], icon: const Icon(Icons.delete_sweep_outlined), onPressed: () => ref.read(noticeClearedProvider.notifier).clearAll(newest: newest)),
      ]),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(t['notices_error'], key: const ValueKey('notices-error'), textAlign: TextAlign.center))),
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
