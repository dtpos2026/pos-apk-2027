import 'dart:io';
import 'package:flutter/material.dart' show Locale, ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_service.dart';
import '../data/bill_history.dart';
import '../data/customer_service.dart';
import '../data/db_helper.dart';
import '../data/expense_service.dart';
import '../data/inventory_service.dart';
import '../data/report_service.dart';
import '../data/staff_service.dart';
import '../data/table_service.dart';
import '../data/backup_service.dart';
import '../data/db/database.dart';
import '../data/menu_import.dart';
import '../data/menu_service.dart';
import '../data/pos_service.dart';
import '../data/print_service.dart';
import '../data/queries.dart';
import '../data/receipt_settings.dart';
import '../domain/receipt_doc.dart';
import '../domain/receipt_template.dart';
import 'bluetooth_printing.dart' show BluetoothPrinterScanner;
import 'import_picker.dart';
import 'logo_picker.dart';
import 'share_service.dart';
import 'themes.dart';
import 'text_rasterizer.dart';
import '../data/shift_service.dart';

/// Overridden in main() (file database) and in tests (in-memory database).
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider must be overridden'));
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final posServiceProvider = Provider<PosService>((ref) => PosService(ref.watch(databaseProvider), now: ref.watch(clockProvider)));
final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(databaseProvider), now: ref.watch(clockProvider)));
final shiftServiceProvider = Provider<ShiftService>((ref) => ShiftService(ref.watch(databaseProvider), ref.watch(posServiceProvider), now: ref.watch(clockProvider)));
final dbHelperProvider = Provider<DbHelper>((ref) => DbHelper(ref.watch(databaseProvider), now: ref.watch(clockProvider)));
final customerServiceProvider = Provider<CustomerService>((ref) => CustomerService(ref.watch(dbHelperProvider)));
final expenseServiceProvider = Provider<ExpenseService>((ref) => ExpenseService(ref.watch(dbHelperProvider)));
final inventoryServiceProvider = Provider<InventoryService>((ref) => InventoryService(ref.watch(dbHelperProvider)));
final tableServiceProvider = Provider<TableService>((ref) => TableService(ref.watch(dbHelperProvider)));
final reportServiceProvider = Provider<ReportService>((ref) => ReportService(ref.watch(dbHelperProvider)));

/// Where exported report files are written before sharing. Defaults to the system temp (cache) folder.
final exportDirProvider = Provider<Directory>((ref) => Directory.systemTemp);
final billHistoryProvider = Provider<BillHistory>((ref) => BillHistory(ref.watch(dbHelperProvider)));
final staffServiceProvider = Provider<StaffService>((ref) => StaffService(ref.watch(dbHelperProvider), ref.watch(authServiceProvider)));

final importFilePickerProvider = Provider<ImportFilePicker>((ref) => const SystemImportFilePicker());
final shareServiceProvider = Provider<ShareService>((ref) => const SystemShareService());

/// Which screen the app shell shows ('pos', 'tables', ...). Other screens switch it (for example Tables opens Sell).
class ShellTabNotifier extends Notifier<String> {
  @override
  String build() => 'pos';
  void go(String key) => state = key;
}

final shellTabProvider = NotifierProvider<ShellTabNotifier, String>(ShellTabNotifier.new);

final textRasterizerProvider = Provider<TextRasterizer>((ref) => const FlutterTextRasterizer());
/// How print jobs reach printers. main() supplies Bluetooth + LAN; the default (and tests) use LAN only.
final printerTransportProvider = Provider<TransportFactory>((ref) => defaultTransport);
final bluetoothScannerProvider = Provider<BluetoothPrinterScanner?>((ref) => null);
final printServiceProvider = Provider<PrintService>((ref) => PrintService(ref.watch(databaseProvider), now: ref.watch(clockProvider), rasterizer: ref.watch(textRasterizerProvider), transport: ref.watch(printerTransportProvider)));

/// Folder for the business logo file. Overridden in main() (and in tests).
final logoDirProvider = Provider<Directory>((ref) => throw UnimplementedError('logoDirProvider must be overridden'));
final logoStoreProvider = Provider<LogoStore>((ref) => LogoStore(ref.watch(databaseProvider), ref.watch(logoDirProvider), now: ref.watch(clockProvider)));
final logoPickerProvider = Provider<LogoPicker>((ref) => const GalleryLogoPicker());
final receiptTemplateStoreProvider = Provider<ReceiptTemplateStore>((ref) => ReceiptTemplateStore(ref.watch(databaseProvider), now: ref.watch(clockProvider)));
final billDesignProvider = FutureProvider<BillDesign>((ref) => ref.watch(receiptTemplateStoreProvider).load());

final menuServiceProvider = Provider<MenuService>((ref) => MenuService(ref.watch(databaseProvider), now: ref.watch(clockProvider)));
final menuImporterProvider = Provider<MenuImporter>((ref) => MenuImporter(ref.watch(databaseProvider), now: ref.watch(clockProvider)));
final backupServiceProvider = Provider<BackupService>((ref) => BackupService(ref.watch(databaseProvider)));

/// Where backups are written. Overridden in main() with the app documents directory (and in tests with a temp dir).
final backupDirProvider = FutureProvider<Directory>((ref) => throw UnimplementedError('backupDirProvider must be overridden'));

final businessProvider = FutureProvider<Business?>((ref) => loadBusiness(ref.watch(databaseProvider)));
final staffListProvider = FutureProvider<List<StaffEntry>>((ref) => loadStaff(ref.watch(databaseProvider)));
final categoriesProvider = FutureProvider<List<MenuCategory>>((ref) => loadCategories(ref.watch(databaseProvider)));
final paymentMethodsProvider = FutureProvider<List<PaymentMethodInfo>>((ref) => loadPaymentMethods(ref.watch(databaseProvider)));

class ProductFilter {
  const ProductFilter({this.categoryId, this.search = ''});
  final String? categoryId;
  final String search;
  @override
  bool operator ==(Object other) => other is ProductFilter && other.categoryId == categoryId && other.search == search;
  @override
  int get hashCode => Object.hash(categoryId, search);
}

final productsProvider = FutureProvider.family<List<MenuProduct>, ProductFilter>(
    (ref, f) => loadProducts(ref.watch(databaseProvider), categoryId: f.categoryId, search: f.search));

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');
  Future<void> set(String code) async {
    state = Locale(code);
    await setSetting(ref.read(databaseProvider), 'language', code, ref.read(clockProvider)().millisecondsSinceEpoch);
  }

  /// Loads the saved language (called once at start-up).
  Future<void> restore() async {
    final saved = await getSetting(ref.read(databaseProvider), 'language');
    if (saved != null) state = Locale(saved);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

/// Chosen colour theme id (see [themePresets]); saved in the settings table.
class ThemeIdNotifier extends Notifier<String> {
  @override
  String build() => 'dt';
  Future<void> set(String id) async {
    state = id;
    await setSetting(ref.read(databaseProvider), 'theme', id, ref.read(clockProvider)().millisecondsSinceEpoch);
  }

  Future<void> restore() async {
    final saved = await getSetting(ref.read(databaseProvider), 'theme');
    if (saved != null) state = presetById(saved).id;
  }
}

final themeIdProvider = NotifierProvider<ThemeIdNotifier, String>(ThemeIdNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  Future<void> set(ThemeMode m) async {
    state = m;
    await setSetting(ref.read(databaseProvider), 'theme_mode', modeId(m), ref.read(clockProvider)().millisecondsSinceEpoch);
  }

  Future<void> restore() async {
    final saved = await getSetting(ref.read(databaseProvider), 'theme_mode');
    if (saved != null) state = modeFromId(saved);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Loads every saved appearance setting (language, theme, mode). Called once at start-up.
Future<void> restoreAppearance(WidgetRef ref) async {
  await ref.read(localeProvider.notifier).restore();
  await ref.read(themeIdProvider.notifier).restore();
  await ref.read(themeModeProvider.notifier).restore();
}

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  Future<PinResult> signIn(String staffId, String pin) async {
    final result = await ref.read(authServiceProvider).verifyPin(staffId, pin);
    if (result == PinResult.ok) {
      state = await loadSession(ref.read(databaseProvider), staffId);
      await ref.read(shiftProvider.notifier).refresh();
    }
    return result;
  }

  /// Sets the session without a PIN check (only right after first-run setup, where the owner just chose the PIN).
  Future<void> startFor(String staffId) async {
    state = await loadSession(ref.read(databaseProvider), staffId);
    await ref.read(shiftProvider.notifier).refresh();
  }

  void signOut() => state = null;
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

/// Id of the signed-in user's open cash shift, or null.
class ShiftNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  Future<void> refresh() async {
    final s = ref.read(sessionProvider);
    state = s == null ? null : await openShiftId(ref.read(databaseProvider), s.staffId);
  }

  Future<void> open(int openingMinor) async {
    final s = ref.read(sessionProvider)!;
    state = await ref.read(shiftServiceProvider).openShift(s.staffId, openingCashMinor: openingMinor);
  }

  Future<int> close(int countedMinor) async {
    final variance = await ref.read(shiftServiceProvider).closeShift(state!, countedMinor: countedMinor);
    state = null;
    return variance;
  }
}

final shiftProvider = NotifierProvider<ShiftNotifier, String?>(ShiftNotifier.new);
