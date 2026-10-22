import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/login/login_screen.dart';
import '../features/setup/setup_screen.dart';
import '../features/shell/home_shell.dart';
import 'providers.dart';
import 'strings.dart';
import 'theme.dart';

class DtFoodPosApp extends ConsumerWidget {
  const DtFoodPosApp({super.key, this.home});

  /// Tests and the splash flow can replace the first screen.
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      title: 'DT Food POS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(brightness: Brightness.dark),
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
