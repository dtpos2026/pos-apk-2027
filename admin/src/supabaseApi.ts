import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { AdminApi } from './api';
import type { AppConfig } from './config';

export function createSupabaseApi(cfg: AppConfig): AdminApi {
  const sb: SupabaseClient<any, any, any> = createClient(cfg.supabaseUrl, cfg.supabaseAnonKey, { db: { schema: 'dtfood' } });
  const ok = <T,>(r: { data: T | null; error: { message: string } | null }): T => {
    if (r.error) throw new Error(r.error.message);
    return r.data as T;
  };
  const rpc = async (fn: string, args: Record<string, unknown>) => { ok(await sb.rpc(fn, args)); };
  return {
    async signIn(email, password) { const { error } = await sb.auth.signInWithPassword({ email, password }); if (error) throw new Error(error.message); },
    async signOut() { await sb.auth.signOut(); },
    async myRole() {
      const { data: u } = await sb.auth.getUser();
      if (!u.user) return null;
      const r = await sb.from('platform_admin').select('role').eq('user_id', u.user.id).maybeSingle();
      return r.error ? null : (r.data?.role as string | undefined) ?? null;
    },
    async dashboard() { return ok(await sb.rpc('admin_dashboard')); },
    async businesses() { return ok(await sb.from('business').select('*').order('created_at', { ascending: false })); },
    setBusinessStatus: (id, status, note) => rpc('admin_set_business_status', { p_business: id, p_status: status, p_note: note || null }),
    async plans() { return ok(await sb.from('plan').select('*').order('name')); },
    async licenses() { return ok(await sb.from('license').select('*').order('updated_at', { ascending: false })); },
    issueLicense: (b, p, s, e) => rpc('admin_issue_license', { p_business: b, p_plan: p, p_starts: s, p_expires: e, p_modules: null, p_grace: null }),
    setLicenseStatus: (id, status, note) => rpc('admin_set_license_status', { p_license: id, p_status: status, p_note: note || null }),
    async invoices() { return ok(await sb.from('platform_invoice').select('*').order('issued_at', { ascending: false })); },
    createInvoice: (b, kind, amt, disc, due, ins) => rpc('admin_create_invoice', { p_business: b, p_kind: kind, p_amount: amt, p_discount: disc, p_due: due, p_instructions: ins || null, p_notes: null }),
    recordPayment: (i, a, m, r) => rpc('admin_record_payment', { p_invoice: i, p_amount: a, p_method: m, p_reference: r || null }),
    async threads() { return ok(await sb.from('support_thread').select('*').order('last_message_at', { ascending: false, nullsFirst: false })); },
    async messages(t) { return ok(await sb.from('support_message').select('*').eq('thread_id', t).order('created_at')); },
    sendSupport: (b, body) => rpc('support_send', { p_business: b, p_body: body }),
    async audit() { return ok(await sb.from('audit_log').select('id,at,actor_kind,action,entity,entity_id,business_id').order('id', { ascending: false }).limit(200)); },
    async company() { const rows = ok(await sb.from('company_setting').select('key,value')) as { key: string; value: string }[]; return Object.fromEntries(rows.map(r => [r.key, r.value])); },
    async setCompany(key, value) { ok(await sb.from('company_setting').upsert({ key, value, updated_at: new Date().toISOString() })); },
  };
}
