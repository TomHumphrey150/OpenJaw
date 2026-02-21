# Repository Instructions

## Scope
These instructions apply to the entire repository rooted at `/Users/tomhumphrey/src/OpenJaw`.

## Ethos
Write the strictest, cleanest code possible. If the code needs a comment to be understood, rewrite the code.

No escape hatches. No `any`. No `as` casts. No `@ts-ignore`. No loosening a rule because it's inconvenient.

Flat control flow. Minimal nesting. Early returns. Small functions that do one thing. Names that make intent obvious.

No TODOs. No dead code. No commented-out blocks.

Catch every mistake at build time. If a class of bug can be prevented statically, prevent it.

Research before writing. Do not guess. Read the actual documentation, check the actual versions, then implement.

Explicit over implicit. If something is configured, pin it. No ambient magic and no unverified defaults.

Modern over legacy. Use current stable APIs and patterns.

Every file does one thing. Every function does one thing. Every module has a clear boundary.

## Accessibility Baseline
Assume teammates and users may be completely blind.

Text is the source of truth for understanding, setup, testing, operations, QA, and design.

No critical workflow may depend on sight alone.

Graphical interfaces are welcome, but they must remain fully operable non-visually through platform assistive technologies.

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

## Library
Reference documents for this repository:

| Document | Purpose |
| --- | --- |
| `docs/text-first-collaboration.md` | Standards for text-first workflows and blind-operable engineering/QA/design. |
| `docs/pr-checklist.md` | PR checklist template and note-linking requirements. |
| `docs/pr-notes/AGENTS.md` | Rules for append-only PR notes and timestamped evidence files. |
| `ios/AGENTS.md` | iOS-specific engineering and accessibility baseline. |
