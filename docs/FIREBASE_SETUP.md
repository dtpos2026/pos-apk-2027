# Firebase setup (DT Food POS)

Project: **dt-food-app** · Console: https://console.firebase.google.com/project/dt-food-app

Plan: **Spark (free) is enough.** This system uses no Cloud Functions and no Storage.

## 1. Console mein ek dafa karna hai

| # | Kahan | Kya karna hai |
|---|---|---|
| 1 | Build → **Authentication** → Get started → Sign-in method | **Email/Password: Enable** → Save |
| 2 | Build → **Firestore Database** → Create database | **Production mode**, location **asia-south1 (Mumbai)** |
| 3 | Build → **Hosting** → Get started | Bas "Get started" dabayein (panel ka address `dt-food-app.web.app` banega) |
| 4 | Project settings → Your apps | Ek **Web app** registered ho (aap ne already banayi hai, config mil chuki hai) |
| 5 | Authentication → Settings → **Authorized domains** | `dt-food-app.web.app` aur `dt-food-app.firebaseapp.com` (default hote hain) |
| 6 | Authentication → Users → **Add user** | Apni admin email + mazboot password (yeh Super Admin login hai) |

## 2. Rules, indexes aur panel deploy (apne computer par)

Repo ka main folder (jahan `firebase.json` hai):

```
cd admin && npm install && npm run build && cd ..
npx firebase-tools login
npx firebase-tools deploy
```

`deploy` ek saath **panel + rules + indexes** publish karta hai. Deploy ke baad browser mein panel ek dafa **Ctrl+F5** se kholein.

## 3. Pehla Super Admin

1. https://dt-food-app.web.app kholein, step 1.6 wali email/password se sign in karein.
2. "No admin access" aaye to **Become Super Admin** dabayein (sirf pehli dafa chalta hai).
3. Doosra admin: us ka user Authentication mein banayein, woh panel par sign in kare (panel us ka UID dikhata hai), aap **Admins** page se add karein.

## 4. Panel ki Settings (khali hain, apni details bharein)

- **App branding:** naam, contact, WhatsApp, email, support message (app ki sign-in screen par dikhta hai).
- **App control:** offline din (default 7), sab restaurants ko notice, latest / minimum version, update link.
- **Billing & invoices:** company, address, bank, QR, signature, terms, reminder template.

## 5. App (APK)

- Firebase ke public identifiers (apiKey, projectId, appId) app mein build ke waqt shamil hain; woh secret nahi hote, data ki hifazat `firestore.rules` karte hain.
- Agar aap Android app (`digital.target.dt_food_pos`) bhi register karna chahein: Project settings → Your apps → Add app → Android, aur uska appId `--dart-define=FIREBASE_APP_ID=...` se dein.
- APK banane ke liye GitHub → Actions → **Build APK** → Run workflow → `publish` = true. APK `releases/dt-food-pos-latest.apk` mein aati hai.

## 6. Data kahan rehta hai

| Sirf restaurant ke phone mein | Firebase mein |
|---|---|
| Har bill, items, qeemat, customers (naam/phone), staff, udhaar, kharche, inventory | Login (email), account ki halat, plan/expiry, approved phones |
| Backup file | Rozana sale ke **totals** (raqam, bills ki tadaad, customers ki tadaad) |
| | Phone ki halat: model, Android/app version, last seen |
| | Support chat, DT ke invoices |

Location abhi app mein nahi bheji jati (panel ka Phones page "not allowed" dikhata hai) — yeh feature baad mein, restaurant ki ijazat ke saath aayega.

## 7. Offline

App internet ke baghair poori chalti hai. Har **7 din** (panel → App control → Offline days) mein ek dafa internet chahiye taake account check ho. Expiry phone ki ghari se offline bhi lagu hoti hai. Ghari peeche karne par app internet maangti hai.

## 8. Masle

| Masla | Hal |
|---|---|
| App: "Email login is not switched on yet" | Authentication → Email/Password **Enable** |
| App: "App setup incomplete" | Firebase start nahi hua: nayi APK lagayein; phir bhi aaye to mujhe error text bhejein |
| App: "New phone needs approval" | Panel → Restaurants → us ka page → **Approve this phone** |
| Panel: "Permission denied" | Rules deploy nahi hue: `npx firebase-tools deploy` |
| Panel: "needs a Firestore index" | `npx firebase-tools deploy --only firestore` |
| Panel: "No admin access" | Section 3 |
