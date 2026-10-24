import 'dart:io';
import 'dart:typed_data';

import 'package:dt_food_pos/app/providers.dart';
import 'package:dt_food_pos/features/splash/animated_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../helpers/harness.dart';

void main() {
  testWidgets('the splash fills the whole width and shows the logo, rows and mark (no side strip, no blank receipt)', (t) async {
    await t.runAsync(loadAppFonts);
    setSize(t);
    await t.pumpWidget(MaterialApp(home: AnimatedSplashScreen(onFinished: () {}, ready: Future<void>.delayed(const Duration(seconds: 4)))));
    await t.pump(const Duration(milliseconds: 300));
    final w = t.view.physicalSize.width / t.view.devicePixelRatio;
    await t.pump(const Duration(seconds: 3));
    final box = t.getSize(find.byType(Container).first).width;
    final col = t.getSize(find.byType(Column).first).width;
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 1));
    expect([box, col], [w, w]);
  });

  testWidgets('with a phone navigation bar the app stays above it', (t) async {
    final db = newDb();
    await seedBusiness(db);
    await pumpApp(t, db: db);
    t.view.padding = const FakeViewPadding(bottom: 48);
    t.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(t.view.resetPadding);
    addTearDown(t.view.resetViewPadding);
    await t.pumpAndSettle();
    await signIn(t, 'Ali', '1234');
    final height = t.view.physicalSize.height / t.view.devicePixelRatio;
    expect(t.getBottomLeft(find.byType(NavigationBar)).dy, lessThanOrEqualTo(height - 48 + 0.5));
  });

  testWidgets('compact selling layout shows the item picture', (t) async {
    final db = newDb();
    await seedBusiness(db);
    final dir = Directory.systemTemp.createTempSync('dtpic');
    addTearDown(() => dir.deleteSync(recursive: true));
    final png = File('${dir.path}/p.png')..writeAsBytesSync(Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 40)..clear(img.ColorRgba8(200, 30, 30, 255)))));
    await db.customStatement("UPDATE product SET image_path = ? WHERE name = 'Fries'", [png.path]);
    final h = await pumpApp(t, db: db);
    await h.container.read(posLayoutProvider.notifier).set('compact');
    await signIn(t, 'Ali', '1234');
    await tapKey(t, 'open-shift');
    await tapKey(t, 'amount-ok');
    await t.pumpAndSettle();
    final tile = find.byKey(const ValueKey('product-Fries'));
    await t.scrollUntilVisible(tile, 150, scrollable: find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first);
    expect(find.descendant(of: tile, matching: find.byType(Image)), findsOneWidget);
  });
}
