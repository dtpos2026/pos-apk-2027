"""Loads docs/schema/local.sql into SQLite and checks the append-only guards. Run: python3 -I tool/check_schema.py"""
import sqlite3, sys, pathlib
sql = (pathlib.Path(__file__).resolve().parent.parent / "docs/schema/local.sql").read_text()
c = sqlite3.connect(":memory:"); c.executescript(sql)
def fails(q, *a):
    try: c.execute(q, *a); return False
    except sqlite3.DatabaseError: return True
c.execute("insert into role(id,name,permissions,updated_at) values('r','owner','[]',1)")
c.execute("insert into staff(id,name,role_id,pin_hash,pin_salt,updated_at) values('s','A','r','h','x',1)")
c.execute("insert into payment_method(id,name,kind,updated_at) values('pm','Cash','cash',1)")
c.execute("""insert into "order"(id,order_type,status,business_date,created_at,updated_at) values('o','counter','paid','2026-01-01',1,1)""")
c.execute("insert into payment(id,order_id,method_id,method_kind,amount_minor,created_at) values('p','o','pm','cash',100,1)")
checks = {
  "payment update blocked": fails("update payment set amount_minor=1"),
  "payment delete blocked": fails("delete from payment"),
  "audit update blocked": (c.execute("insert into audit_log(id,at,action,critical) values('a',1,'x',1)") or fails("update audit_log set action='y'")),
  "critical audit delete blocked": fails("delete from audit_log"),
  "negative qty rejected": fails("""insert into order_item(id,order_id,product_id,name,qty_milli,unit_price_minor,line_total_minor) values('i','o','nope','n',0,1,1)"""),
  "duplicate idempotency key rejected": (c.execute("insert into outbox(idempotency_key,entity,entity_id,op,payload,created_at) values('k','order','o','upsert','{}',1)") or fails("insert into outbox(idempotency_key,entity,entity_id,op,payload,created_at) values('k','order','o','upsert','{}',1)")),
}
bad = [k for k, v in checks.items() if not v]
for k, v in checks.items(): print("PASS" if v else "FAIL", k)
sys.exit(1 if bad else 0)
