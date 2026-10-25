import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { readFileSync } from 'node:fs';
import { doc, getDoc, setDoc, updateDoc, deleteField, deleteDoc, getDocs, collection, query, where, writeBatch, serverTimestamp } from 'firebase/firestore';
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

describe('PIN reset sent from the panel', () => {
  it('only an admin can send a reset; the restaurant may clear it and stamp it done, never set one', async () => {
    await makeAdmin('adm');
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    await assertFails(updateDoc(doc(as('u1'), 'accounts/u1'), { pinReset: { pin: '1234', id: 'x' } }));
    await assertSucceeds(updateDoc(doc(as('adm'), 'accounts/u1'), { pinReset: { pin: '4821', id: 'r1', at: new Date() } }));
    await assertFails(updateDoc(doc(as('u2'), 'accounts/u1'), { pinReset: deleteField() }));
    await assertSucceeds(updateDoc(doc(as('u1'), 'accounts/u1'), { pinReset: deleteField(), pinResetDone: { id: 'r1', at: new Date() } }));
  });
});

describe('restaurant logo for the map pin', () => {
  it('a restaurant may store a small logo picture on its own account, nothing bigger, and nothing else about itself', async () => {
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    const ref = doc(as('u1'), 'accounts/u1');
    await assertSucceeds(updateDoc(ref, { logo: 'data:image/jpeg;base64,AAAA' }));
    await assertFails(updateDoc(ref, { logo: 'x'.repeat(40001) }));
    await assertFails(updateDoc(ref, { logo: 'data:image/jpeg;base64,AAAA', status: 'active' }));
    await assertFails(updateDoc(doc(as('u2'), 'accounts/u1'), { logo: 'data:image/jpeg;base64,AAAA' }));
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
  it('admins append with the server time; nobody edits an entry; restaurants cannot read or write', async () => {
    await makeAdmin('adm');
    await assertSucceeds(setDoc(doc(as('adm'), 'auditLog/e1'), entry('adm')));
    await assertFails(setDoc(doc(as('adm'), 'auditLog/e2'), { ...entry('adm'), at: new Date('2020-01-01') }));
    await assertFails(setDoc(doc(as('adm'), 'auditLog/e3'), entry('someone-else')));
    await assertFails(updateDoc(doc(as('adm'), 'auditLog/e1'), { action: 'x' }));
    await assertFails(setDoc(doc(as('u1'), 'auditLog/e4'), entry('u1')));
    await assertFails(deleteDoc(doc(as('u1'), 'auditLog/e1')));
    await assertFails(getDoc(doc(as('u1'), 'auditLog/e1')));
    await assertSucceeds(getDoc(doc(as('adm'), 'auditLog/e1')));
  });
});

describe('the restaurant\'s business data is never stored here', () => {
  it('there is no backup path: nobody can write or read it, owner and admin included', async () => {
    await makeAdmin('adm');
    const op = { entity: 'customer', entityId: 'c1', op: 'upsert', payload: '{"name":"Ali"}', at: serverTimestamp() };
    await assertFails(setDoc(doc(as('u1'), 'backup/u1/ops/k1'), op));
    await assertFails(getDoc(doc(as('u1'), 'backup/u1/ops/k1')));
    await assertFails(setDoc(doc(as('adm'), 'backup/u1/ops/k2'), op));
    await assertFails(setDoc(doc(as('u1'), 'customers/u1/list/c1'), { name: 'Ali' }));
    await assertFails(setDoc(doc(as('u1'), 'orders/o1'), { total: 1 }));
  });
});

describe('admin permissions', () => {
  const makeLimited = (uid, perms) => seed((db) => setDoc(doc(db, 'admins', uid), { at: 1, perms }));
  const makeOwner = (uid) => seed(async (db) => { await setDoc(doc(db, 'config/owner'), { uid, at: 1 }); await setDoc(doc(db, 'admins', uid), { at: 1, perms: [] }); });

  it('an admin without a perms list keeps full access (older admins)', async () => {
    await makeAdmin('old');
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    await assertSucceeds(updateDoc(doc(as('old'), 'accounts/u1'), { status: 'active' }));
    await assertSucceeds(setDoc(doc(as('old'), 'config/app'), { offlineDays: 3 }));
  });
  it('a limited admin can only change what was ticked', async () => {
    await makeLimited('sup', ['support']);
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    await assertSucceeds(getDocs(collection(as('sup'), 'accounts')));
    await assertFails(updateDoc(doc(as('sup'), 'accounts/u1'), { status: 'active' }));
    await assertFails(setDoc(doc(as('sup'), 'config/app'), { offlineDays: 3 }));
    await assertFails(setDoc(doc(as('sup'), 'admins/new'), { at: 1, perms: ['support', 'admins'] }));
    await assertSucceeds(setDoc(doc(as('sup'), 'support/u1'), { businessName: 'A', lastMessage: 'hi', lastAt: 1, unreadForAdmin: false }));
  });
  it('invoices permission can write invoices and extend an account, but cannot touch settings', async () => {
    await makeLimited('acc', ['invoices']);
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    await assertSucceeds(updateDoc(doc(as('acc'), 'accounts/u1'), { status: 'active' }));
    await assertSucceeds(setDoc(doc(as('acc'), 'invoices/i1'), { accountUid: 'u1', number: 'INV-1' }));
    await assertFails(setDoc(doc(as('acc'), 'config/billing'), { company: 'x' }));
    await assertSucceeds(getDoc(doc(as('acc'), 'config/billing')));
  });
  it('only the owner or an admin with the admins permission adds admins; the owner is never locked out', async () => {
    await makeOwner('own');
    await makeLimited('lim', ['restaurants']);
    await assertSucceeds(setDoc(doc(as('own'), 'admins/n1'), { at: 1, perms: ['restaurants'] }));
    await assertFails(setDoc(doc(as('lim'), 'admins/n2'), { at: 1 }));
    await assertSucceeds(setDoc(doc(as('own'), 'accounts/u9'), newAccount({ status: 'active' })));
  });
});

describe('audit log clean-up', () => {
  const entry = (uid) => ({ at: serverTimestamp(), adminUid: uid, adminEmail: 'a@x', action: 'account.update', accountUid: null, details: {} });
  it('an admin with the audit permission can delete entries; others cannot even read them', async () => {
    await seed(async (db) => { await setDoc(doc(db, 'admins/aud'), { at: 1, perms: ['audit'] }); await setDoc(doc(db, 'admins/oth'), { at: 1, perms: ['support'] }); await setDoc(doc(db, 'auditLog/e1'), { at: new Date(), adminUid: 'x', adminEmail: 'x', action: 'a', accountUid: null, details: {} }); });
    await assertFails(getDoc(doc(as('oth'), 'auditLog/e1')));
    await assertFails(deleteDoc(doc(as('oth'), 'auditLog/e1')));
    await assertSucceeds(getDoc(doc(as('aud'), 'auditLog/e1')));
    await assertFails(updateDoc(doc(as('aud'), 'auditLog/e1'), { action: 'changed' }));
    await assertSucceeds(deleteDoc(doc(as('aud'), 'auditLog/e1')));
    await assertSucceeds(setDoc(doc(as('aud'), 'auditLog/e2'), entry('aud')));
  });
});

describe('notifications (the bell in the app)', () => {
  const note = (over = {}) => ({ title: 'Payment due', body: 'Please pay', kind: 'payment', target: 'all', createdAt: serverTimestamp(), createdBy: 'adm', ...over });
  it('admins with the permission send them; restaurants read what is for everyone or for them, never others, never write', async () => {
    await seed(async (db) => { await setDoc(doc(db, 'admins/adm'), { at: 1, perms: ['notifications'] }); await setDoc(doc(db, 'admins/no'), { at: 1, perms: ['support'] }); });
    await assertSucceeds(setDoc(doc(as('adm'), 'notifications/n1'), note()));
    await assertSucceeds(setDoc(doc(as('adm'), 'notifications/n2'), note({ target: 'u1' })));
    await assertFails(setDoc(doc(as('no'), 'notifications/n3'), note()));
    await assertFails(setDoc(doc(as('adm'), 'notifications/n4'), note({ kind: 'spam' })));
    await assertFails(setDoc(doc(as('adm'), 'notifications/n5'), note({ extra: 1 })));
    await assertFails(setDoc(doc(as('u1'), 'notifications/n6'), note()));
    await assertSucceeds(getDoc(doc(as('u1'), 'notifications/n1')));
    await assertSucceeds(getDoc(doc(as('u1'), 'notifications/n2')));
    await assertFails(getDoc(doc(as('u2'), 'notifications/n2')));
    await assertSucceeds(getDoc(doc(as('u2'), 'notifications/n1')));
    // the exact query the app runs
    await assertSucceeds(getDocs(query(collection(as('u1'), 'notifications'), where('target', 'in', ['all', 'u1']))));
    await assertFails(getDocs(query(collection(as('u1'), 'notifications'), where('target', 'in', ['all', 'u2']))));
    await assertFails(deleteDoc(doc(as('u1'), 'notifications/n1')));
    await assertSucceeds(deleteDoc(doc(as('adm'), 'notifications/n1')));
  });
});

describe('restaurant name and address', () => {
  it('the restaurant may update its own name and address (not empty, not too long), nothing else about itself', async () => {
    await seed((db) => setDoc(doc(db, 'accounts/u1'), newAccount()));
    await assertSucceeds(updateDoc(doc(as('u1'), 'accounts/u1'), { businessName: 'Takeaway Pizza', address: 'Sadar Bazar, Narang' }));
    await assertFails(updateDoc(doc(as('u1'), 'accounts/u1'), { businessName: '' }));
    await assertFails(updateDoc(doc(as('u1'), 'accounts/u1'), { businessName: 'x'.repeat(121) }));
    await assertFails(updateDoc(doc(as('u1'), 'accounts/u1'), { status: 'active' }));
    await assertFails(updateDoc(doc(as('u2'), 'accounts/u1'), { businessName: 'Hijack' }));
  });
});
