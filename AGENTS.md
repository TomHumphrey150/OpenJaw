# Repository Instructions

## Scope
These instructions apply to the entire repository rooted at `/Users/tomhumphrey/src/OpenJaw`.

## Supabase Schema Workflow
- Vercel deployments do not apply Supabase schema changes.
- Apply database schema updates manually from local machine with Supabase CLI.
- Required flow for schema changes:
  1. Create/update migration SQL in `supabase/migrations/`.
  2. Link CLI to project:
     - `npx supabase login`
     - `npx supabase link --project-ref aocndwnnkffumisprifx`
  3. Push migrations:
     - `npx supabase db push`
  4. Verify applied migrations:
     - `npx supabase migration list`

## Commit vs Ignore Rules
- Commit:
  - `supabase/migrations/*.sql`
  - App code/docs/test changes related to migration behavior.
- Ignore:
  - `supabase/.temp/*` (local Supabase CLI state, machine-specific metadata).

## Data Sync Contract
- Personal app data is stored per-user in Supabase table `public.user_data` as a JSONB document.
- Row-level security (RLS) must remain enabled so users can only access their own row.

## Supabase Debug Access (Agent Runbook)
- Use the local diagnostics script for read-only inspection:
  - `npm run debug:user-data -- --list-users --limit 20`
  - `npm run debug:user-data -- --user-id <uuid>`
- The script file is `scripts/debug-user-data.mjs`.
- It reads credentials from `.env.local` (auto-loaded by the npm script):
  - `SUPABASE_URL=https://aocndwnnkffumisprifx.supabase.co`
  - `SUPABASE_SECRET_KEY=sb_secret_...`
  - `SUPABASE_DEBUG_USER_ID=<uuid>` (optional default for `--user-id`)
- For richer output, use:
  - `--window-days <n>` to change rolling window analysis
  - `--raw` to print raw JSON payloads
- Security rules:
  - Never commit secrets to git.
  - Keep `.env.local` local only (already gitignored).
  - Prefer a temporary secret key for debugging and rotate/revoke it after use.
- In sandboxed Codex environments, networked Supabase calls may require escalated command permissions.
