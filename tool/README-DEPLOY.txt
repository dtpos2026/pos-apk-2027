DT Food POS - Super Admin panel (Firebase project: dt-food-app)

Panel PEHLE SE BANA HUA hai (admin/dist). npm install / npm run build ki zaroorat NAHI.

1) Node.js (LTS) install ho.
2) Isi folder mein (jahan firebase.json hai) CMD kholein:

     npx firebase-tools login
     npx firebase-tools deploy

   (deploy panel + Firestore rules + indexes sab upload karta hai. Rules ZAROOR deploy hon: admin permissions,
    notifications aur logo pin unhi par chalte hain.)

3) https://dt-food-app.web.app  (Ctrl+F5)
   digitaltarget.digital@gmail.com se sign in -> "Become Super Admin" (sirf pehli dafa)

4) Settings bharein: App branding (WhatsApp number bhi: app ke Support mein WhatsApp button isi se aata hai),
   App control, Billing (plan prices, bank, logo/signature).

5) Naya admin: Admins page -> email + password likhein (login khud ban jata hai) aur jo kaam dene hain tick karein.
   Notifications page: template chunein, bhejein; restaurant ki app ki bell mein foran aata hai.
   Audit log: purani entries select kar ke ya "X din se purani" delete ho sakti hain.

Guide: docs/USER_GUIDE.md  ·  Setup: docs/FIREBASE_SETUP.md  ·  QA: docs/QA_REPORT.md
