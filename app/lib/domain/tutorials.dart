/// How-to guides shown in the app (Help & Tutorials). Written for a shop owner or cashier: short steps, plain words.
/// Three languages: English, Urdu (script) and Roman Urdu. Every topic has the same steps in every language.
enum TutorialLang { en, ur, ro }

class Tutorial {
  const Tutorial(this.id, this.icon, this.title, this.steps);
  final String id;

  /// A Material icon name from [tutorialIcons].
  final String icon;
  final Map<TutorialLang, String> title;
  final Map<TutorialLang, List<String>> steps;
}

const tutorials = <Tutorial>[
  Tutorial('start', 'rocket', {
    TutorialLang.en: 'Getting started',
    TutorialLang.ur: 'شروعات',
    TutorialLang.ro: 'Shuru karna',
  }, {
    TutorialLang.en: [
      'Open the app and tap your name, then type your PIN.',
      'On the Sell screen tap "Start day" and type the cash in the drawer. At night tap "Close day": today starts again from zero and the closed day stays in Reports.',
      'Open the side menu (three lines, top left) to reach Settings, Menu, Reports and the rest.',
      'Add your menu first: Menu > add items with price. Use categories so items are easy to find.',
      'Add a printer in Settings > Printers (Bluetooth or WiFi) and print a test slip.',
    ],
    TutorialLang.ur: [
      'ایپ کھولیں، اپنے نام پر ٹیپ کریں اور پن لکھیں۔',
      'سیل اسکرین پر "شفٹ کھولیں" دبائیں اور دراز میں موجود کیش لکھیں۔ شفٹ کے بغیر بھی بِکری ہو سکتی ہے مگر کیش گنتی کے لیے شفٹ ضروری ہے۔',
      'سیٹنگز، مینو اور رپورٹس تک جانے کے لیے سائیڈ مینو (اوپر بائیں تین لائنیں) کھولیں۔',
      'پہلے اپنا مینو بنائیں: مینو میں آئٹم اور قیمت شامل کریں۔ کیٹیگری بنائیں تاکہ آئٹم جلدی ملیں۔',
      'سیٹنگز > پرنٹرز میں پرنٹر (بلوٹوتھ یا وائی فائی) جوڑیں اور ٹیسٹ سلپ نکالیں۔',
    ],
    TutorialLang.ro: [
      'App kholein, apne naam par tap karein aur PIN likhein.',
      'Sell screen par "Shift kholein" dabayein aur drawer mein maujood cash likhein. Shift ke baghair bhi sale ho sakti hai, magar cash ginti ke liye shift zaroori hai.',
      'Settings, Menu aur Reports tak jane ke liye side menu (upar left teen lines) kholein.',
      'Pehle apna menu banayein: Menu mein item aur price add karein. Category banayein taake item jaldi milein.',
      'Settings > Printers mein printer (Bluetooth ya WiFi) jorein aur test slip nikalein.',
    ],
  }),
  Tutorial('sell', 'cart', {
    TutorialLang.en: 'Making a sale',
    TutorialLang.ur: 'بل بنانا',
    TutorialLang.ro: 'Bill banana',
  }, {
    TutorialLang.en: [
      'Tap an item to add it. Items with sizes or add-ons open a small sheet to choose them.',
      'Items sold by weight (kg, litre) ask for the weight: type grams or kg and see the price at once.',
      'Pick the order type: Dine-in, Takeaway, Delivery or Counter. Delivery asks for phone, name and address; a saved customer appears when you type the phone.',
      'Open the cart (View Cart), change quantities, add a discount or a note if needed.',
      'Tap Charge, choose how the customer pays (Cash, Card, Easypaisa, JazzCash, Bank, Credit) and tap Complete Order. The receipt prints.',
      'Split payment: tap another payment method to add a second part, for example half cash and half card.',
    ],
    TutorialLang.ur: [
      'آئٹم پر ٹیپ کریں تو شامل ہو جاتا ہے۔ سائز یا ایڈ آن والے آئٹم پر چھوٹی شیٹ کھلتی ہے۔',
      'وزن سے بکنے والے آئٹم (کلو، لیٹر) پر وزن پوچھا جاتا ہے: گرام یا کلو لکھیں، قیمت فوراً نظر آتی ہے۔',
      'آرڈر کی قسم چنیں: ڈائن اِن، ٹیک اوے، ڈیلیوری یا کاؤنٹر۔ ڈیلیوری میں فون، نام اور پتہ آتا ہے؛ فون لکھتے ہی محفوظ گاہک سامنے آ جاتا ہے۔',
      'کارٹ کھولیں، مقدار بدلیں، ضرورت ہو تو ڈسکاؤنٹ یا نوٹ لگائیں۔',
      'چارج دبائیں، ادائیگی کا طریقہ چنیں (کیش، کارڈ، ایزی پیسہ، جاز کیش، بینک، اُدھار) اور آرڈر مکمل کریں۔ رسید پرنٹ ہو جاتی ہے۔',
      'دو طریقوں سے ادائیگی: دوسرا طریقہ دبائیں، مثلاً آدھا کیش اور آدھا کارڈ۔',
    ],
    TutorialLang.ro: [
      'Item par tap karein to add ho jata hai. Size ya add-on wale item par chhoti sheet khulti hai.',
      'Wazan se bikne wale item (kg, litre) par wazan poocha jata hai: gram ya kg likhein, price foran nazar aati hai.',
      'Order type chunein: Dine-in, Takeaway, Delivery ya Counter. Delivery mein phone, naam aur pata aata hai; phone likhte hi saved customer samne aa jata hai.',
      'Cart kholein, quantity badlein, zaroorat ho to discount ya note lagayein.',
      'Charge dabayein, payment ka tareeqa chunein (Cash, Card, Easypaisa, JazzCash, Bank, Udhaar) aur Complete Order dabayein. Receipt print ho jati hai.',
      'Do tareeqon se payment: doosra tareeqa dabayein, maslan aadha cash aur aadha card.',
    ],
  }),
  Tutorial('kitchen', 'kitchen', {
    TutorialLang.en: 'Kitchen, KOT and tokens',
    TutorialLang.ur: 'کچن، کے او ٹی اور ٹوکن',
    TutorialLang.ro: 'Kitchen, KOT aur token',
  }, {
    TutorialLang.en: [
      'In the cart tap "Send to kitchen". The order goes to the kitchen board, the bill becomes a running bill and the cart is cleared for the next customer.',
      'Use the arrow next to it to choose: Send only, or Send and print KOT (the kitchen ticket).',
      'Settings > Print settings: switch KOT, tokens and bills on or off separately, and choose which print by themselves for dine-in, takeaway, delivery and counter.',
      'The Kitchen screen has New, Preparing, Ready and Completed. Tap the button on a ticket to move it on. You get an alert when an order is ready.',
      'To take payment later: Bills > Held / Running, open the bill and tap Take payment. Paying never removes the order from the kitchen history.',
      'KOT and tokens are different papers: the KOT tells the kitchen what to cook, the token is the number given to the customer.',
    ],
    TutorialLang.ur: [
      'کارٹ میں "کچن بھیجیں" دبائیں۔ آرڈر کچن بورڈ پر چلا جاتا ہے، بل رننگ بل بن جاتا ہے اور اگلے گاہک کے لیے کارٹ خالی ہو جاتی ہے۔',
      'اس کے ساتھ والے تیر سے چنیں: صرف بھیجیں، یا بھیجیں اور کے او ٹی پرنٹ کریں (کچن کی پرچی)۔',
      'سیٹنگز > پرنٹ سیٹنگز: کے او ٹی، ٹوکن اور بل الگ الگ آن یا آف کریں، اور ڈائن اِن، ٹیک اوے، ڈیلیوری اور کاؤنٹر کے لیے خودکار پرنٹ چنیں۔',
      'کچن اسکرین پر نیا، تیار ہو رہا، تیار اور مکمل ہیں۔ پرچی کا بٹن دبا کر آگے بڑھائیں۔ آرڈر تیار ہو تو الرٹ آتا ہے۔',
      'بعد میں ادائیگی کے لیے: بلز > ہولڈ / رننگ، بل کھولیں اور ادائیگی لیں دبائیں۔ ادائیگی سے کچن کی ہسٹری نہیں مٹتی۔',
      'کے او ٹی اور ٹوکن الگ کاغذ ہیں: کے او ٹی کچن کو بتاتی ہے کہ کیا پکانا ہے، ٹوکن گاہک کو دیا جانے والا نمبر ہے۔',
    ],
    TutorialLang.ro: [
      'Cart mein "Kitchen bhejein" dabayein. Order kitchen board par chala jata hai, bill running bill ban jata hai aur agle customer ke liye cart khali ho jati hai.',
      'Is ke saath wale teer se chunein: Sirf bhejein, ya Bhejein aur KOT print karein (kitchen ki parchi).',
      'Settings > Print settings: KOT, token aur bill alag alag on ya off karein, aur dine-in, takeaway, delivery aur counter ke liye khud-ba-khud print chunein.',
      'Kitchen screen par New, Preparing, Ready aur Completed hain. Parchi ka button dabakar aage barhayein. Order ready ho to alert aata hai.',
      'Baad mein payment ke liye: Bills > Held / Running, bill kholein aur Take payment dabayein. Payment se kitchen ki history nahi mitti.',
      'KOT aur token alag kaghaz hain: KOT kitchen ko batati hai kya pakana hai, token customer ko diya jane wala number hai.',
    ],
  }),
  Tutorial('tables', 'tables', {
    TutorialLang.en: 'Tables: merge, split, move',
    TutorialLang.ur: 'ٹیبلز: ملانا، تقسیم، منتقل',
    TutorialLang.ro: 'Tables: milana, taqseem, muntaqil',
  }, {
    TutorialLang.en: [
      'Tables > add an area (Hall, Roof...) and its tables.',
      'Tap a free table to start an order for it. A table with an order shows the amount.',
      'Press and hold an occupied table for the menu: Move to another table, Merge bills, Split bill.',
      'Merge bills: pick the other table. Both bills become one, equal items are added together and the old table becomes free.',
      'Split bill: choose how many of each item to move, then pick where they go: a new bill at this table, a free table, or another table\'s bill.',
    ],
    TutorialLang.ur: [
      'ٹیبلز > ایریا (ہال، چھت...) اور اس کی ٹیبلز بنائیں۔',
      'خالی ٹیبل پر ٹیپ کریں تو اس کا آرڈر شروع ہو جاتا ہے۔ آرڈر والی ٹیبل پر رقم نظر آتی ہے۔',
      'بھری ہوئی ٹیبل کو دبائے رکھیں تو مینو کھلتا ہے: دوسری ٹیبل پر منتقل، بل ملائیں، بل تقسیم کریں۔',
      'بل ملانا: دوسری ٹیبل چنیں۔ دونوں بل ایک ہو جاتے ہیں، ایک جیسے آئٹم جمع ہو جاتے ہیں اور پرانی ٹیبل خالی ہو جاتی ہے۔',
      'بل تقسیم: ہر آئٹم میں سے کتنے الگ کرنے ہیں چنیں، پھر منزل چنیں: اسی ٹیبل پر نیا بل، کوئی خالی ٹیبل، یا دوسری ٹیبل کا بل۔',
    ],
    TutorialLang.ro: [
      'Tables > area (Hall, Roof...) aur uski tables banayein.',
      'Khali table par tap karein to uska order shuru ho jata hai. Order wali table par raqam nazar aati hai.',
      'Bhari hui table ko dabaye rakhein to menu khulta hai: Doosri table par muntaqil, Bill milayein, Bill taqseem karein.',
      'Bill milana: doosri table chunein. Dono bill ek ho jate hain, ek jaise item jama ho jate hain aur purani table khali ho jati hai.',
      'Bill taqseem: har item mein se kitne alag karne hain chunein, phir manzil chunein: isi table par naya bill, koi khali table, ya doosri table ka bill.',
    ],
  }),
  Tutorial('delivery', 'delivery', {
    TutorialLang.en: 'Delivery and riders',
    TutorialLang.ur: 'ڈیلیوری اور رائیڈرز',
    TutorialLang.ro: 'Delivery aur riders',
  }, {
    TutorialLang.en: [
      'Staff > Riders > Add rider (name, phone, bike number).',
      'On the Sell screen choose Delivery. Type the phone number: saved customers appear; tap one to fill name and address. A new customer is saved automatically.',
      'Choose the rider in the delivery box. The rider, name and address print on the bill and the kitchen ticket.',
      'The Riders tab shows each rider\'s deliveries for today and their total.',
    ],
    TutorialLang.ur: [
      'سٹاف > رائیڈرز > رائیڈر شامل کریں (نام، فون، موٹر سائیکل نمبر)۔',
      'سیل اسکرین پر ڈیلیوری چنیں۔ فون نمبر لکھیں: محفوظ گاہک سامنے آتے ہیں، کسی پر ٹیپ کریں تو نام اور پتہ بھر جاتا ہے۔ نیا گاہک خود محفوظ ہو جاتا ہے۔',
      'ڈیلیوری بکس میں رائیڈر چنیں۔ رائیڈر، نام اور پتہ بل اور کچن کی پرچی پر پرنٹ ہوتے ہیں۔',
      'رائیڈرز ٹیب میں ہر رائیڈر کی آج کی ڈیلیوریز اور ان کا کل نظر آتا ہے۔',
    ],
    TutorialLang.ro: [
      'Staff > Riders > Rider add karein (naam, phone, bike number).',
      'Sell screen par Delivery chunein. Phone number likhein: saved customers samne aate hain, kisi par tap karein to naam aur pata bhar jata hai. Naya customer khud save ho jata hai.',
      'Delivery box mein rider chunein. Rider, naam aur pata bill aur kitchen ki parchi par print hote hain.',
      'Riders tab mein har rider ki aaj ki deliveries aur unka total nazar aata hai.',
    ],
  }),
  Tutorial('udhaar', 'book', {
    TutorialLang.en: 'Udhaar (credit) and customers',
    TutorialLang.ur: 'اُدھار اور گاہک',
    TutorialLang.ro: 'Udhaar aur customers',
  }, {
    TutorialLang.en: [
      'Customers > Add customer with name, phone and a credit limit. Tap a customer to add a photo.',
      'To sell on credit: Charge > choose Credit (udhaar). Pick the customer, or use "Walk-in credit" for someone not saved.',
      'Open a customer to see the full ledger: every credit bill, every payment, with a running balance.',
      'When money comes in: open the customer > Receive payment. The balance goes down.',
      'Statement: print, share as a picture or save as CSV for the customer. Udhaar reminder opens WhatsApp with the amount due.',
      'Promotion: Customers > Promotion lets you pick many customers and send an offer on WhatsApp, one by one.',
    ],
    TutorialLang.ur: [
      'گاہک > گاہک شامل کریں: نام، فون اور اُدھار کی حد۔ تصویر لگانے کے لیے گاہک پر ٹیپ کریں۔',
      'اُدھار پر بیچنے کے لیے: چارج > اُدھار چنیں۔ گاہک چنیں، یا نامحفوظ گاہک کے لیے "واک اِن اُدھار" استعمال کریں۔',
      'گاہک کھولیں تو پورا کھاتہ نظر آتا ہے: ہر اُدھار بل، ہر ادائیگی اور چلتا ہوا بیلنس۔',
      'پیسے آئیں تو: گاہک > رقم وصول کریں۔ بیلنس کم ہو جاتا ہے۔',
      'اسٹیٹمنٹ: پرنٹ کریں، تصویر کے طور پر شیئر کریں یا CSV میں محفوظ کریں۔ اُدھار یاد دہانی واٹس ایپ پر واجب الادا رقم کے ساتھ کھلتی ہے۔',
      'پروموشن: گاہک > پروموشن میں بہت سے گاہک چن کر واٹس ایپ پر آفر ایک ایک کر کے بھیجیں۔',
    ],
    TutorialLang.ro: [
      'Customers > Customer add karein: naam, phone aur udhaar ki hadd. Photo lagane ke liye customer par tap karein.',
      'Udhaar par bechne ke liye: Charge > Udhaar chunein. Customer chunein, ya na-saved customer ke liye "Walk-in udhaar" istemal karein.',
      'Customer kholein to poora khata nazar aata hai: har udhaar bill, har payment aur chalta hua balance.',
      'Paise aayein to: Customer > Raqam wasool karein. Balance kam ho jata hai.',
      'Statement: print karein, picture ki surat mein share karein ya CSV mein save karein. Udhaar yaad-dahani WhatsApp par wajib-ul-ada raqam ke saath khulti hai.',
      'Promotion: Customers > Promotion mein bohat se customers chun kar WhatsApp par offer ek ek kar ke bhejein.',
    ],
  }),
  Tutorial('menu', 'menu', {
    TutorialLang.en: 'Menu, deals and weight items',
    TutorialLang.ur: 'مینو، ڈیلز اور وزنی آئٹم',
    TutorialLang.ro: 'Menu, deals aur wazni items',
  }, {
    TutorialLang.en: [
      'Menu > Add item: name, price, category, a photo if you like. The counter field sends that item\'s kitchen ticket to a station (tandoor, tea...).',
      'Sizes and add-ons: open an item > options. Half / Full, extra cheese, and so on.',
      'Sold by weight: set the unit to kg or litre when adding the item. The price is per kg; the cashier types grams.',
      'Many items at once: Menu > Import (CSV or Excel). Menu > Export saves your whole menu as a file.',
      'Deals: Menu > Deals > New deal. Pick the items and sizes, set one price, and see how much the customer saves. Deals can also be imported in bulk.',
      'Recipes (Inventory) take stock automatically when you sell; a deal takes stock from the items inside it.',
    ],
    TutorialLang.ur: [
      'مینو > آئٹم شامل کریں: نام، قیمت، کیٹیگری، چاہیں تو تصویر۔ کاؤنٹر والا خانہ اس آئٹم کی کچن پرچی کو کسی اسٹیشن (تندور، چائے...) پر بھیجتا ہے۔',
      'سائز اور ایڈ آن: آئٹم کھولیں > آپشنز۔ آدھا / پورا، ایکسٹرا چیز وغیرہ۔',
      'وزن پر بکنے والا: آئٹم بناتے وقت یونٹ کلو یا لیٹر رکھیں۔ قیمت فی کلو ہوتی ہے؛ کیشیئر گرام لکھتا ہے۔',
      'بہت سے آئٹم ایک ساتھ: مینو > امپورٹ (CSV یا ایکسل)۔ مینو > ایکسپورٹ پورا مینو فائل میں محفوظ کرتا ہے۔',
      'ڈیلز: مینو > ڈیلز > نئی ڈیل۔ آئٹم اور سائز چنیں، ایک قیمت رکھیں اور دیکھیں گاہک کی کتنی بچت ہے۔ ڈیلز بھی ایک ساتھ امپورٹ ہو سکتی ہیں۔',
      'ریسیپی (انوینٹری) بِکری پر خود اسٹاک کم کرتی ہے؛ ڈیل اپنے اندر کے آئٹمز سے اسٹاک لیتی ہے۔',
    ],
    TutorialLang.ro: [
      'Menu > Item add karein: naam, price, category, chahein to photo. Counter wala khana is item ki kitchen parchi ko kisi station (tandoor, chai...) par bhejta hai.',
      'Size aur add-on: item kholein > options. Aadha / Poora, extra cheese waghera.',
      'Wazan par bikne wala: item banate waqt unit kg ya litre rakhein. Price per kg hoti hai; cashier gram likhta hai.',
      'Bohat se item ek saath: Menu > Import (CSV ya Excel). Menu > Export poora menu file mein save karta hai.',
      'Deals: Menu > Deals > Nayi deal. Item aur size chunein, ek price rakhein aur dekhein customer ki kitni bachat hai. Deals bhi ek saath import ho sakti hain.',
      'Recipe (Inventory) sale par khud stock kam karti hai; deal apne andar ke items se stock leti hai.',
    ],
  }),
  Tutorial('print', 'print', {
    TutorialLang.en: 'Printers and receipts',
    TutorialLang.ur: 'پرنٹرز اور رسیدیں',
    TutorialLang.ro: 'Printers aur receipts',
  }, {
    TutorialLang.en: [
      'Settings > Printers > Add printer: Bluetooth (pair it in the phone first) or WiFi/LAN (type its IP). Choose 58 mm or 80 mm and what it prints: bills, kitchen tickets or both.',
      'Receipt Design (side menu) changes the look of the bill, the kitchen ticket and the token. Add your logo, title and footer.',
      'Print a test slip after adding a printer. If it fails, check the paper width, Bluetooth pairing and that the printer is on.',
      'Bills > open a bill: Share, WhatsApp, Image (picture of the receipt) or Reprint. A reprint is marked DUPLICATE.',
    ],
    TutorialLang.ur: [
      'سیٹنگز > پرنٹرز > پرنٹر شامل کریں: بلوٹوتھ (پہلے فون میں جوڑیں) یا وائی فائی/LAN (آئی پی لکھیں)۔ 58 یا 80 ملی میٹر چنیں اور یہ کہ کیا پرنٹ ہوگا: بل، کچن پرچی یا دونوں۔',
      'رسید ڈیزائن (سائیڈ مینو) بل، کچن پرچی اور ٹوکن کی شکل بدلتا ہے۔ اپنا لوگو، عنوان اور فُٹر لگائیں۔',
      'پرنٹر جوڑنے کے بعد ٹیسٹ سلپ نکالیں۔ نہ نکلے تو کاغذ کی چوڑائی، بلوٹوتھ جوڑ اور پرنٹر آن ہونا دیکھیں۔',
      'بلز > بل کھولیں: شیئر، واٹس ایپ، تصویر (رسید کی تصویر) یا دوبارہ پرنٹ۔ دوبارہ پرنٹ پر "ڈپلیکیٹ" لکھا ہوتا ہے۔',
    ],
    TutorialLang.ro: [
      'Settings > Printers > Printer add karein: Bluetooth (pehle phone mein pair karein) ya WiFi/LAN (IP likhein). 58 ya 80 mm chunein aur ye ke kya print hoga: bill, kitchen parchi ya dono.',
      'Receipt Design (side menu) bill, kitchen parchi aur token ki shakal badalta hai. Apna logo, title aur footer lagayein.',
      'Printer jorne ke baad test slip nikalein. Na nikle to kaghaz ki chorai, Bluetooth pairing aur printer on hona dekhein.',
      'Bills > bill kholein: Share, WhatsApp, Image (receipt ki picture) ya Reprint. Reprint par "DUPLICATE" likha hota hai.',
    ],
  }),
  Tutorial('reports', 'chart', {
    TutorialLang.en: 'Reports and Day Close',
    TutorialLang.ur: 'رپورٹس اور دن بند کرنا',
    TutorialLang.ro: 'Reports aur Day Close',
  }, {
    TutorialLang.en: [
      'Reports shows sales, refunds, tax and expenses for any dates, with best items, categories and cashiers.',
      'Save a report as PDF or CSV: it goes to your phone\'s Downloads and the share sheet opens.',
      'Day Close (Reports > Day close): check the figures, count the cash if you want, and close. The day is saved as a final Z report that cannot be changed.',
      'Open cash shifts are closed with the day automatically; cash that was not counted is marked as not counted.',
      'After closing, the next sale starts the next business day.',
      'Save any slip or report as a picture: it is saved in your phone\'s gallery (Pictures > DT Food POS).',
    ],
    TutorialLang.ur: [
      'رپورٹس میں کسی بھی تاریخ کی سیل، ریفنڈ، ٹیکس اور اخراجات نظر آتے ہیں، بہترین آئٹمز، کیٹیگریز اور کیشیئرز سمیت۔',
      'رپورٹ PDF یا CSV میں محفوظ کریں: فون کی ڈاؤن لوڈز میں جاتی ہے اور شیئر شیٹ کھلتی ہے۔',
      'ڈے کلوز (رپورٹس > ڈے کلوز): رقوم دیکھیں، چاہیں تو کیش گنیں، اور بند کریں۔ دن آخری زیڈ رپورٹ کے طور پر محفوظ ہو جاتا ہے جو بدلی نہیں جا سکتی۔',
      'کھلی ہوئی کیش شفٹیں دن کے ساتھ خود بند ہو جاتی ہیں؛ جو کیش گنا نہ گیا ہو اس پر "نہیں گنا" لکھا جاتا ہے۔',
      'بند کرنے کے بعد اگلی سیل اگلے کاروباری دن میں جاتی ہے۔',
      'کوئی بھی سلپ یا رپورٹ تصویر کے طور پر محفوظ کریں: وہ فون کی گیلری (Pictures > DT Food POS) میں ملتی ہے۔',
    ],
    TutorialLang.ro: [
      'Reports mein kisi bhi tareekh ki sale, refund, tax aur akhrajat nazar aate hain, behtareen items, categories aur cashiers samet.',
      'Report PDF ya CSV mein save karein: phone ki Downloads mein jati hai aur share sheet khulti hai.',
      'Day Close (Reports > Day close): raqoom dekhein, chahein to cash ginein, aur band karein. Din aakhri Z report ki surat mein save ho jata hai jo badli nahi ja sakti.',
      'Khuli hui cash shifts din ke saath khud band ho jati hain; jo cash gina na gaya ho us par "nahi gina" likha jata hai.',
      'Band karne ke baad agli sale agle karobari din mein jati hai.',
      'Koi bhi slip ya report picture ki surat mein save karein: woh phone ki gallery (Pictures > DT Food POS) mein milti hai.',
    ],
  }),
  Tutorial('staff', 'people', {
    TutorialLang.en: 'Staff, access and attendance',
    TutorialLang.ur: 'سٹاف، رسائی اور حاضری',
    TutorialLang.ro: 'Staff, access aur hazri',
  }, {
    TutorialLang.en: [
      'Staff > Add staff: name, PIN and role (Cashier, Waiter, Manager, Kitchen).',
      'Turn on "Choose what this person can open" to give exactly the screens and actions you want: for example only Selling and Bills, with discounts allowed. You can change it later from the staff menu > Access.',
      'Staff and Settings stay with the owner and manager; nobody can give themselves more power.',
      'Attendance: tap In when someone arrives and Out when they leave. The month shows hours and wages.',
      'A waiter can be chosen on a dine-in order; his name prints on the kitchen ticket.',
    ],
    TutorialLang.ur: [
      'سٹاف > سٹاف شامل کریں: نام، پن اور کردار (کیشیئر، ویٹر، منیجر، کچن)۔',
      '"چنیں یہ شخص کیا کھول سکتا ہے" آن کریں اور بالکل وہی اسکرینیں اور کام دیں جو چاہیں: مثلاً صرف سیلنگ اور بلز، ڈسکاؤنٹ کی اجازت کے ساتھ۔ بعد میں سٹاف مینو > رسائی سے بدل سکتے ہیں۔',
      'سٹاف اور سیٹنگز اونر اور منیجر کے پاس ہی رہتے ہیں؛ کوئی خود کو زیادہ اختیار نہیں دے سکتا۔',
      'حاضری: کوئی آئے تو اِن دبائیں اور جائے تو آؤٹ۔ مہینے میں گھنٹے اور اجرت نظر آتی ہے۔',
      'ڈائن اِن آرڈر پر ویٹر چنا جا سکتا ہے؛ اس کا نام کچن پرچی پر پرنٹ ہوتا ہے۔',
    ],
    TutorialLang.ro: [
      'Staff > Staff add karein: naam, PIN aur role (Cashier, Waiter, Manager, Kitchen).',
      '"Chunein ye shakhs kya khol sakta hai" on karein aur bilkul wahi screens aur kaam dein jo chahein: maslan sirf Selling aur Bills, discount ki ijazat ke saath. Baad mein staff menu > Access se badal sakte hain.',
      'Staff aur Settings owner aur manager ke paas hi rehte hain; koi khud ko ziyada ikhtiyar nahi de sakta.',
      'Hazri: koi aaye to In dabayein aur jaye to Out. Mahine mein ghante aur ujrat nazar aati hai.',
      'Dine-in order par waiter chuna ja sakta hai; uska naam kitchen parchi par print hota hai.',
    ],
  }),
  Tutorial('backup', 'backup', {
    TutorialLang.en: 'Backup and restore',
    TutorialLang.ur: 'بیک اپ اور بحالی',
    TutorialLang.ro: 'Backup aur restore',
  }, {
    TutorialLang.en: [
      'Your data lives on this phone only. Make a backup often: Settings > Backup > Back up now.',
      'The backup file is saved in Downloads. Copy it to another phone, a computer or WhatsApp yourself, so a lost phone does not lose your business.',
      'To restore on a new phone: install the app, then Settings > Restore and choose the file.',
      'Restoring replaces the data on the phone with the backup, so do it only on a new or empty phone.',
    ],
    TutorialLang.ur: [
      'آپ کا ڈیٹا صرف اسی فون میں ہے۔ بیک اپ باقاعدگی سے بنائیں: سیٹنگز > بیک اپ > ابھی بیک اپ بنائیں۔',
      'بیک اپ فائل ڈاؤن لوڈز میں محفوظ ہوتی ہے۔ اسے دوسرے فون، کمپیوٹر یا واٹس ایپ پر خود کو بھیج لیں تاکہ فون گم ہونے سے کاروبار کا ڈیٹا ضائع نہ ہو۔',
      'نئے فون پر بحالی: ایپ انسٹال کریں، پھر سیٹنگز > بحالی میں فائل چنیں۔',
      'بحالی فون کے ڈیٹا کو بیک اپ سے بدل دیتی ہے، اس لیے صرف نئے یا خالی فون پر کریں۔',
    ],
    TutorialLang.ro: [
      'Aap ka data sirf isi phone mein hai. Backup baqaidgi se banayein: Settings > Backup > Abhi backup banayein.',
      'Backup file Downloads mein save hoti hai. Isay doosre phone, computer ya WhatsApp par khud ko bhej dein taake phone gum hone se karobar ka data zaya na ho.',
      'Naye phone par restore: app install karein, phir Settings > Restore mein file chunein.',
      'Restore phone ke data ko backup se badal deta hai, is liye sirf naye ya khali phone par karein.',
    ],
  }),
  Tutorial('support', 'support', {
    TutorialLang.en: 'Support and licence',
    TutorialLang.ur: 'سپورٹ اور لائسنس',
    TutorialLang.ro: 'Support aur licence',
  }, {
    TutorialLang.en: [
      'Side menu > Support: write to Digital Target. Replies appear in the same chat. The WhatsApp button opens a chat with us.',
      'Account and Licence (side menu) shows your plan, expiry and the phones allowed.',
      'If your account is payment-pending, suspended or blocked, the app stops with a message. Pay or contact support and it opens again as soon as the account is active.',
      'The app works offline. It only needs internet to check the licence, report totals and for support chat.',
    ],
    TutorialLang.ur: [
      'سائیڈ مینو > سپورٹ: ڈیجیٹل ٹارگٹ کو لکھیں۔ جواب اسی چیٹ میں آتے ہیں۔ واٹس ایپ بٹن ہم سے واٹس ایپ چیٹ کھولتا ہے۔',
      'اکاؤنٹ اور لائسنس (سائیڈ مینو) آپ کا پلان، میعاد اور اجازت شدہ فونز دکھاتا ہے۔',
      'اکاؤنٹ ادائیگی زیرِ التوا، معطل یا بلاک ہو تو ایپ پیغام کے ساتھ رک جاتی ہے۔ ادائیگی کریں یا سپورٹ سے رابطہ کریں؛ اکاؤنٹ فعال ہوتے ہی ایپ کھل جاتی ہے۔',
      'ایپ انٹرنیٹ کے بغیر چلتی ہے۔ انٹرنیٹ صرف لائسنس چیک، ٹوٹل رپورٹ اور سپورٹ چیٹ کے لیے چاہیے۔',
    ],
    TutorialLang.ro: [
      'Side menu > Support: Digital Target ko likhein. Jawab isi chat mein aate hain. WhatsApp button hum se WhatsApp chat kholta hai.',
      'Account & Licence (side menu) aap ka plan, expiry aur ijazat-shuda phones dikhata hai.',
      'Account payment-pending, suspend ya block ho to app paigham ke saath ruk jati hai. Payment karein ya support se rabta karein; account active hote hi app khul jati hai.',
      'App internet ke baghair chalti hai. Internet sirf licence check, totals report aur support chat ke liye chahiye.',
    ],
  }),
];

/// A short, searchable text for a topic in [lang] (used by the search box on the help screen).
String tutorialText(Tutorial t, TutorialLang lang) => '${t.title[lang]} ${t.steps[lang]!.join(' ')}';
