# PR Checklist

Add this checklist to every PR and answer each relevant item (`Yes`, `No`, or `N/A`).

Keep supporting notes in dedicated folders only:

- `docs/pr-notes/setup-and-tests/`
- `docs/pr-notes/qa-flow/`
- `docs/pr-notes/ops-and-troubleshooting/`
- `docs/pr-notes/product-and-integration-changes/`
  Follow `docs/pr-notes/AGENTS.md` for note rules.

Filename format:

- `YYYY-MM-DD-HHMM.md` (24-hour time, required)

Before requesting review:

- Add new notes only in folders affected by the PR.
- Do not edit old note files; append a new timestamped note instead.
- If a folder is not applicable, mark it `N/A` in the PR checklist and do not add a note file.
- Never create filler notes for unaffected sections.
- Link the updated note files in the PR description.

Checklist:

- Blind-operable end-to-end: Can a completely blind person complete changed workflows using platform assistive technologies?
- Text parity: Is every critical visual behavior/state also available in text?
- Setup and tests: Are setup/test commands and expected outcomes documented in `docs/pr-notes/setup-and-tests/<timestamp>.md`?
- QA flow: Are text-first reproduce/verify steps and expected vs actual results documented in `docs/pr-notes/qa-flow/<timestamp>.md`?
- Ops and troubleshooting: Are logs, errors, runbook notes, operational steps, and observability checks documented in `docs/pr-notes/ops-and-troubleshooting/<timestamp>.md`?
- Product and integration changes: If product behavior changed (UI, auth/access, integrations, database/sync behavior), is it documented in `docs/pr-notes/product-and-integration-changes/<timestamp>.md`?
- Validation evidence: Are test results and verification notes included in linked, newest timestamped note files?
