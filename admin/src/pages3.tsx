import { useEffect, useState } from 'react';
import type { AdminApi, AppControl, Billing, Branding } from './api';
import { Err, useAction, useLoad } from './ui';
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
  const text = (k: keyof Billing, label: string, multi = false) => (<div className="row" key={k}><label style={{ width: 190 }}>{label}</label>
    {multi ? <textarea aria-label={label} rows={2} style={{ width: 420 }} value={v[k]} onChange={e => { setSaved(false); setV({ ...v, [k]: e.target.value }); }} />
      : <input aria-label={label} style={{ width: 420 }} value={v[k]} onChange={e => { setSaved(false); setV({ ...v, [k]: e.target.value }); }} />}</div>);
  const img = (k: 'paymentQr' | 'signature', label: string) => (<div className="row"><label style={{ width: 190 }}>{label}</label>
    {v[k] && <img src={v[k]} alt={label} height={40} />}<button className="act sec" onClick={() => act.run(async () => { setV({ ...v, [k]: await pickImage() }); setSaved(false); })}>Choose image</button>
    {v[k] && <button className="act sec" onClick={() => { setV({ ...v, [k]: '' }); setSaved(false); }}>Remove</button>}</div>);
  return (<div className="card"><h3>Billing & invoices</h3><small>Only admins can read this.</small><Err text={err || act.err} />
    {text('company', 'Company name')}{text('address', 'Address', true)}{text('bank', 'Bank')}{text('accountTitle', 'Account title')}{text('accountNo', 'Account number / IBAN')}
    {text('terms', 'Invoice terms', true)}{text('reminderTemplate', 'Reminder template', true)}{img('paymentQr', 'Payment QR')}{img('signature', 'Signature')}
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
