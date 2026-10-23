# DT Food POS — audit and status (2026-10-23)

Read from the repository, not assumed.

## 1. What the project is
| Part | Technology | Where |
|---|---|---|
| Android POS | Flutter 3.47 / Dart 3.13, Riverpod 3, Drift + SQLite (offline-first) | `app/` |
| Application ID | `digital.target.dt_food_pos` | `app/android/app/build.gradle.kts` |
| Super Admin panel | React 18 + Vite + TypeScript, Firebase JS SDK v10 | `admin/` |
| Backend | Firebase project `dt-food-app`: Auth (email/password), Firestore, Hosting. Spark plan, no Cloud Functions | `firebase/`, `firebase.json` |
| Local schema | 47 tables, canonical SQL → Drift | `docs/schema/local.sql` |
| CI | GitHub Actions: Firestore rules tests, panel tests on emulators, Flutter analyze/test, split-ABI APK + AAB | `.github/workflows/build-apk.yml` |

## 2. Data placement (decided, documented)
- **Stays on the phone:** every bill, item, price, customer name/phone, staff, udhaar, expenses, inventory, suppliers, audit of POS actions. Backup file is made by the restaurant.
- **Sent to Firebase:** account (email, status, plan, expiry, phones), daily **totals** per date (net/gross/refunds/bills/customers count), phone state (model, Android/app version, last seen), support chat, DT invoices, admin audit log.
- The full order list is deliberately **not** uploaded (data minimisation). The local `outbox`/`SyncEngine` remains for a future full-sync feature but has no server transport.

## 3. Security model (tested on the Firestore emulator, 13 rule tests + 1 end-to-end panel test)
- A restaurant can read/write only its own `accounts/{uid}` (and only `appVersion`, `lastSeenAt`, `phoneRequests`), its own `stats`, `devices`, `support`.
- It cannot approve itself, change plan/expiry/status, approve or unblock phones, read others' data, forge admin chat messages or invoices.
- Only `digitaltarget.digital@gmail.com` can claim the first Super Admin, once. Further admins are added by an admin.
- Billing settings are admin-only; branding/app-control are public read (shown on the app's sign-in screen).
- Every panel change writes an append-only `auditLog` entry in the same batch/transaction, with the server's time; entries cannot be edited or deleted.
- No secrets in the repo. The Firebase web identifiers in the app are public by design.
- Honest limits: licensing is enforced on the phone from the account document (no signed tokens without Cloud Functions); a modified app on a rooted phone could bypass it locally, but cannot change server data. A suspended phone that stays offline keeps working until its offline grace (default 7 days) or expiry, whichever comes first.

## 4. Found and fixed in this pass
| Problem | Fix |
|---|---|
| Sales from days the phone was offline never reached the panel (only "today" was sent) | Reporter re-sends the previous 7 days, one document per date (idempotent) |
| Panel added PKR and AED together in totals | Totals per currency |
| Panel used UTC dates; Pakistan/UAE "today" was wrong for 4–5 hours after midnight | Local dates everywhere |
| Long PDF reports crashed ("more than 20 pages") | Tables split across pages; test with 120 rows |
| No record of admin actions | Append-only audit log + page |
| Restaurants/invoices lists unbounded | Pagination |
| Panel showed old sales as if they were today's | "not today / last report …" labels |
| Brand colour `#3D096D` (traced) vs specified `#3C096C` | `#3C096C` in app and panel |
| Bluetooth printers not supported | Classic Bluetooth (SPP) transport + paired-printer picker |
| No PDF export | A4 PDF sales report (summary, methods, items, categories, cashiers), Urdu names supported |
| No visible sync state in the app | Cloud icon in the app bar (synced / offline) |
| APK 75 MB | Split per CPU: ~26 MB (arm64) / ~25 MB (armv7) |

## 5. Not done / not verified
- **Not verified on hardware:** any real phone, Bluetooth printer, LAN printer, the real `dt-food-app` project (all Firebase testing used the official emulators).
- **Not implemented:** combo deals and per-order-type prices (tables exist, no UI), day-close (Z) report beyond shift close, phone location sharing, AI assistant, push notifications (FCM), App Check, admin 2FA, SQLCipher database encryption, release signing key (APK is debug-signed), full order sync to the cloud (by design).
- **Needs the owner:** deploy (`npx firebase-tools deploy`), first sign-in + "Become Super Admin", panel Settings, a release keystore as GitHub secrets before Play Store.
