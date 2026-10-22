-- DT Food POS: server database (PostgreSQL, designed for Supabase).
-- STATUS: written, NOT yet executed against a database. Run it on a Supabase branch and fix findings before use.
-- Tenancy: every business-owned row has business_id; row level security limits an app session to its own business.
-- Digital Target staff are platform admins (platform_admin table) and use the service role / security-definer functions.

create extension if not exists pgcrypto;

-- ---------- platform ----------
create table platform_admin (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','support','billing','viewer')),
  created_at timestamptz not null default now()
);

create table company_setting (            -- Digital Target details are configuration, never hard-coded guesses
  key text primary key, value text not null, updated_at timestamptz not null default now()
);

create table plan (
  id uuid primary key default gen_random_uuid(), name text not null,
  billing text not null check (billing in ('one_time','monthly')),
  price_minor bigint not null, currency char(3) not null,
  modules text[] not null default '{}', max_devices int not null default 1,
  offline_grace_days int not null default 7,       -- per-plan offline grace period (Super Admin configurable)
  active boolean not null default true
);

create type business_status as enum ('pending','approved','active','suspended','blocked','expired','payment_pending','rejected');

create table business (
  id uuid primary key default gen_random_uuid(),
  name text not null, owner_name text not null, phone text not null, email text, address text,
  country char(2) not null check (country in ('PK','AE')), currency char(3) not null default 'PKR',
  status business_status not null default 'pending',
  status_note text, approved_by uuid references auth.users(id), approved_at timestamptz,
  owner_user_id uuid references auth.users(id),
  created_at timestamptz not null default now()
);
create index business_status_ix on business(status);

create table device (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references business(id) on delete cascade,
  hardware_id_hash text not null,                  -- hash of an app-generated id, no IMEI/serial collected
  name text, os text, app_version text,
  status text not null default 'active' check (status in ('active','unbound','blocked')),
  last_seen_at timestamptz, fcm_token text, created_at timestamptz not null default now(),
  unique (business_id, hardware_id_hash)
);

create table license (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references business(id) on delete cascade,
  plan_id uuid not null references plan(id),
  status text not null check (status in ('active','suspended','blocked','expired')),
  modules text[] not null default '{}',
  starts_at timestamptz not null, expires_at timestamptz,
  offline_grace_days int not null,
  version int not null default 1,                  -- bump on every change; devices keep the highest version seen
  updated_at timestamptz not null default now()
);

-- consent-based location: rows exist only while the owner has granted permission
create table location_consent (
  device_id uuid primary key references device(id) on delete cascade,
  granted boolean not null, granted_at timestamptz, revoked_at timestamptz
);
create table device_location (
  device_id uuid primary key references device(id) on delete cascade,
  lat double precision not null, lng double precision not null, accuracy_m real,
  captured_at timestamptz not null
);

-- ---------- billing (Digital Target invoices to businesses) ----------
create table platform_invoice (
  id uuid primary key default gen_random_uuid(), number text not null unique,
  business_id uuid not null references business(id), kind text not null check (kind in ('license','subscription')),
  amount_minor bigint not null, discount_minor bigint not null default 0, currency char(3) not null,
  issued_at date not null default current_date, due_at date not null,
  status text not null default 'unpaid' check (status in ('unpaid','paid','overdue','void')),
  payment_instructions text, notes text
);
create table platform_payment (            -- financial record: never deleted
  id uuid primary key default gen_random_uuid(), invoice_id uuid not null references platform_invoice(id),
  amount_minor bigint not null, method text, reference text, received_at timestamptz not null default now(),
  recorded_by uuid references auth.users(id)
);

-- ---------- synced business data (mirror of the local tables; payload kept as jsonb to stay schema-flexible) ----------
create table sync_record (
  business_id uuid not null references business(id) on delete cascade,
  entity text not null, entity_id uuid not null,
  version int not null, deleted boolean not null default false,
  payload jsonb not null, updated_at timestamptz not null default now(),
  server_seq bigint generated always as identity,   -- pull cursor
  primary key (business_id, entity, entity_id)
);
create index sync_record_pull_ix on sync_record(business_id, server_seq);

create table applied_operation (           -- idempotency: a key is applied at most once, even after crashes/retries
  business_id uuid not null references business(id) on delete cascade,
  idempotency_key text not null, applied_at timestamptz not null default now(),
  primary key (business_id, idempotency_key)
);

create table daily_sales_summary (         -- totals only; order details are not shown to admins by default
  business_id uuid not null references business(id) on delete cascade, business_date date not null,
  gross_sales_minor bigint not null, refunds_minor bigint not null, net_sales_minor bigint not null,
  bills int not null, updated_at timestamptz not null default now(),
  primary key (business_id, business_date)
);

-- ---------- support, announcements ----------
create table support_thread (id uuid primary key default gen_random_uuid(), business_id uuid not null unique references business(id) on delete cascade, last_message_at timestamptz);
create table support_message (
  id uuid primary key default gen_random_uuid(), thread_id uuid not null references support_thread(id) on delete cascade,
  sender text not null check (sender in ('business','admin','assistant')), sender_user uuid,
  body text not null, created_at timestamptz not null default now(), delivered_at timestamptz, read_at timestamptz
);
create table announcement (
  id uuid primary key default gen_random_uuid(), title text not null, body text not null,
  critical boolean not null default false, audience jsonb not null default '{"all":true}', send_at timestamptz not null default now()
);

-- ---------- audit ----------
create table audit_log (
  id bigint generated always as identity primary key, at timestamptz not null default now(),
  business_id uuid, actor uuid, actor_kind text not null, action text not null, entity text, entity_id text,
  before jsonb, after jsonb, ip inet, device_id uuid, critical boolean not null default false
);
create rule audit_log_no_update as on update to audit_log do instead nothing;
create rule audit_log_no_delete as on delete to audit_log where old.critical do instead nothing;

-- ---------- row level security ----------
create function current_business() returns uuid language sql stable as
  $$ select (auth.jwt() -> 'app_metadata' ->> 'business_id')::uuid $$;
create function is_platform_admin() returns boolean language sql stable security definer as
  $$ select exists (select 1 from platform_admin where user_id = auth.uid()) $$;

alter table business enable row level security;
alter table device enable row level security;
alter table license enable row level security;
alter table sync_record enable row level security;
alter table applied_operation enable row level security;
alter table daily_sales_summary enable row level security;
alter table support_thread enable row level security;
alter table support_message enable row level security;
alter table platform_invoice enable row level security;
alter table audit_log enable row level security;

create policy own_business on business for select using (id = current_business() or is_platform_admin());
create policy own_devices on device for select using (business_id = current_business() or is_platform_admin());
create policy own_license on license for select using (business_id = current_business() or is_platform_admin());
create policy own_sync_read on sync_record for select using (business_id = current_business());
create policy own_summary on daily_sales_summary for select using (business_id = current_business() or is_platform_admin());
create policy own_thread on support_thread for all using (business_id = current_business() or is_platform_admin());
create policy own_messages on support_message for all using (
  exists (select 1 from support_thread t where t.id = thread_id and (t.business_id = current_business() or is_platform_admin())));
create policy own_invoices on platform_invoice for select using (business_id = current_business() or is_platform_admin());
create policy own_audit on audit_log for select using (business_id = current_business() or is_platform_admin());
-- Writes to sync_record / applied_operation / license / summaries go only through security-definer RPCs
-- (sync_push, license_command, ...) so idempotency and licence checks cannot be bypassed from the client.
