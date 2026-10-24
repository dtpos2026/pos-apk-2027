# Food tokens, coupons, 58/80 mm bills and kitchen tickets

For food points where the customer pays at the main counter, receives a printed token, and collects food from the right
stall or tandoor. Everything below is stored in the phone's local database and works with no internet.

## 1. What was added

| Part | Where in the app | Code |
|---|---|---|
| Token types (7) | Settings → *Tokens & designs* → **Token types** | `domain/token.dart` (`TokenRule`), `data/token_service.dart` |
| Seven ready-made designs, visual editor | Settings → *Tokens & designs* → **Designs** | `domain/token.dart` (`TokenDesign`, `builtInTemplates`), `features/tokens/token_designer_screen.dart` |
| Bill styles (Classic / Table + words / Modern / Compact), heading box, token on bill, amount in words | Settings → Receipt design | `domain/receipt.dart` (`buildBillDoc`), `domain/receipt_template.dart` (`BillDesign`) |
| Kitchen ticket (KOT) designs | *Tokens & designs* → **Options** | `domain/receipt.dart` (`buildKotDoc`), `KotDesign` |
| Counter/station on items, categories and printers | Menu → item / Categories; Settings → Add printer | `data/menu_service.dart`, `settings_screen.dart` |
| Today's tokens: collect, print, reprint, redeem coupon | bottom/side bar **Tokens** (appears once a token type exists) | `features/tokens/tokens_screen.dart` |

## 2. Token types

| Type | What it prints | Numbering |
|---|---|---|
| **Order token** | One token, big number, for the whole order | its own counter |
| **Product token** | Items of one counter (group) as one token, or one token per product line | its own counter |
| **Unit token** | One token for every single unit (3 teas = 3 tokens) | its own counter |
| **Price receipt token** | Order token with names, quantities, unit prices, discount, tax, total | its own counter |
| **Tandoor / roti token** | Items of the tandoor counter, quantity in large type | its own counter |
| **Food court / stall token** | Counter name + "Collect from…" instruction + number | its own counter |
| **Prepaid coupon** | One coupon per unit sold, with a unique code + QR; redeemable once | its own counter |

Each token type (a *rule*) has: name, prefix (up to 3 letters/digits), number style (1, 01, 001, 0001), start number, restart-every-day
switch, counter/station, split mode (product), collection instruction, design, printer, copies, automatic/manual printing, on/off.
A business can have any number of rules (for example two stalls, each with its own prefix).

**Product routing.** Every item has a counter: its own (Menu → item → *Counter / station*) or, if empty, its category's
(Menu → Categories → counter icon). A rule picks the items whose counter equals the rule's counter (case-insensitive). A rule with
no counter (order, product, unit, price) takes every item. Tandoor, stall and coupon rules need a counter.

**Numbers.** Handed out inside the same database transaction as the sale, so a number is never used twice and never skipped by a
crash. `token_issue` has a `UNIQUE(order, rule, part)` key, so even a retry cannot create a second token. Restart-every-day uses the
business date.

**Order → token links.** `token_issue.order_id` links a token to its sale; the token stores a snapshot of what it shows. The bill
prints the order token number (switchable). Status: *waiting → collected* (hand-over) or *cancelled*; print count and time are kept.
A voided/fully refunded sale cancels its waiting tokens and unused coupons (collected tokens and redeemed coupons stay).

**Coupons.** Code format `CP-XXXXX-XXXXX` (no 0/O/1/I/L). Redeeming is a single guarded database update (`WHERE status='issued'`), so two cashiers
cannot both redeem the same code; a second try says *Already used (time)*. Redemptions are audited. To sell coupons, set the
counter of the coupon item (e.g. "Coupon"), add a *Prepaid coupon* type with that counter.

## 3. Designs and the editor

Twelve ready-made designs, all genuinely different (checked by test); the first seven are for food counters, the last five (**Retail · Classic, Boxed, Bold Number, Minimal, Ticket**) are the token designs of DT Retail POS: **Classic Food Token**, **Product-Wise Token**,
**Itemized Price Receipt**, **Tandoor / Roti Token**, **Food Court / Stall Token**, **Premium Branded Token** (logo, star frame, prices, QR),
and **Prepaid Coupon**.

The editor changes, with a live preview of exactly what the printer receives (58 or 80 mm):

- show/hide, drag-to-reorder, add and delete **blocks**: logo, business name, heading, counter name, token number, collect-from line,
  order number, date/time, order type + table, cashier, items, totals, coupon code, QR, free text, line, blank space, "Powered by" line;
- per block: alignment, size (1–5), bold, wording (heading/free text/collect line; plus an Urdu line in bilingual designs);
- items: quantity, price, amount, column titles, add-ons/notes, big quantity; totals: subtotal, discount, tax;
- language of the standard words: **English, اردو, or English + اردو**; line style: none / line / double / dots / stars; top and bottom margin;
- create (new design), duplicate, rename, save, **reset to original** (built-in designs), delete (own designs), **copy as JSON (export)** and **import**;
- preview with sample data of any token type; **test print** to the real printer.

**Honest limits.** Thermal paper is black on white with fixed printer fonts: there are no colours or font families on paper.
Colour/font controls are therefore not offered; size, bold, alignment, lines and margins are. Free pixel-level drag-and-drop is not
offered: blocks are dragged up/down in order (the printer prints top to bottom). A **barcode** block is not implemented (QR is).

## 4. Printers

- Supported and tested with fake printers: **LAN/Ethernet (raw port 9100)** and **Bluetooth classic (SPP)** ESC/POS printers, 58 and 80 mm.
- Not implemented: **USB** printers, **Windows-installed printers** and impact/line printers (there is no Windows app yet). The
  database allows a `usb` connection type but no transport exists; the app will not pretend otherwise.
- Hardware has **not** been tested here (no printer available). Bluetooth/LAN code paths are covered with fake sockets/transport.
- Assignment: a printer has a role (*Bill*, *Kitchen*, *Both*) and, for kitchen/both, a **counter** (Tandoor, Tea, BBQ…). A token goes to
  1) the printer chosen on its rule, else 2) the kitchen/both printer whose counter equals the token's counter, else 3) a bill printer.
- Copies per token type (1–5); KOT copies 1–3. **Reprints** are marked `*** REPRINT ***`, counted and audited; Options can restrict
  reprints to managers (`settings.manage`). Automatic printing happens after the sale; manual printing from *Tokens* or *Bills → Print tokens*.
- Failed prints stay in the print queue with the error and retry (existing queue: up to 5 attempts, survives restarts).
- **Tokens only:** *Options → Print the customer bill* off = no bill on sale; the bill can still be reprinted from Bills.
- *Printers → test* button per printer prints a sample token.

## 5. Offline, permissions, super admin

- All numbering, templates and print jobs are local; nothing is sent to Firebase. Pending print jobs survive app and phone restarts.
- Permissions: set rules/designs = `settings.manage`; selling and printing the first copy = `pos.sell`; reprint restricted by option.
- **Super Admin panel** → restaurant page → **App features**: switch off *Food tokens & coupons* (or any module) for one business.
  The app learns this on its next online sign-in (stored locally as `cloud.modules_off`). The token code checks it, so a hidden module
  does not keep numbering or printing; the settings and records are kept and come back when it is switched on again.
  The panel can also assign an **App theme** (a ready-made theme or custom colours, optionally locked) per business; the phone keeps it offline.
  Token formats, printers, designs and branch settings are per phone (set in the app); they are not stored in Firebase.
- Multi-branch: not implemented (each phone/business has its own numbering and designs; export/import of a design moves it between phones).

## 6. Upgrading

Database version 2 (`migrateToV2`): `product.station`, `token_template`, `token_seq`, `token_issue`, `coupon`. Existing data is untouched.
An existing install has its module list saved without `tokens`; adding the first token type switches the module on automatically.
