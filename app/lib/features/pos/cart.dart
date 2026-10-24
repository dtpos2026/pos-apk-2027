import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/pos_service.dart';
import '../../data/print_service.dart';
import '../../data/queries.dart';
import '../../domain/bill.dart';

class CartState {
  const CartState({this.items = const [], this.orderType = 'counter', this.draftId, this.config = const BillConfig(), this.customerId, this.tableId});
  final List<CartItem> items;
  final String orderType;
  final String? draftId;
  final BillConfig config;
  final String? customerId;
  final String? tableId;

  bool get isEmpty => items.isEmpty;
  BillResult get bill => calculateBill([
        for (var i = 0; i < items.length; i++)
          BillLineInput(
              id: '$i',
              unitPriceMinor: items[i].unitPriceMinor,
              qtyMilli: items[i].qtyMilli,
              modifiersMinor: items[i].modifiersMinor,
              lineDiscountMinor: items[i].lineDiscountMinor,
              taxRateBp: items[i].taxRateBp,
              taxInclusive: items[i].taxInclusive)
      ], config);

  CartState copyWith({List<CartItem>? items, String? orderType, String? draftId, bool clearDraft = false, BillConfig? config, String? customerId, bool clearCustomer = false, String? tableId, bool clearTable = false}) => CartState(
      items: items ?? this.items,
      orderType: orderType ?? this.orderType,
      draftId: clearDraft ? null : (draftId ?? this.draftId),
      config: config ?? this.config,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      tableId: clearTable ? null : (tableId ?? this.tableId));
}

/// The order being rung up. Every change is written to the database (as a draft), so a crash, kill or dead battery
/// loses nothing: [restore] brings the cart back on the next start.
/// What happened when the cashier pressed Send to kitchen.
enum KitchenSend { sent, nothingNew, failed, busy }

class CartNotifier extends Notifier<CartState> {
  Future<void> _queue = Future.value();

  @override
  CartState build() => const CartState();

  PosService get _pos => ref.read(posServiceProvider);

  void _persist() {
    final staffId = ref.read(sessionProvider)?.staffId;
    _queue = _queue.then((_) async {
      // Read the state when the save RUNS, not when it was requested: two quick taps must update ONE draft,
      // never create two (the first save is what assigns the draft id).
      final s = state;
      if (s.isEmpty) {
        if (s.draftId != null) await _pos.discardDraft(s.draftId!);
        if (state.isEmpty) state = state.copyWith(clearDraft: true);
        return;
      }
      final id = await _pos.saveDraft(
          DraftOrder(id: s.draftId, orderType: s.orderType, items: s.items, config: s.config, tableId: s.tableId, customerId: s.customerId),
          staffId: staffId);
      if (state.draftId == null) state = state.copyWith(draftId: id);
    }).catchError((Object _) {
      // A failed background save must not crash the UI; the next change retries with the full cart.
    });
  }

  /// Waits for pending saves (used before charging so the stored draft matches the screen).
  Future<void> flush() => _queue;

  Future<void> restore() async {
    final id = await _pos.latestDraftId();
    if (id == null) return;
    final d = await _pos.loadDraft(id);
    if (d == null) return;
    state = CartState(items: d.items, orderType: d.orderType, draftId: id, config: d.config, customerId: d.customerId, tableId: d.tableId);
  }

  /// A fixed discount can become larger than the bill after an item is removed; drop it instead of crashing.
  CartState _valid(CartState s) {
    try {
      s.bill;
      return s;
    } on ArgumentError {
      return s.copyWith(config: BillConfig(serviceChargeBp: s.config.serviceChargeBp, serviceChargeTaxBp: s.config.serviceChargeTaxBp, deliveryChargeMinor: s.config.deliveryChargeMinor, tipMinor: s.config.tipMinor, rounding: s.config.rounding));
    }
  }

  void add(MenuProduct p) {
    final i = state.items.indexWhere((x) => x.productId == p.id && x.modifiers.isEmpty && x.note == null && x.lineDiscountMinor == 0);
    final items = [...state.items];
    final step = p.unit == 'kg' || p.unit == 'l' ? 500 : 1000;
    if (i >= 0) {
      final x = items[i];
      items[i] = CartItem(productId: x.productId, name: x.name, qtyMilli: x.qtyMilli + step, unitPriceMinor: x.unitPriceMinor, taxRateBp: x.taxRateBp, taxInclusive: x.taxInclusive, station: x.station, kotSentMilli: x.kotSentMilli);
    } else {
      items.add(CartItem(productId: p.id, name: p.name, qtyMilli: step, unitPriceMinor: p.priceMinor, taxRateBp: p.taxBp, taxInclusive: p.taxInclusive, station: p.station));
    }
    state = _valid(state.copyWith(items: items));
    _persist();
  }

  /// Adds an item that was configured (variant, add-ons, note). The same configuration merges into one line.
  void addConfigured(CartItem item) {
    String key(CartItem i) => '${i.productId}|${i.variantId}|${(i.modifiers.map((m) => m.optionId ?? m.name).toList()..sort()).join(',')}|${i.note ?? ''}';
    final items = [...state.items];
    final i = items.indexWhere((x) => key(x) == key(item) && x.lineDiscountMinor == 0);
    if (i >= 0) {
      final x = items[i];
      items[i] = CartItem(productId: x.productId, variantId: x.variantId, name: x.name, qtyMilli: x.qtyMilli + item.qtyMilli, unitPriceMinor: x.unitPriceMinor, modifiers: x.modifiers, taxRateBp: x.taxRateBp, taxInclusive: x.taxInclusive, note: x.note, station: x.station, kotSentMilli: x.kotSentMilli);
    } else {
      items.add(item);
    }
    state = _valid(state.copyWith(items: items));
    _persist();
  }

  void changeQty(int index, int deltaMilli) {
    final items = [...state.items];
    final x = items[index];
    final q = x.qtyMilli + deltaMilli;
    if (q <= 0) {
      items.removeAt(index);
    } else {
      items[index] = CartItem(productId: x.productId, name: x.name, qtyMilli: q, unitPriceMinor: x.unitPriceMinor, taxRateBp: x.taxRateBp, taxInclusive: x.taxInclusive, station: x.station, modifiers: x.modifiers, note: x.note, variantId: x.variantId, lineDiscountMinor: x.lineDiscountMinor, kotSentMilli: x.kotSentMilli);
    }
    state = _valid(state.copyWith(items: items));
    _persist();
  }

  void setOrderType(String t) {
    state = state.copyWith(orderType: t);
    if (!state.isEmpty) _persist();
  }

  void setCustomer(String? id) {
    state = id == null ? state.copyWith(clearCustomer: true) : state.copyWith(customerId: id);
    if (!state.isEmpty) _persist();
  }

  void setTable(String? id) {
    state = id == null ? state.copyWith(clearTable: true) : state.copyWith(tableId: id, orderType: 'dine_in');
    if (!state.isEmpty) _persist();
  }

  /// Opens the unsettled order of a table (or starts a fresh cart for it).
  Future<void> openTable(String tableId, {String? orderId}) async {
    await flush();
    if (orderId != null) {
      final d = await _pos.loadDraft(orderId);
      if (d != null) {
        state = CartState(items: d.items, orderType: d.orderType, draftId: orderId, config: d.config, customerId: d.customerId, tableId: d.tableId);
        return;
      }
    }
    state = CartState(orderType: 'dine_in', tableId: tableId);
  }

  bool _sending = false;

  /// Sends the order to the kitchen: it becomes a RUNNING order (same order id as its bill) and the cart is cleared so the
  /// cashier can start the next customer. Resume it from Bills or Tables to add more or to take payment. If anything
  /// fails the cart stays exactly as it was. A second tap while sending is ignored, so no duplicate ticket is possible.
  Future<KitchenSend> sendToKitchen(PrintService printer) async {
    if (_sending) return KitchenSend.busy;
    _sending = true;
    try {
      await flush();
      final id = state.draftId;
      if (id == null) return KitchenSend.nothingNew;
      final r = await printer.sendToKitchen(id);
      if (!r.sent) return KitchenSend.nothingNew;
      printer.processQueue();
      state = CartState(orderType: state.orderType);
      return KitchenSend.sent;
    } catch (_) {
      return KitchenSend.failed;
    } finally {
      _sending = false;
    }
  }

  /// Parks the current order and clears the screen for the next customer.
  Future<void> hold() async {
    await flush();
    final s = state;
    if (s.isEmpty) return;
    await _pos.saveDraft(DraftOrder(id: s.draftId, orderType: s.orderType, items: s.items, config: s.config, tableId: s.tableId, customerId: s.customerId, held: true), staffId: ref.read(sessionProvider)?.staffId);
    state = CartState(orderType: s.orderType);
  }

  Future<void> resume(String orderId) async {
    await flush();
    if (!state.isEmpty) await hold();
    final d = await _pos.loadDraft(orderId);
    if (d == null) return;
    state = CartState(items: d.items, orderType: d.orderType, draftId: orderId, config: d.config, customerId: d.customerId, tableId: d.tableId);
    _persist(); // back to a normal (non-held) draft
  }

  void setConfig(BillConfig c) {
    state = state.copyWith(config: c);
    if (!state.isEmpty) _persist();
  }

  void clear() {
    state = state.copyWith(items: const []);
    _persist();
  }

  /// Settles the current cart. Returns the result and resets the cart for the next customer.
  Future<SettledOrder> checkout(List<SettlePayment> payments) async {
    await flush();
    final id = state.draftId;
    if (id == null) throw PosException('empty_order', 'Nothing to charge');
    final staffId = ref.read(sessionProvider)!.staffId;
    final r = await _pos.settleOrder(orderId: id, payments: payments, staffId: staffId, shiftId: ref.read(shiftProvider));
    state = CartState(orderType: state.orderType);
    return r;
  }
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
