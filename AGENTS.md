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
