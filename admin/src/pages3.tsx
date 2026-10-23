import { useEffect, useState } from 'react';
import type { AdminApi, AppControl, Billing, Branding } from './api';
import { Err, fmtDateTime, useAction, useLoad, usePaged } from './ui';
import { PLANS, parseMoneyToMinor } from './domain';
import type { PageProps } from './pages1';

function Form<T extends object>({ title, load, save, fields, hint }: { title: string; load: () => Promise<T>; save: (v: T) => Promise<void>; fields: { key: keyof T & string; label: string; multi?: boolean; num?: boolean }[]; hint?: string }) {
  const { data, err } = useLoad(load, []);
  const [v, setV] = useState<T | null>(null);
  const act = useAction();
  const [saved, setSaved] = useState(false);
  useEffect(() => { if (data) setV(data); }, [data]);
  if (!v) return <div className="card"><h3>{title}</h3><Err text={err} /></div>;
  return (<div className="card"><h3>{title}</h3>{hint && <small>{hint}</small>}<Err text={err || act.err} />
    {fields.map(f => <div className="row" key={f.key}><label style={{ width: 190 }}>{f.label}</label>
      {f.multi ? <textarea aria-label={f.label} rows={2} style={{ width: 420 }} value={String(v[f.key] ?? '')} onChange={e => { setSaved(false); setV({ ...v, [f.key]: e.target.value }); }} />
        : <input aria-label={f.label} style={{ width: 420 }} value={String(v[f.key] ?? '')} onChange={e => { setSaved(false); setV({ ...v, [f.key]: f.num ? Number(e.target.value.replace(/\D/g, '')) : e.target.value }); }} />}</div>)}
    <button className="act" disabled={act.busy} onClick={() => act.run(async () => { await save(v); setSaved(true); })}>Save</button>{saved && <span> Saved.</span>}</div>);
}

async function pickImage(): Promise<string> {
  return new Promise((res, rej) => {
    const i = document.createElement('input'); i.type = 'file'; i.accept = 'image/*';
    i.onchange = () => { const f = i.files?.[0]; if (!f) return rej(new Error('No file')); if (f.size > 150_000) return rej(new Error('Image is too big: use one under 150 KB')); const r = new FileReader(); r.onload = () => res(String(r.result)); r.readAsDataURL(f); };
    i.click();
  });
}

export function Settings({ api }: PageProps) {
  return (<><h2>Settings</h2><p>Nothing here is pre-filled: enter your own company details.</p>
    <Form<Branding> title="App branding (shown on the app's sign-in screen)" load={() => api.getBranding()} save={v => api.setBranding(v)}
      fields={[{ key: 'appName', label: 'App name' }, { key: 'contact', label: 'Contact number' }, { key: 'whatsapp', label: 'WhatsApp number' }, { key: 'email', label: 'Email' }, { key: 'supportMessage', label: 'Support message', multi: true }]} />
    <Form<AppControl> title="App control" load={() => api.getAppControl()} save={v => api.setAppControl(v)} hint="Offline days: how long the app may work without checking the account online."
      fields={[{ key: 'offlineDays', label: 'Offline days', num: true }, { key: 'notice', label: 'Notice to all restaurants', multi: true }, { key: 'latestVersion', label: 'Latest app version' }, { key: 'minVersion', label: 'Minimum app version' }, { key: 'updateLink', label: 'Update link' }]} />
    <BillingForm api={api} /></>);
}

function BillingForm({ api }: { api: AdminApi }) {
  const { data, err } = useLoad<Billing>(() => api.getBilling(), [api]);
  const [v, setV] = useState<Billing | null>(null); const act = useAction(); const [saved, setSaved] = useState(false);
  useEffect(() => { if (data) setV(data); }, [data]);
  if (!v) return <div className="card"><h3>Billing & invoices</h3><Err text={err} /></div>;
  const text = (k: Exclude<keyof Billing, 'planPrices'>, label: string, multi = false) => (<div className="row" key={k}><label style={{ width: 190 }}>{label}</label>
    {multi ? <textarea aria-label={label} rows={2} style={{ width: 420 }} value={v[k]} onChange={e => { setSaved(false); setV({ ...v, [k]: e.target.value }); }} />
      : <input aria-label={label} style={{ width: 420 }} value={v[k]} onChange={e => { setSaved(false); setV({ ...v, [k]: e.target.value }); }} />}</div>);
  const img = (k: 'paymentQr' | 'signature', label: string) => (<div className="row"><label style={{ width: 190 }}>{label}</label>
    {v[k] && <img src={v[k]} alt={label} height={40} />}<button className="act sec" onClick={() => act.run(async () => { setV({ ...v, [k]: await pickImage() }); setSaved(false); })}>Choose image</button>
    {v[k] && <button className="act sec" onClick={() => { setV({ ...v, [k]: '' }); setSaved(false); }}>Remove</button>}</div>);
  return (<div className="card"><h3>Billing & invoices</h3><small>Only admins can read this.</small><Err text={err || act.err} />
    {text('company', 'Company name')}{text('address', 'Address', true)}{text('bank', 'Bank')}{text('accountTitle', 'Account title')}{text('accountNo', 'Account number / IBAN')}
    {text('terms', 'Invoice terms', true)}{text('reminderTemplate', 'Reminder template', true)}{img('paymentQr', 'Payment QR')}{img('signature', 'Signature')}
    <h4>Plan prices</h4><small>Used to pre-fill the fee when approving a restaurant. Leave empty if you price each restaurant yourself.</small>
    {PLANS.filter(p => p.id !== 'custom').map(p => <PriceRow key={p.id} label={p.label} minor={v.planPrices?.[p.id]} onChange={m => { setSaved(false); const next = { ...(v.planPrices ?? {}) }; if (m === null) delete next[p.id]; else next[p.id] = m; setV({ ...v, planPrices: next }); }} />)}
    <button className="act" disabled={act.busy} onClick={() => act.run(async () => { await api.setBilling(v); setSaved(true); })}>Save</button>{saved && <span> Saved.</span>}</div>);
}

export function Admins({ api, me }: PageProps & { me: string }) {
  const list = useLoad(() => api.admins(), [api]);
  const act = useAction(() => list.reload());
  const [uid, setUid] = useState('');
  return (<><h2>Admins</h2><Err text={list.err || act.err} />
    <p>To add an admin: create their user in Firebase Authentication, ask them to sign in to this panel (it will show their UID), then paste the UID here.</p>
    <div className="row"><input aria-label="UID" placeholder="User UID" style={{ width: 340 }} value={uid} onChange={e => setUid(e.target.value)} />
      <button className="act" disabled={!uid.trim()} onClick={() => act.run(async () => { await api.addAdmin(uid); setUid(''); })}>Add admin</button></div>
    <table><tbody>{(list.data ?? []).map(a => <tr key={a.uid}><td>{a.uid}{a.uid === me && ' (you)'}</td><td>{a.uid !== me && <button className="act danger" onClick={() => act.run(() => api.removeAdmin(a.uid))}>Remove</button>}</td></tr>)}</tbody></table></>);
}

function PriceRow({ label, minor, onChange }: { label: string; minor: number | undefined; onChange: (m: number | null) => void }) {
  const [text, setText] = useState(minor != null ? (minor / 100).toFixed(2) : '');
  const [bad, setBad] = useState(false);
  return (<div className="row"><label style={{ width: 190 }}>{label}</label>
    <input aria-label={`Price ${label}`} style={{ width: 160 }} value={text} placeholder="—" onChange={e => {
      const t = e.target.value; setText(t);
      if (!t.trim()) { setBad(false); onChange(null); return; }
      try { onChange(parseMoneyToMinor(t)); setBad(false); } catch { setBad(true); }
    }} />{bad && <span className="err">Enter an amount like 2500</span>}</div>);
}

const ACTION_LABEL: Record<string, string> = {
  'account.approve': 'Approved restaurant', 'account.update': 'Changed restaurant', 'account.status': 'Changed status',
  'phone.approve': 'Approved phone', 'phone.remove': 'Removed phone', 'phone.block': 'Blocked phone', 'phone.unblock': 'Unblocked phone', 'device.delete': 'Deleted phone record',
  'invoice.create': 'Created invoice', 'invoice.paid': 'Recorded payment', 'invoice.void': 'Voided invoice', 'support.delete': 'Deleted chat',
  'settings.branding': 'Changed app branding', 'settings.app': 'Changed app control', 'settings.billing': 'Changed billing settings', 'admin.add': 'Added admin', 'admin.remove': 'Removed admin',
};

export function Audit({ api }: PageProps) {
  const log = useLoad(() => api.auditLog(), [api]);
  const acc = useLoad(() => api.accounts(), [api]);
  const [q, setQ] = useState('');
  const name = (uid: string | null) => (uid ? acc.data?.find(a => a.uid === uid)?.businessName ?? uid.slice(0, 8) : '');
  const rows = (log.data ?? []).filter(e => { const t = q.trim().toLowerCase(); return !t || [e.action, e.adminEmail, name(e.accountUid), JSON.stringify(e.details)].some(v => v.toLowerCase().includes(t)); });
  const paged = usePaged(rows);
  return (<><h2>Audit log</h2><p className="mut">Every change made in this panel, newest first. Entries cannot be edited or deleted.</p><Err text={log.err} />
    <div className="row"><input aria-label="Search audit" placeholder="Search action, admin, restaurant" style={{ width: 340 }} value={q} onChange={e => setQ(e.target.value)} /></div>
    <table><thead><tr><th>When</th><th>Admin</th><th>Action</th><th>Restaurant</th><th>Details</th></tr></thead><tbody>
      {paged.rows.map(e => <tr key={e.id}><td>{fmtDateTime(e.at)}</td><td>{e.adminEmail}</td><td>{ACTION_LABEL[e.action] ?? e.action}</td><td>{name(e.accountUid)}</td>
        <td className="mut small">{Object.entries(e.details).map(([k, v]) => `${k}: ${typeof v === 'object' ? JSON.stringify(v) : String(v)}`).join(' · ')}</td></tr>)}
    </tbody></table>{paged.pager}{log.data && log.data.length === 0 && <p className="empty">No admin actions recorded yet.</p>}</>);
}
