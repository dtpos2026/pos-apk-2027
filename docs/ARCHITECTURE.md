# DT Food POS: Architecture

Powered by Digital Target. This document records decisions and the honest limits behind them.

## 1. Stack and why

| Layer | Choice | Why |
|---|---|---|
| Mobile app | **Flutter (Dart), Android first** | One codebase, good performance on 2 GB RAM phones, strong RTL/Urdu/Arabic support, rich printing/PDF packages. Native Kotlin would cost more with no benefit for this UI. iOS is a later, separate decision (see 8). |
| Local DB | **SQLite via Drift, encrypted with SQLCipher** | Local DB is the source of truth. Drift gives typed queries, migrations and transactions. |
| State | Riverpod | Testable, small. |
| Backend | **Supabase (PostgreSQL + Auth + Edge Functions + Realtime)** | One operator can run it: managed Postgres, row level security for tenant isolation, built-in auth and 2FA, realtime channel for instant licence commands. Pick a region close to PK/UAE (Mumbai or Singapore) at project creation. |
| Super Admin | **React (Vite) + Supabase JS**, English UI | Thin client over RLS and RPC functions. Admin 2FA via Supabase MFA (TOTP). |
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

## 4. Licensing

- Server issues a **signed licence token** (Ed25519): business id, device ids, modules, plan, `expires_at`, `offline_grace_days`, `version`, `issued_at`. The private key lives only on the server; the app bundles the public key.
- Online: a realtime channel plus FCM carries suspend/block/reactivate/module commands. Suspend takes effect immediately on a connected device.
- Offline: a device cannot receive commands. It keeps working until `last_validated_at + offline_grace_days` (and never past `expires_at`), shows warnings before that, and enforces on reconnect. The UI never claims an offline device received a command.
- Clock rollback: the app stores the highest wall clock and monotonic offset seen; if the clock moves backwards the licence is treated as needing online validation.
- Expiry never deletes data. Export and backup stay available.
- Honest limit: client-side protection is not unbreakable; root detection, obfuscation and pinning raise the cost only.

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
backend/    Supabase migrations and edge functions (planned)
branding/   icon, splash, vector masters
docs/       architecture, schemas (local.sql, server.sql), roadmap
```
