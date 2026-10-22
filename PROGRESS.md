# PROGRESS

Legend for verification: **unit-tested** (automated test passes here), **viewed** (rendered and looked at), **untested**.

## Environment
- Flutter 3.47.7 / Dart 3.13.5 installed in the build container (`/opt/flutter-sdk`). `flutter test` and `flutter analyze` run here.
- **Blocked:** Android SDK / Google Maven (`dl.google.com`) is denied by the container network policy, so no APK/AAB can be built yet. Needs that host allowed (Network access setting of the environment).

## Completed
- [x] Brand assets: vector icon masters, all Android launcher PNGs, splash, Play Store graphic (viewed; not on a device)
- [x] Lottie splash animation (played in lottie-web; not in Flutter yet)
- [x] Architecture doc, local SQLite schema (47 tables; loads in SQLite; append-only guards checked by `tool/check_schema.py`, all pass)
- [x] Server PostgreSQL schema with RLS (**untested**: not executed against Postgres)

- [x] Flutter app scaffold (`app/`, Android)
- [x] Pure-Dart domain core, **unit-tested (50 tests pass, analyzer clean)**: money/rounding, tax (inclusive/exclusive), bill calculator (line + bill discounts with exact allocation, service charge, delivery, tip, rounding), split payments with change, ESC/POS builder (58/80 mm, QR, raster, wrap), bill and KOT renderers (DUPLICATE/REPRINT markers), Urdu/Arabic raster detection, Ed25519 licence verifier (tamper, wrong device, suspend/block, expiry, offline grace, clock rollback)
  - Not yet verified on a real printer or device.

- [x] Local database via Drift from the canonical `docs/schema/local.sql` (`tool/sync_schema.py` generates the Drift schema)
- [x] `PosService`, **integration-tested on real SQLite (16 tests)**: persisted drafts, atomic settlement (gap-free invoice numbers, split payments with tender/change, stock ledger via recipes/direct stock, udhaar with credit limit, audit, outbox), crash rollback of the whole settlement, safe retry (no duplicate sale), permission-gated discount/void/refund with mandatory reason, partial/full refunds, append-only guards, daily report (gross / refunds / net / by method)

- [x] Staff PIN login: salted PBKDF2 hashes, 5-strikes lockout with audit, PIN change (**unit-tested**)
- [x] Shifts and cash drawer (expected cash, variance, cash in/out), day close / Z snapshot, locked once closed (**unit-tested**)
- [x] Menu CSV import: RFC 4180 parser, template, dry-run, row-level errors with line numbers, all-or-nothing commit, update-by-SKU, Urdu names (**unit-tested**). Excel (.xlsx) import is NOT done yet.
- [x] Sync engine (outbox drain, exponential backoff + jitter, per-record ordering, parking of rejected items) tested against a fake server, **including "server applied but ACK lost" with no duplicate**. No real server exists yet, so this is untested against a real backend.
- [x] Encrypted backup/restore: AES-256-GCM, PBKDF2, integrity check, wrong passphrase/tampering/truncation detected, pruning (**unit-tested**). Not yet wired to a UI or to cloud upload.

## In progress
- [ ] App screens (login, POS billing, checkout, tables, menu, reports, settings)

## Pending
Billing UI, menu management UI, tables UI, inventory UI (purchases, wastage), expenses, customer screens, reports and PDF/Excel export, printing transports (Bluetooth/LAN/USB) and real-printer tests, SQLCipher on device, sync pull side, Super Admin web panel, licensing server, invoices, support chat, notifications, Urdu/Arabic, Phase 2 online ordering.

## Blocked
- APK/AAB build: needs `dl.google.com` access.
- Real-printer tests, device/emulator tests: no device available in this container.
