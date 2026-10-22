# PROGRESS

Legend for verification: **unit-tested** (automated test passes here), **viewed** (rendered and looked at), **untested**.

## Environment
- Flutter 3.47.7 stable installed in the build container (`/opt/flutter-sdk`): see status below.
- **Blocked:** Android SDK / Google Maven (`dl.google.com`) is denied by the container network policy, so no APK/AAB can be built yet. Needs that host allowed (Network access setting of the environment).

## Completed
- [x] Brand assets: vector icon masters, all Android launcher PNGs, splash, Play Store graphic (viewed; not on a device)
- [x] Lottie splash animation (played in lottie-web; not in Flutter yet)
- [x] Architecture doc, local SQLite schema (47 tables; loads in SQLite; append-only guards checked by `tool/check_schema.py`, all pass)
- [x] Server PostgreSQL schema with RLS (**untested**: not executed against Postgres)

## In progress
- [ ] Flutter app scaffold and pure-Dart domain core (money, tax, bill calculator, ESC/POS, licence verifier)

## Pending
Billing UI, menu management and CSV/Excel import, tables, inventory, finance, customers/udhaar, staff and PIN login, reports, backup/restore, printing (real printers), sync client, Super Admin web panel, licensing server, invoices, support chat, notifications, Urdu/Arabic, Phase 2 online ordering.

## Blocked
- APK/AAB build: needs `dl.google.com` access.
- Real-printer tests, device/emulator tests: no device available in this container.
