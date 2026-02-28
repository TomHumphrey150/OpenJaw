# Agents (iOS)

## Scope

These rules apply to everything under `ios/`.

## Ethos

Write the strictest, cleanest code possible. If code needs a comment to be understood, rewrite it.

No escape hatches. Avoid `Any` and force casts unless a boundary absolutely requires them and the reason is documented.

Flat control flow. Minimal nesting. Early returns. Small functions. Clear names.

No TODOs. No dead code. No commented-out blocks.

Catch mistakes at build time. Prefer compiler-enforced guarantees over runtime checks.

Research before writing. Read current Apple and dependency docs, then implement.

Explicit over implicit. Pin config. Avoid ambient behavior you cannot explain.

Modern over legacy. Prefer current stable Swift, SwiftUI/UIKit APIs, and Tuist patterns.

Every file does one thing. Every module has a clear boundary.

## iOS Engineering Rules

- Keep app code, infrastructure code, and scripts separated.
- Keep feature logic out of views. Views render state and emit intents.
- Use stable, deterministic identifiers for UI elements that need automated verification.
- Treat warnings as errors for app targets.
- Do not ship placeholder tests.
- A test that only compares constants or reasserts implementation text is invalid.
- UI behavior that is visual or interaction-driven must be verified with UI tests.

## Supabase User-Data Mutation Policy
- Telocare maintenance scripts may directly mutate `public.user_data` only for user ID `58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14`.
- Direct mutation for any other user requires explicit per-run authorization.

## Accessibility Baseline (iOS)

Assume users and teammates may be completely blind.

No critical iOS workflow may depend on sight. This includes onboarding, auth, recording, playback, settings, subscription, notifications, and support/debug flows.

Ship interfaces that are fully operable with VoiceOver and equivalent non-visual feedback.

Minimum requirements:

- Every interactive element exposes a clear accessibility label, value (when applicable), and trait.
- Reading and focus order matches the intended task flow.
- State changes are announced non-visually.
- Critical outcomes are available in text, not only visual styling.
- Do not rely only on color, motion, or iconography to convey meaning.
- Respect Dynamic Type, Reduce Motion, and other platform accessibility settings.
- Permission and error flows are understandable from spoken/output text alone.

## Text-First Collaboration
Use `../docs/text-first-collaboration.md` as the iOS definition of done for blind-operable work.

## Standard Commands

From `ios/Telocare`:

- Generate/open Tuist files: `mise x tuist@latest -- tuist install && mise x tuist@latest -- tuist generate --no-open`
- Visualize dependency graph: `mise x tuist@latest -- tuist graph`
- Build app: `xcodebuild -workspace Telocare.xcworkspace -scheme Telocare -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Run tests: `xcodebuild -workspace Telocare.xcworkspace -scheme Telocare -destination 'platform=iOS Simulator,name=iPhone 17' test`

## Library

Reference documents for `ios/`:

| Document | Purpose |
| --- | --- |
| `../docs/text-first-collaboration.md` | Repository-wide baseline for blind-operable engineering and QA. |
| `../docs/pr-checklist.md` | PR checklist requirements and evidence expectations. |
| `../docs/pr-notes/AGENTS.md` | Rules for append-only PR notes and timestamped evidence files. |
