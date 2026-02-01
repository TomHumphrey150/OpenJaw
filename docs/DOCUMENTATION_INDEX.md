# OpenJaw Documentation Index

Master index of all documentation in the OpenJaw (Skywalker) repository.

> **Note on naming:** This project is called "OpenJaw" publicly but you'll see "Skywalker" throughout the codebase and internal documentation. Skywalker was the original working name. We kept it in the code to avoid breaking changes during development.

---

## Quick Navigation

| What you want to do | Start here |
|---------------------|------------|
| Understand the project | [README.md](../README.md) |
| Get started with V1 | [v1/ONBOARDING.md](../v1/ONBOARDING.md) |
| Set up the iOS/Watch app | [v1/Skywalker/Claude.md](../v1/Skywalker/Claude.md) |
| Set up the relay server | [v1/relay-server/README.md](../v1/relay-server/README.md) |
| Learn about bruxism interventions | [Bruxism Research](Bruxism-research/README.md) |
| Understand why V2 ML doesn't work yet | [V2 Learnings](../v2/muse-detector/docs/learnings/) |

---

## Core Documentation

### Project Overview

| Document | Description |
|----------|-------------|
| [README.md](../README.md) | Project overview, current status, quick start guide |

### V1 Documentation (Working System)

V1 uses Mind Monitor for detection and is the current working solution.

| Document | Description |
|----------|-------------|
| [v1/plan.md](../v1/plan.md) | Original technical specification and product requirements |
| [v1/ONBOARDING.md](../v1/ONBOARDING.md) | Comprehensive onboarding guide for new contributors |
| [v1/Skywalker/Claude.md](../v1/Skywalker/Claude.md) | iOS/watchOS app build instructions and architecture |
| [v1/relay-server/README.md](../v1/relay-server/README.md) | Python relay server setup and troubleshooting |

### V2 Documentation (Experimental — Not Working)

V2 attempted direct ML-based detection. The pure ML approach didn't work; see learnings for why.

| Document | Description |
|----------|-------------|
| [v2/muse-detector/CLAUDE.md](../v2/muse-detector/CLAUDE.md) | V2 overview and current status |
| [v2/muse-detector/docs/ML_SYSTEM_DESIGN.md](../v2/muse-detector/docs/ML_SYSTEM_DESIGN.md) | (Historical) Original ML architecture design |
| [v2/muse-detector/docs/HYBRID_BOOTSTRAP_DESIGN.md](../v2/muse-detector/docs/HYBRID_BOOTSTRAP_DESIGN.md) | Future plan: using V1 to bootstrap V2 training data |

#### V2 Learnings (Important!)

These documents explain what we learned from the V2 experiment:

| Document | Description |
|----------|-------------|
| [001-signal-in-motion-not-eeg.md](../v2/muse-detector/docs/learnings/001-signal-in-motion-not-eeg.md) | Discovery: model learned head motion, not EMG |
| [002-ml-approach-problems.md](../v2/muse-detector/docs/learnings/002-ml-approach-problems.md) | Why we moved back to V1 (critical reading) |

---

## Research & Reference

### Bruxism Research

Evidence-based analysis of bruxism interventions. See [Bruxism Research Index](Bruxism-research/README.md) for summaries.

| Document | Description |
|----------|-------------|
| [bruxism-interventions-meta-analysis.md](Bruxism-research/bruxism-interventions-meta-analysis.md) | Cross-referenced analysis with ROI rankings |
| [claude-research.md](Bruxism-research/claude-research.md) | Claude's research (most rigorous) |
| [openai-research.md](Bruxism-research/openai-research.md) | OpenAI's research |
| [gemini-research.md](Bruxism-research/gemini-research.md) | Gemini's research |

### Technical Reference

| Document | Description |
|----------|-------------|
| [docs/technical-docs/data-format-compatibility.md](technical-docs/data-format-compatibility.md) | Data format specifications |
| [docs/OpenMuse/](OpenMuse/) | OpenMuse library reference (for V2) |

---

## Documentation for AI Agents

If you're an AI agent (Claude, etc.) working on this codebase:

1. **Start with** [README.md](../README.md) for project context
2. **For V1 work:** Read [v1/Skywalker/Claude.md](../v1/Skywalker/Claude.md) and [v1/ONBOARDING.md](../v1/ONBOARDING.md)
3. **For V2 work:** Read [v2/muse-detector/CLAUDE.md](../v2/muse-detector/CLAUDE.md) and the learnings docs
4. **Critical context:** The [002-ml-approach-problems.md](../v2/muse-detector/docs/learnings/002-ml-approach-problems.md) explains why ML doesn't work yet

### Key Facts

- V1 is working; V2 is not
- Use Mind Monitor + relay server for detection (V1)
- Pure ML detection doesn't generalize (V2 learned)
- The hybrid bootstrap plan is the path forward for V2
- "Skywalker" and "OpenJaw" refer to the same project

---

## Document Status

| Document | Status |
|----------|--------|
| README.md | Current |
| v1/plan.md | Implemented — V1 is working |
| v1/ONBOARDING.md | Current |
| v1/Skywalker/Claude.md | Current |
| v1/relay-server/README.md | Current |
| v2/muse-detector/CLAUDE.md | Current |
| v2/muse-detector/docs/ML_SYSTEM_DESIGN.md | Historical — describes abandoned approach |
| v2/muse-detector/docs/HYBRID_BOOTSTRAP_DESIGN.md | Future plan — not yet implemented |
