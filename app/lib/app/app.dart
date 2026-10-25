import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/access_controller.dart';
import '../features/cloud/cloud_reporter.dart';
import '../features/cloud/cloud_screens.dart';
import '../features/login/login_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/home_shell.dart';
import 'feedback.dart';
import 'providers.dart';
import 'strings.dart';
import 'theme.dart';
import 'theme_style.dart';
import 'themes.dart';

class DtFoodPosApp extends ConsumerWidget {
  const DtFoodPosApp({super.key, this.home});

  /// Tests and the splash flow can replace the first screen.
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final themeId = ref.watch(effectiveThemeIdProvider);
    final style = ref.watch(themeStyleProvider).value;
    final preset = themeId == 'studio' ? (style ?? ThemeStyle.defaults).toPreset() : presetById(themeId);
    ref.watch(textOverridesProvider); // loads the owner's edited labels
    final revision = ref.watch(textRevisionProvider);
    final access = ref.watch(accessProvider);
    final blocked = access is AccessDecided && !access.decision.allowed;
    final fontScale = themeId == 'studio' ? (style ?? ThemeStyle.defaults).fontScale : 1.0;
    return MaterialApp(
      title: 'DT Food POS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(spec: preset),
      darkTheme: buildTheme(brightness: Brightness.dark, spec: preset),
      themeMode: ref.watch(themeModeProvider),
      locale: locale,
      supportedLocales: Strings.supported,
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      // Android draws apps edge-to-edge: keep every screen (and bottom sheet) above the phone's navigation bar
      builder: (context, child) => MediaQuery(
        // the owner's text size multiplies the phone's own text-size setting
        data: MediaQuery.of(context).copyWith(textScaler: fontScale == 1.0 ? MediaQuery.textScalerOf(context) : _Scaled(MediaQuery.textScalerOf(context), fontScale)),
        child: TextRevision(
        revision: revision,
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          // the "blocked / suspended / payment pending" screen is laid over everything, so a change made in the panel shows at once,
          // also when a page or dialog is open on top of the app
          child: Stack(children: [
            Positioned.fill(child: ExcludeFocus(excluding: blocked, child: TapFeedback(child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox.shrink())))),
            if (blocked)
              Positioned.fill(
                child: HeroControllerScope.none(
                  child: Navigator(
                    key: const ValueKey('access-overlay'),
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => Consumer(builder: (context, ref, _) {
                        final a = ref.watch(accessProvider);
                        return a is AccessDecided && !a.decision.allowed ? AccessBlockedScreen(state: a) : const SizedBox.shrink();
                      }),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
      ),
      home: home ?? const Gate(),
    );
  }
}

/// Decides what to show: first-run setup, sign-in, or the app.
class Gate extends ConsumerWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider);
    switch (access) {
      case AccessSetupIncomplete(:final problem):
        return SetupIncompleteScreen(problem: problem);
      case AccessChecking():
        return const CheckingScreen();
      case AccessSignedOut():
        return const CloudAuthScreen();
      case AccessNeedsRegistration(:final user):
        return RegisterBusinessScreen(user: user);
      case AccessDecided d when !d.decision.allowed:
        return const SizedBox.shrink(); // shown by the overlay in MaterialApp.builder, above every open page
      case AccessDecided():
        return const CloudReporterHost(child: _LocalGate());
      case AccessOff():
        return const _LocalGate();
    }
  }
}

/// The restaurant's own data: first-run setup, staff PIN sign-in, then the app.
class _LocalGate extends ConsumerWidget {
  const _LocalGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessProvider);
    return business.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Could not open the database: $e'))),
      data: (b) {
        if (b == null) return const SetupScreen();
        return ref.watch(sessionProvider) == null ? const LoginScreen() : const HomeShell();
      },
    );
  }
}

/// The phone's text scaler times the owner's own factor.
class _Scaled extends TextScaler {
  const _Scaled(this.inner, this.factor);
  final TextScaler inner;
  final double factor;
  @override
  double scale(double fontSize) => inner.scale(fontSize) * factor;
  @override
  double get textScaleFactor => inner.scale(1.0) * factor;
  @override
  TextScaler clamp({double minScaleFactor = 0, double maxScaleFactor = double.infinity}) => TextScaler.linear((inner.scale(1.0) * factor).clamp(minScaleFactor, maxScaleFactor).toDouble());
}
