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

## Cloud: Firebase + Super Admin panel (replaces the earlier Supabase draft, which was removed)
Modelled on the owner's DT Salon Management guide (account approval, plans, phones, invoices, support, reminders, settings).
- **Done and tested:**
  - `firebase/firestore.rules` + 11 emulator tests (a restaurant cannot approve itself, read others, forge admin/chat/invoices; first-admin claim works once).
  - `admin/` panel: 12 domain tests, 8 UI tests with a fake API, and one end-to-end test of the real `FirebaseApi` against the Auth+Firestore emulators with the real rules (register → approve → phones → sales → invoice → payment extends expiry → suspend → support chat → settings → admins).
  - App: account gate (`decideAccess`, 11 unit tests), sign-in / register / waiting / blocked screens, offline grace and clock-rollback rules, expiry banner and notice, support chat, totals + phone reporting; 6 widget flow tests with a fake cloud. Whole app: 212 tests pass.
- **Not verified:** nothing has run against the real `dt-food-app` Firebase project, on a real phone, or with real Android Auth (the app uses the Web app's public identifiers; if sign-in fails on a device, register an Android app and pass `--dart-define=FIREBASE_APP_ID`). Deploy and console steps are in `docs/FIREBASE_SETUP.md`.
- **Not done:** location sharing with consent (panel shows "not allowed"), AI assistant, announcements, panel PNG/WhatsApp-image invoices (print/PDF and WhatsApp link only), a live map (links to OpenStreetMap), sync of business data (by design it stays on the phone), TOTP 2FA.
