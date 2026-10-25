import 'package:drift/drift.dart';

part 'database.g.dart';

@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await migrateToV2(this);
          if (from < 3) await migrateToV3(this);
          if (from < 4) await migrateToV4(this);
          if (from < 5) await migrateToV5(this);
          if (from < 6) await migrateToV6(this);
          if (from < 7) await migrateToV7(this);
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

/// Version 7: dine-in waiters are simple team members too (no PIN), on orders and tables. Mirrors docs/schema/local.sql.
Future<void> migrateToV7(AppDatabase db) async {
  final info = await db.customSelect("SELECT sql FROM sqlite_master WHERE type='table' AND name='team_member'").get();
  final sql = info.isEmpty ? '' : (info.first.data['sql'] as String? ?? '');
  if (info.isNotEmpty && !sql.contains("'waiter'")) {
    // the kind CHECK has to widen: rebuild the (small) table, keeping every row and its id
    await db.customStatement("""CREATE TABLE team_member_new (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'rider' CHECK (kind IN ('rider','waiter')),
  name TEXT NOT NULL, phone TEXT, bike_no TEXT, active INTEGER NOT NULL DEFAULT 1,
  version INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL, deleted_at INTEGER
)""");
    await db.customStatement('INSERT INTO team_member_new(id, kind, name, phone, bike_no, active, version, updated_at, deleted_at) SELECT id, kind, name, phone, bike_no, active, version, updated_at, deleted_at FROM team_member');
    await db.customStatement('DROP TABLE team_member');
    await db.customStatement('ALTER TABLE team_member_new RENAME TO team_member');
  }
  for (final t in const ['"order"', 'dining_table']) {
    final cols = await db.customSelect('PRAGMA table_info($t)').get();
    if (!cols.any((c) => c.data['name'] == 'waiter_member_id')) await db.customStatement('ALTER TABLE $t ADD COLUMN waiter_member_id TEXT REFERENCES team_member(id)');
  }
}

/// Version 6: delivery riders and the rider on an order. Mirrors docs/schema/local.sql.
Future<void> migrateToV6(AppDatabase db) async {
  await db.customStatement("""CREATE TABLE IF NOT EXISTS team_member (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'rider' CHECK (kind IN ('rider')),
  name TEXT NOT NULL, phone TEXT, bike_no TEXT, active INTEGER NOT NULL DEFAULT 1,
  version INTEGER NOT NULL DEFAULT 1, updated_at INTEGER NOT NULL, deleted_at INTEGER
)""");
  final cols = await db.customSelect('PRAGMA table_info("order")').get();
  if (!cols.any((c) => c.data['name'] == 'rider_id')) await db.customStatement('ALTER TABLE "order" ADD COLUMN rider_id TEXT REFERENCES team_member(id)');
}

/// Version 5: a photo for each customer. Mirrors docs/schema/local.sql.
Future<void> migrateToV5(AppDatabase db) async {
  final cols = await db.customSelect("PRAGMA table_info('customer')").get();
  if (!cols.any((c) => c.data['name'] == 'image_path')) await db.customStatement('ALTER TABLE customer ADD COLUMN image_path TEXT');
}

/// Version 4: deals / combos (what each deal contains). Mirrors docs/schema/local.sql.
Future<void> migrateToV4(AppDatabase db) async {
  await db.customStatement("""CREATE TABLE IF NOT EXISTS deal_item (
  id TEXT PRIMARY KEY, deal_id TEXT NOT NULL REFERENCES product(id),
  product_id TEXT NOT NULL REFERENCES product(id), variant_id TEXT REFERENCES product_variant(id),
  qty_milli INTEGER NOT NULL CHECK (qty_milli > 0)
)""");
  await db.customStatement('CREATE INDEX IF NOT EXISTS deal_item_ix ON deal_item(deal_id)');
}

/// Version 3: purchase orders. Mirrors docs/schema/local.sql.
Future<void> migrateToV3(AppDatabase db) async {
  for (final sql in const [
    """CREATE TABLE IF NOT EXISTS purchase_order (
  id TEXT PRIMARY KEY, po_no TEXT NOT NULL UNIQUE, supplier_id TEXT REFERENCES supplier(id),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','sent','received','cancelled')),
  note TEXT, expected_date TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  received_at INTEGER, purchase_id TEXT REFERENCES purchase(id), staff_id TEXT REFERENCES staff(id)
)""",
    """CREATE TABLE IF NOT EXISTS purchase_order_line (
  id TEXT PRIMARY KEY, po_id TEXT NOT NULL REFERENCES purchase_order(id),
  stock_item_id TEXT NOT NULL REFERENCES stock_item(id),
  qty_milli INTEGER NOT NULL CHECK (qty_milli > 0), unit_cost_minor INTEGER NOT NULL DEFAULT 0
)""",
    'CREATE INDEX IF NOT EXISTS purchase_order_line_ix ON purchase_order_line(po_id)',
    """CREATE TABLE IF NOT EXISTS kitchen_event (
  id TEXT PRIMARY KEY, order_id TEXT NOT NULL REFERENCES "order"(id),
  status TEXT NOT NULL CHECK (status IN ('new','preparing','ready','served')),
  at INTEGER NOT NULL, staff_id TEXT REFERENCES staff(id)
)""",
    'CREATE INDEX IF NOT EXISTS kitchen_event_ix ON kitchen_event(order_id, at)',
  ]) {
    await db.customStatement(sql);
  }
  await _paymentAccountDetails(db);
  await _allowCancelledOrders(db);
  // orders already in the kitchen get their first history row from their current state
  await db.customStatement("""INSERT INTO kitchen_event(id, order_id, status, at)
    SELECT 'mig-' || o.id, o.id, o.status, o.updated_at FROM "order" o
    WHERE o.status IN ('new','preparing','ready','served') AND NOT EXISTS (SELECT 1 FROM kitchen_event k WHERE k.order_id = o.id)""");
}

/// Orders gain the status 'cancelled' (an unpaid order that was sent to the kitchen and then called off: kept for the
/// kitchen history, never counted as a sale). SQLite cannot change a CHECK, so the table is rebuilt the documented way.
/// Foreign keys are off while a migration runs (beforeOpen switches them on afterwards).
Future<void> _allowCancelledOrders(AppDatabase db) async {
  final row = await db.customSelect("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'order'").getSingleOrNull();
  final sql = row?.data['sql'] as String?;
  if (sql == null || sql.contains("'cancelled'")) return;
  for (final stmt in const [
    '''CREATE TABLE order_v3 (
  id TEXT PRIMARY KEY,
  invoice_no TEXT UNIQUE,
  order_type TEXT NOT NULL CHECK (order_type IN ('dine_in','takeaway','delivery','counter')),
  status TEXT NOT NULL CHECK (status IN ('draft','held','new','preparing','ready','served','paid','void','refunded','cancelled')),
  table_id TEXT REFERENCES dining_table(id), customer_id TEXT REFERENCES customer(id),
  waiter_id TEXT REFERENCES staff(id), cashier_id TEXT REFERENCES staff(id), shift_id TEXT REFERENCES shift(id),
  guests INTEGER, note TEXT, delivery_address TEXT, source TEXT NOT NULL DEFAULT 'pos',
  bill_config TEXT,
  subtotal_minor INTEGER NOT NULL DEFAULT 0, discount_minor INTEGER NOT NULL DEFAULT 0,
  service_charge_minor INTEGER NOT NULL DEFAULT 0, delivery_charge_minor INTEGER NOT NULL DEFAULT 0,
  tax_minor INTEGER NOT NULL DEFAULT 0, tip_minor INTEGER NOT NULL DEFAULT 0,
  rounding_minor INTEGER NOT NULL DEFAULT 0, total_minor INTEGER NOT NULL DEFAULT 0,
  paid_minor INTEGER NOT NULL DEFAULT 0,
  business_date TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, settled_at INTEGER,
  version INTEGER NOT NULL DEFAULT 1
)''',
    // copied by column name, so a table that already has newer columns (or an older one with fewer) still copies safely
    'COPY_ORDERS',
    'DROP TABLE "order"',
    'ALTER TABLE order_v3 RENAME TO "order"',
    'CREATE INDEX IF NOT EXISTS order_date_ix ON "order"(business_date, status)',
    'CREATE INDEX IF NOT EXISTS order_table_ix ON "order"(table_id, status)',
  ]) {
    if (stmt == 'COPY_ORDERS') {
      final oldCols = {for (final r in await db.customSelect('PRAGMA table_info("order")').get()) r.data['name'] as String};
      final newCols = [for (final r in await db.customSelect('PRAGMA table_info(order_v3)').get()) r.data['name'] as String];
      final common = newCols.where(oldCols.contains).map((c) => '"$c"').join(', ');
      await db.customStatement('INSERT INTO order_v3($common) SELECT $common FROM "order"');
    } else {
      await db.customStatement(stmt);
    }
  }
}

/// Payment accounts keep their provider, account number / IBAN, holder name and logo; Pakistani businesses get the
/// standard wallets (Easypaisa, JazzCash, G Wallet) and a bank transfer account if they are missing.
Future<void> _paymentAccountDetails(AppDatabase db) async {
  final cols = {for (final r in await db.customSelect('PRAGMA table_info(payment_method)').get()) r.data['name'] as String};
  for (final c in const ['provider', 'account_no', 'holder', 'image_path']) {
    if (!cols.contains(c)) await db.customStatement('ALTER TABLE payment_method ADD COLUMN $c TEXT');
  }
  final cur = (await db.customSelect("SELECT currency FROM business_profile WHERE id = 'self'").getSingleOrNull())?.data['currency'] as String?;
  if (cur == null || cur == 'AED') return;
  final now = DateTime.now().millisecondsSinceEpoch;
  var sort = ((await db.customSelect('SELECT COALESCE(MAX(sort),0) AS m FROM payment_method WHERE sort < 9').getSingle()).data['m'] as int) + 1;
  for (final (name, kind) in const [('Bank transfer', 'bank'), ('Easypaisa', 'wallet'), ('JazzCash', 'wallet'), ('G Wallet', 'wallet')]) {
    final have = await db.customSelect('SELECT 1 AS x FROM payment_method WHERE lower(name) = lower(?) AND deleted_at IS NULL', variables: [Variable.withString(name)]).get();
    if (have.isNotEmpty) continue;
    await db.customStatement('INSERT INTO payment_method(id, name, kind, sort, updated_at) VALUES (?,?,?,?,?)', ['pm-${name.toLowerCase().replaceAll(' ', '-')}', name, kind, sort++, now]);
  }
}
