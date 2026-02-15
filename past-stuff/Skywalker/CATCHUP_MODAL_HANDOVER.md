# Catch‑Up Tinder Modal — Handover

## Overview
We added a **catch‑up modal** that appears when the app becomes active and there are **undecided, incomplete interventions** from the **last 24 hours** (excluding Anytime). The modal presents a Tinder‑style deck of cards. Users can **swipe right = done**, **swipe left = skipped**, and for counter‑type interventions they can adjust a count before swiping. The existing time‑of‑day home UI remains unchanged.

This document explains what we built, why we built it, how it works, and where the logic lives.

---

## Goals & Product Intent
- **Fast catch‑up**: avoid tapping through items one‑by‑one when returning to the app after missing a section.
- **Time‑aware**: show cards only from past sections in the last 24 hours and **label them by section + day** (e.g., “Morning yesterday”).
- **No duplicates**: anything already completed on the home screen should **not** show in the card deck.
- **Low friction**: allow swipe‑down dismissal at any time; this is a catch‑up helper, not a gate.
- **Hints**: show Apple Health hints for exercise, hydration, and mindfulness to jog memory; if not authorized, show a “Connect” button.

---

## What We Looked Up
We referenced standard SwiftUI stack layout patterns for ZStack/stacked cards and gesture handling in a Tinder‑style UI.

Reference (URL shown for handover completeness):
```
https://developer.apple.com/cn/documentation/swiftui/building-layouts-with-stack-views/
```

---

## Key Behavior (Business Logic)
### Time‑of‑day schedule
- **Morning**: 5am–12pm
- **Afternoon**: 12pm–5pm
- **Evening**: 5pm–9pm
- **Pre‑Bed**: 9pm–11pm
- **Anytime**: all day (excluded from catch‑up deck)
- **No active section** from **11pm–5am**.

### Catch‑up deck rules
- Only **past sections** (interval has ended) are eligible.
- **Lookback window**: last **24 hours**.
- **Excluded**:
  - Anytime items
  - Checklist/appointment/automatic tracking types (for now)
  - Items already **completed** on that day
  - Items already **decided** (done/skipped) on that day
- Interventions that appear in multiple sections are added **once**, in their **latest section** (e.g., exercise in morning+evening will only appear after evening is over).

### Decision states
Each item/day can be:
- **Undecided** (default) → eligible for card
- **Done** → creates a completion entry (back‑dated to noon of that day)
- **Skipped** → records decision but does not create a completion

---

## Data Model Changes
### New decision model
Added in `Skywalker/Models/Intervention.swift`:
- `InterventionDecisionStatus` (done/skipped)
- `InterventionDecision` (interventionId + day + status + count + updatedAt)
- `InterventionCompletion` now supports an explicit timestamp in initializer.

### New deck builder
`Skywalker/Models/CatchUpDeckBuilder.swift`
- Builds the list of cards for the catch‑up deck.
- Computes time windows using `TimeOfDaySection` helpers.
- Applies the 24‑hour lookback and past‑section filter.
- Ensures only undecided & incomplete items are included.
- Maps specific interventions to Apple Health hints.

---

## Persistence & Services
### Decision persistence
`Skywalker/Services/InterventionService.swift`
- New `decisions` array + file `intervention_decisions.json`.
- Methods:
  - `decision(for:on:)` / `decisionStatus(for:on:)`
  - `setDecision(...)`
  - `applyDecision(...)` (records decision + logs completion for done)
- Completions now support **arbitrary timestamps**, enabling back‑dated completions.

### Completion semantics
- If a catch‑up card is marked done, we log a completion at **noon** on that day.
- That prevents the item from reappearing later and keeps streak logic consistent.

---

## HealthKit Hints
`Skywalker/Services/HealthKitService.swift`
- Added `HealthHintType` and authorization per hint:
  - `.exercise` → HKWorkout
  - `.water` → dietary water quantity
  - `.mindfulness` → mindful session
- Added fetchers:
  - `fetchWorkoutSummary(in:)`
  - `fetchWaterLiters(in:)`
  - `fetchMindfulMinutes(in:)`
- Hint cards reload on **scenePhase = .active** to reflect new permissions after the user taps “Allow”.

Mapping (in `CatchUpDeckBuilder`):
- `exercise_timing` → exercise hint
- `hydration_*` and `hydration_target` → water hint
- `stress_reduction` and `mindfulness_prebed` → mindfulness hint

---

## UI Implementation
### Catch‑up modal
`Skywalker/Views/CatchUpModalView.swift`
- Presented from `ContentView` when there are pending cards.
- Sheet presentation, swipe‑down dismissable.
- Top card is interactive; the back cards are static.

### Tinder‑style stacked deck (why + how)
**Problem**: rebuilding the whole stack after each swipe causes awkward animation and visual popping.

**Solution**: maintain a **stable deck + stack**:
- `deck` = full remaining list of cards.
- `stack` = first N cards (N = 4).
- On swipe:
  1. Remove top card from both `deck` and `stack`.
  2. Append **next** card from `deck` to the back of `stack`.
- This keeps a consistent Z‑stack with only the top card moving; the new card appears hidden behind the stack.

Visually:
- The cards behind are scaled down, offset slightly, and faded a touch.
- Card background is fully opaque; ROI tint is applied as an overlay so stacked cards don’t show through.

### Card content
- Section label: “Morning today / Morning yesterday / Morning Monday”
- Title, description/evidence, ROI tint
- Counter stepper if tracking type is `.counter`
- Optional Apple Health hint panel

### Current section summary
After the deck is exhausted, we show:
- “Here’s what you need to try and do in the next X hours.”
- X = remaining time in the current section.
- If no active section (11pm–5am), we show “All caught up”.

---

## Home Screen Integration
`Skywalker/ContentView.swift`
- Adds modal state and shows catch‑up sheet on app foreground.
- Fetches cards from `CatchUpDeckBuilder`.
- Uses current section info for the closing summary card.

---

## JSON Change
`Skywalker/Resources/interventions.json`
- **Charge Biofeedback Device** moved to **Morning** and re‑ordered.

---

## Files Changed / Added
### Added
- `Skywalker/Models/CatchUpDeckBuilder.swift`
- `Skywalker/Views/CatchUpModalView.swift`
- `CATCHUP_MODAL_HANDOVER.md` (this file)

### Updated
- `Skywalker/Models/Intervention.swift`
- `Skywalker/Services/InterventionService.swift`
- `Skywalker/Services/HealthKitService.swift`
- `Skywalker/Views/InterventionsSectionView.swift`
- `Skywalker/Views/CatchUpModalView.swift`
- `Skywalker/ContentView.swift`
- `Skywalker/Resources/interventions.json`

---

## Implementation Notes / Gotchas
- **Lookback window** is **24 hours**; if you want 48 again, update `CatchUpDeckBuilder.build(...)`.
- **Anytime items** are intentionally excluded from cards.
- **Non‑binary tracking types**: we currently only include `binary`, `counter`, and `timer`. Others are skipped.
- **Counts**: we prefill counter items with `1`; user can adjust before swiping.
- **Refresh**: Health hints reload on scene reactivation to reflect new permissions.

---

## Suggested Next Steps
- Add an “Is this you?” prompt for counter/timer cards.
- Add dopamine UI polish (animations, particles, streaks).
- Add per‑intervention HealthKit hint mapping in JSON (if you want config‑driven hints).
- Add tests for deck filtering and decision persistence.

