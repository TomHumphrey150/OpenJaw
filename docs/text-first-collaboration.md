# Text-First Collaboration

## Purpose
This project is operated with the assumption that teammates may be blind across engineering, QA, and design roles.

Critical work must be fully understandable and executable through text consumable via screen readers and text-to-speech.

This applies across product surfaces (iOS, web, internal tools), native/device permission flows, auth/access workflows, database and ops workflows, observability/support tooling, and end-to-end QA workflows.

## Non-negotiable Rules
1. Text is the source of truth for implementation, validation, and operations.
2. No critical workflow can depend on sight.
3. Graphical interfaces are acceptable and should be high quality for sighted users.
4. Those same interfaces must be fully operable end-to-end by blind users through platform assistive technologies and equivalent non-visual feedback.
5. Visual assets are optional supplements, never required context.
6. If a visual artifact exists, provide an equivalent text representation.

## Required Text Deliverables by Area

### Project Understanding
- Keep architecture, behavior, and decisions in Markdown.
- When using diagrams, include a plain-language mapping of components and relationships.
- Do not rely on screenshots to explain system behavior.

### Setup and Local Development
- Provide exact setup commands in order.
- Include prerequisites, expected command output, and common failure recovery.
- Ensure instructions can be followed from terminal text alone.

### Tests and Validation
- Document the command to run each test suite and what it verifies.
- Ensure failures are diagnosable through logs and error text.
- Do not require visual-only checks as the sole acceptance path.

### Infrastructure and Operations
- Prefer infrastructure-as-code and scripted operations.
- Maintain text runbooks for deploy, rollback, incident response, and routine ops.
- Include command examples and expected results for each operational action.

### QA Workflows
- Test plans must be stepwise and text-executable.
- Bug reports must include reproducible steps, expected result, actual result, and relevant logs.
- If a screenshot is attached, include a text description of what matters.

### Design Workflows
- Design specs must describe structure, hierarchy, states, and interactions in text.
- Include copy, spacing/token intent, and component behavior in writing.
- Prototypes should include text descriptions of non-visual interaction behavior for each target platform.
- Every user action available visually must also be reachable and understandable non-visually.

## Definition of Done
Work is complete only when a blind teammate can, from text alone:

1. Understand what changed and why.
2. Set up and run the relevant project commands.
3. Validate behavior and test outcomes.
4. Operate or troubleshoot related infrastructure steps.
5. Review design intent and interaction behavior.
6. Use each changed interface end-to-end without sight, using platform assistive technologies.
