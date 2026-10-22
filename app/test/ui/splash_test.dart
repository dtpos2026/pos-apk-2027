import 'package:dt_food_pos/features/splash/animated_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('splash plays the Lottie logo, reveals the text, waits for start-up work, then hands over', (t) async {
    await t.runAsync(loadAppFonts);
    setSize(t);
    var finished = 0;
    final startup = Future<void>.delayed(const Duration(seconds: 4));
    await t.pumpWidget(MaterialApp(home: AnimatedSplashScreen(ready: startup, onFinished: () => finished++)));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Powered by Digital Target'), findsOneWidget);
    expect(find.text('DT Food POS'), findsOneWidget);

    // animation (130 frames at 60 fps = 2.17 s) is done, but start-up work (4 s) is not: still on the splash
    await t.pump(const Duration(seconds: 3));
    expect(finished, 0);

    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 1));
    expect(finished, 1);
  });

  testWidgets('with reduced motion the splash shows the final frame immediately', (t) async {
    setSize(t);
    var finished = 0;
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true, size: Size(412, 860)),
      child: MaterialApp(home: AnimatedSplashScreen(onFinished: () => finished++, hold: const Duration(milliseconds: 100))),
    ));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('DT Food POS'), findsOneWidget);
    expect(finished, 1);
  });
}
