import { useEffect, useState } from 'react';
import type { Account, AdminApi } from './api';
import { APP_MODULES, APP_THEMES, customThemeId, parseCustomTheme, PLANS, STATUS_LABEL, STATUSES, daysLeft, effectiveStatus, expiryFor, isOnline, localDate, money, parseMoneyToMinor, sumByCurrency, type PlanId, type Status } from './domain';
import { Badge, Err, ago, fmtDate, useAction, useLoad, usePaged } from './ui';

export interface PageProps { api: AdminApi; go: (page: string, arg?: string) => void; arg?: string }

const tone = (s: Status) => ({ active: 'ok', pending: 'warn', payment_pending: 'warn', expired: 'bad', suspended: 'bad', blocked: 'bad', rejected: 'bad' }[s]);
export const isToday = (d: Date | null, now = new Date()) => !!d && d.toDateString() === now.toDateString();
/** Today's reported sales, or a clear "stale" note when the last report is from an earlier day. */
export function SalesCell({ a }: { a: Account }) {
  if (!a.todayAt) return <span className="mut">no report yet</span>;
  if (!isToday(a.todayAt)) return <span className="mut">last report {ago(a.todayAt)}</span>;
  return <>{money(a.todayNetMinor, a.currency)}</>;
}
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
  const reportingToday = a.filter(x => isToday(x.todayAt, now));
  const salesToday = sumByCurrency(reportingToday.map(x => ({ minor: x.todayNetMinor, currency: x.currency })));
  const unpaid = (inv.data ?? []).filter(i => i.status === 'unpaid');
  const month = localDate(now).slice(0, 7);
  const collected = sumByCurrency((inv.data ?? []).filter(i => i.status === 'paid' && i.paidAt && localDate(i.paidAt).slice(0, 7) === month).map(i => ({ minor: i.amountMinor - i.discountMinor, currency: i.currency })));
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
      {tile(salesToday, `Sales reported today (${reportingToday.length} of ${count(x => eff(x) === 'active')} active restaurants reported)`)}
      {tile(online.length, 'Phones online now', 'Phones')}
      {tile((dev.data ?? []).length - online.length, 'Phones offline', 'Phones')}
      {tile(unpaid.length, 'Unpaid invoices', 'Invoices')}
      {tile(collected, 'Collected this month')}
      {tile(sumByCurrency(unpaid.map(i => ({ minor: i.amountMinor - i.discountMinor, currency: i.currency }))), 'Outstanding')}
    </div>
    <h3>Sales by restaurant</h3>
    <table><thead><tr><th>Restaurant</th><th>Last report</th><th>Net sales (that day)</th><th>App</th></tr></thead><tbody>
      {a.filter(x => x.todayAt).sort((x, y) => y.todayNetMinor - x.todayNetMinor).map(x => <tr key={x.uid}><td><a onClick={() => go('Restaurant', x.uid)}>{x.businessName}</a></td><td>{ago(x.todayAt)} {!isToday(x.todayAt) && <Badge tone="warn">not today</Badge>}</td><td>{isToday(x.todayAt) ? money(x.todayNetMinor, x.currency) : '—'}</td><td>{x.appVersion}</td></tr>)}
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
  const paged = usePaged(rows);
  return (<><h2>Restaurants</h2><Err text={err} />
    <div className="row">
      <input aria-label="Search" placeholder="Search name, email, phone, Customer ID, License ID" style={{ width: 380 }} value={q} onChange={e => setQ(e.target.value)} />
      <select aria-label="Filter" value={filter} onChange={e => setFilter(e.target.value)}>
        <option value="all">All</option>{STATUSES.map(s => <option key={s} value={s}>{STATUS_LABEL[s]}</option>)}<option value="newphone">New phone requests</option>
      </select></div>
    <table><thead><tr><th>Restaurant</th><th>Owner</th><th>Phone</th><th>Status</th><th>Plan</th><th>Expires</th><th>Customer ID</th><th>Last sales</th></tr></thead><tbody>
      {paged.rows.map(a => <tr key={a.uid} className="click" onClick={() => go('Restaurant', a.uid)}>
        <td>{a.businessName}{a.phoneRequests.length > 0 && a.status !== 'pending' && <Badge tone="warn">new phone</Badge>}</td><td>{a.ownerName}</td><td>{a.phone}</td><td><StatusBadge a={a} /></td>
        <td>{a.plan ?? '—'}</td><td>{a.plan === 'lifetime' ? 'never' : fmtDate(a.expiresAt)}</td><td>{a.customerId ?? '—'}</td><td><SalesCell a={a} /></td></tr>)}
    </tbody></table>{paged.pager}{data && rows.length === 0 && <p className="empty">{data.length === 0 ? 'No restaurant has registered yet. Restaurants appear here after they sign up in the app.' : 'No restaurants match.'}</p>}</>);
}

export function RestaurantPage({ api, go, arg }: PageProps) {
  const uid = arg ?? '';
  const acc = useLoad(() => api.account(uid), [api, uid]);
  const notes = useLoad(() => api.notes(uid), [api, uid]);
  const days = useLoad(() => api.days(uid), [api, uid]);
  const devs = useLoad(() => api.devices(), [api]);
  const billing = useLoad(() => api.getBilling(), [api]);
  const act = useAction(() => { acc.reload(); });
  const [editing, setEditing] = useState<null | { businessName: string; ownerName: string; phone: string; city: string; email: string }>(null);
  const [plan, setPlan] = useState<PlanId>('monthly'); const [fee, setFee] = useState(''); const [custom, setCustom] = useState('');
  const [msgText, setMsgText] = useState(''); const [note, setNote] = useState<string | null>(null);
  const [maxPhones, setMaxPhones] = useState('');
  const [offDraft, setOffDraft] = useState<string[] | null>(null);
  const [themeDraft, setThemeDraft] = useState<{ id: string; locked: boolean } | null>(null);
  // pre-fill the fee from Settings > Plan prices once they load
  useEffect(() => {
    const m = billing.data?.planPrices?.monthly;
    if (m != null) setFee(f => f || (m / 100).toFixed(2));
  }, [billing.data]);
  const a = acc.data;
  if (acc.err) return <Err text={acc.err} />;
  if (!a) return <p>Loading…</p>;
  const theme = themeDraft ?? { id: a.themeId, locked: a.themeLocked };
  const custom_ = parseCustomTheme(theme.id) ?? { main: '#3C096C', accent: '#FF5A1F' };
  const off = offDraft ?? a.disabledModules;
  const setOff = setOffDraft;
  const now = new Date();
  const mine = (devs.data ?? []).filter(d => d.uid === uid);
  const sum = (n: number) => (days.data ?? []).slice(0, n).reduce((s, d) => s + d.netMinor, 0);
  const today = localDate(now), yday = localDate(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1));
  const dayNet = (d: string) => (days.data ?? []).find(x => x.date === d)?.netMinor ?? (d === today && isToday(a.todayAt, now) ? a.todayNetMinor : 0);
  const priceFor = (p: PlanId) => billing.data?.planPrices?.[p];
  const pickPlan = (p: PlanId) => { setPlan(p); const m = priceFor(p); if (m != null) setFee((m / 100).toFixed(2)); };
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
        {editing ? (<div>
          {(['businessName', 'ownerName', 'phone', 'city', 'email'] as const).map(k => <div className="row" key={k}><label style={{ width: 120 }}>{({ businessName: 'Restaurant', ownerName: 'Owner', phone: 'Phone', city: 'City', email: 'Email' })[k]}</label>
            <input aria-label={`Edit ${k}`} value={editing[k]} onChange={e => setEditing({ ...editing, [k]: e.target.value })} /></div>)}
          <button className="act" onClick={() => act.run(async () => {
            if (!editing.businessName.trim() || !editing.ownerName.trim()) throw new Error('Restaurant and owner name are required');
            await api.patchAccount(uid, { businessName: editing.businessName.trim(), ownerName: editing.ownerName.trim(), phone: editing.phone.trim(), city: editing.city.trim(), email: editing.email.trim() });
            setEditing(null);
          })}>Save details</button> <button className="act sec" onClick={() => setEditing(null)}>Cancel</button></div>)
          : <button className="act sec" onClick={() => setEditing({ businessName: a.businessName, ownerName: a.ownerName, phone: a.phone, city: a.city, email: a.email })}>Edit details</button>}
      </div>
      <div className="card"><h3>Sales</h3>
        <p>Today: <b>{money(dayNet(today), a.currency)}</b><br />Yesterday: {money(dayNet(yday), a.currency)}<br />Last 30 reported days: {money(sum(30), a.currency)}</p>
        {(days.data ?? []).length === 0 ? <p className="mut small">No daily totals reported yet.</p> : (
          <table className="mini"><thead><tr><th>Date</th><th>Bills</th><th>Customers</th><th>Net sales</th></tr></thead><tbody>
            {(days.data ?? []).slice(0, 14).map(d => <tr key={d.date}><td>{d.date}</td><td>{d.bills}</td><td>{d.customers}</td><td>{money(d.netMinor, a.currency)}</td></tr>)}
          </tbody></table>)}
        <p className="mut small">Totals only, sent by the restaurant's phone when it is online{a.todayAt ? `; last report ${ago(a.todayAt)}` : ''}.</p>
      </div>
    </div>
    {a.status === 'pending' ? (
      <div className="card"><h3>Approve this restaurant</h3><div className="row">
        <select aria-label="Plan" value={plan} onChange={e => pickPlan(e.target.value as PlanId)}>{PLANS.map(p => <option key={p.id} value={p.id}>{p.label}</option>)}</select>
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
    <div className="card"><h3>App theme</h3>
      <p className="mut small">Choose how this restaurant's app looks. "Locked" means the restaurant cannot change it in Settings. Colours only: prices and data never change. The phone gets it the next time it is online and signs in, then keeps it offline.</p>
      <div className="row" style={{ flexWrap: 'wrap', gap: 8 }}>
        <button className={'act ' + (theme.id === '' ? '' : 'sec')} aria-label="No assigned theme" onClick={() => setThemeDraft({ ...theme, id: '' })}>None (restaurant chooses)</button>
        {APP_THEMES.map(t => (
          <button key={t.id} aria-label={t.label} aria-pressed={theme.id === t.id} className={'act ' + (theme.id === t.id ? '' : 'sec')} onClick={() => setThemeDraft({ ...theme, id: t.id })}
            style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ width: 14, height: 14, borderRadius: 7, background: t.main, border: '1px solid #0003' }} /><span style={{ width: 14, height: 14, borderRadius: 7, background: t.accent, border: '1px solid #0003' }} />{t.label}
          </button>))}
      </div>
      <div className="row">Custom colours:
        <input type="color" aria-label="Custom main colour" value={custom_.main} onChange={e => setThemeDraft({ ...theme, id: customThemeId(e.target.value, custom_.accent) })} />
        <input type="color" aria-label="Custom accent colour" value={custom_.accent} onChange={e => setThemeDraft({ ...theme, id: customThemeId(custom_.main, e.target.value) })} />
        <small className="mut">{theme.id.startsWith('custom:') ? 'custom colours selected' : ''}</small></div>
      <div className="row"><label><input type="checkbox" aria-label="Lock theme" checked={theme.locked} onChange={e => setThemeDraft({ ...theme, locked: e.target.checked })} /> Restaurant cannot change it</label>
        <button className="act sec" onClick={() => act.run(async () => { await api.patchAccount(uid, { themeId: theme.id, themeLocked: theme.id !== '' && theme.locked }); })}>Save theme</button></div>
    </div>
    <div className="card"><h3>App features</h3>
      <p className="mut small">Switch a feature off to hide it in this restaurant's app. Their saved data is kept. The phone learns about the change the next time it is online and signs in.</p>
      <div className="row" style={{ flexWrap: 'wrap' }}>
        {APP_MODULES.map(m => (
          <label key={m.id} title={m.hint} style={{ display: 'flex', gap: 6, alignItems: 'center', marginRight: 16 }}>
            <input type="checkbox" aria-label={m.label} checked={!off.includes(m.id)} onChange={e => setOff(e.target.checked ? off.filter(x => x !== m.id) : [...off, m.id])} /> {m.label}
          </label>))}
        <button className="act sec" onClick={() => act.run(async () => { await api.patchAccount(uid, { disabledModules: APP_MODULES.map(m => m.id).filter(id => off.includes(id)) }); setOffDraft(null); })}>Save features</button>
      </div>
    </div>
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
