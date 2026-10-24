import 'package:drift/drift.dart';

part 'database.g.dart';

@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await migrateToV2(this);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// Version 2: item counter override and the food-token tables. Mirrors docs/schema/local.sql (a test checks they agree).
Future<void> migrateToV2(AppDatabase db) async {
  for (final sql in const [
    'ALTER TABLE product ADD COLUMN station TEXT',
    'CREATE TABLE IF NOT EXISTS token_template (id TEXT PRIMARY KEY, name TEXT NOT NULL, config TEXT NOT NULL, updated_at INTEGER NOT NULL)',
    'CREATE TABLE IF NOT EXISTS token_seq (scope TEXT PRIMARY KEY, last_no INTEGER NOT NULL)',
    """CREATE TABLE IF NOT EXISTS token_issue (
  id TEXT PRIMARY KEY, order_id TEXT NOT NULL REFERENCES "order"(id),
  rule_id TEXT NOT NULL, kind TEXT NOT NULL, part INTEGER NOT NULL DEFAULT 0,
  seq INTEGER NOT NULL, label TEXT NOT NULL, station TEXT,
  payload TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'issued' CHECK (status IN ('issued','collected','void')),
  print_count INTEGER NOT NULL DEFAULT 0, last_printed_at INTEGER,
  business_date TEXT NOT NULL, created_at INTEGER NOT NULL, collected_at INTEGER,
  UNIQUE (order_id, rule_id, part)
)""",
    'CREATE INDEX IF NOT EXISTS token_issue_date_ix ON token_issue(business_date, status)',
    """CREATE TABLE IF NOT EXISTS coupon (
  id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, token_id TEXT REFERENCES token_issue(id),
  order_id TEXT NOT NULL REFERENCES "order"(id), label TEXT NOT NULL, value_minor INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'issued' CHECK (status IN ('issued','redeemed','void')),
  created_at INTEGER NOT NULL, redeemed_at INTEGER, redeemed_by TEXT
)""",
  ]) {
    await db.customStatement(sql);
  }
}
