import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../cloud/access_controller.dart';
import '../../cloud/cloud_gateway.dart';
import 'package:drift/drift.dart' show Variable;

import '../../data/queries.dart';

/// Where the phone model and Android version come from. Overridden in main() (device_info_plus) and in tests.
final deviceDescriptionProvider = FutureProvider<({String model, String android})>((ref) async => (model: 'unknown', android: '?'));

/// While the app is open and allowed to sell, sends Digital Target only: this phone's model/version/last seen and
/// today's sales TOTALS. Failures (no internet) are ignored and retried on the next round.
class CloudReporter {
  CloudReporter(this.ref);
  final Ref ref;

  Future<void> reportNow() async {
    final gw = ref.read(cloudGatewayProvider);
    final state = ref.read(accessProvider);
    if (gw == null || state is! AccessDecided || !state.decision.allowed) return;
    final uid = state.user.uid;
    final version = ref.read(appVersionProvider);
    try {
      final dev = await ref.read(deviceDescriptionProvider.future);
      final phoneId = await ref.read(accessProvider.notifier).phoneId();
      await gw.reportDevice(uid, DeviceInfoReport(phoneId: phoneId, model: dev.model, android: dev.android, appVersion: version));
      final totals = await todayTotals();
      if (totals != null) await gw.reportSales(uid, totals, version);
    } catch (_) {
      // offline or temporarily refused: the next round tries again
    }
  }

  Future<DayTotals?> todayTotals() async {
    final now = ref.read(clockProvider)();
    final date = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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
