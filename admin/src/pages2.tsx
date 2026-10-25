import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';
import { PhonesMap } from './PhonesMap';
import type { AdminApi, Billing, Invoice, Message } from './api';
import { PLANS, daysLeft, effectiveStatus, fillTemplate, isOnline, money, parseMoneyToMinor, whatsappLink, type PlanId } from './domain';
import { Badge, Err, ago, fmtDate, fmtDateTime, useAction, useLoad, usePaged } from './ui';
import type { PageProps } from './pages1';

export function Invoices({ api, arg }: PageProps) {
  const inv = useLoad(() => api.invoices(), [api]);
  const acc = useLoad(() => api.accounts(), [api]);
  const act = useAction(() => inv.reload());
  const [uid, setUid] = useState(arg ?? ''); const [amt, setAmt] = useState(''); const [disc, setDisc] = useState(''); const [due, setDue] = useState('');
  const [plan, setPlan] = useState<PlanId | ''>('monthly'); const [view, setView] = useState<Invoice | null>(null);
  const paged = usePaged(inv.data ?? []);
  if (view) return <InvoiceView api={api} inv={view} phone={acc.data?.find(a => a.uid === view.accountUid)?.phone ?? ''} onBack={() => setView(null)} />;
  return (<><h2>Invoices</h2><Err text={inv.err || acc.err || act.err} />
    <div className="card"><h3>New invoice</h3><div className="row">
      <select aria-label="Restaurant" value={uid} onChange={e => setUid(e.target.value)}><option value="">Restaurant…</option>{(acc.data ?? []).filter(a => a.status !== 'pending' && a.status !== 'rejected').map(a => <option key={a.uid} value={a.uid}>{a.businessName}</option>)}</select>
      <input aria-label="Amount" placeholder="Amount" value={amt} onChange={e => setAmt(e.target.value)} />
      <input aria-label="Discount" placeholder="Discount" value={disc} onChange={e => setDisc(e.target.value)} />
      <select aria-label="Plan to extend on payment" value={plan} onChange={e => setPlan(e.target.value as PlanId | '')}><option value="">No renewal</option>{PLANS.filter(p => p.id !== 'custom').map(p => <option key={p.id} value={p.id}>{p.label}</option>)}</select>
      <input aria-label="Due date" type="date" value={due} onChange={e => setDue(e.target.value)} />
      <button className="act" disabled={act.busy || !uid || !amt || !due} onClick={() => act.run(async () => {
        const created = await api.createInvoice(uid, parseMoneyToMinor(amt), disc ? parseMoneyToMinor(disc) : 0, new Date(due + 'T23:59:59'), plan || null);
        setAmt(''); setDisc(''); setView(created);
      })}>Create</button></div></div>
    <table><thead><tr><th>No.</th><th>Restaurant</th><th>Total</th><th>Due</th><th>Status</th><th /></tr></thead><tbody>
      {paged.rows.map(i => <tr key={i.id}><td>{i.number}</td><td>{i.businessName}</td><td>{money(i.amountMinor - i.discountMinor, i.currency)}</td><td>{fmtDate(i.dueAt)}</td>
        <td><Badge tone={i.status === 'paid' ? 'ok' : i.status === 'void' ? '' : 'warn'}>{i.status}</Badge></td>
        <td><button className="act sec" onClick={() => setView(i)}>Open</button>{' '}
          {i.status === 'unpaid' && <button className="act" disabled={act.busy} onClick={() => act.run(() => api.recordPayment(i.id))}>Record payment</button>}{' '}
          {i.status === 'unpaid' && <button className="act danger" onClick={() => act.run(() => api.voidInvoice(i.id))}>Void</button>}</td></tr>)}
    </tbody></table>{paged.pager}{inv.data && inv.data.length === 0 && <p className="empty">No invoices yet. Create one above.</p>}</>);
}

/** The invoice as a branded A4 page: red header with the logo, who bills whom, the items, totals, payment details, a real verification QR and a signature. */
export function InvoiceView({ api, inv, phone, onBack }: { api: AdminApi; inv: Invoice; phone: string; onBack: () => void }) {
  const bill = useLoad<Billing>(() => api.getBilling(), [api]);
  const [qr, setQr] = useState('');
  const [png, setPng] = useState('');
  const sheet = useRef<HTMLDivElement>(null);
  const link = `${window.location.origin}/verify/${inv.verifyToken}`;
  useEffect(() => { QRCode.toDataURL(link, { margin: 1, width: 220 }).then(setQr, () => setQr('')); }, [link]);
  const b = bill.data;
  const total = inv.amountMinor - inv.discountMinor;
  const downloadPng = async () => {
    setPng('');
    try {
      const { default: html2canvas } = await import('html2canvas');
      const canvas = await html2canvas(sheet.current!, { scale: 2, backgroundColor: '#ffffff', useCORS: true });
      const a = document.createElement('a');
      a.download = `${inv.number}.png`; a.href = canvas.toDataURL('image/png'); a.click();
    } catch (e) { setPng(e instanceof Error ? e.message : 'Could not make the picture'); }
  };
  return (<>
    <p className="noprint"><a onClick={onBack}>← Invoices</a> · <button className="act" onClick={downloadPng}>Download PNG</button> <button className="act sec" onClick={() => window.print()}>Print / Save as PDF</button>
      {' '}<a className="btn" href={whatsappLink(phone, `Invoice ${inv.number} for ${inv.businessName}: ${money(total, inv.currency)}, due ${fmtDate(inv.dueAt)}. Verify: ${link}`)} target="_blank" rel="noreferrer">Send on WhatsApp</a></p>
    {png && <p className="err">{png}</p>}
    <div className="inv-a4" ref={sheet} data-testid="invoice-sheet">
      <header className="inv-head"><img src="/logo.png" alt="DT Food POS" width={64} height={64} /><div className="inv-co"><b>{b?.company || 'Digital Target'}</b><small>{b?.address}</small></div>
        <div className="inv-title"><span>INVOICE</span><b>{inv.number}</b><i className={'inv-pill ' + inv.status}>{inv.status.toUpperCase()}</i></div></header>
      <section className="inv-parties"><div><small>BILL TO</small><b>{inv.businessName}</b></div><div><small>ISSUED</small><b>{fmtDate(inv.issuedAt)}</b></div><div><small>DUE</small><b>{fmtDate(inv.dueAt)}</b></div></section>
      <table className="inv-items"><thead><tr><th>#</th><th>Description</th><th style={{ textAlign: 'right' }}>Amount</th></tr></thead><tbody>
        <tr><td>1</td><td>DT Food POS subscription {inv.plan ? `(${inv.plan})` : ''}</td><td style={{ textAlign: 'right' }}>{money(inv.amountMinor, inv.currency)}</td></tr>
        {inv.discountMinor > 0 && <tr><td>2</td><td>Discount</td><td style={{ textAlign: 'right' }}>− {money(inv.discountMinor, inv.currency)}</td></tr>}</tbody></table>
      <section className="inv-bottom"><div className="inv-pay"><small>PAYMENT DETAILS</small>{b && (b.bank || b.accountNo) ? <p>{b.bank}<br />{b.accountTitle}<br />{b.accountNo}</p> : <p className="mut">Add bank details in Settings</p>}
        {b?.paymentQr && <img src={b.paymentQr} alt="Payment QR" height={96} />}</div>
        <div className="inv-total"><div><span>Total</span><b>{money(total, inv.currency)}</b></div>{inv.status === 'paid' && <div className="paid"><span>Paid</span><b>{fmtDate(inv.paidAt)}</b></div>}
          {inv.status === 'unpaid' && <div className="due"><span>Balance due</span><b>{money(total, inv.currency)}</b></div>}</div></section>
      <section className="inv-sign"><div className="inv-verify">{qr && <img src={qr} alt="Scan to verify" width={96} height={96} />}<small>Scan to verify this invoice</small></div>
        <div className="inv-terms">{b?.terms && <small>{b.terms}</small>}</div>
        <div className="inv-sig">{b?.signature && <img src={b.signature} alt="Signature" height={52} />}<div className="line" /><small>Authorized signatory</small></div></section>
      <footer className="inv-foot"><span>Thank you for your business!</span><span>Powered by Digital Target · DT Food POS</span></footer>
    </div>
  </>);
}

export function Support({ api }: PageProps) {
  const th = useLoad(() => api.threads(), [api]);
  const [sel, setSel] = useState<string | null>(null); const [msgs, setMsgs] = useState<Message[]>([]); const [text, setText] = useState('');
  const act = useAction();
  const open = async (uid: string) => { setSel(uid); act.setErr(''); try { setMsgs(await api.messages(uid)); await api.markRead(uid); th.reload(); } catch (e) { act.setErr(String(e)); } };
  useEffect(() => { if (!sel) return; const t = setInterval(() => { api.messages(sel).then(setMsgs, () => {}); }, 5000); return () => clearInterval(t); }, [api, sel]);
  const name = th.data?.find(t => t.uid === sel)?.businessName ?? '';
  return (<><h2>Support</h2><Err text={th.err || act.err} />
    <div className="row" style={{ alignItems: 'flex-start' }}>
      <div className="card" style={{ minWidth: 240 }}>{(th.data ?? []).map(t => <button key={t.uid} className={'sec btn full' + (t.uid === sel ? ' on' : '')} onClick={() => open(t.uid)}>{t.businessName || t.uid.slice(0, 8)}{t.unreadForAdmin && <Badge tone="warn">new</Badge>}<br /><small>{t.lastMessage}</small></button>)}
        {th.data && th.data.length === 0 && <small>No conversations yet.</small>}</div>
      {sel && <div className="card" style={{ flex: 1, minWidth: 300 }}><h3>{name}</h3>
        {msgs.map(m => <p key={m.id} className={m.sender === 'admin' ? 'me' : ''}><b>{m.sender === 'admin' ? 'DT' : 'Restaurant'}:</b> {m.text} <small>{fmtDateTime(m.at)}</small></p>)}
        <div className="row"><input aria-label="Reply" style={{ flex: 1 }} value={text} onChange={e => setText(e.target.value)} />
          <button className="act" disabled={!text.trim()} onClick={() => act.run(async () => { await api.sendMessage(sel, text.trim()); setText(''); await open(sel); })}>Send</button></div>
        <div className="row"><button className="act sec" onClick={() => act.run(async () => { await api.clearChat(sel); await open(sel); })}>Clear chat</button>
          <button className="act danger" onClick={() => act.run(async () => { await api.deleteChat(sel); setSel(null); th.reload(); })}>Delete chat</button></div></div>}
    </div></>);
}

export function Phones({ api }: PageProps) {
  const dev = useLoad(() => api.devices(), [api]);
  const acc = useLoad(() => api.accounts(), [api]);
  const act = useAction(() => { dev.reload(); acc.reload(); });
  const [q, setQ] = useState('');
  const now = new Date();
  const nameOf = (uid: string) => acc.data?.find(a => a.uid === uid)?.businessName ?? 'Unknown account';
  const logoOf = (uid: string) => acc.data?.find(a => a.uid === uid)?.logo;
  // one row per phone (documents are keyed restaurant+phone id, so a phone never appears twice)
  const rows = (dev.data ?? [])
    .filter(d => { const t = q.trim().toLowerCase(); return !t || [nameOf(d.uid), d.model, d.appVersion, d.ip ?? ''].some(v => v.toLowerCase().includes(t)); })
    .sort((a, b) => (b.lastSeenAt?.getTime() ?? 0) - (a.lastSeenAt?.getTime() ?? 0));
  const paged = usePaged(rows);
  const located = rows.filter(d => d.locationAllowed && d.lat != null && d.lng != null);
  return (<><h2>Phones</h2><Err text={dev.err || acc.err || act.err} />
    <div className="grid">
      <div className="card stat"><b>{rows.filter(d => isOnline(d.lastSeenAt, now)).length}</b><span>online now (seen in the last 5 min)</span></div>
      <div className="card stat"><b>{rows.length}</b><span>phones</span></div>
      <div className="card stat"><b>{located.length}</b><span>sharing location</span></div>
    </div>
    <div className="card"><h3>Map</h3>
      {located.length === 0 ? <p className="empty">No phone shares its location yet. The restaurant owner turns it on in the app (Settings › Account).</p>
        : <PhonesMap points={located.map(d => ({ device: d, restaurant: nameOf(d.uid), logo: logoOf(d.uid), online: isOnline(d.lastSeenAt, now) }))} />}
    </div>
    <div className="row"><input aria-label="Search phones" placeholder="Search restaurant, model, version" style={{ width: 320 }} value={q} onChange={e => setQ(e.target.value)} /></div>
    <table><thead><tr><th>Restaurant</th><th>Model</th><th>Android / app</th><th>Last seen</th><th>Location</th><th /></tr></thead><tbody>
      {paged.rows.map(d => { const a = acc.data?.find(x => x.uid === d.uid); const blocked = !!a?.blockedPhones.includes(d.phoneId); const approved = !!a?.approvedPhones.includes(d.phoneId); return (
        <tr key={d.id}><td>{nameOf(d.uid)} {blocked ? <Badge tone="bad">blocked</Badge> : approved ? <Badge tone="ok">approved</Badge> : <Badge tone="warn">not approved</Badge>}</td><td>{d.model}</td><td>{d.android} / {d.appVersion}{d.ip ? <><br /><small className="mut">{d.ip}</small></> : null}</td>
          <td><Badge tone={isOnline(d.lastSeenAt, now) ? 'ok' : ''}>{isOnline(d.lastSeenAt, now) ? 'online' : 'offline'}</Badge> {ago(d.lastSeenAt)}</td>
          <td>{d.locationAllowed && d.lat != null && d.lng != null ? <a href={`https://www.openstreetmap.org/?mlat=${d.lat}&mlon=${d.lng}#map=17/${d.lat}/${d.lng}`} target="_blank" rel="noreferrer">±{Math.round(d.accuracyM ?? 0)} m, {ago(d.locationAt ?? null)}</a> : d.locationAllowed ? 'allowed, no fix yet' : <span className="mut">not shared</span>}</td>
          <td><button className="act sec" onClick={() => act.run(() => api.setDeviceBlocked(d.uid, d.phoneId, !blocked))}>{blocked ? 'Unblock' : 'Block'}</button>{' '}
            <button className="act danger" onClick={() => { if (confirm('Delete this phone record? It reappears if the phone reports again.')) act.run(() => api.deleteDevice(d.id)); }}>Delete</button></td></tr>); })}
    </tbody></table>{paged.pager}{dev.data && dev.data.length === 0 && <p className="empty">No phone has reported yet.</p>}</>);
}

export function Reminders({ api }: PageProps) {
  const acc = useLoad(() => api.accounts(), [api]);
  const bill = useLoad(() => api.getBilling(), [api]);
  const [tpl, setTpl] = useState<string | null>(null);
  const now = new Date();
  const template = tpl ?? bill.data?.reminderTemplate ?? '';
  const rows = (acc.data ?? []).filter(a => {
    const st = effectiveStatus(a.status, a.expiresAt, now); const d = daysLeft(a.expiresAt, now);
    return st === 'payment_pending' || st === 'expired' || (st === 'active' && d !== null && d <= 7);
  });
  return (<><h2>Reminders</h2><Err text={acc.err || bill.err} />
    <p>Placeholders: {'{owner} {business} {amount} {expiry} {customerId}'}. The message opens in WhatsApp; you press Send yourself.</p>
    <textarea aria-label="Template" rows={3} style={{ width: '100%' }} value={template} onChange={e => setTpl(e.target.value)} />
    <table><thead><tr><th>Restaurant</th><th>Status</th><th>Expiry</th><th /></tr></thead><tbody>
      {rows.map(a => <tr key={a.uid}><td>{a.businessName}</td><td>{effectiveStatus(a.status, a.expiresAt, now)}</td><td>{fmtDate(a.expiresAt)}</td>
        <td><a className="btn" target="_blank" rel="noreferrer" href={whatsappLink(a.phone, fillTemplate(template, { owner: a.ownerName, business: a.businessName, amount: a.feeMinor ? money(a.feeMinor, a.currency) : '', expiry: fmtDate(a.expiresAt), customerId: a.customerId ?? '' }))}>WhatsApp</a></td></tr>)}
    </tbody></table>{acc.data && rows.length === 0 && <p>Nothing needs a reminder right now.</p>}</>);
}
