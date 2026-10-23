import { useEffect, useState } from 'react';
import type { AdminApi } from './api';
import { loadConfig } from './config';
import { createFirebaseApi } from './firebaseApi';
import { Dashboard, Restaurants, RestaurantPage } from './pages1';
import { Invoices, Phones, Reminders, Support } from './pages2';
import { Admins, Audit, Settings } from './pages3';
import { Icon } from './icons';
import { Err, fmtDate, msg } from './ui';
import { money } from './domain';

export function Root() {
  const [st, setSt] = useState<{ api?: AdminApi; problem?: string } | null>(null);
  useEffect(() => { loadConfig().then(r => setSt(r.config ? { api: createFirebaseApi(r.config, r.config.useEmulators ? { host: window.location.hostname, authPort: 9099, firestorePort: 8080 } : undefined) } : { problem: r.problem })); }, []);
  if (!st) return <div className="center">Loading…</div>;
  if (!st.api) return <SetupNeeded problem={st.problem ?? ''} />;
  const m = window.location.pathname.match(/^\/verify\/([\w-]+)/);
  return m ? <Verify api={st.api} token={m[1]} /> : <App api={st.api} />;
}

export function SetupNeeded({ problem }: { problem: string }) {
  return (<div className="center"><div className="card"><h2>Setup needed</h2>
    <p>This panel is not connected to Firebase yet, so it shows no data.</p><p className="err">{problem}</p>
    <p>See <code>docs/FIREBASE_SETUP.md</code>.</p></div></div>);
}

export function Verify({ api, token }: { api: AdminApi; token: string }) {
  const [r, setR] = useState<Awaited<ReturnType<AdminApi['verifyInvoice']>> | undefined>(undefined); const [err, setErr] = useState('');
  useEffect(() => { api.verifyInvoice(token).then(setR, e => setErr(msg(e))); }, [api, token]);
  return (<div className="center"><div className="card"><h2>Invoice verification</h2><Err text={err} />
    {r === undefined && !err && <p>Checking…</p>}
    {r === null && <p className="err">This invoice could not be verified.</p>}
    {r && <p>Invoice <b>{r.number}</b> for <b>{r.businessName}</b><br />Amount {money(r.amountMinor, r.currency)} · status <b>{r.status}</b><br />Issued {fmtDate(r.issuedAt)}</p>}</div></div>);
}

const PAGES = ['Dashboard', 'Restaurants', 'Invoices', 'Support', 'Phones', 'Reminders', 'Settings', 'Admins', 'Audit'] as const;

export function App({ api }: { api: AdminApi }) {
  const [user, setUser] = useState<{ uid: string; email: string } | null | undefined>(undefined);
  const [admin, setAdmin] = useState<boolean | undefined>(undefined);
  const [page, setPage] = useState<string>('Dashboard'); const [arg, setArg] = useState<string | undefined>();
  useEffect(() => api.onAuth(u => { setUser(u); setAdmin(undefined); if (u) api.isAdmin(u.uid).then(setAdmin, () => setAdmin(false)); }), [api]);
  if (user === undefined) return <div className="center">Loading…</div>;
  if (!user) return <Login api={api} />;
  if (admin === undefined) return <div className="center">Loading…</div>;
  if (!admin) return <NoAccess api={api} uid={user.uid} email={user.email} onClaimed={() => setAdmin(true)} />;
  const go = (p: string, a?: string) => { setPage(p); setArg(a); };
  const props = { api, go, arg };
  return (<div className="shell"><nav>
    <div className="brand"><img src="/dt-mark-white.png" alt="" width={30} height={30} /><div><b>DT Food POS</b><small>Super Admin</small></div></div>
    {PAGES.map(p => <button key={p} className={p === page || (page === 'Restaurant' && p === 'Restaurants') ? 'on' : ''} aria-current={p === page ? 'page' : undefined} onClick={() => go(p)}><Icon name={p} /><span>{p === 'Audit' ? 'Audit log' : p}</span></button>)}
    <div className="spacer" />
    <div className="who">{user.email}</div>
    <button onClick={() => api.signOut()}><Icon name="Sign out" /><span>Sign out</span></button>
    <div className="powered">Powered by Digital Target</div></nav>
    <main>{page === 'Dashboard' && <Dashboard {...props} />}{page === 'Restaurants' && <Restaurants {...props} />}{page === 'Restaurant' && <RestaurantPage {...props} />}
      {page === 'Invoices' && <Invoices key={arg} {...props} />}{page === 'Support' && <Support {...props} />}{page === 'Phones' && <Phones {...props} />}
      {page === 'Reminders' && <Reminders {...props} />}{page === 'Settings' && <Settings {...props} />}{page === 'Admins' && <Admins {...props} me={user.uid} />}
      {page === 'Audit' && <Audit {...props} />}</main></div>);
}

function Login({ api }: { api: AdminApi }) {
  const [email, setEmail] = useState(''); const [pw, setPw] = useState(''); const [err, setErr] = useState(''); const [info, setInfo] = useState('');
  return (<div className="center"><div className="card login"><img src="/logo.png" alt="DT Food POS" width={64} height={64} /><h2>DT Food POS</h2><p className="mut">Super Admin · Digital Target</p>
    <form onSubmit={async e => { e.preventDefault(); setErr(''); try { await api.signIn(email, pw); } catch (x) { setErr(msg(x)); } }}>
      <div className="row"><input aria-label="Email" type="email" autoComplete="username" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} /></div>
      <div className="row"><input aria-label="Password" type="password" autoComplete="current-password" placeholder="Password" value={pw} onChange={e => setPw(e.target.value)} /></div>
      <button className="act wide" type="submit">Sign in</button>
    </form>
    <p><a onClick={async () => { setErr(''); setInfo(''); try { if (!email) throw new Error('Type your email first'); await api.resetPassword(email); setInfo('Password reset email sent.'); } catch (e) { setErr(msg(e)); } }}>Forgot password?</a></p>
    <Err text={err} />{info && <p>{info}</p>}</div></div>);
}

function NoAccess({ api, uid, email, onClaimed }: { api: AdminApi; uid: string; email: string; onClaimed: () => void }) {
  const [claimed, setClaimed] = useState<boolean | undefined>(undefined); const [err, setErr] = useState('');
  useEffect(() => { api.ownerClaimed().then(setClaimed, e => { setErr(msg(e)); setClaimed(true); }); }, [api]);
  return (<div className="center"><div className="card"><h2>No admin access</h2><p>Signed in as {email}.</p>
    {claimed === false ? (<><p>No Super Admin exists yet. If you are the owner of this project, claim it now. This works only once.</p>
      <button className="act" onClick={async () => { try { await api.claimSuperAdmin(uid); onClaimed(); } catch (e) { setErr(msg(e)); } }}>Become Super Admin</button></>)
      : (<><p>Ask an existing admin to add this UID in Admins:</p><code>{uid}</code></>)}
    <Err text={err} /><p><a onClick={() => api.signOut()}>Sign out</a></p></div></div>);
}
