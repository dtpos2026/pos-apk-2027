-- DT Food POS backend. Everything lives in its own schema `dtfood`, so it can sit next to any other
-- application in the same Postgres database without touching its tables.
-- Multi-tenant: every business-owned row carries business_id and row level security keeps tenants apart.
-- Digital Target staff are rows in dtfood.platform_admin. Writes that must not be bypassed (sync, licence changes,
-- status changes) go through SECURITY DEFINER functions that check who is calling.

create schema if not exists dtfood;
create extension if not exists pgcrypto;

-- ---------- platform ----------
create table dtfood.platform_admin (
  user_id uuid primary key,
  role text not null check (role in ('owner','support','billing','viewer')),
  created_at timestamptz not null default now()
);

create table dtfood.company_setting (       -- Digital Target details are configuration, never hard-coded guesses
  key text primary key, value text not null, updated_at timestamptz not null default now()
);

create table dtfood.plan (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  billing text not null check (billing in ('one_time','monthly')),
  price_minor bigint not null check (price_minor >= 0), currency char(3) not null,
  modules text[] not null default '{}', max_devices int not null default 1 check (max_devices >= 1),
  offline_grace_days int not null default 7 check (offline_grace_days between 0 and 365),
  active boolean not null default true
);

create type dtfood.business_status as enum ('pending','approved','active','suspended','blocked','expired','payment_pending','rejected');

create table dtfood.business (
  id uuid primary key default gen_random_uuid(),
  name text not null, owner_name text not null, phone text not null, email text, address text,
  country char(2) not null check (country in ('PK','AE')), currency char(3) not null default 'PKR',
  status dtfood.business_status not null default 'pending',
  status_note text, decided_by uuid, decided_at timestamptz,
  owner_user_id uuid unique,
  created_at timestamptz not null default now()
);
create index business_status_ix on dtfood.business(status);

create table dtfood.device (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references dtfood.business(id) on delete cascade,
  hardware_id_hash text not null,                -- hash of an app-generated id; no IMEI or serial is collected
  name text, os text, app_version text,
  status text not null default 'active' check (status in ('active','unbound','blocked')),
  last_seen_at timestamptz, push_token text, created_at timestamptz not null default now(),
  unique (business_id, hardware_id_hash)
);

create table dtfood.license (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references dtfood.business(id) on delete cascade,
  plan_id uuid not null references dtfood.plan(id),
  status text not null check (status in ('active','suspended','blocked','expired')),
  modules text[] not null default '{}',
  starts_at timestamptz not null, expires_at timestamptz,
  offline_grace_days int not null check (offline_grace_days between 0 and 365),
  version int not null default 1,                -- bumped on every change; devices keep the highest they have seen
  token text,                                    -- signed licence (Ed25519), produced by the issue-license edge function
  updated_at timestamptz not null default now()
);
create index license_business_ix on dtfood.license(business_id);

create table dtfood.location_consent (
  device_id uuid primary key references dtfood.device(id) on delete cascade,
  granted boolean not null, granted_at timestamptz, revoked_at timestamptz
);
create table dtfood.device_location (          -- a row exists only while consent is granted
  device_id uuid primary key references dtfood.device(id) on delete cascade,
  lat double precision not null check (lat between -90 and 90), lng double precision not null check (lng between -180 and 180),
  accuracy_m real, captured_at timestamptz not null
);

-- ---------- billing (Digital Target invoices to businesses) ----------
create table dtfood.platform_invoice (
  id uuid primary key default gen_random_uuid(), number text not null unique,
  business_id uuid not null references dtfood.business(id),
  kind text not null check (kind in ('license','subscription')),
  amount_minor bigint not null check (amount_minor >= 0), discount_minor bigint not null default 0 check (discount_minor >= 0),
  currency char(3) not null, issued_at date not null default current_date, due_at date not null,
  status text not null default 'unpaid' check (status in ('unpaid','paid','overdue','void')),
  payment_instructions text, notes text
);
create table dtfood.platform_payment (          -- financial record: protected from deletion
  id uuid primary key default gen_random_uuid(), invoice_id uuid not null references dtfood.platform_invoice(id),
  amount_minor bigint not null check (amount_minor > 0), method text, reference text,
  received_at timestamptz not null default now(), recorded_by uuid
);

-- ---------- synced business data ----------
create table dtfood.sync_record (
  business_id uuid not null references dtfood.business(id) on delete cascade,
  entity text not null, entity_id text not null,
  version int not null, deleted boolean not null default false,
  payload jsonb not null, updated_at timestamptz not null default now(),
  server_seq bigint generated always as identity,
  primary key (business_id, entity, entity_id)
);
create index sync_record_pull_ix on dtfood.sync_record(business_id, server_seq);

create table dtfood.applied_operation (         -- idempotency: a key is applied at most once, even after crashes and retries
  business_id uuid not null references dtfood.business(id) on delete cascade,
  idempotency_key text not null, applied_at timestamptz not null default now(),
  primary key (business_id, idempotency_key)
);

create table dtfood.daily_sales_summary (       -- totals only; order details are not shown to admins by default
  business_id uuid not null references dtfood.business(id) on delete cascade, business_date date not null,
  gross_sales_minor bigint not null, refunds_minor bigint not null, net_sales_minor bigint not null,
  bills int not null, updated_at timestamptz not null default now(),
  primary key (business_id, business_date)
);

-- ---------- support and announcements ----------
create table dtfood.support_thread (id uuid primary key default gen_random_uuid(), business_id uuid not null unique references dtfood.business(id) on delete cascade, last_message_at timestamptz);
create table dtfood.support_message (
  id uuid primary key default gen_random_uuid(), thread_id uuid not null references dtfood.support_thread(id) on delete cascade,
  sender text not null check (sender in ('business','admin','assistant')), sender_user uuid,
  body text not null check (length(body) between 1 and 4000), created_at timestamptz not null default now(),
  delivered_at timestamptz, read_at timestamptz
);
create table dtfood.announcement (
  id uuid primary key default gen_random_uuid(), title text not null, body text not null,
  critical boolean not null default false, audience jsonb not null default '{"all":true}', send_at timestamptz not null default now()
);

-- ---------- audit (append-only) ----------
create table dtfood.audit_log (
  id bigint generated always as identity primary key, at timestamptz not null default now(),
  business_id uuid, actor uuid, actor_kind text not null, action text not null, entity text, entity_id text,
  before jsonb, after jsonb, ip inet, critical boolean not null default false
);
create function dtfood.audit_log_guard() returns trigger language plpgsql as $$
begin
  if tg_op = 'UPDATE' then raise exception 'audit_log is append-only'; end if;
  if tg_op = 'DELETE' and old.critical then raise exception 'critical audit rows cannot be deleted'; end if;
  return old;
end $$;
create trigger audit_log_guard_u before update on dtfood.audit_log for each row execute function dtfood.audit_log_guard();
create trigger audit_log_guard_d before delete on dtfood.audit_log for each row execute function dtfood.audit_log_guard();

create function dtfood.payment_guard() returns trigger language plpgsql as $$
begin raise exception 'platform_payment is a financial record and cannot be changed or deleted'; end $$;
create trigger platform_payment_guard before update or delete on dtfood.platform_payment for each row execute function dtfood.payment_guard();

-- ---------- identity helpers ----------
-- auth.uid() comes from Supabase Auth. The business of the caller is looked up from the server-side
-- owner_user_id column, never from anything the user can edit (so it also works right after registering).
create function dtfood.current_business() returns uuid language sql stable security definer set search_path = dtfood, public as
  $$ select id from dtfood.business where owner_user_id = auth.uid() $$;
create function dtfood.is_admin(min_roles text[] default array['owner','support','billing','viewer']) returns boolean
  language sql stable security definer set search_path = dtfood, public as
  $$ select exists (select 1 from dtfood.platform_admin where user_id = auth.uid() and role = any(min_roles)) $$;

create function dtfood.log(p_business uuid, p_actor_kind text, p_action text, p_entity text, p_entity_id text, p_before jsonb, p_after jsonb, p_critical boolean)
  returns void language sql security definer set search_path = dtfood, public as
  $$ insert into dtfood.audit_log(business_id, actor, actor_kind, action, entity, entity_id, before, after, critical)
     values (p_business, auth.uid(), p_actor_kind, p_action, p_entity, p_entity_id, p_before, p_after, p_critical) $$;

-- ---------- row level security ----------
do $$
declare t text;
begin
  foreach t in array array['platform_admin','company_setting','plan','business','device','license','location_consent','device_location','platform_invoice','platform_payment','sync_record','applied_operation','daily_sales_summary','support_thread','support_message','announcement','audit_log']
  loop execute format('alter table dtfood.%I enable row level security', t); end loop;
end $$;

create policy admin_read_admins on dtfood.platform_admin for select using (user_id = auth.uid() or dtfood.is_admin());
create policy read_company on dtfood.company_setting for select using (true);
create policy admin_write_company on dtfood.company_setting for all using (dtfood.is_admin(array['owner'])) with check (dtfood.is_admin(array['owner']));
create policy read_plan on dtfood.plan for select using (active or dtfood.is_admin());
create policy admin_write_plan on dtfood.plan for all using (dtfood.is_admin(array['owner','billing'])) with check (dtfood.is_admin(array['owner','billing']));
create policy own_business on dtfood.business for select using (id = dtfood.current_business() or dtfood.is_admin());
create policy own_devices on dtfood.device for select using (business_id = dtfood.current_business() or dtfood.is_admin());
create policy own_license on dtfood.license for select using (business_id = dtfood.current_business() or dtfood.is_admin());
create policy own_consent on dtfood.location_consent for select using (exists (select 1 from dtfood.device d where d.id = device_id and (d.business_id = dtfood.current_business() or dtfood.is_admin())));
-- location is visible to admins ONLY for devices whose owner has granted consent
create policy consented_location on dtfood.device_location for select using (
  dtfood.is_admin() and exists (select 1 from dtfood.location_consent c where c.device_id = device_location.device_id and c.granted));
create policy own_invoices on dtfood.platform_invoice for select using (business_id = dtfood.current_business() or dtfood.is_admin());
create policy own_payments on dtfood.platform_payment for select using (exists (select 1 from dtfood.platform_invoice i where i.id = invoice_id and (i.business_id = dtfood.current_business() or dtfood.is_admin())));
create policy own_sync_read on dtfood.sync_record for select using (business_id = dtfood.current_business());
create policy own_summary on dtfood.daily_sales_summary for select using (business_id = dtfood.current_business() or dtfood.is_admin());
create policy own_thread on dtfood.support_thread for select using (business_id = dtfood.current_business() or dtfood.is_admin());
create policy own_messages on dtfood.support_message for select using (exists (select 1 from dtfood.support_thread t where t.id = thread_id and (t.business_id = dtfood.current_business() or dtfood.is_admin())));
create policy read_announcements on dtfood.announcement for select using (true);
create policy admin_announce on dtfood.announcement for all using (dtfood.is_admin(array['owner','support'])) with check (dtfood.is_admin(array['owner','support']));
create policy own_audit on dtfood.audit_log for select using (business_id = dtfood.current_business() or dtfood.is_admin());
-- No insert/update/delete policies on the other tables: all writes go through the functions below.

-- ---------- functions (the only write paths) ----------
-- A business registers once; it stays 'pending' until Digital Target approves it.
create function dtfood.register_business(p_name text, p_owner text, p_phone text, p_email text, p_address text, p_country text)
returns uuid language plpgsql security definer set search_path = dtfood, public as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  if dtfood.current_business() is not null or exists (select 1 from dtfood.business where owner_user_id = auth.uid()) then
    raise exception 'this account already registered a business';
  end if;
  if length(trim(p_name)) = 0 or length(trim(p_owner)) = 0 or length(trim(p_phone)) = 0 then raise exception 'name, owner and phone are required'; end if;
  insert into dtfood.business(name, owner_name, phone, email, address, country, currency, owner_user_id)
    values (trim(p_name), trim(p_owner), trim(p_phone), p_email, p_address, p_country, case p_country when 'AE' then 'AED' else 'PKR' end, auth.uid())
    returning id into v_id;
  insert into dtfood.support_thread(business_id) values (v_id);
  perform dtfood.log(v_id, 'business', 'business.register', 'business', v_id::text, null, jsonb_build_object('name', p_name), false);
  return v_id;
end $$;

create function dtfood.admin_set_business_status(p_business uuid, p_status dtfood.business_status, p_note text)
returns void language plpgsql security definer set search_path = dtfood, public as $$
declare v_old dtfood.business_status;
begin
  if not dtfood.is_admin(array['owner','support']) then raise exception 'not allowed'; end if;
  select status into v_old from dtfood.business where id = p_business for update;
  if not found then raise exception 'business not found'; end if;
  if v_old in ('rejected') and p_status <> 'rejected' then raise exception 'a rejected registration cannot be revived: ask the business to register again'; end if;
  if p_status in ('rejected','suspended','blocked') and coalesce(trim(p_note), '') = '' then raise exception 'a note is required'; end if;
  update dtfood.business set status = p_status, status_note = p_note, decided_by = auth.uid(), decided_at = now() where id = p_business;
  -- a suspension or block also stops the licence: devices learn it the next time they are online
  if p_status in ('suspended','blocked') then
    update dtfood.license set status = p_status::text, version = version + 1, token = null, updated_at = now() where business_id = p_business and status = 'active';
  end if;
  perform dtfood.log(p_business, 'admin', 'business.status', 'business', p_business::text, jsonb_build_object('status', v_old), jsonb_build_object('status', p_status, 'note', p_note), true);
end $$;

-- Creates (or replaces) the licence row. The signed token is written afterwards by the edge function that holds the private key.
create function dtfood.admin_issue_license(p_business uuid, p_plan uuid, p_starts timestamptz, p_expires timestamptz, p_modules text[], p_grace int)
returns uuid language plpgsql security definer set search_path = dtfood, public as $$
declare v_plan dtfood.plan; v_status dtfood.business_status; v_id uuid;
begin
  if not dtfood.is_admin(array['owner','billing']) then raise exception 'not allowed'; end if;
  select * into v_plan from dtfood.plan where id = p_plan and active;
  if not found then raise exception 'plan not found'; end if;
  select status into v_status from dtfood.business where id = p_business;
  if not found then raise exception 'business not found'; end if;
  if v_status in ('pending','rejected','blocked') then raise exception 'business is %: approve it first', v_status; end if;
  if p_expires is not null and p_expires <= p_starts then raise exception 'expiry must be after the start'; end if;
  select id into v_id from dtfood.license where business_id = p_business order by updated_at desc limit 1;
  if v_id is null then
    insert into dtfood.license(business_id, plan_id, status, modules, starts_at, expires_at, offline_grace_days)
      values (p_business, p_plan, 'active', coalesce(p_modules, v_plan.modules), p_starts, p_expires, coalesce(p_grace, v_plan.offline_grace_days)) returning id into v_id;
  else
    update dtfood.license set plan_id = p_plan, status = 'active', modules = coalesce(p_modules, v_plan.modules), starts_at = p_starts, expires_at = p_expires,
      offline_grace_days = coalesce(p_grace, v_plan.offline_grace_days), version = version + 1, token = null, updated_at = now() where id = v_id;
  end if;
  update dtfood.business set status = 'active' where id = p_business and status in ('approved','payment_pending','expired','suspended');
  perform dtfood.log(p_business, 'admin', 'license.issue', 'license', v_id::text, null, jsonb_build_object('plan', v_plan.name, 'expires', p_expires), true);
  return v_id;
end $$;

create function dtfood.admin_set_license_status(p_license uuid, p_status text, p_note text)
returns void language plpgsql security definer set search_path = dtfood, public as $$
declare v_b uuid; v_old text;
begin
  if not dtfood.is_admin(array['owner','support','billing']) then raise exception 'not allowed'; end if;
  if p_status not in ('active','suspended','blocked','expired') then raise exception 'bad status'; end if;
  select business_id, status into v_b, v_old from dtfood.license where id = p_license for update;
  if not found then raise exception 'licence not found'; end if;
  update dtfood.license set status = p_status, version = version + 1, token = null, updated_at = now() where id = p_license;
  perform dtfood.log(v_b, 'admin', 'license.status', 'license', p_license::text, jsonb_build_object('status', v_old), jsonb_build_object('status', p_status, 'note', p_note), true);
end $$;

-- Called by the issue-license edge function (service role) after signing.
create function dtfood.store_license_token(p_license uuid, p_token text)
returns void language plpgsql security definer set search_path = dtfood, public as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role only'; end if;
  update dtfood.license set token = p_token where id = p_license;
end $$;

create function dtfood.admin_create_invoice(p_business uuid, p_kind text, p_amount bigint, p_discount bigint, p_due date, p_instructions text, p_notes text)
returns uuid language plpgsql security definer set search_path = dtfood, public as $$
declare v_id uuid; v_cur char(3); v_n text;
begin
  if not dtfood.is_admin(array['owner','billing']) then raise exception 'not allowed'; end if;
  if p_discount > p_amount then raise exception 'discount is more than the amount'; end if;
  select currency into v_cur from dtfood.business where id = p_business;
  if not found then raise exception 'business not found'; end if;
  v_n := 'DT-' || to_char(now(), 'YYYYMM') || '-' || lpad((select count(*) + 1 from dtfood.platform_invoice where number like 'DT-' || to_char(now(), 'YYYYMM') || '-%')::text, 4, '0');
  insert into dtfood.platform_invoice(number, business_id, kind, amount_minor, discount_minor, currency, due_at, payment_instructions, notes)
    values (v_n, p_business, p_kind, p_amount, coalesce(p_discount, 0), v_cur, p_due, p_instructions, p_notes) returning id into v_id;
  perform dtfood.log(p_business, 'admin', 'invoice.create', 'platform_invoice', v_id::text, null, jsonb_build_object('number', v_n, 'amount', p_amount), true);
  return v_id;
end $$;

create function dtfood.admin_record_payment(p_invoice uuid, p_amount bigint, p_method text, p_reference text)
returns void language plpgsql security definer set search_path = dtfood, public as $$
declare v_b uuid; v_due bigint; v_paid bigint;
begin
  if not dtfood.is_admin(array['owner','billing']) then raise exception 'not allowed'; end if;
  select business_id, amount_minor - discount_minor into v_b, v_due from dtfood.platform_invoice where id = p_invoice and status <> 'void' for update;
  if not found then raise exception 'invoice not found or void'; end if;
  select coalesce(sum(amount_minor), 0) into v_paid from dtfood.platform_payment where invoice_id = p_invoice;
  if v_paid + p_amount > v_due then raise exception 'payment is more than what is due'; end if;
  insert into dtfood.platform_payment(invoice_id, amount_minor, method, reference, recorded_by) values (p_invoice, p_amount, p_method, p_reference, auth.uid());
  if v_paid + p_amount = v_due then update dtfood.platform_invoice set status = 'paid' where id = p_invoice; end if;
  perform dtfood.log(v_b, 'admin', 'payment.record', 'platform_invoice', p_invoice::text, null, jsonb_build_object('amount', p_amount, 'method', p_method), true);
end $$;

create function dtfood.support_send(p_business uuid, p_body text)
returns uuid language plpgsql security definer set search_path = dtfood, public as $$
declare v_thread uuid; v_id uuid; v_sender text;
begin
  if dtfood.is_admin(array['owner','support']) then v_sender := 'admin';
  elsif p_business = dtfood.current_business() then v_sender := 'business';
  else raise exception 'not allowed'; end if;
  select id into v_thread from dtfood.support_thread where business_id = p_business;
  if v_thread is null then raise exception 'no thread'; end if;
  insert into dtfood.support_message(thread_id, sender, sender_user, body) values (v_thread, v_sender, auth.uid(), p_body) returning id into v_id;
  update dtfood.support_thread set last_message_at = now() where id = v_thread;
  return v_id;
end $$;

-- Device sync. Applies each change at most once (idempotency key) and refuses anything for a business whose
-- licence is not active, so a suspended business cannot keep pushing. Returns the keys it now holds.
create function dtfood.sync_push(p_items jsonb)
returns text[] language plpgsql security definer set search_path = dtfood, public as $$
declare v_b uuid := dtfood.current_business(); v_item jsonb; v_ack text[] := '{}'; v_key text; v_ok boolean;
begin
  if v_b is null then raise exception 'not a business account'; end if;
  if not exists (select 1 from dtfood.license where business_id = v_b and status = 'active' and (expires_at is null or expires_at > now())) then
    raise exception 'licence is not active';
  end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_key := v_item ->> 'key';
    insert into dtfood.applied_operation(business_id, idempotency_key) values (v_b, v_key) on conflict do nothing;
    get diagnostics v_ok = row_count;
    if v_ok then   -- first time we see this key: apply it
      insert into dtfood.sync_record(business_id, entity, entity_id, version, deleted, payload)
        values (v_b, v_item ->> 'entity', v_item ->> 'entity_id', coalesce((v_item ->> 'version')::int, 1), (v_item ->> 'op') = 'delete', coalesce(v_item -> 'payload', '{}'))
      on conflict (business_id, entity, entity_id) do update
        set version = excluded.version, deleted = excluded.deleted, payload = excluded.payload, updated_at = now()
        where dtfood.sync_record.version <= excluded.version;   -- an older change never overwrites a newer one
    end if;
    v_ack := v_ack || v_key;
  end loop;
  update dtfood.device set last_seen_at = now() where business_id = v_b and id::text = coalesce(nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-device-id', '');
  return v_ack;
end $$;

-- What the licence check on a device reads. A device only ever sees its own business.
create function dtfood.my_license() returns table (status text, modules text[], expires_at timestamptz, offline_grace_days int, version int, token text, server_time timestamptz)
language sql stable security definer set search_path = dtfood, public as $$
  select l.status, l.modules, l.expires_at, l.offline_grace_days, l.version, l.token, now()
  from dtfood.license l where l.business_id = dtfood.current_business() order by l.updated_at desc limit 1 $$;

create function dtfood.admin_dashboard() returns jsonb language plpgsql stable security definer set search_path = dtfood, public as $$
begin
  if not dtfood.is_admin() then raise exception 'not allowed'; end if;
  return jsonb_build_object(
    'businesses', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from dtfood.business group by status) s),
    'licenses', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from dtfood.license group by status) s),
    'devices', (select count(*) from dtfood.device),
    'sales_today', (select coalesce(sum(net_sales_minor), 0) from dtfood.daily_sales_summary where business_date = current_date),
    'unpaid_invoices', (select count(*) from dtfood.platform_invoice where status in ('unpaid','overdue')),
    'stale_sync', (select count(*) from dtfood.device where last_seen_at is null or last_seen_at < now() - interval '2 days'));
end $$;

-- Functions are callable by signed-in users only; each checks the caller itself.
revoke all on all functions in schema dtfood from public;
grant usage on schema dtfood to authenticated;
grant select on all tables in schema dtfood to authenticated;
grant execute on function dtfood.register_business, dtfood.admin_set_business_status, dtfood.admin_issue_license, dtfood.admin_set_license_status,
  dtfood.admin_create_invoice, dtfood.admin_record_payment, dtfood.support_send, dtfood.sync_push, dtfood.my_license, dtfood.admin_dashboard,
  dtfood.current_business, dtfood.is_admin to authenticated;
grant execute on function dtfood.store_license_token to service_role;
