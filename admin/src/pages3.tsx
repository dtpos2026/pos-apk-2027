import { useEffect, useState } from 'react';
import type { AdminApi, AppControl, Billing, Branding } from './api';
import { Badge, Err, fmtDateTime, useAction, useLoad, usePaged } from './ui';
import { DEFAULT_NEW_ADMIN_PERMS, NOTICE_KINDS, NOTICE_TEMPLATES, PANEL_SECTIONS, PLANS, parseMoneyToMinor } from './domain';
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
  const [uid, setUid] = useState(''); const [email, setEmail] = useState(''); const [pw, setPw] = useState(''); const [name, setName] = useState('');
  const [perms, setPerms] = useState<string[]>(DEFAULT_NEW_ADMIN_PERMS);
  const [edit, setEdit] = useState<Record<string, string[]>>({});
  const toggle = (cur: string[], id: string) => (cur.includes(id) ? cur.filter(x => x !== id) : [...cur, id]);
  const canAdd = !!uid.trim() || (!!email.trim() && pw.length >= 6);
  const Grid = ({ value, on, prefix }: { value: string[]; on: (v: string[]) => void; prefix: string }) => (
    <div className="permgrid">{PANEL_SECTIONS.map(s => <label key={s.id} title={s.hint}><input type="checkbox" aria-label={`${prefix} ${s.label}`} checked={value.includes(s.id)} onChange={() => on(toggle(value, s.id))} /> {s.label}</label>)}</div>);
  return (<><h2>Admins</h2><Err text={list.err || act.err} />
    <div className="card"><h3>Add an admin</h3>
      <p className="mut small">Type an email and a password and the login is created for them automatically. Or paste the UID of someone who already has a login. Tick what they may do; everything else stays hidden and is blocked on the server.</p>
      <div className="row"><input aria-label="Admin name" placeholder="Name" value={name} onChange={e => setName(e.target.value)} />
        <input aria-label="Admin email" type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} />
        <input aria-label="Admin password" type="password" placeholder="Password (6+ characters)" autoComplete="new-password" value={pw} onChange={e => setPw(e.target.value)} />
        <span className="mut">or</span><input aria-label="UID" placeholder="Existing user UID" style={{ width: 280 }} value={uid} onChange={e => setUid(e.target.value)} /></div>
      <Grid value={perms} on={setPerms} prefix="New admin may" />
      <button className="act" disabled={!canAdd || act.busy} onClick={() => act.run(async () => { await api.addAdmin({ uid, email, password: pw, name, perms }); setUid(''); setEmail(''); setPw(''); setName(''); })}>Add admin</button></div>
    <table><thead><tr><th>Admin</th><th>Access</th><th /></tr></thead><tbody>{(list.data ?? []).map(a => {
      const cur = edit[a.uid] ?? a.perms ?? PANEL_SECTIONS.map(s => s.id);
      const full = a.owner || a.perms === null;
      return (<tr key={a.uid}><td><b>{a.name || a.email || a.uid}</b>{a.uid === me && ' (you)'}{a.owner && <Badge tone="ok">Owner</Badge>}<br /><small className="mut">{a.email ? `${a.email} · ` : ''}{a.uid}</small></td>
        <td>{a.owner ? <span className="mut">Full access, always</span> : <><Grid value={cur} on={v => setEdit({ ...edit, [a.uid]: v })} prefix={`${a.name || a.email || a.uid} may`} />
          {full && !edit[a.uid] && <small className="mut">Older admin: full access until you save a list.</small>}
          {edit[a.uid] && <button className="act" disabled={act.busy} onClick={() => act.run(async () => { await api.setAdminPerms(a.uid, edit[a.uid]); setEdit(({ [a.uid]: _drop, ...rest }) => rest); })}>Save access</button>}</>}</td>
        <td>{a.uid !== me && !a.owner && <button className="act danger" onClick={() => act.run(() => api.removeAdmin(a.uid))}>Remove</button>}</td></tr>);
    })}</tbody></table></>);
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
  'settings.branding': 'Changed app branding', 'settings.app': 'Changed app control', 'settings.billing': 'Changed billing settings', 'admin.add': 'Added admin', 'admin.remove': 'Removed admin', 'admin.perms': 'Changed admin access', 'audit.delete': 'Deleted audit entries', 'audit.clean': 'Cleaned old audit entries', 'notice.send': 'Sent notification', 'notice.delete': 'Deleted notification',
};

export function Audit({ api }: PageProps) {
  const log = useLoad(() => api.auditLog(), [api]);
  const acc = useLoad(() => api.accounts(), [api]);
  const act = useAction(() => { setPicked([]); log.reload(); });
  const [q, setQ] = useState('');
  const [days, setDays] = useState('90');
  const [picked, setPicked] = useState<string[]>([]);
  const [done, setDone] = useState('');
  const name = (uid: string | null) => (uid ? acc.data?.find(a => a.uid === uid)?.businessName ?? uid.slice(0, 8) : '');
  const rows = (log.data ?? []).filter(e => { const t = q.trim().toLowerCase(); return !t || [e.action, e.adminEmail, name(e.accountUid), JSON.stringify(e.details)].some(v => v.toLowerCase().includes(t)); });
  const paged = usePaged(rows);
  const allShown = paged.rows.length > 0 && paged.rows.every(e => picked.includes(e.id));
  return (<><h2>Audit log</h2><p className="mut">Every change made in this panel, newest first. Old entries can be deleted to save space; the clean-up itself is recorded.</p><Err text={log.err || act.err} />
    <div className="row"><input aria-label="Search audit" placeholder="Search action, admin, restaurant" style={{ width: 300 }} value={q} onChange={e => setQ(e.target.value)} />
      <button className="act danger" disabled={!picked.length || act.busy} onClick={() => { if (window.confirm(`Delete ${picked.length} selected entries?`)) act.run(async () => { await api.deleteAudit(picked); setDone(`${picked.length} entries deleted.`); }); }}>Delete selected ({picked.length})</button>
      <span className="mut">Older than</span><input aria-label="Days" type="number" min={1} style={{ width: 80 }} value={days} onChange={e => setDays(e.target.value)} /><span className="mut">days</span>
      <button className="act sec" disabled={act.busy || !(Number(days) >= 1)} onClick={() => { if (window.confirm(`Delete every entry older than ${days} days?`)) act.run(async () => { const n = await api.cleanAudit(Number(days)); setDone(`${n} old entries deleted.`); }); }}>Clean old entries</button></div>
    {done && <p className="ok-note">{done}</p>}
    <table><thead><tr><th><input type="checkbox" aria-label="Select all shown" checked={allShown} onChange={() => setPicked(allShown ? picked.filter(id => !paged.rows.some(r => r.id === id)) : [...new Set([...picked, ...paged.rows.map(r => r.id)])])} /></th><th>When</th><th>Admin</th><th>Action</th><th>Restaurant</th><th>Details</th></tr></thead><tbody>
      {paged.rows.map(e => <tr key={e.id}><td><input type="checkbox" aria-label={`Select ${e.action} ${e.id}`} checked={picked.includes(e.id)} onChange={() => setPicked(picked.includes(e.id) ? picked.filter(x => x !== e.id) : [...picked, e.id])} /></td><td>{fmtDateTime(e.at)}</td><td>{e.adminEmail}</td><td>{ACTION_LABEL[e.action] ?? e.action}</td><td>{name(e.accountUid)}</td>
        <td className="mut small">{Object.entries(e.details).map(([k, v]) => `${k}: ${typeof v === 'object' ? JSON.stringify(v) : String(v)}`).join(' · ')}</td></tr>)}
    </tbody></table>{paged.pager}{log.data && log.data.length === 0 && <p className="empty">No admin actions recorded yet.</p>}</>);
}

/** Send a notice to the bell in the restaurants' apps: to everyone or to one restaurant, from a ready-made template or your own words. */
export function Notifications({ api }: PageProps) {
  const sent = useLoad(() => api.notices(), [api]);
  const acc = useLoad(() => api.accounts(), [api]);
  const act = useAction(() => sent.reload());
  const [tpl, setTpl] = useState('');
  const [title, setTitle] = useState(''); const [body, setBody] = useState(''); const [kind, setKind] = useState<string>('info'); const [target, setTarget] = useState('all');
  const [ok, setOk] = useState('');
  const pick = (id: string) => { setTpl(id); const t = NOTICE_TEMPLATES.find(x => x.id === id); if (t) { setTitle(t.title); setBody(t.body); setKind(t.kind); } };
  const who = (t: string) => (t === 'all' ? 'Everyone' : acc.data?.find(a => a.uid === t)?.businessName ?? t.slice(0, 8));
  return (<><h2>Notifications</h2><p className="mut">What you send appears at once in the bell inside the app (side menu header and top bar). The app works offline, so restaurants see it when they next have internet.</p><Err text={sent.err || act.err} />
    <div className="card"><h3>New notification</h3>
      <div className="row"><label style={{ width: 90 }}>Template</label><select aria-label="Template" value={tpl} onChange={e => pick(e.target.value)}><option value="">Write my own</option>{NOTICE_TEMPLATES.map(t => <option key={t.id} value={t.id}>{t.label}</option>)}</select>
        <label>To</label><select aria-label="Send to" value={target} onChange={e => setTarget(e.target.value)}><option value="all">Everyone</option>{(acc.data ?? []).map(a => <option key={a.uid} value={a.uid}>{a.businessName}</option>)}</select>
        <label>Type</label><select aria-label="Type" value={kind} onChange={e => setKind(e.target.value)}>{NOTICE_KINDS.map(k => <option key={k} value={k}>{k}</option>)}</select></div>
      <div className="row"><input aria-label="Title" placeholder="Title" style={{ width: 460 }} maxLength={120} value={title} onChange={e => setTitle(e.target.value)} /></div>
      <div className="row"><textarea aria-label="Message" placeholder="Message" rows={3} style={{ width: 460 }} maxLength={1000} value={body} onChange={e => setBody(e.target.value)} /></div>
      <button className="act" disabled={!title.trim() || act.busy} onClick={() => act.run(async () => { await api.sendNotice({ title, body, kind, target }); setOk(`Sent to ${who(target)}.`); setTitle(''); setBody(''); setTpl(''); })}>Send</button>{ok && <span className="mut"> {ok}</span>}</div>
    <table><thead><tr><th>When</th><th>To</th><th>Type</th><th>Notification</th><th /></tr></thead><tbody>
      {(sent.data ?? []).map(n => <tr key={n.id}><td>{fmtDateTime(n.createdAt)}</td><td>{who(n.target)}</td><td><Badge>{n.kind}</Badge></td><td><b>{n.title}</b><br /><small className="mut">{n.body}</small></td>
        <td><button className="act danger" onClick={() => act.run(() => api.deleteNotice(n.id))}>Delete</button></td></tr>)}
    </tbody></table>{sent.data && sent.data.length === 0 && <p className="empty">Nothing sent yet.</p>}</>);
}
