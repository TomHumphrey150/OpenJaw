# Foundation Graph Expansion Plan (User-Specific, Report-Driven)

## Summary
Convert `docs/health_graph_report.md` into a full foundational causal layer on top of your existing acute graph for user `58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14`, add all missing report habits via canonical+trace mapping, store explicit habit-to-edge links, keep new habits available (not auto-active), expand pending outcome questions to 12, and add a measurement-roadmap stub section in Outcomes UI.

## Public Interfaces / Type Changes
1. Add a new patch CLI script and npm command:
   - [scripts/patch-user-foundation-graph.ts](/Users/tomhumphrey/src/OpenJaw/scripts/patch-user-foundation-graph.ts)
   - `npm run patch:user-foundation-graph -- --user-id <uuid> [--dry-run|--write] [--trace-out <path>]`
2. Extend intervention JSON schema (user_content override) with optional `graphEdgeIds: string[]` for explicit habit-to-edge attachments.
3. Upgrade graph audit output to include habit edge-link validation:
   - [scripts/debug-user-graph-audit.ts](/Users/tomhumphrey/src/OpenJaw/scripts/debug-user-graph-audit.ts)
   - bump `audit_version` to `user-graph-audit.v2`.
4. Add Outcomes measurement stub identifiers/UI hooks:
   - [ios/Telocare/Telocare/Sources/App/AccessibilityID.swift](/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/App/AccessibilityID.swift)
   - [ios/Telocare/Telocare/Sources/Features/Explore/Outcomes/ExploreOutcomesScreen.swift](/Users/tomhumphrey/src/OpenJaw/ios/Telocare/Telocare/Sources/Features/Explore/Outcomes/ExploreOutcomesScreen.swift)

## Implementation Plan
1. Create canonical habit mapping asset from report:
   - Add [data/health-report-habit-map.v1.json](/Users/tomhumrey/src/OpenJaw/data/health-report-habit-map.v1.json) with canonical habits, alias mentions, target node IDs, target edge IDs, pillar tags, planning tags.
   - Parse all Tier and Per-Pillar habit mentions; require 100% mention coverage by canonical map.
   - Include explicit loop templates for VC1–VC11, VV1–VV11, Compound 1–3 as graph edge specs.
2. Build user-specific graph merge logic:
   - Preserve existing graph nodes/edges.
   - Add foundational state/mechanism nodes and habit intervention nodes from mapping.
   - Add interlinks from loop templates and cross-pillar causal links.
   - Generate deterministic edge IDs (`edge:source|target|type|label#n`), preserve idempotency.
   - Recompute `graphVersion` with same FNV-1a algorithm used in app.
3. Build user-specific content/data merge logic:
   - Read current `user_data` and first-party/user-content catalog rows.
   - Upsert `user_content` `inputs/interventions_catalog` with merged `47 + new` interventions, including `graphNodeId`, `acuteTargets`, `graphEdgeIds`, `pillars`, `planningTags`.
   - Keep `activeInterventions` unchanged (new ones available but inactive).
   - Update `user_data.customCausalDiagram` with merged graph + version metadata.
4. Update outcome question proposal (12 total):
   - Keep existing 8 `morning.*` questions.
   - Append 4 new foundation questions tied to new foundation nodes and linked edges.
   - Set `progressQuestionSetState.pendingProposal` to new graph version and 12-question proposal; keep active set unchanged.
5. Add Outcomes measurement stub UI:
   - Add a non-interactive “Measurement roadmap” card in Progress tab with text-first planned measurement bundles.
   - No measurement nodes added to graph in this pass.
   - Add accessibility identifiers and one UI test assertion for stub presence.
6. Strengthen audit tooling:
   - Extend audit parser/output to validate `graphEdgeIds` existence and report missing habit edge sources.
   - Ensure post-patch audit can prove node+edge link integrity for habits and questions.

## Execution Runbook
1. Baseline:
   - `npm run debug:user-graph-audit -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --raw`
   - `npm run debug:pillar-integrity -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --raw`
2. Dry run:
   - `npm run patch:user-foundation-graph -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --dry-run --trace-out artifacts/foundation-trace-dry-run.json`
3. Apply:
   - `npm run patch:user-foundation-graph -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --write --trace-out artifacts/foundation-trace-write.json`
4. Verify:
   - `npm run debug:user-graph-audit -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --raw`
   - `npm run debug:pillar-integrity -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --strict --raw`
   - `npm run debug:foundation-coverage -- --user-id 58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14 --raw`
5. iOS validation:
   - `xcodebuild -workspace ios/Telocare/Telocare.xcworkspace -scheme Telocare -destination 'platform=iOS Simulator,name=iPhone 17' test`

## Test Cases / Acceptance Criteria
1. Report coverage test: every parsed habit mention maps to exactly one canonical habit.
2. Graph merge idempotency test: second dry-run after write reports zero additions.
3. Link integrity test: audit shows `habits_unlinked_count=0`, no missing habit node/edge links.
4. Outcome linkage test: `outcome_questions_total=12`, all linked, zero missing sources.
5. Regression check: existing acute node/edge IDs and existing 8 morning question IDs preserved.
6. UI test: Progress tab shows measurement roadmap stub (accessible non-visual text present).

## Assumptions and Defaults (Locked)
1. Canonical+trace dedupe is authoritative for “all habits mentioned”.
2. Keep planner at 10 pillars; no new Purpose pillar in planning policy.
3. Purpose/meaning habits are mapped into existing pillars (social/stress/financial as defined in mapping file).
4. New habits are added as available but not auto-activated.
5. Habit-to-edge links are stored in intervention extension field `graphEdgeIds`.
6. Changes are user-scoped only (`user_data` + `user_content` for authorized user); no global `first_party_content` mutation.
