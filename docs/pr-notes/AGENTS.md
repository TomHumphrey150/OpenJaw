# PR Notes Agents

## Purpose
`docs/pr-notes/` is an append-only event log for PR support notes.

Do not treat past notes as editable state.

Treat notes as ordered events used to reconstruct current state.

## Folders
- `docs/pr-notes/setup-and-tests/`
- `docs/pr-notes/qa-flow/`
- `docs/pr-notes/ops-and-troubleshooting/`
- `docs/pr-notes/product-and-integration-changes/`

## File Naming
- Required format: `YYYY-MM-DD-HHMM.md` (24-hour time).
- Always include hours and minutes.
- If multiple notes are created in the same minute, append a short suffix, e.g. `YYYY-MM-DD-HHMM-a.md`.

## Update Rules
- Append-only: never edit or delete prior note files.
- Add a new note file for each update.
- Update only folders relevant to the PR.
- If a folder is not relevant, do not add a note file for it.
- In the PR checklist, mark non-applicable folders as `N/A`.
- Never invent or pad note content just to satisfy a template.
- In PR descriptions, link the newest note file(s) used as current state.

## Reading Rules (Event-Sourcing Style)
- Sort note filenames lexicographically within each folder.
- Read from oldest to newest to reconstruct state.
- Use the newest note as current source of truth when no conflict exists.
- When conflicts exist, newest timestamp wins.
