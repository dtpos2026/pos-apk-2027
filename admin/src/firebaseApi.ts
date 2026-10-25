import { deleteApp, initializeApp } from 'firebase/app';
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, onAuthStateChanged, sendPasswordResetEmail, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import {
  Timestamp, arrayRemove, arrayUnion, collection, connectFirestoreEmulator, deleteDoc, doc, getDoc, getDocs, getFirestore, orderBy, query, runTransaction, serverTimestamp,
  limit, setDoc, updateDoc, where, writeBatch, type DocumentData, type Firestore, type Transaction, type WriteBatch,
} from 'firebase/firestore';
import type {
  Account, AccountPatch, AdminApi, AdminUser, AppControl, AuditEntry, Billing, Branding, DayTotal, Device, Invoice, Message, Notice, Thread,
} from './api';
import type { FirebaseWebConfig } from './config';
import { customerId, expiryFor, invoiceNumber, type PlanId, type Status } from './domain';

const date = (v: unknown): Date | null => (v instanceof Timestamp ? v.toDate() : v instanceof Date ? v : null);
const str = (v: unknown, d = '') => (typeof v === 'string' ? v : d);
const num = (v: unknown, d = 0) => (typeof v === 'number' ? v : d);
const arr = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);
const rid = () => Array.from(crypto.getRandomValues(new Uint8Array(8)), b => b.toString(16).padStart(2, '0')).join('');

function toAccount(uid: string, d: DocumentData, stats?: DocumentData): Account {
  return {
    uid, businessName: str(d.businessName), ownerName: str(d.ownerName), phone: str(d.phone), city: str(d.city), country: str(d.country, 'PK'),
    email: str(d.email), status: str(d.status, 'pending') as Status, plan: (d.plan ?? null) as PlanId | null, feeMinor: num(d.feeMinor),
    currency: str(d.currency, d.country === 'AE' ? 'AED' : 'PKR'), expiresAt: date(d.expiresAt), customerId: d.customerId ?? null,
    businessId: d.businessId ?? null, licenseId: d.licenseId ?? null, approvedPhones: arr(d.approvedPhones), phoneRequests: arr(d.phoneRequests).filter(p => !arr(d.approvedPhones).includes(p)),
    blockedPhones: arr(d.blockedPhones), maxPhones: num(d.maxPhones, 1), disabledModules: arr(d.disabledModules), themeId: str(d.themeId), themeLocked: d.themeLocked === true, adminMessage: str(d.adminMessage), createdAt: date(d.createdAt),
    appVersion: str(d.appVersion), todayNetMinor: num(stats?.todayNetMinor), todayAt: date(stats?.updatedAt), logo: str(d.logo) || undefined,
    pinResetPending: d.pinReset != null, pinResetDoneAt: date((d.pinResetDone as DocumentData | undefined)?.at),
  };
}
function toInvoice(id: string, d: DocumentData): Invoice {
  return {
    id, accountUid: str(d.accountUid), number: str(d.number), businessName: str(d.businessName), amountMinor: num(d.amountMinor), discountMinor: num(d.discountMinor),
    currency: str(d.currency, 'PKR'), issuedAt: date(d.issuedAt) ?? new Date(0), dueAt: date(d.dueAt) ?? new Date(0), status: d.status ?? 'unpaid',
    plan: d.plan ?? null, verifyToken: str(d.verifyToken), paidAt: date(d.paidAt),
  };
}

export function createFirebaseApi(cfg: FirebaseWebConfig, emulator?: { host: string; authPort: number; firestorePort: number }, appName?: string): AdminApi & { _register?: (e: string, p: string) => Promise<string> } {
  const app = initializeApp(cfg, appName);
  const auth = getAuth(app);
  const db: Firestore = getFirestore(app);
  if (emulator) { connectAuthEmulator(auth, `http://${emulator.host}:${emulator.authPort}`, { disableWarnings: true }); connectFirestoreEmulator(db, emulator.host, emulator.firestorePort); }
  const cfgDoc = async <T,>(name: string, defaults: T): Promise<T> => ({ ...defaults, ...((await getDoc(doc(db, 'config', name))).data() as Partial<T> | undefined) });
  // Every privileged change is written together with an audit entry, in the same batch or transaction.
  const auditEntry = (action: string, accountUid: string | null, details: DocumentData = {}) => ({
    at: serverTimestamp(), adminUid: auth.currentUser?.uid ?? '', adminEmail: auth.currentUser?.email ?? '', action, accountUid, details,
  });
  const audited = async (action: string, accountUid: string | null, details: DocumentData, fill: (b: WriteBatch) => void) => {
    const b = writeBatch(db);
    fill(b);
    b.set(doc(collection(db, 'auditLog')), auditEntry(action, accountUid, details));
    await b.commit();
  };
  const auditTx = (tx: Transaction, action: string, accountUid: string | null, details: DocumentData = {}) => tx.set(doc(collection(db, 'auditLog')), auditEntry(action, accountUid, details));
  const nextCounter = (name: string) => runTransaction(db, async tx => {
    const ref = doc(db, 'counters', name);
    const n = num((await tx.get(ref)).data()?.next, 1);
    tx.set(ref, { next: n + 1 });
    return n;
  });

  return {
    async _register(e: string, p: string) { return (await createUserWithEmailAndPassword(auth, e, p)).user.uid; },
    onAuth(cb) { return onAuthStateChanged(auth, u => cb(u ? { uid: u.uid, email: u.email ?? '' } : null)); },
    async signIn(email, password) { await signInWithEmailAndPassword(auth, email, password); },
    async signOut() { await signOut(auth); },
    async resetPassword(email) { await sendPasswordResetEmail(auth, email); },
    async isAdmin(uid) { return (await getDoc(doc(db, 'admins', uid))).exists(); },
    async ownerClaimed() { return (await getDoc(doc(db, 'config', 'owner'))).exists(); },
    async claimSuperAdmin(uid) {
      const b = writeBatch(db);
      b.set(doc(db, 'config', 'owner'), { uid, at: serverTimestamp() });
      b.set(doc(db, 'admins', uid), { at: serverTimestamp() });
      await b.commit();
    },

    async accounts() {
      const [acc, stats] = await Promise.all([getDocs(collection(db, 'accounts')), getDocs(collection(db, 'stats'))]);
      const st = new Map(stats.docs.map(d => [d.id, d.data()]));
      return acc.docs.map(d => toAccount(d.id, d.data(), st.get(d.id))).sort((a, b) => (b.createdAt?.getTime() ?? 0) - (a.createdAt?.getTime() ?? 0));
    },
    async account(uid) {
      const s = await getDoc(doc(db, 'accounts', uid));
      if (!s.exists()) return null;
      return toAccount(uid, s.data(), (await getDoc(doc(db, 'stats', uid))).data());
    },
    async approve(uid, plan, feeMinor, expiresAt) {
      const n = await nextCounter('customer');
      await runTransaction(db, async tx => {
        const ref = doc(db, 'accounts', uid);
        const s = await tx.get(ref);
        if (!s.exists()) throw new Error('Account not found');
        const a = toAccount(uid, s.data());
        if (a.status !== 'pending') throw new Error('Only a pending registration can be approved');
        const maxPhones = a.maxPhones || 1;
        tx.update(ref, {
          status: 'active', plan, feeMinor, expiresAt: expiresAt ? Timestamp.fromDate(expiresAt) : null, customerId: customerId(n), businessId: 'DTB-' + rid(),
          licenseId: 'DTL-' + rid(), maxPhones, approvedPhones: a.phoneRequests.slice(0, maxPhones), phoneRequests: a.phoneRequests.slice(maxPhones),
          adminMessage: '', approvedAt: serverTimestamp(),
        });
        auditTx(tx, 'account.approve', uid, { plan, feeMinor, expiresAt: expiresAt ? expiresAt.toISOString() : null, customerId: customerId(n) });
      });
    },
    async patchAccount(uid, patch: AccountPatch) {
      const data: DocumentData = { ...patch };
      if ('expiresAt' in patch) data.expiresAt = patch.expiresAt ? Timestamp.fromDate(patch.expiresAt) : null;
      const details: DocumentData = { ...patch };
      if ('expiresAt' in patch) details.expiresAt = patch.expiresAt ? patch.expiresAt.toISOString() : null;
      await audited('account.update', uid, details, b => b.update(doc(db, 'accounts', uid), data));
    },
    async resetOwnerPin(uid, pin) {
      if (!/^\d{4,8}$/.test(pin)) throw new Error('The PIN must be 4 to 8 digits');
      // The PIN lives on the restaurant's own account document only until its app applies it and deletes it; the audit entry never holds it.
      await audited('account.pinreset', uid, {}, b => b.update(doc(db, 'accounts', uid), { pinReset: { pin, id: rid(), at: serverTimestamp() } }));
    },
    async setStatus(uid, status, message) { await audited('account.status', uid, { status, message }, b => b.update(doc(db, 'accounts', uid), { status, adminMessage: message })); },
    async approvePhone(uid, phoneId) {
      await runTransaction(db, async tx => {
        const ref = doc(db, 'accounts', uid);
        const a = toAccount(uid, (await tx.get(ref)).data() ?? {});
        if (a.approvedPhones.includes(phoneId)) return;
        if (a.approvedPhones.length >= a.maxPhones) throw new Error(`This account allows ${a.maxPhones} phone(s). Raise the phone limit or remove a phone first.`);
        tx.update(ref, { approvedPhones: arrayUnion(phoneId), phoneRequests: arrayRemove(phoneId) });
        auditTx(tx, 'phone.approve', uid, { phoneId });
      });
    },
    async removePhone(uid, phoneId) { await audited('phone.remove', uid, { phoneId }, b => b.update(doc(db, 'accounts', uid), { approvedPhones: arrayRemove(phoneId), phoneRequests: arrayRemove(phoneId) })); },
    async notes(uid) { return str((await getDoc(doc(db, 'adminNotes', uid))).data()?.text); },
    async setNotes(uid, text) { await setDoc(doc(db, 'adminNotes', uid), { text, at: serverTimestamp() }); },
    async days(uid): Promise<DayTotal[]> {
      const s = await getDocs(query(collection(db, 'stats', uid, 'days'), orderBy('date', 'desc')));
      return s.docs.slice(0, 60).map(d => ({ date: str(d.data().date), netMinor: num(d.data().netMinor), bills: num(d.data().bills), customers: num(d.data().customers) }));
    },

    async devices(): Promise<Device[]> {
      const s = await getDocs(collection(db, 'devices'));
      return s.docs.map(d => { const x = d.data(); return {
        id: d.id, uid: str(x.uid), phoneId: str(x.phoneId), model: str(x.model), android: str(x.android), appVersion: str(x.appVersion), lastSeenAt: date(x.lastSeenAt),
        locationAllowed: x.locationAllowed === true, lat: x.lat, lng: x.lng, accuracyM: x.accuracyM, locationAt: date(x.locationAt),
      }; });
    },
    async setDeviceBlocked(uid, phoneId, blocked) {
      await audited(blocked ? 'phone.block' : 'phone.unblock', uid, { phoneId }, b => b.update(doc(db, 'accounts', uid), { blockedPhones: blocked ? arrayUnion(phoneId) : arrayRemove(phoneId) }));
    },
    async deleteDevice(id) { await audited('device.delete', id.split('__')[0] || null, { device: id }, b => b.delete(doc(db, 'devices', id))); },

    async invoices() {
      const s = await getDocs(query(collection(db, 'invoices'), orderBy('issuedAt', 'desc')));
      return s.docs.map(d => toInvoice(d.id, d.data()));
    },
    async invoice(id) { const s = await getDoc(doc(db, 'invoices', id)); return s.exists() ? toInvoice(id, s.data()) : null; },
    async createInvoice(uid, amountMinor, discountMinor, dueAt, plan) {
      if (discountMinor > amountMinor) throw new Error('Discount is more than the amount');
      const acc = await this.account(uid);
      if (!acc) throw new Error('Account not found');
      const n = await nextCounter('invoice');
      const now = new Date();
      const number = invoiceNumber(now, n);
      const token = rid() + rid();
      const ref = doc(collection(db, 'invoices'));
      const base = { accountUid: uid, number, businessName: acc.businessName, amountMinor, discountMinor, currency: acc.currency, status: 'unpaid', plan, verifyToken: token };
      const b = writeBatch(db);
      b.set(ref, { ...base, issuedAt: Timestamp.fromDate(now), dueAt: Timestamp.fromDate(dueAt) });
      b.set(doc(db, 'invoiceVerify', token), { number, businessName: acc.businessName, amountMinor: amountMinor - discountMinor, currency: acc.currency, status: 'unpaid', issuedAt: Timestamp.fromDate(now) });
      b.set(doc(collection(db, 'auditLog')), auditEntry('invoice.create', uid, { number, amountMinor, discountMinor }));
      await b.commit();
      return toInvoice(ref.id, { ...base, issuedAt: Timestamp.fromDate(now), dueAt: Timestamp.fromDate(dueAt) });
    },
    async recordPayment(invoiceId) {
      await runTransaction(db, async tx => {
        const iref = doc(db, 'invoices', invoiceId);
        const inv = toInvoice(invoiceId, (await tx.get(iref)).data() ?? {});
        if (inv.status !== 'unpaid') throw new Error('This invoice is not waiting for payment');
        const aref = doc(db, 'accounts', inv.accountUid);
        const acc = toAccount(inv.accountUid, (await tx.get(aref)).data() ?? {});
        const now = new Date();
        tx.update(iref, { status: 'paid', paidAt: serverTimestamp() });
        auditTx(tx, 'invoice.paid', inv.accountUid, { number: inv.number, amountMinor: inv.amountMinor - inv.discountMinor });
        tx.update(doc(db, 'invoiceVerify', inv.verifyToken), { status: 'paid' });
        const plan = inv.plan ?? acc.plan;
        if (plan && plan !== 'custom') {
          const exp = expiryFor(plan, now, acc.expiresAt);
          tx.update(aref, { status: acc.status === 'pending' || acc.status === 'rejected' || acc.status === 'blocked' ? acc.status : 'active', expiresAt: exp ? Timestamp.fromDate(exp) : null, plan, adminMessage: '' });
        }
      });
    },
    async voidInvoice(invoiceId) {
      const iref = doc(db, 'invoices', invoiceId);
      const inv = toInvoice(invoiceId, (await getDoc(iref)).data() ?? {});
      if (inv.status === 'paid') throw new Error('A paid invoice cannot be voided');
      const b = writeBatch(db);
      b.update(iref, { status: 'void' });
      b.update(doc(db, 'invoiceVerify', inv.verifyToken), { status: 'void' });
      b.set(doc(collection(db, 'auditLog')), auditEntry('invoice.void', inv.accountUid, { number: inv.number }));
      await b.commit();
    },
    async verifyInvoice(token) {
      const s = await getDoc(doc(db, 'invoiceVerify', token));
      if (!s.exists()) return null;
      const d = s.data();
      return { number: str(d.number), businessName: str(d.businessName), amountMinor: num(d.amountMinor), currency: str(d.currency), status: str(d.status), issuedAt: date(d.issuedAt) ?? new Date(0) };
    },

    async threads(): Promise<Thread[]> {
      const s = await getDocs(collection(db, 'support'));
      return s.docs.map(d => ({ uid: d.id, businessName: str(d.data().businessName), lastMessage: str(d.data().lastMessage), lastAt: date(d.data().lastAt), unreadForAdmin: d.data().unreadForAdmin === true }))
        .sort((a, b) => (b.lastAt?.getTime() ?? 0) - (a.lastAt?.getTime() ?? 0));
    },
    async messages(uid): Promise<Message[]> {
      const s = await getDocs(query(collection(db, 'support', uid, 'messages'), orderBy('at')));
      return s.docs.map(d => ({ id: d.id, sender: d.data().sender === 'admin' ? 'admin' : 'business', text: str(d.data().text), at: date(d.data().at) }));
    },
    async sendMessage(uid, text) {
      const b = writeBatch(db);
      b.set(doc(collection(db, 'support', uid, 'messages')), { sender: 'admin', text, at: serverTimestamp() });
      b.set(doc(db, 'support', uid), { lastMessage: text, lastAt: serverTimestamp(), unreadForAdmin: false }, { merge: true });
      await b.commit();
    },
    async markRead(uid) { await setDoc(doc(db, 'support', uid), { unreadForAdmin: false }, { merge: true }); },
    async clearChat(uid) {
      const s = await getDocs(collection(db, 'support', uid, 'messages'));
      for (let i = 0; i < s.docs.length; i += 400) { const b = writeBatch(db); s.docs.slice(i, i + 400).forEach(d => b.delete(d.ref)); await b.commit(); }
      await setDoc(doc(db, 'support', uid), { lastMessage: '', unreadForAdmin: false }, { merge: true });
    },
    async deleteChat(uid) { await this.clearChat(uid); await audited('support.delete', uid, {}, b => b.delete(doc(db, 'support', uid))); },

    getBranding: () => cfgDoc<Branding>('branding', { appName: 'DT Food POS', contact: '', whatsapp: '', email: '', supportMessage: '' }),
    setBranding: v => audited('settings.branding', null, {}, b => b.set(doc(db, 'config', 'branding'), v)),
    getAppControl: () => cfgDoc<AppControl>('app', { offlineDays: 7, notice: '', latestVersion: '', minVersion: '', updateLink: '' }),
    setAppControl: v => audited('settings.app', null, { ...v }, b => b.set(doc(db, 'config', 'app'), v)),
    getBilling: () => cfgDoc<Billing>('billing', { company: '', address: '', bank: '', accountTitle: '', accountNo: '', terms: '', paymentQr: '', signature: '', reminderTemplate: 'Assalam o Alaikum {owner}, your DT Food POS subscription for {business} (ID {customerId}) needs attention. Amount due: {amount}. Expiry: {expiry}. Thank you.', planPrices: {} }),
    setBilling: v => audited('settings.billing', null, {}, b => b.set(doc(db, 'config', 'billing'), v)),

    async admins(): Promise<AdminUser[]> {
      const owner = (await getDoc(doc(db, 'config', 'owner'))).data()?.uid;
      return (await getDocs(collection(db, 'admins'))).docs.map(d => ({ uid: d.id, email: str(d.data().email), name: str(d.data().name), perms: Array.isArray(d.data().perms) ? arr(d.data().perms) : null, owner: d.id === owner }));
    },
    async addAdmin(a) {
      let id = (a.uid ?? '').trim();
      const email = (a.email ?? '').trim();
      if (!id) {
        if (!email || !(a.password ?? '')) throw new Error('Enter a UID, or an email and a password to create the login');
        if ((a.password ?? '').length < 6) throw new Error('The password needs at least 6 characters');
        // a second app instance, so creating the login does not sign this admin out
        const second = initializeApp(cfg, `dt-new-admin-${rid()}`);
        try {
          const sa = getAuth(second);
          if (emulator) connectAuthEmulator(sa, `http://${emulator.host}:${emulator.authPort}`, { disableWarnings: true });
          id = (await createUserWithEmailAndPassword(sa, email, a.password!)).user.uid;
          await signOut(sa);
        } finally {
          await deleteApp(second);
        }
      }
      const perms = [...a.perms];
      await audited('admin.add', null, { uid: id, email, perms }, b => b.set(doc(db, 'admins', id), { at: serverTimestamp(), email, name: (a.name ?? '').trim(), perms }));
      return id;
    },
    async setAdminPerms(uid, perms) { await audited('admin.perms', null, { uid, perms }, b => b.update(doc(db, 'admins', uid), { perms })); },
    async removeAdmin(uid) {
      if (uid === auth.currentUser?.uid) throw new Error('You cannot remove yourself');
      if ((await getDoc(doc(db, 'config', 'owner'))).data()?.uid === uid) throw new Error('The owner cannot be removed');
      await audited('admin.remove', null, { uid }, b => b.delete(doc(db, 'admins', uid)));
    },
    async myAccess(uid) {
      const owner = (await getDoc(doc(db, 'config', 'owner'))).data()?.uid === uid;
      const d = (await getDoc(doc(db, 'admins', uid))).data();
      return { owner, perms: owner || !Array.isArray(d?.perms) ? null : arr(d?.perms) };
    },
    async deleteAudit(ids) {
      for (let i = 0; i < ids.length; i += 400) {
        const b = writeBatch(db);
        ids.slice(i, i + 400).forEach(id => b.delete(doc(db, 'auditLog', id)));
        await b.commit();
      }
      await setDoc(doc(collection(db, 'auditLog')), auditEntry('audit.delete', null, { count: ids.length }));
    },
    async cleanAudit(days) {
      if (!(days >= 1)) throw new Error('Choose at least 1 day');
      const cutoff = Timestamp.fromDate(new Date(Date.now() - days * 86400000));
      let total = 0;
      for (;;) {
        const s = await getDocs(query(collection(db, 'auditLog'), where('at', '<', cutoff), orderBy('at'), limit(400)));
        if (s.empty) break;
        const b = writeBatch(db);
        s.docs.forEach(d => b.delete(d.ref));
        await b.commit();
        total += s.size;
      }
      await setDoc(doc(collection(db, 'auditLog')), auditEntry('audit.clean', null, { olderThanDays: days, count: total }));
      return total;
    },
    async notices(): Promise<Notice[]> {
      const s = await getDocs(query(collection(db, 'notifications'), orderBy('createdAt', 'desc'), limit(200)));
      return s.docs.map(d => ({ id: d.id, title: str(d.data().title), body: str(d.data().body), kind: str(d.data().kind, 'info'), target: str(d.data().target, 'all'), createdAt: date(d.data().createdAt) }));
    },
    async sendNotice(n) {
      if (!n.title.trim()) throw new Error('Write a title');
      await audited('notice.send', n.target === 'all' ? null : n.target, { title: n.title.trim(), kind: n.kind }, b => b.set(doc(collection(db, 'notifications')), { title: n.title.trim(), body: n.body.trim(), kind: n.kind, target: n.target, createdAt: serverTimestamp(), createdBy: auth.currentUser?.uid ?? '' }));
    },
    async deleteNotice(id) { await audited('notice.delete', null, { id }, b => b.delete(doc(db, 'notifications', id))); },
    async auditLog(): Promise<AuditEntry[]> {
      const s = await getDocs(query(collection(db, 'auditLog'), orderBy('at', 'desc'), limit(500)));
      return s.docs.map(d => ({ id: d.id, at: date(d.data().at), adminEmail: str(d.data().adminEmail), action: str(d.data().action), accountUid: d.data().accountUid ?? null, details: (d.data().details ?? {}) as Record<string, unknown> }));
    },
  };
}
