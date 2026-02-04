# Catch-Up Tinder Modal Implementation Plan

## Goals
- Keep existing time-of-day home UI unchanged.
- Add a catch-up modal that appears on app foreground when there are undecided items from the last 48 hours (excluding Anytime).
- Cards are swipeable: right = done, left = skipped; counter items allow +/− count before swipe.
- Cards clearly label the day/section (e.g., "Morning yesterday").
- Provide Apple Health hints for exercise, hydration, and mindfulness cards, with a “Connect to Apple Health” button when not authorized.
- Pre‑Bed ends at 11:00 PM; after 11 PM there is no active section (Anytime only).

## Step 1 — Time-of-Day Schedule Helpers
- Update `TimeOfDaySection`:
  - Time windows: Morning 5–12, Afternoon 12–17, Evening 17–21, Pre‑Bed 21–23, Anytime all day.
  - Add helpers to compute the date interval for a section on a given day.
  - Add helper to compute the current section (nil between 23:00–05:00).
  - Update the default expanded section logic to respect “no active section.”

## Step 2 — Decision Persistence (Skip/Done)
- Add new model: `InterventionDecision` with `interventionId`, `day` (start-of-day), `status` (done/skipped), optional `count`, and timestamp.
- Add persistence to `InterventionService`:
  - Load/save `intervention_decisions.json`.
  - Helpers to fetch/set decisions by day + intervention.
  - Helpers to check completion for a specific day.
  - When a card is marked done, log a completion back‑dated to that day (noon), and persist decision.

## Step 3 — HealthKit Hints for Cards
- Extend `HealthKitService`:
  - Add read authorization requests for workout, dietary water, and mindful sessions.
  - Add fetch helpers for each type over a date interval.
  - Surface an “authorized/not authorized” check per type.
- Map interventions to hint types in the catch‑up flow:
  - `exercise_timing` → workout/exercise.
  - `hydration_*` and `hydration_target` → dietary water.
  - `stress_reduction` + `mindfulness_prebed` → mindful sessions.

## Step 4 — Catch-Up Modal Data Pipeline
- Build a list of “past sections” within the last 48 hours:
  - For each day in the lookback window, include sections whose end time has passed.
  - Exclude Anytime.
- For each enabled intervention:
  - Determine its **catch‑up section** as the *latest* time-of-day in its `timeOfDay` list (excluding Anytime), so multi‑section items appear only once and only after their last opportunity has passed.
  - Create a card only if the item is still undecided for that day and has no completion on that day.
- Sort cards chronologically by day, then section order.

## Step 5 — Catch-Up Modal UI
- Add `CatchUpModalView` presented as a sheet from `ContentView` when cards exist.
- Tinder-style card interaction:
  - Swipe right = done; swipe left = skipped.
  - Counter cards show +/− to set count before swiping right.
  - Each card shows: title, section label with relative day, evidence summary, ROI tint, and Apple Health hint (or “Connect” CTA).
- When cards are exhausted, show a final “Current section” card:
  - If a current section exists, show: “Here’s what you need to try and do in the next X hours,” with X = time remaining in that section.
  - If no active section (23:00–05:00), show a simple “All caught up” message.

## Step 6 — JSON Adjustment
- Move “Charge Biofeedback Device” to `timeOfDay: ["morning"]` and adjust its `defaultOrder` position.

## Step 7 — Wire-Up & Safety
- Present modal on app foreground only when there are undecided past cards.
- Ensure dismiss is always possible (swipe-down).
- Ensure decisions update existing completion state immediately so cards don’t reappear.

