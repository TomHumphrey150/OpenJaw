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
  - `artifacts/*` (generated diagnostics, audits, snapshots).

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

## Supabase User-Data Mutation Policy
- Direct mutation of `public.user_data` is allowed only for user ID `58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14` during Telocare maintenance.
- Never mutate any other user row without explicit per-run authorization.
- Use a dry run first, then apply writes only after confirming the targeted diff.

## Script Runbook (Data Audit + Graph Maintenance)
- `npm run debug:user-data -- --list-users --limit 20`
  - Lists recent users in `public.user_data` for targeting.
- `npm run debug:user-data -- --user-id <uuid> [--window-days <n>] [--raw]`
  - Read-only inspection of one user row (counts, recent activity, raw JSON).
- `npm run debug:pillar-integrity -- --user-id <uuid> [--pillar <pillar-id>] [--strict] [--report-out <path>] [--raw]`
  - Read-only pillar integrity audit using interventions catalog + planning policy + canonical graph.
  - Reports interventions per pillar, active coverage per pillar, pillar node sets, missing node IDs in user graph, missing canonical edges, and per-pillar connectivity.
  - `--strict` exits non-zero when missing nodes/edges/disconnected pillar nodes exist.
- `npm run debug:user-graph-audit -- --user-id <uuid> [--report-out <path>] [--raw] [--pretty true|false]`
  - Read-only provenance-first graph audit for one user.
  - Emits one JSON bundle with graph nodes/edges, habit-to-graph links, outcome-question-to-graph links (from `progressQuestionSetState.pendingProposal.questions`), compact summary counts, strict validation results, and inline source references (`source_ref` + `provenance.refs`).
  - Exit codes: `0` success, `1` runtime/config/query error, `2` strict schema validation failure.
- `npm run debug:user-pillar-audit -- --user-id <uuid> --pillar <pillar-id> [--report-out <path>] [--raw] [--pretty true|false]`
  - Read-only pillar-scoped audit wrapper over `debug:user-graph-audit`.
  - Emits pillar-filtered nodes/edges, habits, and outcome question links for fast diagnosis without full-user payload review.
- `npm run snapshot:user-pillar-graphs -- --user-id <uuid> [--pillar <pillar-id>] [--pillars <a,b,c>] [--out <path>] [--include-isolated] [--no-compact-tiers] [--show-interventions] [--show-feedback] [--show-protective] [--width <px>] [--height <px>] [--scale <n>]`
  - Read-only pillar graph screenshot generator using `ios/Telocare/Telocare/Resources/Graph/index.html`.
  - Writes one PNG per pillar and a `manifest.json` with raw vs rendered node/edge counts under `artifacts/user-pillar-snapshots/` unless `--out` overrides.
  - Default render compaction removes isolated nodes and compacts sparse tiers for readability; use `--include-isolated` and/or `--no-compact-tiers` for full-fidelity debug views.
- `npm run patch:user-graph -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --dry-run`
  - Read-only preview of additive canonical graph merge for social/relationship/financial nodes and edges.
- `npm run patch:user-graph -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --write`
  - Applies the same additive merge to `public.user_data.data.customCausalDiagram.graphData` for the authorized user only.
  - Idempotent: repeat runs should be zero-op after first successful write.
- `npm run debug:foundation-coverage -- --user-id <uuid> [--report-out <path>] [--raw]`
  - Read-only foundation/acute coverage audit by pillar and mapping source.
- `npm run debug:graph-clusters -- --user-id <uuid> [--max-depth <n>] [--report-out <path>]`
  - Read-only graph-cluster introspection for map connectivity and neighborhood analysis.

## Mermaid Graph Debug Runbook (Text-First AI Diagnostics)
- Purpose:
  - Generate text-native graph projections that are easier/faster for AI structural reasoning than raw JSON.
  - Keep a renderable local viewer for human inspection when needed.
- Primary commands:
  - Full graph Mermaid from DB user row:
    - `npm run graph:to-mermaid -- --user-id <uuid> --out artifacts/user-graph.mmd`
  - Pillar-scoped Mermaid from DB user row (preferred first step for large graphs):
    - `npm run graph:to-mermaid -- --user-id <uuid> --pillar <pillar-id> --out artifacts/user-graph-<pillar>.mmd`
  - Local gallery build (timestamp-sorted diagram picker):
    - `npm run mermaid:gallery`
    - Output: `artifacts/mermaid-gallery/index.html`
- Behavior and limits:
  - `graph:to-mermaid` validates syntax using Mermaid parser before writing output (unless `--no-validate`).
  - `--pillar` uses `debug:user-graph-audit` + pillar filtering to derive a smaller focused subgraph.
  - `--pillar` requires `--user-id` (or `SUPABASE_DEBUG_USER_ID`) and cannot be combined with `--graph-path`.
  - Local gallery initializes Mermaid with raised secure limits:
    - `maxEdges: 20000`
    - `maxTextSize: 2000000`
  - This avoids common Mermaid website failures such as edge/text-size cap errors.
- When to use Mermaid vs JSON:
  - Use Mermaid first for topology/causal-flow debugging and quick AI context.
  - Use JSON for exact field-level validation (`disclosureLevel`, `parentIds`, `isDeactivated`, IDs, mappings).
  - Treat Mermaid as a derived/debug representation, not source of truth.
- Current measured size example (user `58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14`, measured March 1, 2026):
  - Graph JSON payload: `373,972` bytes (~`93,493` tokens).
  - Full Mermaid output: `214,095` bytes (~`53,524` tokens).
  - Mermaid was ~43% smaller for AI context in this case.

## Required Order for User Graph Patch
1. Run `debug:pillar-integrity` for baseline.
2. Run `patch:user-graph --dry-run`.
3. Run `patch:user-graph --write` only after confirming diff.
4. Re-run `debug:pillar-integrity --strict` and confirm zero missing nodes/edges for targeted pillars.

## Library
Reference documents for this repository:

| Document | Purpose |
| --- | --- |
| `docs/text-first-collaboration.md` | Standards for text-first workflows and blind-operable engineering/QA/design. |
| `docs/pr-checklist.md` | PR checklist template and note-linking requirements. |
| `docs/pr-notes/AGENTS.md` | Rules for append-only PR notes and timestamped evidence files. |
| `ios/AGENTS.md` | iOS-specific engineering and accessibility baseline. |
