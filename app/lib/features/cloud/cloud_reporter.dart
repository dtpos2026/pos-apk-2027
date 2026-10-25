import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../cloud/access_controller.dart';
import '../../cloud/cloud_gateway.dart';
import '../../cloud/location_consent.dart';
import '../../data/queries.dart';

/// Where the phone model and Android version come from. Overridden in main() (device_info_plus) and in tests.
final deviceDescriptionProvider = FutureProvider<({String model, String android})>((ref) async => (model: 'unknown', android: '?'));

/// How many earlier days are re-sent each round, so days spent offline still reach the panel.
const resendDays = 7;

/// Result of the last attempt to reach Digital Target's servers. Shown as the cloud icon in the app bar.
class CloudSyncStatus {
  const CloudSyncStatus({this.lastOkAt, this.lastError, this.lastTryAt});
  final DateTime? lastOkAt;
  final String? lastError;
  final DateTime? lastTryAt;
  bool get ok => lastTryAt != null && lastError == null;
}

class CloudSyncStatusNotifier extends Notifier<CloudSyncStatus> {
  @override
  CloudSyncStatus build() => const CloudSyncStatus();
  void succeeded(DateTime at) => state = CloudSyncStatus(lastOkAt: at, lastTryAt: at);
  void failed(DateTime at, String error) => state = CloudSyncStatus(lastOkAt: state.lastOkAt, lastTryAt: at, lastError: error);
}

final cloudSyncStatusProvider = NotifierProvider<CloudSyncStatusNotifier, CloudSyncStatus>(CloudSyncStatusNotifier.new);

/// While the app is open and allowed to sell, sends Digital Target only: this phone's model/version/last seen and
/// daily sales TOTALS (today plus the previous [resendDays] days). Failures (no internet) are recorded and retried
/// on the next round; nothing on the phone waits for them.
class CloudReporter {
  CloudReporter(this.ref);
  final Ref ref;

  Future<void> reportNow() async {
    final gw = ref.read(cloudGatewayProvider);
    final state = ref.read(accessProvider);
    if (gw == null || state is! AccessDecided || !state.decision.allowed) return;
    final uid = state.user.uid;
    final version = ref.read(appVersionProvider);
    final now = ref.read(clockProvider)();
    try {
      final dev = await ref.read(deviceDescriptionProvider.future);
      final phoneId = await ref.read(accessProvider.notifier).phoneId();
      final share = await getSetting(ref.read(databaseProvider), LocationConsentNotifier.key) == '1';
      final source = ref.read(locationSourceProvider);
      final loc = share && source != null ? await source().catchError((_) => null) : null;
      await gw.reportDevice(uid, DeviceInfoReport(
        phoneId: phoneId, model: dev.model, android: dev.android, appVersion: version,
        locationAllowed: share, lat: loc?.lat, lng: loc?.lng, accuracyM: loc?.accuracyM, locationAt: loc?.at,
      ));
      await _reportLogo(gw, uid);
      final today = await totalsFor(now);
      if (today != null) await gw.reportSales(uid, today, version);
      final past = <DayTotals>[];
      for (var i = 1; i <= resendDays; i++) {
        final t = await totalsFor(now.subtract(Duration(days: i)));
        if (t != null && (t.bills > 0 || t.refundsMinor > 0)) past.add(t);
      }
      await gw.reportPastDays(uid, past);
      ref.read(cloudSyncStatusProvider.notifier).succeeded(now);
    } catch (e) {
      ref.read(cloudSyncStatusProvider.notifier).failed(now, e.toString());
    }
  }

  /// The restaurant's logo as a tiny round-pin picture (96 px JPEG, a few KB). Sent again only when the logo file changed.
  Future<void> _reportLogo(CloudGateway gw, String uid) async {
    try {
      final db = ref.read(databaseProvider);
      final path = (await loadBusiness(db))?.logoPath;
      if (path == null || !File(path).existsSync()) return;
      final stamp = '$path:${File(path).lengthSync()}:${File(path).lastModifiedSync().millisecondsSinceEpoch}';
      if (await getSetting(db, 'cloud.logo_key') == stamp) return;
      final decoded = img.decodeImage(File(path).readAsBytesSync());
      if (decoded == null) return;
      final s = decoded.width < decoded.height ? decoded.width : decoded.height;
      final square = img.copyCrop(decoded, x: (decoded.width - s) ~/ 2, y: (decoded.height - s) ~/ 2, width: s, height: s);
      final small = img.copyResize(square, width: 96, height: 96, interpolation: img.Interpolation.average);
      await gw.reportLogo(uid, 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(small, quality: 72))}');
      await setSetting(db, 'cloud.logo_key', stamp, ref.read(clockProvider)().millisecondsSinceEpoch);
    } catch (_) {
      // the pin falls back to the first letter of the name; never let a logo problem stop the report
    }
  }

  static String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<DayTotals?> todayTotals() => totalsFor(ref.read(clockProvider)());

  Future<DayTotals?> totalsFor(DateTime day) async {
    final date = dateKey(day);
    final db = ref.read(databaseProvider);
    final business = await loadBusiness(db);
    if (business == null) return null;
    final r = await ref.read(posServiceProvider).salesReport(date);
    final rows = await db.customSelect("SELECT COUNT(DISTINCT customer_id) AS n FROM \"order\" WHERE business_date = ? AND status IN ('paid','void','refunded') AND customer_id IS NOT NULL", variables: [Variable.withString(date)]).get();
    return DayTotals(
      date: date, netMinor: r.netMinor, grossMinor: r.grossMinor, refundsMinor: r.refundsMinor, bills: r.bills,
      customers: rows.first.read<int>('n'), currency: business.currency.code,
    );
  }
}

final cloudReporterProvider = Provider<CloudReporter>((ref) => CloudReporter(ref));

class CloudReporterHost extends ConsumerStatefulWidget {
  const CloudReporterHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<CloudReporterHost> createState() => _CloudReporterHostState();
}

class _CloudReporterHostState extends ConsumerState<CloudReporterHost> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => ref.read(cloudReporterProvider).reportNow());
    Future.microtask(() => ref.read(cloudReporterProvider).reportNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(cloudReporterProvider).reportNow();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// App-bar indicator: green cloud = reached the server recently, crossed cloud = offline (sales keep working).
class CloudSyncIndicator extends ConsumerWidget {
  const CloudSyncIndicator({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(cloudGatewayProvider) == null) return const SizedBox.shrink();
    final t = Strings.of(context);
    final s = ref.watch(cloudSyncStatusProvider);
    final now = ref.watch(clockProvider)();
    final String tip;
    final IconData icon;
    if (s.lastTryAt == null) {
      tip = t['sync_waiting'];
      icon = Icons.cloud_queue;
    } else if (s.ok) {
      tip = t['sync_ok'].replaceAll('{m}', '${now.difference(s.lastOkAt!).inMinutes}');
      icon = Icons.cloud_done_outlined;
    } else {
      tip = t['sync_offline'];
      icon = Icons.cloud_off_outlined;
    }
    return Tooltip(
      message: tip,
      child: Semantics(label: tip, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Icon(icon, key: const Key('cloud_sync_icon')))),
    );
  }
}
