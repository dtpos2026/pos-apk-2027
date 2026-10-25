# DT Food POS — audit against the master specification, and plan

Status of each part of the master spec. **Done** = built and covered by automated tests (nothing has been tried on a real phone or printer yet).
**Partial** = some of it exists. **Not started** = not built.

| # | Spec section | Status | Notes |
|---|---|---|---|
| 2 | Red branding / design system | Done (app) | Restaurant Red default, Restaurant Red 2 (#C41414), red price badge, red splash/sign-in/PDF. Panel still uses its own look: **Partial** |
| 3 | Fast mobile billing, order types | Done | Dine-in, takeaway, delivery, counter. Admin control of which order types a restaurant gets: **Not started** (module switches exist) |
| 4 | Payment accounts | Done | Bank/wallet details, logo, edit, delete (only if unused), G Wallet/Easypaisa/JazzCash seeded |
| 5 | Udhaar ledger | Done | Partial credit (split payments), repayments separate from sales, running balance with bill numbers, statement (print/PNG/CSV), Walk-in credit account |
| 6 | Kitchen / KDS | Done | New / Preparing / Ready / Completed, kept after payment, ready alerts, same order id as the bill |
| 7 | Cart, hold, bills | Done | Send to kitchen clears the cart, Bills tabs, resume, cancel keeps kitchen history |
| 8 | Tables: simple + advanced | Partial | Simple mode and transfer done. **Merge / split bills not started** |
| 9 | Menu, CSV, weight items, recipes | Partial | CSV import, kg/l items, recipes, profit report exist. Menu CSV export and grams-entry for weight items: **not started** |
| 10 | Deals / combos | **Not started** | |
| 11 | Customers / CRM | Partial | Customers, address, ledger, WhatsApp reminder. Photo, multi-customer promo, Excel/PDF export: **not started** |
| 12 | Staff, roles, riders | Partial | Roles, PIN login, attendance. Rider role and finer permissions: **not started** |
| 13 | Receipts / 58 mm | Partial | 12 bill styles incl. DT Retail look. "Standard / Original design" switch and real-printer tuning: **not started** |
| 14 | Reports, PDF, PNG, gallery | Done (code) | PNG to Pictures/DT Food POS, PDF/CSV/backup to Downloads (MediaStore). Android part compiled in CI but not tried on a phone |
| 15 | Support, tutorials | **Not started** | |
| 16-22 | Super-admin: restaurants, themes, licence states, admin permissions, audit cleanup, invoices + verification, notifications | Partial | Salon-style panel, licence states (active / payment pending / suspended / blocked / expired), module + theme control, device map exist. Per-admin module permissions, audit cleanup, invoice PNG + verification page, notifications, push: **not started** |
| 23 | Profile / login | Partial | Red branding done; circular logo frame and re-login behaviour not reviewed |
| 24 | Offline-first + sync | Partial | Fully offline BY DESIGN: the restaurant's data (menu, customers, bills, stock) is never uploaded. Firebase only carries licence/account state, device info, daily sales totals, support chat and DT invoices for the Super Admin panel |
| — | KOT / token / bill print switches | Done | Separate masters and automatic switches, per order type, manual Print KOT / Token / Bill |
| — | Theme customisation | Done | Theme Studio (colours, gradient, shadow, borders, buttons, fonts, text size, contrast guard, live preview) and an editor for any label |
| — | Day Close bug | Fixed | See docs/QA_REPORT.md row 47 |

## Order of the remaining work
1. Tables: merge / split bills. Deals. Menu export, grams for weight items.
2. Customers: photo, promotions, exports. Rider role and permissions.
3. Receipt "Original design" mode (needs the owner's real print to tune).
4. Panel: admin permissions, audit cleanup, invoices PNG + verification, notifications, red design.
5. Help section and tutorials in English, Urdu, Roman Urdu.
