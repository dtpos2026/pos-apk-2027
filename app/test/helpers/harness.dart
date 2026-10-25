import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';

import 'package:dt_food_pos/app/app.dart';
import 'package:dt_food_pos/app/device_channel.dart';
import 'package:dt_food_pos/data/print_service.dart';
import 'package:dt_food_pos/cloud/access_controller.dart';
import 'package:dt_food_pos/cloud/cloud_gateway.dart';
import 'package:dt_food_pos/app/import_picker.dart';
import 'package:dt_food_pos/app/logo_picker.dart';
import 'package:dt_food_pos/app/share_service.dart';
import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/data/auth_service.dart';
import 'package:dt_food_pos/data/db/database.dart';
import 'package:dt_food_pos/data/menu_service.dart';
import 'package:dt_food_pos/data/setup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

final _boundary = GlobalKey();
bool _fontsLoaded = false;

/// Widget tests render with the Ahem placeholder font unless real fonts are loaded; that makes every glyph
/// one em wide, which causes bogus overflows and useless screenshots. Load the app's own fonts and the icon font.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  Future<ByteData> bytes(String path) async => ByteData.sublistView(await File(path).readAsBytes());
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'ExtraBold']) {
    inter.addFont(bytes('assets/fonts/Inter-$w.otf'));
  }
  await inter.load();
  final naskh = FontLoader('NotoNaskhArabic')..addFont(bytes('assets/fonts/NotoNaskhArabic.ttf'));
  await naskh.load();
  final mono = FontLoader('JetBrainsMono')..addFont(bytes('assets/fonts/JetBrainsMono-Regular.ttf'));
  await mono.load();
  // flutter_tester lives at <sdk>/bin/cache/artifacts/engine/<platform>/flutter_tester
  final exe = Platform.resolvedExecutable;
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? (exe.contains('/bin/cache/') ? exe.substring(0, exe.indexOf('/bin/cache/')) : '/opt/flutter-sdk/flutter');
  final icons = FontLoader('MaterialIcons')..addFont(bytes('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  _fontsLoaded = true;
}

/// Fixed clock so invoice numbers and dates are deterministic.
final testNow = DateTime(2026, 1, 12, 19, 40);

class Harness {
  Harness(this.db, this.container);
  final AppDatabase db;
  final ProviderContainer container;
}

AppDatabase newDb() => AppDatabase(NativeDatabase.memory());

/// Phone (portrait) or tablet (landscape) logical size.
void setSize(WidgetTester t, {bool tablet = false}) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = tablet ? const Size(1280, 800) : const Size(412, 860);
  addTearDown(t.view.reset);
}

class FakeShare implements ShareService {
  final shared = <String>[];
  final files = <String>[];
  @override
  Future<void> shareText(String text, {String? subject}) async => shared.add(text);
  @override
  Future<void> shareFile(String path, {String? mimeType, String? subject}) async => files.add(path);
  final multi = <({List<String> paths, String? text})>[];
  @override
  Future<void> shareFiles(List<String> paths, {String? text, String? mimeType, String? subject}) async => multi.add((paths: paths, text: text));
}

/// Stands in for Android's Downloads / gallery: remembers what was saved and where.
class FakeSaver implements PhoneFileSaver {
  final saved = <({String name, String mime, bool gallery})>[];
  @override
  Future<String> save({required String path, required String name, required String mime, bool gallery = false}) async {
    saved.add((name: name, mime: mime, gallery: gallery));
    return '${gallery ? 'Pictures' : 'Downloads'}/DT Food POS/$name';
  }
}

class FakeImportPicker implements ImportFilePicker {
  FakeImportPicker(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
  @override
  Future<({String name, Uint8List bytes})?> pick() async => (name: name, bytes: bytes);
}

class FakeLogoPicker implements LogoPicker {
  FakeLogoPicker(this.bytes);
  Uint8List? bytes;
  @override
  Future<Uint8List?> pick() async => bytes;
  @override
  Future<Uint8List?> capture() async => bytes;
}

Future<Harness> pumpApp(WidgetTester t, {AppDatabase? db, bool tablet = false, Locale? locale, Directory? backupDir, LogoPicker? logoPicker, Directory? logoDir, ShareService? share, FakeSaver? saver, ImportFilePicker? importPicker, CloudGateway? cloud, BluetoothPrinterScanner? btScanner, TransportFactory? transport, String? platformPhoneId, List<Override> extra = const []}) async {
  await t.runAsync(loadAppFonts);
  setSize(t, tablet: tablet);
  final database = db ?? newDb();
  addTearDown(database.close);
  final container = ProviderContainer(overrides: [
    databaseProvider.overrideWithValue(database),
    clockProvider.overrideWithValue(() => testNow),
    authServiceProvider.overrideWithValue(AuthService(database, now: () => testNow, iterations: 1000)),
    if (backupDir != null) backupDirProvider.overrideWith((ref) async => backupDir),
    logoDirProvider.overrideWithValue(logoDir ?? Directory.systemTemp.createTempSync('dtlogo')),
    if (logoPicker != null) logoPickerProvider.overrideWithValue(logoPicker),
    if (share != null) shareServiceProvider.overrideWithValue(share),
    phoneFileSaverProvider.overrideWithValue(saver ?? FakeSaver()),
    if (importPicker != null) importFilePickerProvider.overrideWithValue(importPicker),
    if (cloud != null) cloudGatewayProvider.overrideWithValue(cloud),
    if (btScanner != null) bluetoothScannerProvider.overrideWithValue(btScanner),
    if (platformPhoneId != null) platformPhoneIdProvider.overrideWithValue(() async => platformPhoneId),
    if (transport != null) printerTransportProvider.overrideWithValue(transport),
    appVersionProvider.overrideWithValue('1.0.0'),
    ...extra,
  ]);
  addTearDown(container.dispose);
  if (locale != null) container.read(localeProvider.notifier).state = locale;
  await t.pumpWidget(UncontrolledProviderScope(container: container, child: RepaintBoundary(key: _boundary, child: const DtFoodPosApp())));
  await t.pumpAndSettle();
  return Harness(database, container);
}

/// Configures the business and seeds a small menu, bypassing the UI (for tests that start after setup).
Future<String> seedBusiness(AppDatabase db, {String country = 'PK', bool menu = true}) async {
  final auth = AuthService(db, now: () => testNow, iterations: 1000);
  final ownerId = await SetupService(db, auth, now: () => testNow).completeSetup(businessName: 'Burger Point', ownerName: 'Ali', pin: '1234', country: country, phone: '0300-0000000', address: 'Main Bazaar, Burewala');
  if (menu) {
    final m = MenuService(db, now: () => testNow);
    await m.saveProduct(name: 'Zinger Burger', priceMinor: 45000, categoryName: 'Burgers', sku: 'BRG-1', staffId: ownerId);
    await m.saveProduct(name: 'Beef Burger', priceMinor: 55000, categoryName: 'Burgers', sku: 'BRG-2', staffId: ownerId);
    await m.saveProduct(name: 'Fries', priceMinor: 15000, categoryName: 'Sides', sku: 'SDE-1', staffId: ownerId);
    await m.saveProduct(name: 'Cola 500ml', priceMinor: 10000, categoryName: 'Drinks', sku: 'DRK-1', staffId: ownerId);
    await m.saveProduct(name: 'Chicken Karahi (kg)', priceMinor: 180000, categoryName: 'Desi', sku: 'DSI-1', staffId: ownerId);
    await db.customStatement("UPDATE product SET unit = 'kg' WHERE sku = 'DSI-1'");
  }
  return ownerId;
}

Future<void> typeInto(WidgetTester t, Finder f, String text) async {
  if (f.evaluate().isNotEmpty) await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pump();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await t.tap(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

Future<void> signIn(WidgetTester t, String name, String pin) async {
  await t.tap(find.byKey(ValueKey('staff-$name')));
  await t.pumpAndSettle();
  for (final d in pin.split('')) {
    await tapKey(t, 'key-$d');
  }
  await tapKey(t, 'key-ok');
}

/// Saves a PNG of the app when SCREENSHOT_DIR is set (used to look at the UI during development). No-op otherwise.
Future<void> shot(WidgetTester t, String name) async {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  if (dir == null) return;
  await t.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await b.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Opens a screen from the shell whatever the layout: the rail on tablets, the bottom bar or "More" on phones.
Future<void> openTab(WidgetTester t, String key, String label) async {
  final direct = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
  final rail = find.descendant(of: find.byType(NavigationRail), matching: find.text(label));
  if (direct.evaluate().isNotEmpty) {
    await t.tap(direct.first);
  } else if (rail.evaluate().isNotEmpty) {
    await t.ensureVisible(rail.first); // a tall rail scrolls: bring the destination into view first
    await t.pumpAndSettle();
    await t.tap(rail.first);
  } else {
    await t.tap(find.byKey(const ValueKey('nav-more')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(ValueKey('more-$key')));
  }
  await t.pumpAndSettle();
}

/// Scrolls the selling-screen grid until the item is on screen, then taps it once.
Future<void> tapProduct(WidgetTester t, String name) async {
  final f = find.byKey(ValueKey('product-$name'));
  if (f.evaluate().isEmpty || !t.getRect(f).overlaps(Offset.zero & t.view.physicalSize / t.view.devicePixelRatio)) {
    await t.scrollUntilVisible(f, 150, scrollable: find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first);
  }
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

Override menuImageDirOverride(Directory dir) => menuImageDirProvider.overrideWithValue(dir);

/// Scrolls the horizontal theme row in Settings until [key] is visible.
Future<void> showThemeCard(WidgetTester t, String key) async {
  final vertical = find.byWidgetPredicate((w) => w is Scrollable && (w.axisDirection == AxisDirection.down || w.axisDirection == AxisDirection.up));
  await t.scrollUntilVisible(find.byKey(const ValueKey('theme-red')), 200, scrollable: vertical.last);
  await t.pumpAndSettle();
  final row = find.byWidgetPredicate((w) => w is Scrollable && (w.axisDirection == AxisDirection.right || w.axisDirection == AxisDirection.left));
  await t.scrollUntilVisible(find.byKey(ValueKey(key)), 200, scrollable: row.first);
  await t.pumpAndSettle();
  await t.ensureVisible(find.byKey(ValueKey(key)));
  await t.pumpAndSettle();
}

/// The innermost vertical scrolling list on screen (the settings page has a horizontal theme row inside it).
Finder get verticalScroll => find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last;

/// The text on the receipt shown after a sale (what the printer prints).
String receiptPaperText(WidgetTester t) =>
    t.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('receipt-paper')), matching: find.byType(Text))).map((w) => w.data ?? '').join('\n');
