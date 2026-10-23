// Pure rules shared by the pages (and unit tested). Money is integer minor units (paisa/fils).
export type Status = 'pending' | 'active' | 'payment_pending' | 'suspended' | 'blocked' | 'expired' | 'rejected';
export const STATUSES: Status[] = ['pending', 'active', 'payment_pending', 'suspended', 'blocked', 'expired', 'rejected'];
export const STATUS_LABEL: Record<Status, string> = {
  pending: 'Waiting for approval', active: 'Active', payment_pending: 'Payment pending', suspended: 'Suspended',
  blocked: 'Blocked', expired: 'Expired', rejected: 'Rejected',
};

export type PlanId = 'trial' | 'monthly' | 'quarterly' | 'half_yearly' | 'yearly' | 'lifetime' | 'custom';
export const PLANS: { id: PlanId; label: string; months?: number; days?: number }[] = [
  { id: 'trial', label: 'Trial (14 days)', days: 14 },
  { id: 'monthly', label: 'Monthly', months: 1 },
  { id: 'quarterly', label: '3 months', months: 3 },
  { id: 'half_yearly', label: '6 months', months: 6 },
  { id: 'yearly', label: 'Yearly', months: 12 },
  { id: 'lifetime', label: 'Lifetime' },
  { id: 'custom', label: 'Custom date' },
];

/** Adds calendar months, clamping the day (31 Jan + 1 month = 28/29 Feb). */
export function addMonths(d: Date, n: number): Date {
  const r = new Date(d.getTime());
  const day = r.getDate();
  r.setDate(1);
  r.setMonth(r.getMonth() + n);
  const last = new Date(r.getFullYear(), r.getMonth() + 1, 0).getDate();
  r.setDate(Math.min(day, last));
  return r;
}

/** New expiry for a plan. Renewals start from the current expiry when it is still in the future. Lifetime = null. */
export function expiryFor(plan: PlanId, now: Date, currentExpiry: Date | null, custom?: Date): Date | null {
  if (plan === 'lifetime') return null;
  if (plan === 'custom') {
    if (!custom || custom.getTime() <= now.getTime()) throw new Error('Pick a date in the future');
    return custom;
  }
  const spec = PLANS.find(p => p.id === plan)!;
  const base = currentExpiry && currentExpiry.getTime() > now.getTime() && plan !== 'trial' ? currentExpiry : now;
  if (spec.days) { const r = new Date(base.getTime()); r.setDate(r.getDate() + spec.days); return r; }
  return addMonths(base, spec.months!);
}

export function daysLeft(expiry: Date | null, now: Date): number | null {
  if (!expiry) return null;
  return Math.ceil((expiry.getTime() - now.getTime()) / 86_400_000);
}

/** Status the app should treat the account as right now (expiry is enforced even if the stored status is still active). */
export function effectiveStatus(status: Status, expiry: Date | null, now: Date): Status {
  if (status === 'active' && expiry && expiry.getTime() <= now.getTime()) return 'expired';
  return status;
}

export function customerId(n: number) { return 'DTC-' + String(n).padStart(4, '0'); }
export function invoiceNumber(now: Date, n: number) {
  return `DT-${String(now.getFullYear()).slice(2)}${String(now.getMonth() + 1).padStart(2, '0')}-${String(n).padStart(4, '0')}`;
}

export function money(minor: number, cur: string) {
  return `${cur} ${(minor / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}
export function parseMoneyToMinor(s: string): number {
  const t = s.replace(/,/g, '').trim();
  if (!/^\d+(\.\d{1,2})?$/.test(t)) throw new Error('Enter an amount like 1500 or 1500.50');
  const [w, f = ''] = t.split('.');
  return Number(w) * 100 + Number((f + '00').slice(0, 2));
}

/** Fills {owner} {business} {amount} {expiry} {customerId} in a reminder message. */
export function fillTemplate(t: string, v: Record<string, string>): string {
  return t.replace(/\{(\w+)\}/g, (m, k) => (k in v ? v[k] : m));
}
export function whatsappLink(phone: string, text: string): string {
  const digits = phone.replace(/[^\d]/g, '').replace(/^0+/, '');
  return `https://wa.me/${digits}?text=${encodeURIComponent(text)}`;
}

export const ONLINE_WINDOW_MS = 5 * 60_000;
export function isOnline(lastSeen: Date | null, now: Date) { return !!lastSeen && now.getTime() - lastSeen.getTime() <= ONLINE_WINDOW_MS; }

/** YYYY-MM-DD in the browser's local time zone (the app also keys days by local date). */
export function localDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** Totals per currency, never added across currencies: "PKR 1,200.00 · AED 50.00". */
export function sumByCurrency(rows: { minor: number; currency: string }[]): string {
  const m = new Map<string, number>();
  for (const r of rows) m.set(r.currency, (m.get(r.currency) ?? 0) + r.minor);
  if (m.size === 0) return '0';
  return [...m.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([c, v]) => money(v, c)).join(' · ');
}
