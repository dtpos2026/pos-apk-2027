# PROGRESS

Legend: **tested** = automated test passes in this container; **viewed** = rendered and looked at; **untested** = not verified.
Nothing below has been run on a real phone or a real printer yet: see "Not verified on hardware".

## Environment
- Flutter 3.47.7 / Dart 3.13.5 in the authoring container. `flutter test` and `flutter analyze` run here (**200+ tests, analyzer clean**).
- The container cannot reach `dl.google.com` (Android SDK), so the APK is built by **GitHub Actions** (`.github/workflows/build-apk.yml`). A manual run with "publish" commits the APK to `releases/` (see `docs/BUILD.md`).

## Done (all **tested** unless noted)
- **Branding**: vector icon masters, all launcher icons, splash, Play Store graphic, Lottie splash (viewed; not on a device).
- **Billing core**: money/tax/discount/service/rounding, split payments with change, atomic settlement with gap-free invoice numbers, stock ledger (recipes), udhaar with credit limit, void/refund with reason and permissions, crash rollback, safe retry.
- **Screens** (phone and tablet sizes, English / اردو / العربية with right-to-left): first-run setup, branded sign-in (logo, name, address, phone centred) with PIN lockout, Sell (menu grid, search, categories, kg items, **sizes/variants and add-ons**, discount, hold/resume, customer, table, send to kitchen), checkout, shifts and cash variance, **Tables** (areas, tables, transfer, statuses), **Bills** (search, reprint marked DUPLICATE, share, refund, void), **Customers/udhaar**, **Expenses**, **Inventory** (stock, purchases, wastage, counts, recipes, suppliers, low stock, valuation), **Staff**, **Reports** (summary with expenses/result, items, categories, cashiers, CSV export), Menu (add/edit, CSV and **Excel .xlsx import**), Settings.
- **Receipt designer**: logo (any picture, converted to a printer bitmap), business name, address, phone and tax number centred by default, every block switchable and alignable, extra header/footer lines, QR, copies, 58/80 mm, **bill language English/Urdu/Arabic**, live preview rendered from the same document the printer prints, test print.
- **Themes**: default is the Digital Target logo purple (exact), plus Ocean, Forest, Sunset, Rose, Slate, Gold, Teal; light/dark/automatic; saved.
- **Printing**: ESC/POS 58/80 mm, LAN (TCP 9100) transport, print queue with retry, KOT routing by station, kitchen tickets print only what is new, Urdu/Arabic lines printed as bitmaps. Tested against a fake LAN printer only.
- **Backup**: AES-256-GCM encrypted backup/restore with integrity check. **Sync engine** (outbox, backoff, ordering, no duplicate on lost ACK) tested against a fake server.
- **Docs/schemas**: architecture, local SQLite schema (47 tables), server PostgreSQL schema with RLS (**untested against Postgres**).

## Not verified on hardware
- Any real Android phone/tablet, emulator, or thermal printer. Screens were checked in Flutter's test renderer.
- Bluetooth, BLE and USB printing are **not implemented** (need native plugins and hardware). Only LAN printing exists.
- The database file is **not encrypted yet** (SQLCipher is planned; needs device testing).
- PDF export is not done (CSV export is). Urdu in PDF needs text shaping the `pdf` package lacks.
- Per-order-type prices and combos exist in the schema but have no screens yet.

## Pending
Super Admin web panel, licensing server and signed-licence issuing, platform invoices and payments, support chat, push notifications, announcements, consent-based location, sync pull side and server, SQLCipher, Bluetooth/USB printers, combos and per-order-type prices UI, PDF export, FBR/PRA and UAE e-invoicing (future modules), Phase 2 online ordering.

## Blocked
- Anything needing a real device or printer.
- Supabase project creation and keys: waiting for the owner (the Super Admin panel is being built to read them from a config file).
