import { useCallback, useEffect, useState, type ReactNode } from 'react';

export function useLoad<T>(fn: () => Promise<T>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null);
  const [err, setErr] = useState('');
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const reload = useCallback(() => { fn().then(d => { setData(d); setErr(''); }, e => setErr(msg(e))); }, deps);
  useEffect(reload, [reload]);
  return { data, err, reload };
}
export const msg = (e: unknown) => {
  const m = e instanceof Error ? e.message : String(e);
  if (/permission-denied|Missing or insufficient permissions/i.test(m)) return 'Permission denied. If you just changed the rules, deploy them again (see docs/FIREBASE_SETUP.md).';
  if (/requires an index/i.test(m)) return 'This query needs a Firestore index. Run: npx firebase-tools deploy --only firestore';
  return m;
};
export function Err({ text }: { text: string }) { return text ? <p className="err" role="alert">{text}</p> : null; }
export function Badge({ children, tone }: { children: ReactNode; tone?: string }) { return <span className={'badge ' + (tone ?? '')}>{children}</span>; }

/** Runs an action, shows its error, and calls `after` on success. */
export function useAction(after?: () => void) {
  const [err, setErr] = useState(''); const [busy, setBusy] = useState(false);
  const run = async (fn: () => Promise<unknown>) => {
    setBusy(true);
    try { await fn(); setErr(''); after?.(); } catch (e) { setErr(msg(e)); } finally { setBusy(false); }
  };
  return { err, busy, run, setErr };
}
export const fmtDate = (d: Date | null | undefined) => (d ? d.toISOString().slice(0, 10) : '—');
export const fmtDateTime = (d: Date | null | undefined) => (d ? d.toISOString().replace('T', ' ').slice(0, 16) : '—');
export const ago = (d: Date | null, now = new Date()) => {
  if (!d) return 'never';
  const m = Math.round((now.getTime() - d.getTime()) / 60000);
  return m < 1 ? 'just now' : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : `${Math.round(m / 1440)} d ago`;
};
