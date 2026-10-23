// Edge function: signs a licence with the Ed25519 private key and stores the token.
// Needs secrets: LICENSE_PRIVATE_KEY_PKCS8 (base64 PKCS#8 Ed25519 key). The key never leaves Supabase secrets.
// Called by the panel with the admin's session token; the licence row must already exist (dtfood.admin_issue_license).
// UNTESTED against a deployed project: only the SQL side is tested. The payload fields mirror LicensePayload.fromJson in app/lib/domain/license.dart.
import { createClient } from 'npm:@supabase/supabase-js@2';

const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
const b64url = (u: Uint8Array) => b64(u).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const fromB64 = (s: string) => Uint8Array.from(atob(s), c => c.charCodeAt(0));

Deno.serve(async (req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const asUser = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } }, db: { schema: 'dtfood' },
  });
  const { licenseId } = await req.json();
  // RLS + is_admin: a non-staff caller cannot read the licence, so nothing is signed for them.
  const { data: staff } = await asUser.rpc('is_admin', { min_roles: ['owner', 'billing'] });
  if (!staff) return new Response('forbidden', { status: 403 });
  const { data: lic, error } = await asUser.from('license').select('*').eq('id', licenseId).single();
  if (error || !lic) return new Response('licence not found', { status: 404 });

  const { data: plan } = await asUser.from('plan').select('name').eq('id', lic.plan_id).single();
  const { data: devices } = await asUser.from('device').select('hardware_id_hash').eq('business_id', lic.business_id).eq('status', 'active');
  const secs = (t: string | null) => (t ? Math.floor(new Date(t).getTime() / 1000) : null);
  // Field names match LicensePayload.fromJson in app/lib/domain/license.dart.
  const payload = {
    bid: lic.business_id, dev: (devices ?? []).map((d: { hardware_id_hash: string }) => d.hardware_id_hash),
    mod: lic.modules, plan: plan?.name ?? '', st: lic.status, grace: lic.offline_grace_days, ver: lic.version,
    iat: Math.floor(Date.now() / 1000), exp: secs(lic.expires_at),
  };
  const body = new TextEncoder().encode(JSON.stringify(payload));
  const key = await crypto.subtle.importKey('pkcs8', fromB64(Deno.env.get('LICENSE_PRIVATE_KEY_PKCS8')!), { name: 'Ed25519' }, false, ['sign']);
  const sig = new Uint8Array(await crypto.subtle.sign('Ed25519', key, body));
  const token = `${b64url(body)}.${b64url(sig)}`;

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { db: { schema: 'dtfood' } });
  const { error: e2 } = await admin.rpc('store_license_token', { p_license: lic.id, p_token: token });
  if (e2) return new Response(e2.message, { status: 500 });
  return Response.json({ ok: true, version: lic.version });
});
