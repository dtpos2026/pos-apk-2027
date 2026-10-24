# DT Food POS — QC / UAT report

Version **0.3.0** · date 2026-10-23 · prepared from actual test runs (commands and results below).

## 1. Verdict

| Area | Result | How it was checked |
|---|---|---|
| Android app logic and screens | **PASS** (396 automated tests) | `flutter test` — real SQLite, real widgets, fonts loaded |
| Static analysis | **PASS** (0 issues) | `flutter analyze` |
| Firestore security rules | **PASS** (13 tests) | Firebase emulator, `npm test` in `firebase/` |
| Super Admin panel | **PASS** (23 unit/UI + 1 end-to-end) | Vitest; end-to-end runs the real panel code against Auth + Firestore emulators |
| Android release build (APK/AAB) | **PASS** (run 26, includes the new Android code) | GitHub Actions |
| **Real phone, real printer, real Firebase project** | **NOT TESTED** | No device or printer is available to this build environment. Must be done by DT before giving the app to restaurants (checklist in §6). |

## 2. What the automated tests cover (UAT scenarios)

| # | Scenario | Result |
|---|---|---|
| 1 | First run: business setup, owner PIN, staff sign-in, wrong PIN, lock-out | PASS |
| 2 | Sell: add items, sizes/add-ons, quantity, discount, tax, service charge, rounding | PASS |
| 3 | Payment: cash, card, split, udhaar (credit), change due | PASS |
| 4 | Hold / resume order, tables, KOT sends only new items | PASS |
| 5 | Refund / void with permission + reason; audit entry written | PASS |
| 6 | Gap-free invoice numbers; settlement is all-or-nothing (crash safety) | PASS |
| 7 | Inventory: purchase, supplier credit, supplier payment, wastage, stock count | PASS |
| 8 | Reports: summary, items, categories, cashiers; CSV; **PDF** (incl. 120-row multi-page, Urdu names) | PASS |
| 9 | Receipt design: logo, centred name/address/phone, Urdu/Arabic, 58/80 mm, ESC/POS bytes | PASS |
| 10 | Printing: LAN printer (fake socket), **Bluetooth** setup + job routed by MAC (fake transport) | PASS (hardware not tested) |
| 11 | Backup with password and restore | PASS |
| 12 | Language English / اردو / العربية (all strings present), RTL | PASS |
| 13 | Themes (DT purple `#3C096C` default), dark mode | PASS |
| 14 | Account: sign in, wrong password, register, waiting for approval, approved → app opens | PASS |
| 15 | Panel suspends → app stops and shows the admin's message; activate → app works again | PASS |
| 16 | New phone needs approval (requested once); **reinstall on an approved phone does not ask again** | PASS |
| 17 | Expiry enforced offline; offline grace (7 days); clock moved back is refused; minimum version | PASS |
| 18 | Only totals leave the phone; **days spent offline are sent later**; sync icon offline/synced | PASS |
| 19 | **Location**: asked once, shared only when allowed, switch off stops it; "Not now" shares nothing | PASS |
| 20 | Support chat both ways | PASS |
| 21 | Rules: restaurant cannot approve itself, read others, forge admin/chat/invoice; only the owner email can claim Super Admin; audit log append-only | PASS |
| 23 | **Day close (Z report)**: totals, methods, udhaar given/recovered, expenses, cash short/over; refused while a shift is open; closed once; slip text; share | PASS |
| 24 | **Payment accounts**: add JazzCash/bank, duplicate refused, switch off hides it at checkout, cash cannot be switched off | PASS |
| 25 | **WhatsApp**: bill to customer (0300-… becomes 92300…), udhaar reminder with name/amount/business | PASS (opens WhatsApp on a phone; tested with a fake) |
| 26 | **Bill as image** (PNG) shared | PASS |
| 27 | **Food tokens**: 7 types numbered with prefix/padding/start, daily restart, product routing by counter, idempotent issue, coupons redeemed once (also under a simultaneous second redeem), void cancels waiting tokens/coupons | PASS (`token_test.dart`) |
| 28 | **Seven designs × 58/80 mm × every token kind** fit the paper and print; editing (hide, reorder, align, size, wording, border, margins), JSON export/import, Urdu/bilingual go through the bitmap path | PASS (`token_design_test.dart`) |
| 29 | **Token UI**: set up types, sale prints each token to its counter's printer, Tokens screen collect/reprint (REPRINT), tokens-only mode, module off, designer edit/save/reopen/drag/reset/duplicate/export/import/delete, rule test print, coupon redeem, bill styles | PASS (`tokens_flow_test.dart`) |
| 30 | Panel: switch app features off per restaurant (saved to Firestore, persisted in emulator test) | PASS |
| 22 | Panel end-to-end: register → approve (DTC-0001) → phone limit → block → sales → invoice → payment extends expiry → suspend → chat → settings → admins → audit entries | PASS |

## 3. Defects found during QC and fixed

| Defect | Severity | Fix |
|---|---|---|
| White strip at the side during start-up on some phones (Android window background was white) | Medium (visual) | Window background is now brand purple |
| Reinstalling the app made an approved phone appear as a new phone again | High (support load) | Stable phone id from Android (ANDROID_ID + app, hashed) |
| Sales from offline days never reached the panel | High | Last 7 days re-sent, one record per date |
| PDF report crashed with long item lists | High | Tables continue across pages |
| Panel added PKR and AED together; used UTC dates | Medium | Per-currency totals; local dates |
| APK 75 MB | Medium | Split per CPU type, fonts subset, obfuscated code, two plugins replaced by ~150 lines of own Android code |
| Bluetooth plugin needed Android SDK 37 (build failure) | Blocker (build) | Replaced by own code |
| Location dialog blocked other screens in tests | Low | Asked only when the phone can read location |

## 4. Why the APK is bigger than a 5 MB app

A Flutter app always contains the Flutter engine (`libflutter.so`, ~11 MB uncompressed for one CPU type) plus the compiled app (`libapp.so`). This app also bundles an offline SQLite database engine (1.5 MB), Firebase (login + Firestore), PDF generation and fonts for English and Urdu/Arabic. A 5 MB app is normally a native Kotlin app or a web-view wrapper without an offline database. React Native apps start around 8–15 MB for the same reasons. The installable APK is now one file per CPU type; see §5 for the measured size.

## 5. Build

| Item | Value |
|---|---|
| Commands (CI) | `flutter analyze` · `flutter test` · `flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols` · `flutter build appbundle …` |
| Artifacts | `releases/dt-food-pos-latest.apk` (arm64) **25,787,288 bytes (24.6 MB)**, `releases/dt-food-pos-armv7-old-phones.apk` **23,885,062 bytes (22.8 MB)**, `releases/dt-food-admin-panel.zip` |
| SHA-256 (arm64) | `0cb6481b6233d6fe1031afde490e6c25cd6ca67b11e84475d0026a028c66a9f5` |
| Size history | 75 MB (one APK for all phones) → 27.2 MB (split) → **24.6 MB** (fonts, obfuscation, plugins replaced). What remains: Flutter engine 11.7 MB, app code 9.4 MB, Android/Firebase code 3.4 MB, SQLite 1.5 MB (uncompressed). |
| Signing | Debug key until the 4 GitHub secrets are added (keystore was generated and given to the owner privately, not committed). Install works; Play Store needs a release key. **Updates install over the old app only with the same key** — set the release key before giving the app to restaurants. |

## 6. Manual acceptance on real hardware (to be done by DT)

1. Install on 2 phones (Android 10 and 13+). Splash: no white strip.
2. Create account → panel: approve with plan/fee → app opens by itself.
3. Uninstall + reinstall on the same phone → sign in → it must **not** ask for phone approval.
4. Second phone → "New phone needs approval" → approve in panel.
5. Bluetooth printer: pair in Android settings → Settings › Add printer › Bluetooth → test print, a bill with Urdu item names, a KOT.
6. LAN printer: IP:9100 → test print.
7. Turn on location sharing → panel › Phones map shows the phone.
8. Make sales, turn off internet for a day, then reconnect → panel shows both days.
9. Panel: suspend → app shows the message within seconds (online). Activate → app works.
10. Reports → PDF opens and prints.
