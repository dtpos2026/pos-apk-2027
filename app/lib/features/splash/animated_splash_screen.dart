// Animated splash for DT Food POS: Lottie logo + staggered text, then onFinished().
//
// STATUS: compiles, passes `flutter analyze` and widget tests (test/ui/splash_test.dart). Not yet run on a device.
//
// pubspec.yaml:
//   dependencies:
//     lottie: ^3.1.0
//   flutter:
//     assets:
//       - assets/brand/dt_splash_logo.json
//       - assets/brand/dt_mark_white.png
//     fonts:
//       - family: Inter
//         fonts:
//           - asset: assets/fonts/Inter-Medium.otf
//             weight: 500
//           - asset: assets/fonts/Inter-SemiBold.otf
//             weight: 600
//           - asset: assets/fonts/Inter-ExtraBold.otf
//             weight: 800
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({
    super.key,
    required this.onFinished,
    this.ready,
    this.hold = const Duration(milliseconds: 500),
  });

  /// Called once the animation has played AND [ready] has completed.
  final VoidCallback onFinished;

  /// App start-up work (open local DB, check licence...). The splash never ends before this does.
  final Future<void>? ready;

  /// Pause on the finished frame before leaving.
  final Duration hold;

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> with TickerProviderStateMixin {
  static const _frames = 130.0; // length of dt_splash_logo.json (60 fps)
  static const _lavender = Color(0xFFF7CFCF);

  late final AnimationController _logo = AnimationController(vsync: this);
  late final AnimationController _dots =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _finishing = false;

  Animation<double> _fade(double from, double to) => CurvedAnimation(
        parent: _logo,
        curve: Interval(from / _frames, to / _frames, curve: Curves.easeOutCubic),
      );

  @override
  void initState() {
    super.initState();
    _logo.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _dots.repeat();
        _finish();
      }
    });
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await Future.wait([Future.delayed(widget.hold), if (widget.ready != null) widget.ready!]);
    if (mounted) widget.onFinished();
  }

  @override
  void dispose() {
    _logo.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final size = MediaQuery.of(context).size;
    final logoSide = size.width * 0.86;

    return Scaffold(
      body: Container(
        // Scaffold gives its body loose constraints: without an explicit width this shrank to the logo's width (86%) and left a strip
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFC92A2A), Color(0xFF6E0F0F)],
          ),
        ),
        child: DecoratedBox(
          position: DecorationPosition.background,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.4, -0.5),
              radius: 0.9,
              colors: [const Color(0xFFFF6B6B).withValues(alpha: 0.45), const Color(0x00FF6B6B)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 5),
                SizedBox(
                  width: logoSide,
                  height: logoSide,
                  child: Lottie.asset(
                    'assets/brand/dt_splash_logo.json',
                    controller: _logo,
                    onLoaded: (c) {
                      _logo.duration = c.duration;
                      reduceMotion ? _logo.value = 1 : _logo.forward();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                _Reveal(
                  animation: _fade(92, 116),
                  child: const Text('DT Food POS',
                      style: TextStyle(
                          fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 40, letterSpacing: -0.8, color: Colors.white)),
                ),
                const SizedBox(height: 10),
                _Reveal(
                  animation: _fade(104, 128),
                  child: const Text('Offline-first restaurant POS',
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 16, color: _lavender)),
                ),
                const SizedBox(height: 36),
                FadeTransition(
                  opacity: _fade(112, 124),
                  child: AnimatedBuilder(
                    animation: _dots,
                    builder: (_, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (i) {
                        final p = ((_dots.value - i * 0.18) % 1.0);
                        final o = 0.35 + 0.65 * (0.5 + 0.5 * (p < 0.5 ? p * 2 : (1 - p) * 2));
                        return Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: o), shape: BoxShape.circle),
                        );
                      }),
                    ),
                  ),
                ),
                const Spacer(flex: 6),
                FadeTransition(
                  opacity: _fade(60, 90),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/brand/dt_mark_white.png', width: 22, height: 22),
                      const SizedBox(width: 10),
                      const Text('Powered by Digital Target',
                          style: TextStyle(
                              fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.6, color: _lavender)),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fade + small upward slide, driven by [animation].
class _Reveal extends StatelessWidget {
  const _Reveal({required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(animation),
          child: child,
        ),
      );
}
