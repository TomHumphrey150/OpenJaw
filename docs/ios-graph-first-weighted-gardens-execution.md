# Telocare iOS Graph-First Architecture + Weighted Health Gardens

Last updated: 2026-02-27

## Goal
Complete the graph-first cutover so the runtime graph drives Habits, Progress, Map, and Guide behavior, while preserving existing backend table/RPC contracts and keeping document changes backward-compatible.

## Status Key
- `[x]` Done
- `[-]` In progress
- `[ ]` Remaining

## Running Tab

### 1) Core graph-first architecture
- [x] Add `GraphKernel` actor and patching interfaces (`GraphPatchApplier`, `GraphPatchValidator`, `GraphPatchRebaser`).
- [x] Add `GraphProjectionHub` scaffolding.
- [ ] Wire all major tab read models to projection outputs as primary source.
- [ ] Replace remaining direct graph/tab reads with projection subscriptions end-to-end.
- [ ] Ensure projection recompute/publish path is atomic and off-main where needed.

### 2) Data model and migration
- [x] Extend `GraphEdgeData` with `id` and `strength`.
- [x] Extend `CustomCausalDiagram` with `graphVersion` and `baseGraphVersion`.
- [x] Add `GraphAssociationRef` and optional event association fields.
- [x] Add progress question state/proposal/question types.
- [x] Add alias override/proposal types.
- [x] Add migration for edge ID inference, strength inference, and graph version initialization.
- [x] Add migration for initial `ProgressQuestionSetState`.
- [x] Ensure runtime writes persist new progress/alias state consistently.

### 3) Weighted recursive clustering (Habits)
- [x] Replace pathway-root hierarchy with graph-target affinity hierarchy.
- [x] Use weighted affinity: `|strength| * evidenceFactor`.
- [x] Keep informative clusters only (`0 < cluster < parent`).
- [x] Preserve overlap across siblings.
- [x] Deterministic ordering by weighted coverage, count, title/signature.
- [x] Cap top-level clusters to 6 via weighted-Jaccard deterministic merging.
- [x] Keep deep recursion and leaf current-garden behavior.

### 4) Naming, labels, and themes
- [x] Add deterministic `GardenNameResolver` with node/layer alias rules.
- [x] Add `GardenAliasCatalog`, `GardenAliasOverride`, and proposal types.
- [x] Add deterministic branch theme inheritance.
- [x] Use `Health Gardens` as Habits top-level title in hierarchy UI.
- [ ] Remove remaining pathway-era naming (`Roots/Canopy/Bloom`) from active user-facing surfaces.

### 5) Guide structured graph editing
- [x] Add JSON patch envelope codec and operation model.
- [x] Add parse/preview/apply/rollback/export command path in `AppViewModel`.
- [x] Add conflict detection and local/server conflict-resolution path in kernel.
- [x] Add visual diff presentation in Guide UI (summary + operation breakdown + explanations).
- [x] Add per-conflict UI controls with explicit user choices before apply.
- [x] Add visible checkpoint timeline/history controls in Guide UI.

### 6) Progress suggest-and-adopt flow
- [x] Add progress question state/proposal domain types.
- [x] Derive proposal on graph version change at runtime.
- [x] Show blocking one-time proposal prompt on entering Progress for new graph version.
- [x] Persist accept/decline decisions and suppress re-prompt until newer graph version.
- [ ] Keep historical lens behavior explicit in UI state.

### 7) Tests
- [x] Add graph-core unit tests for migration/validator/applier/rebaser.
- [x] Add weighted hierarchy tests including top-level cap.
- [x] Add naming resolver tests for 1/2/3+ layer rules and overrides.
- [ ] Add projection propagation tests across tabs.
- [ ] Add Progress proposal prompt tests (accept/decline cadence).
- [ ] Add Guide visual diff/conflict review/rollback UI tests.
- [ ] Add performance coverage for medium-scale graph/projection refresh.

### 8) Non-regression baseline
- [x] `xcodebuild ... build`
- [x] `xcodebuild ... -only-testing:TelocareTests test`
- [x] `xcodebuild ... -only-testing:TelocareUITests/TelocareUITests test`

Validated on 2026-02-27:
- `build` passed.
- `TelocareTests` passed: `219 tests`, `0 failures`.
- `TelocareUITests` passed: `25 tests`, `0 failures`.

## Current Focus
- [-] Complete projection-first consumption path and tests.
- [-] Clarify historical-lens/legacy-badge behavior in Progress UI state.
- [-] Add missing projection/proposal/Guide UI and performance test coverage.
