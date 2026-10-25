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

/** Optional parts of the restaurant app that can be switched off per business (ids match the app's module ids). */
export const APP_MODULES: { id: string; label: string; hint: string }[] = [
  { id: 'tables', label: 'Tables (dine-in)', hint: 'Table map and table orders' },
  { id: 'kitchen', label: 'Kitchen display', hint: 'Kitchen screen for new orders' },
  { id: 'inventory', label: 'Inventory & recipes', hint: 'Stock, suppliers, purchases' },
  { id: 'customers', label: 'Customers & udhaar', hint: 'Customer list and credit sales' },
  { id: 'expenses', label: 'Expenses', hint: 'Daily expenses' },
  { id: 'staff', label: 'Staff & roles', hint: 'Staff accounts and permissions' },
  { id: 'tokens', label: 'Food tokens & coupons', hint: 'Order/tandoor/stall tokens, prepaid coupons' },
  { id: 'online', label: 'Online & phone orders', hint: 'WhatsApp / phone / delivery-app orders typed in and sent to the kitchen' },
];

/** What an admin can be allowed to do in the panel. Dashboard and Reminders are open to every admin. */
export const PANEL_SECTIONS: { id: string; label: string; hint: string }[] = [
  { id: 'restaurants', label: 'Restaurants', hint: 'Approve, change plan, status, modules, themes, notes' },
  { id: 'invoices', label: 'Invoices', hint: 'Create invoices, record payments' },
  { id: 'support', label: 'Support chat', hint: 'Read and answer restaurants' },
  { id: 'phones', label: 'Phones & map', hint: 'Approve, block and remove phones' },
  { id: 'notifications', label: 'Notifications', hint: 'Send notices to the app bell' },
  { id: 'settings', label: 'Settings', hint: 'Branding, app control, billing details' },
  { id: 'audit', label: 'Audit log', hint: 'Read and clean the log' },
  { id: 'admins', label: 'Admins', hint: 'Add admins and change their access' },
];
/** The panel page that needs each permission ('' = every admin). */
export const PAGE_PERM: Record<string, string> = { Dashboard: '', Reminders: '', Restaurants: 'restaurants', Invoices: 'invoices', Support: 'support', Phones: 'phones', Notifications: 'notifications', Settings: 'settings', Audit: 'audit', Admins: 'admins' };
export const DEFAULT_NEW_ADMIN_PERMS = ['restaurants', 'invoices', 'support', 'phones', 'notifications'];

export const NOTICE_KINDS = ['info', 'payment', 'update', 'warning', 'offer'] as const;
export type NoticeKind = (typeof NOTICE_KINDS)[number];
/** Ready-made notices: pick one, change the words if needed, send. */
export const NOTICE_TEMPLATES: { id: string; label: string; kind: NoticeKind; title: string; body: string }[] = [
  { id: 'payment', label: 'Payment reminder', kind: 'payment', title: 'Subscription payment due', body: 'Your DT Food POS subscription payment is due. Please pay on time so the app keeps working without interruption.' },
  { id: 'renewal', label: 'Renewal soon', kind: 'warning', title: 'Your subscription ends soon', body: 'Your DT Food POS licence is about to expire. Contact Digital Target to renew and avoid any stop in service.' },
  { id: 'update', label: 'New version', kind: 'update', title: 'New version available', body: 'A new version of DT Food POS is ready with improvements. Please update the app from the link we sent you.' },
  { id: 'maintenance', label: 'Maintenance', kind: 'warning', title: 'Short maintenance', body: 'We are doing a short maintenance. The app keeps working offline; online features may pause for a little while.' },
  { id: 'welcome', label: 'Welcome', kind: 'info', title: 'Welcome to DT Food POS', body: 'Thank you for choosing DT Food POS. Open Help & Tutorials in the side menu to learn the app, or write to Support any time.' },
  { id: 'offer', label: 'Offer', kind: 'offer', title: 'Special offer', body: 'A special offer is waiting for you. Contact Digital Target to know more.' },
];

/** The app's ready-made themes (ids match the app). main/accent/header/bg are only for the preview swatches. */
export const APP_THEMES: { id: string; label: string; main: string; accent: string; bg: string }[] = [
  { id: 'red', label: 'Restaurant Red (default)', main: '#C92A2A', accent: '#F59F00', bg: '#FBF5F5' },
  { id: 'red2', label: 'Restaurant Red 2', main: '#C41414', accent: '#C41414', bg: '#FAF7F7' },
  { id: 'green', label: 'Fresh Green', main: '#2B8A3E', accent: '#F08C00', bg: '#F3F8F4' },
  { id: 'golden', label: 'Golden Yellow', main: '#B7791F', accent: '#1F2937', bg: '#FBF8F1' },
  { id: 'yellow', label: 'Food Yellow', main: '#FFC107', accent: '#D9480F', bg: '#FFFBEB' },
  { id: 'coffee', label: 'Coffee Brown', main: '#6F4E37', accent: '#C8A27A', bg: '#F7F1EA' },
  { id: 'ocean', label: 'Ocean Blue', main: '#0B5FA5', accent: '#F59F00', bg: '#F2F6FB' },
  { id: 'blackgold', label: 'Luxury Black & Gold', main: '#D4AF37', accent: '#D4AF37', bg: '#121212' },
  { id: 'orange', label: 'Classic Orange', main: '#E8590C', accent: '#1E2A78', bg: '#FFF8F3' },
  { id: 'navy', label: 'Navy', main: '#1E2A78', accent: '#FF5A1F', bg: '#F4F5FB' },
  { id: 'teal', label: 'Teal', main: '#0F766E', accent: '#FF5A1F', bg: '#F1F8F7' },
  { id: 'rose', label: 'Rose', main: '#BE185D', accent: '#0F766E', bg: '#FDF2F7' },
  { id: 'rosegold', label: 'Rose Gold', main: '#9A4B5E', accent: '#A56E43', bg: '#FDF5F6' },
  { id: 'slate', label: 'Slate', main: '#334155', accent: '#FF5A1F', bg: '#F3F5F8' },
];

/** 'custom:MAIN,ACCENT,HEADER,BG,card,radius' (hex without #). Only main and accent are set from the panel. */
export function customThemeId(main: string, accent: string): string {
  const hex = (c: string) => c.replace('#', '').toUpperCase();
  return `custom:${hex(main)},${hex(accent)},,,outline,14`;
}
export function parseCustomTheme(id: string): { main: string; accent: string } | null {
  if (!id.startsWith('custom:')) return null;
  const p = id.slice(7).split(',');
  return /^[0-9A-Fa-f]{6}$/.test(p[0] ?? '') && /^[0-9A-Fa-f]{6}$/.test(p[1] ?? '') ? { main: '#' + p[0].toUpperCase(), accent: '#' + p[1].toUpperCase() } : null;
}
