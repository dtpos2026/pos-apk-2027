// Runs the REAL FirebaseApi against the local Firebase emulators (auth + firestore) with the real security rules.
// Skipped unless FIRESTORE_EMULATOR_HOST is set (see `npm run test:emulator`).
import { describe, expect, it } from 'vitest';
import { createFirebaseApi } from './firebaseApi';
import { initializeApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, createUserWithEmailAndPassword } from 'firebase/auth';
import { addDoc, collection, connectFirestoreEmulator, doc, getDocs, getFirestore, query, serverTimestamp, setDoc, Timestamp, where } from 'firebase/firestore';

const on = !!process.env.FIRESTORE_EMULATOR_HOST;
const cfg = { apiKey: 'fake', authDomain: 'localhost', projectId: 'dt-food-app', appId: 'fake' };
const emu = { host: '127.0.0.1', authPort: 9099, firestorePort: 8080 };

// A second Firebase app instance stands in for the restaurant's phone.
async function restaurant(name: string, email: string) {
  const app = initializeApp(cfg, name);
  const auth = getAuth(app); connectAuthEmulator(auth, `http://${emu.host}:${emu.authPort}`, { disableWarnings: true });
  const db = getFirestore(app); connectFirestoreEmulator(db, emu.host, emu.firestorePort);
  const uid = (await createUserWithEmailAndPassword(auth, email, 'secret123')).user.uid;
  return { db, uid };
}

describe.skipIf(!on)('FirebaseApi on the emulator', () => {
  it('runs the whole life of a restaurant', async () => {
    const api = createFirebaseApi(cfg, emu, 'admin');
    const adminUid = await api._register!('digitaltarget.digital@gmail.com', 'secret123');
    expect(await api.ownerClaimed()).toBe(false);
    expect(await api.isAdmin(adminUid)).toBe(false);
    await api.claimSuperAdmin(adminUid);
    expect(await api.isAdmin(adminUid)).toBe(true);
    expect(await api.ownerClaimed()).toBe(true);

    // the restaurant registers from its phone
    const r = await restaurant('rest1', 'cafe@x.pk');
    await setDoc(doc(r.db, 'accounts', r.uid), { businessName: 'Cafe One', ownerName: 'Ali', phone: '0300', city: 'Lahore', country: 'PK', email: 'cafe@x.pk', status: 'pending', phoneRequests: ['ph1'], createdAt: serverTimestamp(), appVersion: '0.1.0' });
    // ...and cannot approve itself
    await expect(setDoc(doc(r.db, 'accounts', r.uid), { status: 'active' }, { merge: true })).rejects.toThrow();

    let list = await api.accounts();
    expect(list).toHaveLength(1);
    expect(list[0].status).toBe('pending');

    await api.approve(r.uid, 'monthly', 150000, new Date(Date.now() + 30 * 86400000));
    const a = (await api.account(r.uid))!;
    expect(a.status).toBe('active');
    expect(a.customerId).toBe('DTC-0001');
    expect(a.approvedPhones).toEqual(['ph1']);
    expect(a.phoneRequests).toEqual([]);
    await expect(api.approve(r.uid, 'monthly', 1, null)).rejects.toThrow(/pending/);

    // a second phone needs approval and the limit is enforced
    await setDoc(doc(r.db, 'accounts', r.uid), { phoneRequests: ['ph2'] }, { merge: true });
    await expect(api.approvePhone(r.uid, 'ph2')).rejects.toThrow(/allows 1 phone/);
    await api.patchAccount(r.uid, { maxPhones: 2 });
    await api.patchAccount(r.uid, { disabledModules: ['tokens', 'tables'] });
    expect((await api.account(r.uid))!.disabledModules).toEqual(['tokens', 'tables']);
    await api.patchAccount(r.uid, { themeId: 'custom:112233,FF5A1F,,,outline,14', themeLocked: true });
    const themed = (await api.account(r.uid))!;
    expect([themed.themeId, themed.themeLocked]).toEqual(['custom:112233,FF5A1F,,,outline,14', true]);
    await api.approvePhone(r.uid, 'ph2');
    expect((await api.account(r.uid))!.approvedPhones).toEqual(['ph1', 'ph2']);
    await api.setDeviceBlocked(r.uid, 'ph2', true);
    expect((await api.account(r.uid))!.blockedPhones).toEqual(['ph2']);

    // sales totals the app reports
    await setDoc(doc(r.db, 'stats', r.uid), { todayNetMinor: 250000, todayBills: 9, updatedAt: serverTimestamp(), currency: 'PKR' });
    await setDoc(doc(r.db, 'stats', r.uid, 'days', '2026-10-23'), { date: '2026-10-23', netMinor: 250000, bills: 9, customers: 4 });
    expect((await api.accounts())[0].todayNetMinor).toBe(250000);
    expect((await api.days(r.uid))[0]).toMatchObject({ date: '2026-10-23', netMinor: 250000 });

    // invoice -> payment extends the licence from the current expiry
    const before = (await api.account(r.uid))!.expiresAt!;
    const inv = await api.createInvoice(r.uid, 150000, 10000, new Date(Date.now() + 7 * 86400000), 'monthly');
    expect(inv.number).toMatch(/^DT-\d{4}-0001$/);
    expect((await api.verifyInvoice(inv.verifyToken))!.status).toBe('unpaid');
    await api.recordPayment(inv.id);
    await expect(api.recordPayment(inv.id)).rejects.toThrow(/not waiting/);
    expect((await api.verifyInvoice(inv.verifyToken))!.status).toBe('paid');
    const after = (await api.account(r.uid))!;
    expect(after.expiresAt!.getTime()).toBeGreaterThan(before.getTime() + 27 * 86400000);
    await expect(api.voidInvoice(inv.id)).rejects.toThrow(/paid/);

    // suspend with a message
    await api.setStatus(r.uid, 'suspended', 'Please pay');
    expect((await api.account(r.uid))!).toMatchObject({ status: 'suspended', adminMessage: 'Please pay' });

    // support chat both ways
    await setDoc(doc(r.db, 'support', r.uid), { businessName: 'Cafe One', lastMessage: 'help', lastAt: serverTimestamp(), unreadForAdmin: true });
    await addDoc(collection(r.db, 'support', r.uid, 'messages'), { sender: 'business', text: 'help', at: serverTimestamp() });
    expect((await api.threads())[0]).toMatchObject({ uid: r.uid, unreadForAdmin: true });
    await api.sendMessage(r.uid, 'on it');
    expect((await api.messages(r.uid)).map(m => m.sender)).toEqual(['business', 'admin']);
    await api.clearChat(r.uid);
    expect(await api.messages(r.uid)).toEqual([]);
    await api.deleteChat(r.uid);
    expect(await api.threads()).toEqual([]);

    // settings + admins + notes
    await api.setAppControl({ offlineDays: 5, notice: 'hi', latestVersion: '1', minVersion: '1', updateLink: '' });
    expect((await api.getAppControl()).offlineDays).toBe(5);
    await api.setNotes(r.uid, 'pays late');
    expect(await api.notes(r.uid)).toBe('pays late');
    await api.addAdmin({ uid: 'someone', perms: ['support'] });
    expect((await api.admins()).map(x => x.uid).sort()).toEqual([adminUid, 'someone'].sort());

    // every privileged change left an audit entry, stamped with the admin's email
    const log = await api.auditLog();
    const actions = log.map(e => e.action);
    for (const a of ['account.approve', 'account.update', 'phone.approve', 'phone.block', 'invoice.create', 'invoice.paid', 'account.status', 'support.delete', 'settings.app', 'admin.add']) {
      expect(actions).toContain(a);
    }
    expect(log.every(e => e.adminEmail === 'digitaltarget.digital@gmail.com')).toBe(true);
    expect(log.find(e => e.action === 'account.status')!.details).toMatchObject({ status: 'suspended', message: 'Please pay' });
    await expect(api.removeAdmin(adminUid)).rejects.toThrow(/yourself/);

    // plan prices round-trip through billing settings
    await api.setBilling({ ...(await api.getBilling()), planPrices: { monthly: 250000, yearly: 2400000 } });
    expect((await api.getBilling()).planPrices).toEqual({ monthly: 250000, yearly: 2400000 });

    // a second person cannot become admin by claiming
    const other = await restaurant('rest2', 'other@x.pk');
    await expect(setDoc(doc(other.db, 'admins', other.uid), { at: Timestamp.now() })).rejects.toThrow();
  }, 60000);

  it('admin permissions, audit clean-up and notifications work against the real security rules', async () => {
    const owner = createFirebaseApi(cfg, emu, 'owner2');
    // the project was claimed by the owner in the test above (same emulator data)
    await owner.signIn('digitaltarget.digital@gmail.com', 'secret123');
    const ownerUid = (await owner.admins()).find(a => a.owner)!.uid;
    const r = await restaurant('rest3', 'bistro@x.pk');
    await setDoc(doc(r.db, 'accounts', r.uid), { businessName: 'Bistro', ownerName: 'Sana', phone: '0301', city: 'Lahore', country: 'PK', email: 'bistro@x.pk', status: 'pending', phoneRequests: ['ph9'], createdAt: serverTimestamp(), appVersion: '0.4.0' });

    // an admin is created with a login in one step, and can only do what was ticked
    const newUid = await owner.addAdmin({ email: 'sara@dt.test', password: 'secret123', name: 'Sara', perms: ['support'] });
    const sara = createFirebaseApi(cfg, emu, 'sara');
    await sara.signIn('sara@dt.test', 'secret123');
    expect(await sara.isAdmin(newUid)).toBe(true);
    expect(await sara.myAccess(newUid)).toEqual({ owner: false, perms: ['support'] });
    await expect(sara.setStatus(r.uid, 'suspended', 'x')).rejects.toThrow();
    await expect(sara.sendNotice({ title: 'hi', body: '', kind: 'info', target: 'all' })).rejects.toThrow();
    await expect(sara.auditLog()).rejects.toThrow();
    await expect(sara.addAdmin({ uid: 'friend', perms: ['support'] })).rejects.toThrow();
    const list = await owner.admins();
    expect(list.find(a => a.uid === newUid)).toMatchObject({ email: 'sara@dt.test', name: 'Sara', perms: ['support'], owner: false });
    expect(list.find(a => a.uid === ownerUid)?.owner).toBe(true);

    // the owner gives more access and it works at once
    await owner.setAdminPerms(newUid, ['support', 'restaurants']);
    await owner.approve(r.uid, 'monthly', 100000, new Date(Date.now() + 86400000));
    await sara.setStatus(r.uid, 'suspended', 'late payment');
    expect((await owner.account(r.uid))?.status).toBe('suspended');
    await expect(owner.removeAdmin(ownerUid)).rejects.toThrow();

    // notifications: the restaurant reads what is for everyone and for it, nothing else
    await owner.sendNotice({ title: 'For all', body: 'a', kind: 'info', target: 'all' });
    await owner.sendNotice({ title: 'For Bistro', body: 'b', kind: 'payment', target: r.uid });
    await owner.sendNotice({ title: 'For someone else', body: 'c', kind: 'info', target: 'other-uid' });
    expect((await owner.notices()).map(n => n.title).sort()).toEqual(['For Bistro', 'For all', 'For someone else']);
    const mine = await getDocs(query(collection(r.db, 'notifications'), where('target', 'in', ['all', r.uid])));
    expect(mine.docs.map(d => d.data().title).sort()).toEqual(['For Bistro', 'For all']);
    await expect(getDocs(collection(r.db, 'notifications'))).rejects.toThrow();
    const toDelete = (await owner.notices()).find(n => n.title === 'For someone else')!;
    await owner.deleteNotice(toDelete.id);
    expect(await owner.notices()).toHaveLength(2);

    // audit log: delete chosen entries, and clean old ones (nothing is that old yet); both are recorded
    const before = await owner.auditLog();
    await owner.deleteAudit(before.slice(0, 2).map(e => e.id));
    expect(await owner.cleanAudit(1)).toBe(0);
    const after = await owner.auditLog();
    expect(after.map(e => e.action)).toEqual(expect.arrayContaining(['audit.delete', 'audit.clean']));
    expect(after.some(e => e.id === before[0].id)).toBe(false);
  });
});
