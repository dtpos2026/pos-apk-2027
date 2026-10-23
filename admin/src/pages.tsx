import { useCallback, useEffect, useState, type ReactNode } from 'react';
import type { AdminApi, Business, Dashboard as Dash, Invoice, License, Plan, SupportThread, SupportMessage, AuditRow } from './api';

export interface PageProps { api: AdminApi; role: string }

export function money(minor: number, cur: string) { return `${cur} ${(minor / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`; }

function useLoad<T>(fn: () => Promise<T>) {
  const [data, setData] = useState<T | null>(null); const [err, setErr] = useState('');
  const reload = useCallback(() => { fn().then(d => { setData(d); setErr(''); }, e => setErr(e instanceof Error ? e.message : String(e))); }, [fn]);
  useEffect(reload, [reload]);
  return { data, err, reload };
}
function Err({ msg }: { msg: string }) { return msg ? <p className="err" role="alert">{msg}</p> : null; }
function Guard({ children, err }: { children: ReactNode; err: string }) { return <>{err ? <Err msg={err} /> : children}</>; }
async function run(fn: () => Promise<void>, after: () => void, setErr: (s: string) => void) {
  try { await fn(); setErr(''); after(); } catch (e) { setErr(e instanceof Error ? e.message : String(e)); }
}

export function Dashboard({ api }: PageProps) {
  const { data, err } = useLoad<Dash>(useCallback(() => api.dashboard(), [api]));
  return (<><h2>Dashboard</h2><Guard err={err}>{data && (
    <div className="grid">
      {Object.entries(data.businesses).map(([k, n]) => <div className="card stat" key={'b' + k}><b>{n}</b><span>businesses · {k}</span></div>)}
      {Object.entries(data.licenses).map(([k, n]) => <div className="card stat" key={'l' + k}><b>{n}</b><span>licences · {k}</span></div>)}
      <div className="card stat"><b>{data.devices}</b><span>devices</span></div>
      <div className="card stat"><b>{data.unpaid_invoices}</b><span>unpaid invoices</span></div>
    </div>)}</Guard></>);
}

export function Businesses({ api }: PageProps) {
  const { data, err, reload } = useLoad<Business[]>(useCallback(() => api.businesses(), [api]));
  const [e2, setE2] = useState(''); const [note, setNote] = useState('');
  const set = (id: string, s: string) => run(() => api.setBusinessStatus(id, s, note), () => { setNote(''); reload(); }, setE2);
  return (<><h2>Businesses</h2><Err msg={err || e2} />
    <div className="row"><input aria-label="Note" placeholder="Note (required to reject, suspend or block)" style={{ width: 360 }} value={note} onChange={e => setNote(e.target.value)} /></div>
    <table><thead><tr><th>Name</th><th>Owner</th><th>Phone</th><th>Country</th><th>Status</th><th>Actions</th></tr></thead><tbody>
      {(data ?? []).map(b => <tr key={b.id}><td>{b.name}</td><td>{b.owner_name}</td><td>{b.phone}</td><td>{b.country}</td><td><span className="badge">{b.status}</span></td>
        <td>
          {b.status === 'pending' && <><button className="act" onClick={() => set(b.id, 'approved')}>Approve</button> <button className="act danger" onClick={() => set(b.id, 'rejected')}>Reject</button></>}
          {b.status === 'active' && <button className="act danger" onClick={() => set(b.id, 'suspended')}>Suspend</button>}
          {b.status === 'suspended' && <button className="act" onClick={() => set(b.id, 'approved')}>Reinstate</button>}
        </td></tr>)}
    </tbody></table>{data && data.length === 0 && <p>No businesses have registered yet.</p>}</>);
}

export function Licenses({ api }: PageProps) {
  const lic = useLoad<License[]>(useCallback(() => api.licenses(), [api]));
  const biz = useLoad<Business[]>(useCallback(() => api.businesses(), [api]));
  const plans = useLoad<Plan[]>(useCallback(() => api.plans(), [api]));
  const [e2, setE2] = useState(''); const [b, setB] = useState(''); const [p, setP] = useState(''); const [exp, setExp] = useState('');
  const name = (id: string) => biz.data?.find(x => x.id === id)?.name ?? id.slice(0, 8);
  return (<><h2>Licences</h2><Err msg={lic.err || biz.err || plans.err || e2} />
    <div className="card"><div className="row">
      <select aria-label="Business" value={b} onChange={e => setB(e.target.value)}><option value="">Business…</option>{(biz.data ?? []).filter(x => !['pending', 'rejected', 'blocked'].includes(x.status)).map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</select>
      <select aria-label="Plan" value={p} onChange={e => setP(e.target.value)}><option value="">Plan…</option>{(plans.data ?? []).map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</select>
      <input aria-label="Expiry date" type="date" value={exp} onChange={e => setExp(e.target.value)} title="Leave empty for a lifetime licence" />
      <button className="act" disabled={!b || !p} onClick={() => run(() => api.issueLicense(b, p, new Date().toISOString(), exp ? new Date(exp + 'T23:59:59').toISOString() : null), lic.reload, setE2)}>Issue / renew</button>
    </div><small>The signed licence file is produced by the issue-license function (see backend/README.md).</small></div>
    <table><thead><tr><th>Business</th><th>Status</th><th>Expires</th><th>Grace</th><th>Version</th><th>Signed</th><th /></tr></thead><tbody>
      {(lic.data ?? []).map(l => <tr key={l.id}><td>{name(l.business_id)}</td><td><span className="badge">{l.status}</span></td><td>{l.expires_at?.slice(0, 10) ?? 'never'}</td><td>{l.offline_grace_days}d</td><td>{l.version}</td><td>{l.token ? 'yes' : 'not yet'}</td>
        <td>{l.status === 'active' ? <button className="act danger" onClick={() => run(() => api.setLicenseStatus(l.id, 'suspended', 'suspended from panel'), lic.reload, setE2)}>Suspend</button>
          : <button className="act" onClick={() => run(() => api.setLicenseStatus(l.id, 'active', 'reactivated from panel'), lic.reload, setE2)}>Activate</button>}</td></tr>)}
    </tbody></table></>);
}

export function Invoices({ api }: PageProps) {
  const inv = useLoad<Invoice[]>(useCallback(() => api.invoices(), [api]));
  const biz = useLoad<Business[]>(useCallback(() => api.businesses(), [api]));
  const [e2, setE2] = useState(''); const [b, setB] = useState(''); const [amt, setAmt] = useState(''); const [due, setDue] = useState('');
  const [payAmt, setPayAmt] = useState('');
  return (<><h2>Invoices</h2><Err msg={inv.err || biz.err || e2} />
    <div className="card"><div className="row">
      <select aria-label="Business" value={b} onChange={e => setB(e.target.value)}><option value="">Business…</option>{(biz.data ?? []).map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</select>
      <input aria-label="Amount" placeholder="Amount" inputMode="decimal" value={amt} onChange={e => setAmt(e.target.value)} />
      <input aria-label="Due date" type="date" value={due} onChange={e => setDue(e.target.value)} />
      <button className="act" disabled={!b || !(Number(amt) > 0) || !due} onClick={() => run(() => api.createInvoice(b, 'license', Math.round(Number(amt) * 100), 0, due, ''), () => { setAmt(''); inv.reload(); }, setE2)}>Create invoice</button>
    </div></div>
    <div className="row"><input aria-label="Payment amount" placeholder="Payment amount for the row you click" value={payAmt} onChange={e => setPayAmt(e.target.value)} style={{ width: 280 }} /></div>
    <table><thead><tr><th>No.</th><th>Business</th><th>Total</th><th>Due</th><th>Status</th><th /></tr></thead><tbody>
      {(inv.data ?? []).map(i => <tr key={i.id}><td>{i.number}</td><td>{biz.data?.find(x => x.id === i.business_id)?.name ?? ''}</td><td>{money(i.amount_minor - i.discount_minor, i.currency)}</td><td>{i.due_at}</td><td><span className="badge">{i.status}</span></td>
        <td>{i.status !== 'paid' && i.status !== 'void' && <button className="act" disabled={!(Number(payAmt) > 0)} onClick={() => run(() => api.recordPayment(i.id, Math.round(Number(payAmt) * 100), 'manual', ''), () => { setPayAmt(''); inv.reload(); }, setE2)}>Record payment</button>}</td></tr>)}
    </tbody></table></>);
}

export function Support({ api }: PageProps) {
  const th = useLoad<SupportThread[]>(useCallback(() => api.threads(), [api]));
  const biz = useLoad<Business[]>(useCallback(() => api.businesses(), [api]));
  const [sel, setSel] = useState<SupportThread | null>(null); const [msgs, setMsgs] = useState<SupportMessage[]>([]);
  const [text, setText] = useState(''); const [e2, setE2] = useState('');
  const open = async (t: SupportThread) => { setSel(t); try { setMsgs(await api.messages(t.id)); } catch (e) { setE2(String(e)); } };
  return (<><h2>Support</h2><Err msg={th.err || e2} />
    <div className="row" style={{ alignItems: 'flex-start' }}>
      <div className="card" style={{ minWidth: 220 }}>{(th.data ?? []).map(t => <div key={t.id}><button className="sec btn" style={{ width: '100%', marginBottom: 6 }} onClick={() => open(t)}>{biz.data?.find(x => x.id === t.business_id)?.name ?? t.business_id.slice(0, 8)}</button></div>)}
        {th.data && th.data.length === 0 && <small>No conversations yet.</small>}</div>
      {sel && <div className="card" style={{ flex: 1 }}>
        {msgs.map(m => <p key={m.id}><b>{m.sender}:</b> {m.body}</p>)}
        <div className="row"><input aria-label="Reply" style={{ flex: 1 }} value={text} onChange={e => setText(e.target.value)} />
          <button className="act" disabled={!text.trim()} onClick={() => run(() => api.sendSupport(sel.business_id, text.trim()), () => { setText(''); open(sel); }, setE2)}>Send</button></div>
      </div>}
    </div></>);
}

export function Audit({ api }: PageProps) {
  const { data, err } = useLoad<AuditRow[]>(useCallback(() => api.audit(), [api]));
  return (<><h2>Audit log</h2><Guard err={err}><table><thead><tr><th>When</th><th>Who</th><th>Action</th><th>Entity</th></tr></thead><tbody>
    {(data ?? []).map(a => <tr key={a.id}><td>{a.at.replace('T', ' ').slice(0, 19)}</td><td>{a.actor_kind}</td><td>{a.action}</td><td>{a.entity} {a.entity_id?.slice(0, 8)}</td></tr>)}</tbody></table></Guard></>);
}

const COMPANY_KEYS = ['company_name', 'address', 'phone', 'email', 'website', 'payment_instructions'];
export function Settings({ api, role }: PageProps) {
  const { data, err, reload } = useLoad<Record<string, string>>(useCallback(() => api.company(), [api]));
  const [edit, setEdit] = useState<Record<string, string>>({}); const [e2, setE2] = useState('');
  const canEdit = role === 'owner';
  return (<><h2>Company details</h2><p>These appear on invoices and in the app. Nothing here is pre-filled: enter your own details.</p><Err msg={err || e2} />
    <div className="card">{COMPANY_KEYS.map(k => <div className="row" key={k}><label style={{ width: 170 }}>{k.replace('_', ' ')}</label>
      <input aria-label={k} disabled={!canEdit} style={{ width: 360 }} value={edit[k] ?? data?.[k] ?? ''} onChange={e => setEdit({ ...edit, [k]: e.target.value })} />
      {canEdit && edit[k] !== undefined && edit[k] !== (data?.[k] ?? '') && <button className="act" onClick={() => run(() => api.setCompany(k, edit[k]), () => { setEdit(({ [k]: _, ...rest }) => rest); reload(); }, setE2)}>Save</button>}</div>)}
      {!canEdit && <small>Only the owner role can change these.</small>}</div></>);
}
