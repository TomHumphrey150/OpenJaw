# Bruxism Research Index

Evidence-based research on bruxism interventions, compiled from systematic reviews and meta-analyses.

**Related docs:** [Documentation Index](../DOCUMENTATION_INDEX.md) | [Main README](../../README.md)

---

## Summary

These documents analyze evidence-based interventions for bruxism (teeth grinding). The research was gathered from multiple AI sources and cross-referenced against published systematic reviews.

**Key finding:** No single intervention cures bruxism. A strategic combination of evidence-based approaches works best.

---

## Research Files

### Meta-Analysis (Start Here)

| Document | Description |
|----------|-------------|
| [bruxism-interventions-meta-analysis.md](bruxism-interventions-meta-analysis.md) | Cross-referenced analysis of all interventions, ranked by evidence quality and ROI |

This is the most useful document — it synthesizes all three AI research sources and verifies claims against published research.

### Individual AI Research

These are the raw research outputs from different AI models. The meta-analysis above synthesizes and fact-checks these.

| Document | Description | Reliability |
|----------|-------------|-------------|
| [claude-research.md](claude-research.md) | Evidence-graded analysis with systematic review citations | Most rigorous |
| [openai-research.md](openai-research.md) | Comprehensive overview with clinical citations | Good |
| [gemini-research.md](gemini-research.md) | Detailed mechanistic analysis | Some overclaims |

---

## Top Interventions by Evidence

From the meta-analysis:

### Tier 1: Strong Evidence

1. **Botulinum toxin (Botox)** — Reduces pain, bite force, and bruxism events
2. **Custom occlusal splints** — Protects teeth (but doesn't reduce grinding)
3. **Treating sleep apnea (CPAP/MAD)** — If OSA is present
4. **Biofeedback (EMG-based)** — 35-55% reduction in episodes
5. **Lifestyle modification** — Caffeine, alcohol, smoking reduction

### Tier 2: Moderate Evidence

6. **Massage therapy** — Improves sleep quality, jaw mobility
7. **Physical therapy/jaw exercises** — Improves pain and mobility
8. **GERD treatment** — Strong association (OR=6.87) with bruxism

### Not Recommended (Insufficient Evidence)

- Magnesium supplementation (no RCT evidence)
- Hypnotherapy (2024 RCT showed no benefit)
- Acupuncture (very limited evidence)

---

## Relevance to OpenJaw

The OpenJaw biofeedback system implements intervention #4 (EMG-based biofeedback). The app also includes:

- **Daily habit tracking** for lifestyle factors (Tier 1, #5)
- **Intervention recommendations** based on this research
- **Progress tracking** to measure effectiveness

See the [app interventions.json](../../v1/Skywalker/Skywalker/Resources/interventions.json) for how this research is applied in the app.

---

## How to Use This Research

1. **Start with the meta-analysis** — It's the most actionable
2. **Focus on Tier A ROI interventions** — Free/low-cost, high-evidence
3. **Reference individual AI docs** for deeper mechanistic understanding
4. **Cross-check any specific claim** against the cited systematic reviews
