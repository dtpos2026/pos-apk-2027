# DT Food POS: owner's requests and their status

Every request from the owner in this project, in order, with its status. Updated with each build.

## Done (in the app, tests pass; real phone / real printer not tried yet unless said)
- Splash and login: logo animation, no white side strip, red look
- Selling screen: item pictures, red price badge, View Cart bar, Complete Order button, safe area above the phone's buttons
- Receipt after payment: Print, Share, PNG, WhatsApp
- 12 bill designs (including the DT Retail look: boxed TYPE/TABLE/TOKEN, black TOTAL bar) and 12 token designs; 58 / 80 mm
- Logo and business name left / centre / right on the bill
- Tokens: 7 kinds, counters, coupons, categories or items, department / item / piece stubs
- KOT: separate designs, routing to stations, Send to kitchen with or without printing, Print KOT, Print Token, Print Bill
- Print switches: KOT, token, bill (master + automatic, per order type)
- Kitchen board: New / Preparing / Ready / Completed, ready alert, history kept after payment
- Bills: All / Paid / Held-Running / Kitchen / Cancelled; resume, take payment, cancel
- Tables: Dine-in / Takeaway, status cards, New Order, transfer
- Dashboard (sales, vs yesterday, top items), profile menu, inventory OK / Low stock, profit report
- Payment accounts: Cash, Credit, Bank, Easypaisa, JazzCash, G Wallet, your own (provider, number, holder, logo, edit, delete)
- Udhaar: partial credit, repayments, statement (print / PNG / CSV), Walk-in credit account, total owed
- Expenses: category optional, one-tap categories, delete categories
- Day Close bug fixed; Z report saved permanently; next business day
- Backup, PDF, PNG, CSV saved to the phone (Downloads / gallery): Android code not yet tried on a phone
- Themes: Restaurant Red default, Restaurant Red 2 (#C41414), 15 more; Theme Studio (colours, gradient, shadow, borders, buttons, fonts, text size, contrast guard); edit any label
- Staff attendance and wages, purchase orders, online / phone orders, menu share, WhatsApp order QR
- (Removed on the owner's instruction) cloud copy of business data: the data never leaves the phone
- Super Admin panel (Salon-style): restaurants, plans, licence states, modules, theme assign / lock, phones map, support, invoices, reminders, admins, audit

## Not done yet (in the order I will do them)
1. Tables: merge bills, split bills, move items between bills
2. Deals / combos (as in DT Enterprise)
3. Menu: CSV export, weight items entered in grams
4. Customers: photo (gallery / camera), WhatsApp promotion to several customers, Excel / PDF export
5. Staff: rider role, finer permissions checked inside the logic
6. Receipt: "Standard" vs "Original design" switch tuned from a real print
7. Panel: red design, add admin with module permissions, audit-log cleanup, invoice PNG + verification page, notifications, restaurant logo on the map
8. Help section and tutorials (English, Urdu, Roman Urdu), WhatsApp icon in support, restaurant name in support
9. Customer-facing ordering app: later, by your decision

## Needs something from the owner
- Stable signing key: add the GitHub secrets so updates install over the old app
- A photo of a real 58 mm print from the new bill design, to tune it
