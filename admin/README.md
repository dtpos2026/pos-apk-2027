# DT Food POS – Super Admin panel

React + Vite + TypeScript. No data is built in: it reads `config.json` at runtime and talks to **your** Supabase project.

## Configure
1. Create/choose a Supabase project (a *new* one is recommended; do not reuse a project that holds other live data).
2. Apply `backend/supabase/migrations/0001_dtfood.sql` (SQL editor or `supabase db push`).
3. In Supabase → Settings → API → **Exposed schemas**, add `dtfood`.
4. Create your admin user in Supabase Auth, then run once in the SQL editor:
   `insert into dtfood.platform_admin(user_id, role) values ('<that user id>', 'owner');`
5. Copy `public/config.example.json` to `public/config.json` (or put `config.json` next to the built `index.html`) and fill in `supabaseUrl` and `supabaseAnonKey` (the public anon key; never the service-role key).
6. `npm install && npm run build`; host the `dist/` folder on any static host.

Without a valid `config.json` the panel shows a "Setup needed" screen and no data.

## Licence signing
Deploy `backend/supabase/functions/issue-license` and set the secret `LICENSE_PRIVATE_KEY_PKCS8` (base64 Ed25519 PKCS#8). The matching public key goes into the app build. The function has not been run against a deployed project yet.

## Not done yet
TOTP two-factor login (Supabase MFA), announcements UI, device list, consent-based location map, plan editor, and PDF invoices. Tested: config validation, login gate, approve/reject flow, role-limited settings (`npm test`).
