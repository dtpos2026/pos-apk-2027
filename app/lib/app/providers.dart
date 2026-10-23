import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_service.dart';
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
import 'logo_picker.dart';
import 'text_rasterizer.dart';
import '../data/shift_service.dart';

/// Overridden in main() (file database) and in tests (in-memory database).
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError('databaseProvider must be overridden'));
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final posServiceProvider = Provider<PosService>((ref) => PosService(ref.watch(databaseProvider), now: ref.watch(clockProvider)));
final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(databaseProvider), now: ref.watch(clockProvider)));
final shiftServiceProvider = Provider<ShiftService>((ref) => ShiftService(ref.watch(databaseProvider), ref.watch(posServiceProvider), now: ref.watch(clockProvider)));
final textRasterizerProvider = Provider<TextRasterizer>((ref) => const FlutterTextRasterizer());
final printServiceProvider = Provider<PrintService>((ref) => PrintService(ref.watch(databaseProvider), now: ref.watch(clockProvider), rasterizer: ref.watch(textRasterizerProvider)));

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
