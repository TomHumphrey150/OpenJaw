# Telocare iOS Refactor Target Architecture

## Dependency rules

1. `RootViewModel` may depend on:
   - `AuthClient`
   - `SessionHydrationUseCase`
   - UI announcer and local preference persistence closures

2. `SessionHydrationUseCase` may depend on:
   - `UserDataRepository`
   - `UserDataMigrationPipeline`
   - `RootDashboardFactory`

3. `UserDataMigrationPipeline` is pure transformation logic:
   - Inputs: fetched user document + first-party content
   - Outputs: migrated document + side-effect intents (backfill/patch)

4. `RootDashboardFactory` is object assembly only:
   - Builds `DashboardSnapshot`
   - Builds `AppViewModel`

5. `AppViewModel` is coordinator-only:
   - Publishes state
   - Delegates mutation computations to `Sources/App/Logic/*`
   - Owns operation-token rollback semantics

6. Mutation services are deterministic and side-effect free except async health-reference fetch and error mapping coordinators:
   - `GraphMutationService`
   - `InputMutationService`
   - `MorningOutcomeMutationService`
   - `AppleHealthSyncCoordinator`
   - `MuseSessionCoordinator`

7. Views in `Sources/Features/Explore/*` should render and emit intents only.

## Guardrails

- Preserve `UserDataPatch` payload keys and `UserDataDocument` schema field names.
- Preserve all `AccessibilityID` identifiers and user-visible strings unless explicitly requested.
- Use `scripts/guard-ios-hotspots.sh` in CI to stop hotspot file growth beyond agreed line limits.

## Review checklist additions

- New business mutation logic belongs in `Sources/App/Logic`, not directly in `AppViewModel`.
- New tab/screen UI belongs in `Sources/Features/Explore/<Domain>/` and keeps `ExploreTabShell` composition-only.
- Every migration change requires explicit tests for:
  - canonical graph backfill behavior
  - dormant graph migration behavior
  - wake-day sleep attribution migration behavior
