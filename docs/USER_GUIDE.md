# DT Food POS — User Guide (mukhtasar)

## A. Restaurant (Android app)
1. **Install:** `releases/dt-food-pos-latest.apk` (purane 32-bit phone: `dt-food-pos-armv7-old-phones.apk`).
2. **Account:** "Create account" → email + password → restaurant ka naam, owner, phone, shehar → **Submit for approval**. Approve hote hi app khud khulti hai.
3. **Setup (pehli dafa):** business details, logo, currency, owner PIN. Phir Menu mein categories/items (ya CSV/Excel import), Staff mein cashier/waiter aur un ke PIN.
4. **Rozana:** PIN se sign in → shift kholein (opening cash) → **Sell**: item tap karein → Dine-in/Takeaway/Delivery/Counter → Charge → payment (cash/card/wallet/udhaar, split bhi) → raseed print/share.
5. **Tables, Hold, KOT:** Tables se order kholein; "Send to kitchen" sirf naye items ki KOT print karta hai; Held orders se wapas laayein.
6. **Refund/void:** Bills → bill kholein → refund (PIN/permission aur wajah zaroori, audit mein likha jata hai).
7. **Printer:** Settings → Add printer → **Wi-Fi/LAN** (IP:9100) ya **Bluetooth** (pehle Android Bluetooth settings mein printer pair karein, phir yahan chunein) → 58/80 mm → Bill/KOT/Both. Raseed ka design: Settings → Receipt design.
8. **Reports:** tareekh/muddat chunein → Summary, Items, Categories, Cashiers → **CSV** ya **PDF** share.
9. **Inventory/Suppliers:** stock items, purchase (supplier ke udhaar ke saath), supplier payment, wastage, stock count.
10. **Backup:** Settings → Backup (password ke saath). Hafte mein kam az kam ek dafa.
11. **Internet:** app offline chalti hai. App bar ka badal (cloud) icon: ✓ = sync ho gaya, kata hua = offline (sale mehfooz hai, baad mein report hogi). Har 7 din mein ek dafa internet zaroori.
12. **Support:** app bar ka support icon → DT se chat.

## B. Digital Target (Super Admin panel) — https://dt-food-app.web.app
| Page | Kaam |
|---|---|
| Dashboard | Restaurants ki ginti har status mein, aaj ki reported sale (currency ke hisaab se alag), phones online/offline, unpaid invoices |
| Restaurants | Search/filter → restaurant kholein → **Approve** (plan + fee; fee Settings ki plan prices se khud bhar jati hai) → status (Active, Payment pending, Suspend, Block, Expire — message ke saath) → plan extend → phones approve/block/remove → details edit → private notes |
| Invoices | Invoice banayein → Print/PDF, WhatsApp → **Record payment** (licence plan ke hisaab se khud aage) → Void |
| Support | Har restaurant ki chat, jawab, clear/delete |
| Phones | Model, Android/app version, last seen, block/delete |
| Reminders | Payment pending / expire hone wale restaurants ko WhatsApp paigham |
| Settings | Branding, App control (offline din, notice, min version), Billing (bank, QR, signature, terms, **plan prices**) |
| Admins | Doosre admin ka UID add/remove |
| Audit log | Panel ki har tabdeeli, kis ne aur kab (mitayi nahi ja sakti) |

## C. Setup / deploy
`docs/FIREBASE_SETUP.md` dekhein. Panel update: ZIP folder mein `npx firebase-tools login` phir `npx firebase-tools deploy`.
