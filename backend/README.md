# Backend (Supabase / Postgres)
- `supabase/migrations/0001_dtfood.sql` – schema `dtfood`, row level security, SECURITY DEFINER write functions.
- `supabase/functions/issue-license` – Ed25519 licence signing (not yet run on a deployed project).
- `tests/run.sh` – applies the migration to a throwaway local Postgres (using `tests/auth_stub.sql` instead of Supabase Auth) and runs `tests/0001_dtfood_test.sql`: tenant isolation, admin-only functions, idempotent sync, licence gating, append-only audit/payments.
The stub only imitates `auth.uid()`; behaviour against real Supabase Auth is untested.
Nothing in this folder has been applied to any live Supabase project.
