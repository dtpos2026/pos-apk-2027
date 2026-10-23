import { useEffect, useState } from 'react';
import type { AdminApi } from './api';
import { loadConfig } from './config';
import { createSupabaseApi } from './supabaseApi';
import { Dashboard, Businesses, Licenses, Invoices, Support, Audit, Settings } from './pages';

export function Root() {
  const [state, setState] = useState<{ api?: AdminApi; brand?: string; problem?: string } | null>(null);
  useEffect(() => {
    loadConfig().then(r => setState(r.config ? { api: createSupabaseApi(r.config), brand: r.config.brandName } : { problem: r.problem }));
  }, []);
  if (!state) return <div className="center">Loading…</div>;
  if (!state.api) return <SetupNeeded problem={state.problem ?? ''} />;
  return <App api={state.api} brand={state.brand ?? ''} />;
}

export function SetupNeeded({ problem }: { problem: string }) {
  return (
    <div className="center">
      <div className="card">
        <h2>Setup needed</h2>
        <p>This panel is not connected to a backend yet, so it shows no data.</p>
        <p className="err">{problem}</p>
        <p>Copy <code>config.example.json</code> to <code>config.json</code> next to this page and fill in your Supabase project URL and public (anon) key. See <code>admin/README.md</code>.</p>
      </div>
    </div>
  );
}

const TABS = ['Dashboard', 'Businesses', 'Licenses', 'Invoices', 'Support', 'Audit', 'Settings'] as const;
type Tab = typeof TABS[number];

export function App({ api, brand }: { api: AdminApi; brand: string }) {
  const [role, setRole] = useState<string | null | undefined>(undefined);
  const [tab, setTab] = useState<Tab>('Dashboard');
  useEffect(() => { api.myRole().then(setRole, () => setRole(null)); }, [api]);
  if (role === undefined) return <div className="center">Loading…</div>;
  if (role === null) return <Login api={api} brand={brand} onDone={() => api.myRole().then(setRole)} />;
  const page = { Dashboard, Businesses, Licenses, Invoices, Support, Audit, Settings }[tab];
  const Page = page;
  return (
    <div className="shell">
      <nav>
        <h1>{brand} · DT Food POS<br /><small>{role}</small></h1>
        {TABS.map(t => <button key={t} className={t === tab ? 'on' : ''} onClick={() => setTab(t)}>{t}</button>)}
        <button onClick={async () => { await api.signOut(); setRole(null); }}>Sign out</button>
      </nav>
      <main><Page api={api} role={role} /></main>
    </div>
  );
}

function Login({ api, brand, onDone }: { api: AdminApi; brand: string; onDone: () => void }) {
  const [email, setEmail] = useState(''); const [pw, setPw] = useState(''); const [err, setErr] = useState('');
  async function go() {
    setErr('');
    try { await api.signIn(email, pw); await onDone(); } catch (e) { setErr(e instanceof Error ? e.message : String(e)); }
  }
  return (
    <div className="center"><div className="card">
      <h2>{brand} Super Admin</h2>
      <div className="row"><input aria-label="Email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} /></div>
      <div className="row"><input aria-label="Password" type="password" placeholder="Password" value={pw} onChange={e => setPw(e.target.value)} /></div>
      <button className="act" onClick={go}>Sign in</button>
      {err && <p className="err" role="alert">{err}</p>}
      <p style={{ color: '#6b6177', fontSize: 12 }}>Only accounts listed as Digital Target staff can use this panel.</p>
    </div></div>
  );
}
