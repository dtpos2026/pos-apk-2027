import { useState } from 'react';
import type { Account, AdminApi } from './api';
import { PLANS, STATUS_LABEL, STATUSES, daysLeft, effectiveStatus, expiryFor, isOnline, money, parseMoneyToMinor, type PlanId, type Status } from './domain';
import { Badge, Err, ago, fmtDate, useAction, useLoad } from './ui';

export interface PageProps { api: AdminApi; go: (page: string, arg?: string) => void; arg?: string }

const tone = (s: Status) => ({ active: 'ok', pending: 'warn', payment_pending: 'warn', expired: 'bad', suspended: 'bad', blocked: 'bad', rejected: 'bad' }[s]);
export const StatusBadge = ({ a }: { a: Account }) => <Badge tone={tone(effectiveStatus(a.status, a.expiresAt, new Date()))}>{STATUS_LABEL[effectiveStatus(a.status, a.expiresAt, new Date())]}</Badge>;

export function Dashboard({ api, go }: PageProps) {
  const acc = useLoad(() => api.accounts(), [api]);
  const dev = useLoad(() => api.devices(), [api]);
  const inv = useLoad(() => api.invoices(), [api]);
  const now = new Date();
  const a = acc.data ?? [];
  const count = (f: (x: Account) => boolean) => a.filter(f).length;
  const eff = (x: Account) => effectiveStatus(x.status, x.expiresAt, now);
  const online = (dev.data ?? []).filter(d => isOnline(d.lastSeenAt, now));
  const today = now.toISOString().slice(0, 10);
  const salesToday = a.filter(x => x.todayAt && x.todayAt.toISOString().slice(0, 10) === today).reduce((s, x) => s + x.todayNetMinor, 0);
  const unpaid = (inv.data ?? []).filter(i => i.status === 'unpaid');
  const month = now.toISOString().slice(0, 7);
  const collected = (inv.data ?? []).filter(i => i.status === 'paid' && i.paidAt && i.paidAt.toISOString().slice(0, 7) === month).reduce((s, i) => s + i.amountMinor - i.discountMinor, 0);
  const tile = (n: string | number, label: string, page?: string) => (
    <button className="card stat" onClick={() => page && go(page)} key={label}><b>{n}</b><span>{label}</span></button>);
  return (<><h2>Dashboard</h2><Err text={acc.err || dev.err || inv.err} />
    <div className="grid">
      {tile(a.length, 'Total restaurants', 'Restaurants')}
      {tile(count(x => x.status === 'pending'), 'Waiting for approval', 'Restaurants')}
      {tile(a.reduce((s, x) => s + x.phoneRequests.length, 0), 'New phone requests', 'Restaurants')}
      {tile(count(x => eff(x) === 'active'), 'Active')}
      {tile(count(x => x.status === 'payment_pending'), 'Payment pending')}
      {tile(count(x => eff(x) === 'expired'), 'Expired')}
      {tile(count(x => { const d = daysLeft(x.expiresAt, now); return eff(x) === 'active' && d !== null && d <= 7; }), 'Expiring in 7 days', 'Reminders')}
      {tile(count(x => x.status === 'suspended' || x.status === 'blocked'), 'Suspended / blocked')}
      {tile((salesToday / 100).toLocaleString(), 'Sales reported today (all restaurants)')}
      {tile(online.length, 'Phones online now', 'Phones')}
      {tile((dev.data ?? []).length - online.length, 'Phones offline', 'Phones')}
      {tile(unpaid.length, 'Unpaid invoices', 'Invoices')}
      {tile((collected / 100).toLocaleString(), 'Collected this month')}
      {tile((unpaid.reduce((s, i) => s + i.amountMinor - i.discountMinor, 0) / 100).toLocaleString(), 'Outstanding')}
    </div>
    <h3>Sales by restaurant</h3>
    <table><thead><tr><th>Restaurant</th><th>Last report</th><th>Net sales (that day)</th><th>App</th></tr></thead><tbody>
      {a.filter(x => x.todayAt).sort((x, y) => y.todayNetMinor - x.todayNetMinor).map(x => <tr key={x.uid}><td><a onClick={() => go('Restaurant', x.uid)}>{x.businessName}</a></td><td>{ago(x.todayAt)}</td><td>{money(x.todayNetMinor, x.currency)}</td><td>{x.appVersion}</td></tr>)}
    </tbody></table>{a.length > 0 && !a.some(x => x.todayAt) && <p>No restaurant has reported sales yet.</p>}
  </>);
}

export function Restaurants({ api, go }: PageProps) {
  const { data, err } = useLoad(() => api.accounts(), [api]);
  const [q, setQ] = useState(''); const [filter, setFilter] = useState('all');
  const now = new Date();
  const rows = (data ?? []).filter(a => {
    const t = q.trim().toLowerCase();
    const hit = !t || [a.businessName, a.ownerName, a.email, a.phone, a.customerId, a.licenseId].some(v => (v ?? '').toLowerCase().includes(t));
    const st = effectiveStatus(a.status, a.expiresAt, now);
    const f = filter === 'all' || filter === st || (filter === 'newphone' && a.phoneRequests.length > 0 && a.status !== 'pending');
    return hit && f;
  });
  return (<><h2>Restaurants</h2><Err text={err} />
    <div className="row">
      <input aria-label="Search" placeholder="Search name, email, phone, Customer ID, License ID" style={{ width: 380 }} value={q} onChange={e => setQ(e.target.value)} />
      <select aria-label="Filter" value={filter} onChange={e => setFilter(e.target.value)}>
        <option value="all">All</option>{STATUSES.map(s => <option key={s} value={s}>{STATUS_LABEL[s]}</option>)}<option value="newphone">New phone requests</option>
      </select></div>
    <table><thead><tr><th>Restaurant</th><th>Owner</th><th>Phone</th><th>Status</th><th>Plan</th><th>Expires</th><th>Customer ID</th><th>Last sales</th></tr></thead><tbody>
      {rows.map(a => <tr key={a.uid} className="click" onClick={() => go('Restaurant', a.uid)}>
        <td>{a.businessName}{a.phoneRequests.length > 0 && a.status !== 'pending' && <Badge tone="warn">new phone</Badge>}</td><td>{a.ownerName}</td><td>{a.phone}</td><td><StatusBadge a={a} /></td>
        <td>{a.plan ?? '—'}</td><td>{a.plan === 'lifetime' ? 'never' : fmtDate(a.expiresAt)}</td><td>{a.customerId ?? '—'}</td><td>{a.todayAt ? money(a.todayNetMinor, a.currency) : '—'}</td></tr>)}
    </tbody></table>{data && rows.length === 0 && <p>No restaurants match.</p>}</>);
}

export function RestaurantPage({ api, go, arg }: PageProps) {
  const uid = arg ?? '';
  const acc = useLoad(() => api.account(uid), [api, uid]);
  const notes = useLoad(() => api.notes(uid), [api, uid]);
  const days = useLoad(() => api.days(uid), [api, uid]);
  const devs = useLoad(() => api.devices(), [api]);
  const act = useAction(() => { acc.reload(); });
  const [plan, setPlan] = useState<PlanId>('monthly'); const [fee, setFee] = useState(''); const [custom, setCustom] = useState('');
  const [msgText, setMsgText] = useState(''); const [note, setNote] = useState<string | null>(null);
  const [maxPhones, setMaxPhones] = useState('');
  const a = acc.data;
  if (acc.err) return <Err text={acc.err} />;
  if (!a) return <p>Loading…</p>;
  const now = new Date();
  const mine = (devs.data ?? []).filter(d => d.uid === uid);
  const sum = (n: number) => (days.data ?? []).slice(0, n).reduce((s, d) => s + d.netMinor, 0);
  const today = now.toISOString().slice(0, 10), yday = new Date(now.getTime() - 86400000).toISOString().slice(0, 10);
  const dayNet = (d: string) => (days.data ?? []).find(x => x.date === d)?.netMinor ?? 0;
  const approve = () => act.run(async () => {
    const exp = expiryFor(plan, now, null, custom ? new Date(custom + 'T23:59:59') : undefined);
    await api.approve(uid, plan, fee ? parseMoneyToMinor(fee) : 0, exp);
  });
  const setStatus = (s: Status, needMsg: boolean) => act.run(async () => {
    if (needMsg && !msgText.trim()) throw new Error('Write a message the restaurant will see in the app');
    await api.setStatus(uid, s, msgText.trim()); setMsgText('');
  });
  return (<>
    <p><a onClick={() => go('Restaurants')}>← Restaurants</a></p>
    <h2>{a.businessName} <StatusBadge a={a} /></h2><Err text={act.err} />
    <div className="grid2">
      <div className="card"><h3>Details</h3>
        <p>Owner: <b>{a.ownerName}</b><br />Phone: {a.phone}<br />Email: {a.email}<br />City: {a.city}, {a.country}<br />Registered: {fmtDate(a.createdAt)}<br />App version: {a.appVersion || '—'}</p>
        <p>Customer ID: <b>{a.customerId ?? '—'}</b><br />Business ID: {a.businessId ?? '—'}<br />License ID: {a.licenseId ?? '—'}<br />
          Plan: {a.plan ?? '—'} · Fee: {a.feeMinor ? money(a.feeMinor, a.currency) : '—'}<br />Expires: {a.plan === 'lifetime' ? 'never' : fmtDate(a.expiresAt)}{a.expiresAt && ` (${daysLeft(a.expiresAt, now)} days)`}</p>
        {a.adminMessage && <p>Message shown in app: <i>{a.adminMessage}</i></p>}
      </div>
      <div className="card"><h3>Sales</h3>
        <p>Today: <b>{money(dayNet(today), a.currency)}</b><br />Yesterday: {money(dayNet(yday), a.currency)}<br />Last 30 reported days: {money(sum(30), a.currency)}</p>
        {(days.data ?? []).length === 0 && <small>No sales reported yet.</small>}
      </div>
    </div>
    {a.status === 'pending' ? (
      <div className="card"><h3>Approve this restaurant</h3><div className="row">
        <select aria-label="Plan" value={plan} onChange={e => setPlan(e.target.value as PlanId)}>{PLANS.map(p => <option key={p.id} value={p.id}>{p.label}</option>)}</select>
        {plan === 'custom' && <input aria-label="Custom date" type="date" value={custom} onChange={e => setCustom(e.target.value)} />}
        <input aria-label="Fee" placeholder={`Fee (${a.currency})`} value={fee} onChange={e => setFee(e.target.value)} />
        <button className="act" disabled={act.busy} onClick={approve}>Approve</button>
      </div><div className="row"><input aria-label="Message" placeholder="Reason (required to reject)" style={{ width: 360 }} value={msgText} onChange={e => setMsgText(e.target.value)} />
        <button className="act danger" onClick={() => setStatus('rejected', true)}>Reject</button></div></div>
    ) : (
      <div className="card"><h3>Status</h3>
        <div className="row"><input aria-label="Message" placeholder="Message shown in the app (required to suspend, block or set payment pending)" style={{ width: 460 }} value={msgText} onChange={e => setMsgText(e.target.value)} /></div>
        <div className="row">
          <button className="act" onClick={() => setStatus('active', false)}>Active</button>
          <button className="act sec" onClick={() => setStatus('payment_pending', true)}>Payment pending</button>
          <button className="act danger" onClick={() => setStatus('suspended', true)}>Suspend</button>
          <button className="act danger" onClick={() => setStatus('blocked', true)}>Block</button>
          <button className="act sec" onClick={() => setStatus('expired', false)}>Expire</button>
          <button className="act sec" onClick={() => go('Invoices', uid)}>+ Invoice</button>
        </div>
        <div className="row"><select aria-label="Renew plan" value={plan} onChange={e => setPlan(e.target.value as PlanId)}>{PLANS.map(p => <option key={p.id} value={p.id}>{p.label}</option>)}</select>
          {plan === 'custom' && <input aria-label="Custom date" type="date" value={custom} onChange={e => setCustom(e.target.value)} />}
          <button className="act sec" onClick={() => act.run(async () => { const e = expiryFor(plan, now, a.expiresAt, custom ? new Date(custom + 'T23:59:59') : undefined); await api.patchAccount(uid, { plan, expiresAt: e, status: 'active', adminMessage: '' }); })}>Set plan / extend</button></div>
      </div>)}
    <div className="card"><h3>Phones</h3>
      <div className="row">Phone limit: <input aria-label="Phone limit" style={{ width: 60 }} value={maxPhones || String(a.maxPhones)} onChange={e => setMaxPhones(e.target.value)} />
        <button className="act sec" onClick={() => act.run(async () => { const n = Number(maxPhones); if (!Number.isInteger(n) || n < 1 || n > 20) throw new Error('Limit must be 1 to 20'); await api.patchAccount(uid, { maxPhones: n }); setMaxPhones(''); })}>Save</button></div>
      <table><tbody>
        {a.approvedPhones.map(p => { const d = mine.find(x => x.phoneId === p); const blocked = a.blockedPhones.includes(p); return (
          <tr key={p}><td>{d?.model ?? p.slice(0, 8)}</td><td>{d ? `Android ${d.android} · app ${d.appVersion}` : ''}</td><td>{d ? ago(d.lastSeenAt) : ''}</td><td><Badge tone={blocked ? 'bad' : 'ok'}>{blocked ? 'blocked' : 'approved'}</Badge></td>
            <td><button className="act sec" onClick={() => act.run(() => api.setDeviceBlocked(uid, p, !blocked))}>{blocked ? 'Unblock' : 'Block'}</button> <button className="act danger" onClick={() => act.run(() => api.removePhone(uid, p))}>Remove</button></td></tr>); })}
        {a.phoneRequests.map(p => { const d = mine.find(x => x.phoneId === p); return (
          <tr key={p}><td>{d?.model ?? p.slice(0, 8)}</td><td>{d ? `Android ${d.android}` : ''}</td><td /><td><Badge tone="warn">needs approval</Badge></td>
            <td><button className="act" onClick={() => act.run(() => api.approvePhone(uid, p))}>Approve this phone</button> <button className="act danger" onClick={() => act.run(() => api.removePhone(uid, p))}>Reject</button></td></tr>); })}
      </tbody></table>{a.approvedPhones.length + a.phoneRequests.length === 0 && <small>No phones yet.</small>}
    </div>
    <div className="card"><h3>Private notes</h3>
      <textarea aria-label="Notes" rows={3} style={{ width: '100%' }} value={note ?? notes.data ?? ''} onChange={e => setNote(e.target.value)} />
      <button className="act" disabled={note === null} onClick={() => act.run(async () => { await api.setNotes(uid, note ?? ''); setNote(null); notes.reload(); })}>Save notes</button></div>
  </>);
}
