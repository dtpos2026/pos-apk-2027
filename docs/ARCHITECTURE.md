# DT Food POS: Architecture

Powered by Digital Target. This document records decisions and the honest limits behind them.

## 1. Stack and why

| Layer | Choice | Why |
|---|---|---|
| Mobile app | **Flutter (Dart), Android first** | One codebase, good performance on 2 GB RAM phones, strong RTL/Urdu/Arabic support, rich printing/PDF packages. Native Kotlin would cost more with no benefit for this UI. iOS is a later, separate decision (see 8). |
| Local DB | **SQLite via Drift, encrypted with SQLCipher** | Local DB is the source of truth. Drift gives typed queries, migrations and transactions. |
| State | Riverpod | Testable, small. |
| Backend | **Firebase (Auth + Firestore + Hosting, Spark plan)** (replaced the earlier Supabase plan) | One operator can run it: managed Postgres, row level security for tenant isolation, built-in auth and 2FA, realtime channel for instant licence commands. Pick a region close to PK/UAE (Mumbai or Singapore) at project creation. |
| Super Admin | **React (Vite) + Firebase JS SDK**, English UI | Thin client; access is enforced by `firebase/firestore.rules`, not by the client. |
| Push | FCM, sent from an Edge Function | Wake devices for licence/support/announcements. |

Money is always integer minor units; quantities are integer thousandths. No floats near money.

## 2. App layers

```
presentation (screens, widgets)   -> Riverpod providers
application  (use cases)          -> BillingService, ShiftService, SyncService, LicenseService, PrintService
domain       (pure Dart, tested)  -> Money, Tax, Cart/Bill calculator, ESC/POS builder, licence verifier
data         (Drift DB, repositories, outbox, network)
```

`domain/` has no Flutter or database imports so it is unit-tested on any machine.

## 3. Offline-first and sync

- Every operation works with no network. Reads and writes hit SQLite only.
- **Outbox:** each write to a synced table inserts an `outbox` row in the same transaction. A background worker drains it oldest-first with exponential backoff. Each row has a unique `idempotency_key`; the server records applied keys in `applied_operation`, so a retry after a crash mid-sync can never create a duplicate sale.
- **Conflict policy:** bills, payments, refunds, stock movements and ledgers are append-only (no conflicts possible). Stock is a delta ledger, never an overwritten number. Settings and menu use per-record `version` with last-write-wins. Deletes are soft (tombstones).
- **Pull:** device stores a `server_seq` cursor per business and fetches rows newer than it.
- **Multi-device in one business:** cloud sync is eventual (seconds when both online). LAN sync is a later optional module; until then "real time" across devices means "when both are online".
- **Crash safety:** drafts are persisted on every cart change; settlement (bill + payments + stock + ledger + outbox + invoice number) is a single SQLite transaction.

## 4. Licensing (account-based, as in the Digital Target salon system)

- Each restaurant signs in with email + password. Its account document (`accounts/{uid}`) holds status (pending, active, payment_pending, suspended, blocked, expired, rejected), plan, expiry, approved phones, blocked phones and an admin message. Only admins can change those fields (enforced by Firestore rules, tested on the emulator).
- The app watches its account document. A change made in the panel reaches an online phone within seconds; any status other than `active` stops selling and shows the admin's message. Local data is never touched.
- Offline: the app keeps the last server-confirmed copy. It keeps working until `offlineDays` (panel setting, default 7) after the last confirmation and never past the expiry date (checked against the phone clock). The UI never claims an offline phone received a change.
- Phones: a phone id is generated on first run. One phone is allowed by default; a new phone is put in `phoneRequests` and needs approval in the panel.
- Clock rollback: the highest clock value seen is stored; moving the clock back asks for internet.
- Expiry never deletes data.
- Honest limit: this is account-based checking on the phone; a rooted phone with a modified app could bypass it. The server rules still stop it from reading other restaurants' data or approving itself.
- Replaced the earlier Ed25519 signed-token design because there are no Cloud Functions on the Spark plan.

## 5. Printing

- ESC/POS, 58 mm primary, 80 mm supported. Transports: Bluetooth classic (SPP, Android), BLE, LAN raw TCP 9100, USB-OTG where feasible.
- Printers have roles (bill/kot/both) and a station; KOTs route to printers by category station.
- Print jobs go through `print_job`: saving an order never waits on a printer; failures stay queued with a clear error and retry. Reprints carry a DUPLICATE marker and an audit row.
- **Urdu/Arabic:** most thermal printers have no Arabic-script fonts, so those lines are rendered to a bitmap (with correct shaping/RTL) and sent as raster. This is slower and larger than text; the printer's `raster_text` flag controls it.
- A tested-printer compatibility matrix is kept in `docs/PRINTERS.md` and only lists printers actually tested.

## 6. Security

Argon2id/PBKDF2 for PINs and passwords, short-lived access tokens + refresh tokens, device-bound sessions, TLS with certificate pinning, Android Keystore for the DB key, SQLCipher, encrypted backups, role-based permissions in app and server, permission-gated and audited sensitive actions (void, refund, price edit, delete, discount), dependency scanning, RLS tenant isolation. Location is collected only with explicit consent, with a visible indicator and revocation at any time.

## 7. Super Admin and monitoring

Registration queue, approve/reject, licence and plan management, device list with last-seen, consent-based location (labelled stale/unavailable, never fabricated), per-business totals (completed, refunds, net) without order detail, invoices (PDF), support inbox, announcements, audit log, storage dashboard, remote configuration.

## 8. Known limitations (stated early on purpose)

- **iOS:** Bluetooth classic/SPP printers are not supported on iOS (BLE or LAN only), background execution is restricted, and there is no sideloading path for most customers. Android first; iOS gets its own assessment.
- **Background location** on Android is limited by OEM battery managers; live updates are best-effort.
- **No payment-gateway integration:** wallets (Easypaisa, JazzCash, UAE equivalents) are recorded as payment methods only.
- **FBR/PRA POS and UAE e-invoicing** are future optional modules requiring official integration; not claimed.
- **WhatsApp:** share intent/deep link only in Phase 1 (no Business API).
- **Remote control of offline devices is impossible**; enforcement happens at reconnect.

## 9. Repository layout

```
app/        Flutter mobile app
admin/      Super Admin web panel (planned)
firebase/   Firestore rules, indexes, emulator tests
admin/      Super Admin panel (React + Firebase)
branding/   icon, splash, vector masters
docs/       architecture, schemas (local.sql, server.sql), roadmap
```
