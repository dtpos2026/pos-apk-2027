-- Run after auth_stub.sql + the migration:  psql -v ON_ERROR_STOP=1 -d <db> -f tests/0001_dtfood_test.sql
-- Each check raises on failure. Runs in one transaction and rolls back.
begin;
create temp table _ids(k text primary key, v text);
grant all on _ids to public;

create function pg_temp.as_user(u text, r text default 'authenticated') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u, true);
  perform set_config('request.jwt.claim.role', r, true);
end $$;
create function pg_temp.expect_error(q text, frag text) returns void language plpgsql as $$
begin
  begin execute q; exception when others then
    if sqlerrm like '%' || frag || '%' then return; end if;
    raise exception 'wrong error for [%]: %', q, sqlerrm;
  end;
  raise exception 'expected error "%" but succeeded: %', frag, q;
end $$;
create function pg_temp.ok(c boolean, m text) returns void language plpgsql as $$ begin if not coalesce(c,false) then raise exception 'FAILED: %', m; end if; end $$;

-- fixtures (as superuser)
insert into dtfood.platform_admin(user_id, role) values
 ('00000000-0000-0000-0000-0000000000a1','owner'),
 ('00000000-0000-0000-0000-0000000000a2','viewer'),
 ('00000000-0000-0000-0000-0000000000a3','billing');
insert into dtfood.plan(id, name, billing, price_minor, currency, modules) values
 ('11111111-1111-1111-1111-111111111111','Standard','one_time',5000000,'PKR','{pos,kitchen}');

set local role authenticated;

-- 1. two businesses register; both start pending
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
insert into _ids select 'biz1', dtfood.register_business('Biz One','Owner One','0300','a@x.pk','Addr','PK');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b2');
insert into _ids select 'biz2', dtfood.register_business('Biz Two','Owner Two','0301',null,null,'AE');
select pg_temp.expect_error($$select dtfood.register_business('Again','x','1',null,null,'PK')$$, 'already registered');
select pg_temp.ok((select status from dtfood.business where id = (select v::uuid from _ids where k='biz2')) = 'pending', 'new business is pending');
select pg_temp.ok((select currency from dtfood.business where id = (select v::uuid from _ids where k='biz2')) = 'AED', 'UAE currency');

-- 2. tenant isolation
select pg_temp.ok((select count(*) from dtfood.business) = 1, 'tenant sees only its own business row');
select pg_temp.ok((select name from dtfood.business) = 'Biz Two', 'tenant sees own business');
select pg_temp.expect_error($$update dtfood.business set status='active'$$, 'permission denied');

-- 3. non-admin cannot use admin functions
select pg_temp.expect_error(format($$select dtfood.admin_set_business_status(%L,'approved',null)$$, (select v from _ids where k='biz1')), 'not allowed');
select pg_temp.expect_error($$select dtfood.admin_dashboard()$$, 'not allowed');

-- 4. admin approvals
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');  -- viewer
select pg_temp.expect_error(format($$select dtfood.admin_set_business_status(%L,'approved',null)$$, (select v from _ids where k='biz1')), 'not allowed');
select pg_temp.ok((select count(*) from dtfood.business) = 2, 'admin sees all businesses');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select pg_temp.expect_error(format($$select dtfood.admin_set_business_status(%L,'rejected',' ')$$, (select v from _ids where k='biz2')), 'note is required');
select pg_temp.expect_error(format($$select dtfood.admin_issue_license(%L,%L,now(),now()+interval '1 year',null,null)$$, (select v from _ids where k='biz1'), '11111111-1111-1111-1111-111111111111'), 'approve it first');
select dtfood.admin_set_business_status((select v::uuid from _ids where k='biz1'),'approved','ok');
insert into _ids select 'lic1', dtfood.admin_issue_license((select v::uuid from _ids where k='biz1'),'11111111-1111-1111-1111-111111111111', now()-interval '1 day', now()+interval '1 year', null, null);
select pg_temp.ok((select status from dtfood.business where id=(select v::uuid from _ids where k='biz1')) = 'active', 'issuing a licence activates business');
select pg_temp.ok((select modules from dtfood.license limit 1) = '{pos,kitchen}', 'plan modules copied');
select pg_temp.expect_error(format($$select dtfood.admin_issue_license(%L,%L,now(),now()-interval '1 day',null,null)$$, (select v from _ids where k='biz1'), '11111111-1111-1111-1111-111111111111'), 'expiry must be after');
select pg_temp.expect_error($$select dtfood.store_license_token(gen_random_uuid(),'x')$$, 'permission denied');

-- 5. sync_push: only with an active licence, idempotent, newest version wins
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b2');
select pg_temp.expect_error($$select dtfood.sync_push('[]')$$, 'licence is not active');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select pg_temp.ok(dtfood.sync_push('[{"key":"k1","entity":"menu_item","entity_id":"m1","version":2,"op":"upsert","payload":{"name":"Tea"}}]') = '{k1}', 'ack key');
select dtfood.sync_push('[{"key":"k1","entity":"menu_item","entity_id":"m1","version":2,"op":"upsert","payload":{"name":"CHANGED"}}]');
select pg_temp.ok((select payload->>'name' from dtfood.sync_record where entity_id='m1') = 'Tea', 'replayed key is not applied twice');
select dtfood.sync_push('[{"key":"k2","entity":"menu_item","entity_id":"m1","version":1,"op":"upsert","payload":{"name":"Old"}}]');
select pg_temp.ok((select payload->>'name' from dtfood.sync_record where entity_id='m1') = 'Tea', 'older version never overwrites newer');
select dtfood.sync_push('[{"key":"k3","entity":"menu_item","entity_id":"m1","version":3,"op":"delete","payload":{}}]');
select pg_temp.ok((select deleted from dtfood.sync_record where entity_id='m1'), 'delete recorded');
select pg_temp.ok((select count(*) from dtfood.sync_record) = 1, 'tenant sees own sync rows');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b2');
select pg_temp.ok((select count(*) from dtfood.sync_record) = 0, 'other tenant sees no sync rows');
select pg_temp.expect_error($$insert into dtfood.sync_record(business_id,entity,entity_id,version,payload) select id,'x','y',1,'{}' from dtfood.business$$, 'permission denied');

-- 6. suspension stops the licence and sync
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select dtfood.admin_set_business_status((select v::uuid from _ids where k='biz1'),'suspended','unpaid');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select pg_temp.expect_error($$select dtfood.sync_push('[]')$$, 'licence is not active');
select pg_temp.ok((select status from dtfood.my_license()) = 'suspended', 'device sees suspended licence');
select pg_temp.ok((select token from dtfood.my_license()) is null, 'token cleared on suspension');

-- 7. invoices and payments
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.expect_error(format($$select dtfood.admin_create_invoice(%L,'license',100,0,current_date,null,null)$$, (select v from _ids where k='biz1')), 'not allowed');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a3');
insert into _ids select 'inv1', dtfood.admin_create_invoice((select v::uuid from _ids where k='biz1'),'license',10000,1000,current_date+7,'Bank','n');
select pg_temp.expect_error(format($$select dtfood.admin_record_payment(%L,9001,'bank',null)$$, (select v from _ids where k='inv1')), 'more than what is due');
select dtfood.admin_record_payment((select v::uuid from _ids where k='inv1'),4000,'bank','r1');
select pg_temp.ok((select status from dtfood.platform_invoice) = 'unpaid', 'partial payment leaves invoice unpaid');
select dtfood.admin_record_payment((select v::uuid from _ids where k='inv1'),5000,'bank','r2');
select pg_temp.ok((select status from dtfood.platform_invoice) = 'paid', 'full payment marks paid');
select pg_temp.expect_error($$delete from dtfood.platform_payment$$, 'permission denied');
reset role;
select pg_temp.expect_error($$delete from dtfood.platform_payment$$, '');
select pg_temp.expect_error($$update dtfood.audit_log set action='x'$$, '');
select pg_temp.expect_error($$delete from dtfood.audit_log$$, '');
select pg_temp.ok((select count(*) from dtfood.audit_log where critical) >= 4, 'critical actions audited');

-- 8. support: business and admin can talk, other tenants cannot
set local role authenticated;
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b2');
select dtfood.support_send((select v::uuid from _ids where k='biz2'),'help');
select pg_temp.expect_error(format($$select dtfood.support_send(%L,'spy')$$, (select v from _ids where k='biz1')), 'not allowed');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a1');
select dtfood.support_send((select v::uuid from _ids where k='biz2'),'hello');
select pg_temp.ok((select count(*) from dtfood.support_message) = 2, 'admin sees both messages');
select pg_temp.as_user('00000000-0000-0000-0000-0000000000b1');
select pg_temp.ok((select count(*) from dtfood.support_message) = 0, 'other tenant sees no messages');

-- 9. admin dashboard
select pg_temp.as_user('00000000-0000-0000-0000-0000000000a2');
select pg_temp.ok((dtfood.admin_dashboard() -> 'businesses' ->> 'suspended')::int = 1, 'dashboard counts');

rollback;
\echo ALL BACKEND TESTS PASSED
