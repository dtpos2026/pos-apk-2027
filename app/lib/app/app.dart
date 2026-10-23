import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/access_controller.dart';
import '../features/cloud/cloud_reporter.dart';
import '../features/cloud/cloud_screens.dart';
import '../features/login/login_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/home_shell.dart';
import 'providers.dart';
import 'strings.dart';
import 'theme.dart';
import 'themes.dart';

class DtFoodPosApp extends ConsumerWidget {
  const DtFoodPosApp({super.key, this.home});

  /// Tests and the splash flow can replace the first screen.
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final seed = presetById(ref.watch(themeIdProvider)).seed;
    return MaterialApp(
      title: 'DT Food POS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(seed: seed),
      darkTheme: buildTheme(brightness: Brightness.dark, seed: seed),
      themeMode: ref.watch(themeModeProvider),
      locale: locale,
      supportedLocales: Strings.supported,
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
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
        return AccessBlockedScreen(state: d);
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
