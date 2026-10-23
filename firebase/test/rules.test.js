import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, getDocs, collection, writeBatch, serverTimestamp } from 'firebase/firestore';
import { beforeAll, afterAll, beforeEach, describe, it } from 'vitest';

let env;
beforeAll(async () => {
  env = await initializeTestEnvironment({ projectId: 'dt-food-app', firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 8080 } });
});
afterAll(() => env.cleanup());
beforeEach(() => env.clearFirestore());

const OWNER = 'digitaltarget.digital@gmail.com';
const as = (uid, email) => env.authenticatedContext(uid, email ? { email } : {}).firestore();
const anon = () => env.unauthenticatedContext().firestore();
const seed = (fn) => env.withSecurityRulesDisabled(async (c) => fn(c.firestore()));
const newAccount = (over = {}) => ({ businessName: 'Cafe A', ownerName: 'Ali', phone: '0300', city: 'Lahore', country: 'PK', email: 'a@x.pk', status: 'pending', phoneRequests: ['p1'], createdAt: new Date(), appVersion: '0.1.0', ...over });
const makeAdmin = (uid) => seed((db) => setDoc(doc(db, 'admins', uid), { at: 1 }));

describe('accounts', () => {
  it('a new restaurant can register itself as pending only', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'accounts/u1'), newAccount()));
    await assertFails(setDoc(doc(as('u2'), 'accounts/u2'), newAccount({ status: 'active' })));
    await assertFails(setDoc(doc(as('u3'), 'accounts/u3'), newAccount({ plan: 'lifetime' })));
    await assertFails(setDoc(doc(as('u4'), 'accounts/u4'), newAccount({ approvedPhones: ['p1'] })));
    await assertFails(setDoc(doc(as('u5'), 'accounts/other'), newAccount()));
    await assertFails(setDoc(doc(anon(), 'accounts/u6'), newAccount()));
  });
  it('a restaurant reads only its own account', async () => {
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    await assertSucceeds(getDoc(doc(as('u1'), 'accounts/u1')));
    await assertFails(getDoc(doc(as('u2'), 'accounts/u1')));
    await assertFails(getDocs(collection(as('u2'), 'accounts')));
  });
  it('a restaurant cannot approve itself, extend its licence or approve a phone', async () => {
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    const ref = doc(as('u1'), 'accounts/u1');
    await assertFails(updateDoc(ref, { status: 'active' }));
    await assertFails(updateDoc(ref, { expiresAt: new Date('2099-01-01') }));
    await assertFails(updateDoc(ref, { approvedPhones: ['p1', 'p2'] }));
    await assertFails(updateDoc(ref, { blockedPhones: [] }));
    await assertSucceeds(updateDoc(ref, { phoneRequests: ['p1', 'p2'], appVersion: '0.2.0' }));
  });
  it('admin can change status, plan and phones', async () => {
    await makeAdmin('adm');
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    await assertSucceeds(updateDoc(doc(as('adm'), 'accounts/u1'), { status: 'active', plan: 'monthly', approvedPhones: ['p1'] }));
    await assertSucceeds(getDocs(collection(as('adm'), 'accounts')));
  });
});

describe('admin claim', () => {
  it('the first signed-in user can claim, a second cannot', async () => {
    const f = as('first', OWNER);
    const b = writeBatch(f);
    b.set(doc(f, 'config/owner'), { uid: 'first', at: serverTimestamp() });
    b.set(doc(f, 'admins/first'), { at: serverTimestamp() });
    await assertSucceeds(b.commit());
    const s2 = as('second');
    const b2 = writeBatch(s2);
    b2.set(doc(s2, 'config/owner'), { uid: 'second', at: serverTimestamp() });
    b2.set(doc(s2, 'admins/second'), { at: serverTimestamp() });
    await assertFails(b2.commit());
    await assertFails(setDoc(doc(as('third'), 'admins/third'), { at: 1 }));
  });
  it('a different email cannot claim even when nobody has yet', async () => {
    const s = as('imposter', 'someone@else.com');
    const b = writeBatch(s);
    b.set(doc(s, 'config/owner'), { uid: 'imposter', at: serverTimestamp() });
    b.set(doc(s, 'admins/imposter'), { at: serverTimestamp() });
    await assertFails(b.commit());
  });
  it('an admin can add another admin; a normal user cannot', async () => {
    await makeAdmin('adm');
    await assertSucceeds(setDoc(doc(as('adm'), 'admins/new'), { at: 1 }));
    await assertFails(setDoc(doc(as('rando'), 'admins/rando'), { at: 1 }));
  });
});

describe('config', () => {
  it('branding and app control are public to read, admin-only to write; billing is admin-only', async () => {
    await seed(async (db) => { await setDoc(doc(db, 'config/branding'), { name: 'X' }); await setDoc(doc(db, 'config/billing'), { bank: 'secret' }); });
    await assertSucceeds(getDoc(doc(anon(), 'config/branding')));
    await assertFails(setDoc(doc(as('u1'), 'config/branding'), { name: 'Hacked' }));
    await assertFails(getDoc(doc(as('u1'), 'config/billing')));
    await makeAdmin('adm');
    await assertSucceeds(getDoc(doc(as('adm'), 'config/billing')));
    await assertSucceeds(setDoc(doc(as('adm'), 'config/app'), { offlineDays: 7 }));
  });
});

describe('sales totals', () => {
  const day = { date: '2026-10-23', netMinor: 150000, bills: 12, customers: 5 };
  it('owner writes numbers for own uid only; admin reads', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'stats/u1/days/2026-10-23'), day));
    await assertFails(setDoc(doc(as('u1'), 'stats/u2/days/2026-10-23'), day));
    await assertFails(setDoc(doc(as('u1'), 'stats/u1/days/2026-10-24'), { ...day, customerNames: ['Ali'] }));
    await assertFails(setDoc(doc(as('u1'), 'stats/u1/days/2026-10-25'), { ...day, netMinor: 'lots' }));
    await assertFails(getDoc(doc(as('u2'), 'stats/u1/days/2026-10-23')));
    await makeAdmin('adm');
    await assertSucceeds(getDoc(doc(as('adm'), 'stats/u1/days/2026-10-23')));
  });
});

describe('devices', () => {
  const dev = (uid, p) => ({ uid, phoneId: p, model: 'Pixel', android: '14', appVersion: '0.1.0', lastSeenAt: new Date(), locationAllowed: false });
  it('owner writes own phone doc; cannot write another uid or a made-up key', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'devices/u1__p1'), dev('u1', 'p1')));
    await assertFails(setDoc(doc(as('u1'), 'devices/u2__p1'), dev('u2', 'p1')));
    await assertFails(setDoc(doc(as('u1'), 'devices/u1__p2'), { ...dev('u1', 'p2'), approved: true }));
    await assertFails(getDoc(doc(as('u2'), 'devices/u1__p1')));
  });
});

describe('support chat', () => {
  it('owner can post as business only, in own thread; cannot read others', async () => {
    await assertSucceeds(setDoc(doc(as('u1'), 'support/u1'), { businessName: 'A', lastMessage: 'hi', lastAt: 1, unreadForAdmin: true }));
    await assertSucceeds(setDoc(doc(as('u1'), 'support/u1/messages/m1'), { sender: 'business', text: 'hi', at: 1 }));
    await assertFails(setDoc(doc(as('u1'), 'support/u1/messages/m2'), { sender: 'admin', text: 'fake', at: 1 }));
    await assertFails(setDoc(doc(as('u1'), 'support/u2/messages/m3'), { sender: 'business', text: 'x', at: 1 }));
    await assertFails(getDoc(doc(as('u2'), 'support/u1/messages/m1')));
    await makeAdmin('adm');
    await assertSucceeds(setDoc(doc(as('adm'), 'support/u1/messages/m4'), { sender: 'admin', text: 'hello', at: 2 }));
  });
});

describe('invoices', () => {
  it('only admin writes; owner reads own; verify page is public get only', async () => {
    await seed(async (db) => { await setDoc(doc(db, 'invoices/i1'), { accountUid: 'u1', status: 'unpaid' }); await setDoc(doc(db, 'invoiceVerify/tok'), { number: 'DT-1' }); });
    await assertSucceeds(getDoc(doc(as('u1'), 'invoices/i1')));
    await assertFails(getDoc(doc(as('u2'), 'invoices/i1')));
    await assertFails(updateDoc(doc(as('u1'), 'invoices/i1'), { status: 'paid' }));
    await assertSucceeds(getDoc(doc(anon(), 'invoiceVerify/tok')));
    await assertFails(getDocs(collection(anon(), 'invoiceVerify')));
    await assertFails(deleteDoc(doc(as('u1'), 'invoices/i1')));
  });
});

describe('audit log', () => {
  const entry = (uid) => ({ at: serverTimestamp(), adminUid: uid, adminEmail: 'a@b.c', action: 'account.status', accountUid: 'u1', details: { status: 'active' } });
  it('admins append with the server time; nobody edits or deletes; others cannot read or write', async () => {
    await makeAdmin('adm');
    await assertSucceeds(setDoc(doc(as('adm'), 'auditLog/e1'), entry('adm')));
    await assertFails(setDoc(doc(as('adm'), 'auditLog/e2'), { ...entry('adm'), at: new Date('2020-01-01') }));
    await assertFails(setDoc(doc(as('adm'), 'auditLog/e3'), entry('someone-else')));
    await assertFails(updateDoc(doc(as('adm'), 'auditLog/e1'), { action: 'x' }));
    await assertFails(deleteDoc(doc(as('adm'), 'auditLog/e1')));
    await assertFails(setDoc(doc(as('u1'), 'auditLog/e4'), entry('u1')));
    await assertFails(getDoc(doc(as('u1'), 'auditLog/e1')));
    await assertSucceeds(getDoc(doc(as('adm'), 'auditLog/e1')));
  });
});
