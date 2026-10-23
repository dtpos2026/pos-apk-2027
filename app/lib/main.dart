import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/db/database.dart';
import 'features/splash/animated_splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  // NOTE: the database file is not yet encrypted. SQLCipher is planned (see PROGRESS.md) and needs on-device testing.
  final db = AppDatabase(NativeDatabase(File(p.join(dir.path, 'dt_food_pos.sqlite'))));
  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      backupDirProvider.overrideWith((ref) async => Directory(p.join(dir.path, 'backups'))),
      logoDirProvider.overrideWithValue(Directory(p.join(dir.path, 'logo'))),
    ],
    child: const _Root(),
  ));
}

/// Plays the splash while the saved language loads, then hands over to the gate.
class _Root extends ConsumerStatefulWidget {
  const _Root();
  @override
  ConsumerState<_Root> createState() => _RootState();
}

class _RootState extends ConsumerState<_Root> {
  bool _splashDone = false;
  late final Future<void> _ready = restoreAppearance(ref);

  @override
  Widget build(BuildContext context) => DtFoodPosApp(
        home: _splashDone ? const Gate() : AnimatedSplashScreen(ready: _ready, onFinished: () => setState(() => _splashDone = true)),
      );
}
