# Kitchen Garden & Harvest Table — UX/UI/Product Design

## Context

Telocare needs a visual framework that separates **what you can control** (habits/inputs) from **what you measure** (outcomes/health metrics), while making the relationship between them visible. The current UI uses 3D SceneKit "gardens" that are under-surfaced and an Outcomes tab with basic line charts. Neither tells the user a clear story about whether their effort is working.

The core insight: **the gap between effort and outcomes IS the story**. When effort is high but outcomes are poor, external forces are at play — and the user should feel proud of their effort regardless. The UI must show both signals independently so users can see this.

---

## The Framework

```
HABITS TAB (what you control)          PROGRESS TAB (what you measure)
┌──────────────────────────┐           ┌──────────────────────────┐
│    KITCHEN GARDEN        │           │    HARVEST TABLE          │
│    (effort signal)       │──────────→│    (outcome signal)       │
│                          │           │                           │
│  Plants lush = tending   │           │  Food abundant = good     │
│  Plants droopy = slipping│           │  Food sparse = struggling │
│                          │           │  Flowers = effort echo    │
└──────────────────────────┘           └──────────────────────────┘
                                                    ↑
                                        External forces also
                                        affect the food
```

**Two independent signals on the harvest table:**
- **Food** = 7-day rolling outcome score for that pillar. Affected by habits AND external forces the user can't control.
- **Flowers** = habit effort for that pillar. Mirrors the garden. Bridges the two views visually with matching colors.

**The four stories the table tells:**

| Food | Flowers | Meaning |
|------|---------|---------|
| Abundant | Full | "It's working." |
| Sparse | Full | "You're doing everything right. Something external is at play. Keep going." |
| Abundant | Wilting | "Outcomes are okay but you're coasting on momentum." |
| Sparse | Wilting | "Time to get back to tending." |

---

## Visual Aesthetic

**Style:** Ghibli-inspired with high color saturation. Think Howl's Moving Castle flower fields, Arrietty's garden, Ponyo's ocean. 2D illustrated, not 3D. Hand-painted feel with luminous, deeply saturated natural colors — emerald greens, vivid coral, intense lavender, golden amber. Not neon; rich and warm.

**Cozy game principles applied:**
- Rounded shapes, soft edges, organic forms
- Warm muted backgrounds with vivid foreground elements
- Grayscale-to-color progression for untended beds (color drains when habits are neglected, blooms back when tended — borrowed from Cozy Grove)
- Gentle animations: plants sway, flowers bob, food appears softly
- Abundance as reward: the visual payoff is seeing things fill up

**Implementation approach (recommended):**
- Pre-rendered raster assets (PNG @1x/@2x/@3x) for the painterly Ghibli texture — this can't be achieved with vectors
- Lottie animations for growth transitions and ambient motion (swaying plants, gentle sparkle)
- SwiftUI Canvas or standard layout for dynamic positioning based on data
- SVG for small UI icons and badges only

---

## Layout: The Allotment Grid

Both the kitchen garden and harvest table share the same layout: a **flat top-down aerial view**, 3-column grid, card-sized within the scrollable tab.

```
┌────────────┬────────────┬────────────┐
│   Sleep    │ Nutrition  │  Medical   │
│            │            │            │
├────────────┼────────────┼────────────┤
│  Exercise  │  Stress    │Environment │
│            │            │            │
├────────────┼────────────┼────────────┤
│ Av. Drugs  │ Romance    │  Finance   │
│            │            │            │
├────────────┴────────────┼────────────┤
│                         │   Social   │
│                         │            │
└─────────────────────────┴────────────┘
```

**Grid behavior:**
- 3 columns, rows wrap as needed
- Currently 10 pillars = 3 full rows + 1 cell in row 4
- Users can add custom pillars, so the grid grows dynamically
- Spacing between cells: 8pt (sm)
- Each cell is a card with the pillar name overlaid on the illustration

**Camera angle:** Flat top-down aerial. Each bed/table section is seen from directly above. This is simpler to render, more diagrammatic, and cleaner at card sizes than a 3/4 isometric view.

---

## The Kitchen Garden (Habits Tab)

**Position:** Top of the Habits (currently "Inputs") tab, above the habit list.

**What each garden bed card shows:**
- Pillar name (text overlay)
- Illustrated garden bed seen from above: soil, plants, flowers in the pillar's color palette
- Visual state reflects habit adherence (10 growth stages)

**10 Growth Stages** (each visually distinct from adjacent stages):

| Stage | Adherence | Visual Description |
|-------|-----------|-------------------|
| 1 | 0-10% | Bare soil. Dry, cracked earth. A few seeds visible. No color. |
| 2 | 10-20% | First sprouts breaking through. Tiny green shoots. Soil still mostly bare. |
| 3 | 20-30% | Small seedlings established. A few leaves unfurling. First hint of pillar color in stem tips. |
| 4 | 30-40% | Young plants with visible leaf structure. First flower bud appears (closed). Soil darkening (healthier). |
| 5 | 40-50% | Plants filling out. First flower opens. A small vegetable/herb forming. Weeds retreating. |
| 6 | 50-60% | Garden bed half-full. 2-3 flowers open. Produce starting to show color. Lush green foliage. |
| 7 | 60-70% | Dense foliage. Multiple flowers in full bloom. Produce ripening. Bees/butterflies appear. |
| 8 | 70-80% | Abundant growth. Flowers nodding with weight. Produce nearly harvest-ready. Rich, saturated colors. |
| 9 | 80-90% | Overflowing. Plants spilling over bed edges. Full flower display. Produce fully ripe and colorful. |
| 10 | 90-100% | Peak garden. Maximum bloom. Golden light effect. Gentle sparkle/glow. The Ghibli "magic moment." |

**Key visual principle:** Each stage adds new elements AND evolves existing ones. Stage 5 doesn't just have "more" than stage 4 — the existing plants are visibly larger and more developed. The progression should feel like watching a time-lapse of a real garden growing.

**Interaction:**
- Tapping a garden bed:
  1. Filters the habit list below to show only that pillar's habits
  2. Hides the other garden beds (or dims them, showing only the selected one prominently)
  3. Sets the global health lens filter to that pillar (persists across tabs via `HealthLensState`)
- Tapping again (or a "show all" action) clears the filter and restores the full grid

---

## The Harvest Table (Progress Tab)

**Position:** Top of the Progress (currently "Outcomes") tab, above the outcome detail / trend content.

**What each table section card shows:**
- Pillar name (text overlay)
- Illustrated table surface seen from above: wooden table section with food items and flowers
- Food abundance reflects 7-day rolling outcome score for that pillar
- Flower abundance reflects habit effort (mirrors the garden bed state)

**Food on the table (outcome signal):**
- Each pillar has a set of food items in its color palette
- 7-day rolling outcome score determines how full/sparse the food display is
- Good outcomes → table section overflowing with colorful produce
- Poor outcomes → sparse, muted, few items on bare wood
- This is NOT today's snapshot — it's a 7-day rolling picture, so it changes gradually

**Flowers on the table (effort echo):**
- Cut flowers and small vases on the table section, in the same colors as the garden bed's flowers
- Abundance matches the garden bed's growth stage
- This bridges the two views: you see your Sleep garden's lavender in the garden AND on the table
- Creates the visual link between cause (garden) and effect (table)

**The "gap" is self-evident:**
- Lush flowers + sparse food = "Your effort is strong but outcomes aren't reflecting it yet. External forces."
- Sparse flowers + abundant food = "You're coasting."
- No explicit messaging needed — the visual contrast tells the story.

**Interaction:**
- Tapping a table section:
  1. Filters the outcome/progress content below to that pillar
  2. Hides/dims other table sections
  3. Sets global health lens to that pillar (same mechanism as garden tap)
- Tapping again clears the filter

---

## Pillar Color Palettes

Each pillar needs a distinct, highly saturated color family that works across:
- Garden plants and flowers
- Food items on the table
- Cut flowers on the table
- Any UI accents (pillar badges, filter pills)

**Proposed palette (Ghibli-saturated):**

| Pillar | Primary Hue | Garden Plants | Garden Flowers | Table Food | Table Flowers |
|--------|-------------|---------------|----------------|------------|---------------|
| Sleep | Deep lavender/indigo | Chamomile, lavender bushes | Lavender sprigs, chamomile blooms | Chamomile tea jar, lavender honey | Lavender in small vase |
| Nutrition | Rich sage/emerald | Basil, rosemary, mint | Herb flowers (white-green) | Herb bundle, pesto jar, fresh leaves | Herb blossoms in cup |
| Medical | Deep berry/plum | Elderberry, echinacea | Purple coneflowers | Berry preserves, tincture bottles | Echinacea in vase |
| Exercise | Vivid coral/orange | Squash vines, pumpkin | Marigolds, nasturtiums | Squash, pumpkin, carrots | Marigolds on table |
| Stress Mgmt | Rich gold/amber | Sunflower stalks, calendula | Sunflowers, calendula | Honey jar, sunflower seeds | Small sunflower in jar |
| Environment | Teal/deep green | Ferns, leafy greens, kale | Teal/green wildflowers | Bowl of greens, lettuce | Green wildflowers |
| Avoiding Drugs | Cool mint/sky blue | Mint, borage, blue herbs | Borage stars, forget-me-nots | Mint tea, dried mint bundle | Blue flowers in glass |
| Romance | Dusty rose/pink | Rose bushes, peonies | Roses, peonies | Rose water bottle, rose jam | Roses in vase |
| Finance | Wheat/warm amber | Wheat stalks, grain, barley | Golden wildflowers | Bread loaf, grain sheaf | Dried wheat arrangement |
| Social | Warm yellow/sunshine | Tomato plants, peppers | Yellow daisies, zinnias | Bowl of tomatoes, peppers | Yellow daisies on table |

**Color continuity principle:** The flowers in the garden bed are the same species as the cut flowers on the harvest table. The food on the table is the produce from the garden's edible plants. Color ties them together even when the views are on different tabs.

---

## New Outcome Questions (Product Requirement)

Currently, outcome metrics are symptom-based (jaw soreness, neck tension, etc.) and don't map to individual pillars. For the harvest table to work — where each pillar section shows its own food abundance — **each pillar needs its own outcome question(s)**.

**Requirement:** Create pillar-specific outcome check-in questions. Each pillar gets 1-2 daily or periodic questions that measure outcomes in that domain.

**Example structure (to be defined with clinical input):**

| Pillar | Example Outcome Question | Scale |
|--------|--------------------------|-------|
| Sleep | "How rested did you feel this morning?" | 0-10 |
| Nutrition | "How was your energy from food today?" | 0-10 |
| Medical | "How are your symptoms overall?" | 0-10 |
| Exercise | "How does your body feel physically?" | 0-10 |
| Stress Mgmt | "How manageable did stress feel today?" | 0-10 |
| Environment | "How comfortable was your environment?" | 0-10 |
| Avoiding Drugs | "How clean/clear did you feel today?" | 0-10 |
| Romance | "How connected did you feel in relationships?" | 0-10 |
| Finance | "How secure did you feel financially?" | 0-10 |
| Social | "How socially nourished did you feel?" | 0-10 |

These questions feed the 7-day rolling score that determines food abundance on the harvest table. The exact questions need clinical/product review — the above are illustrative.

---

## Where Things Live in the App

**Habits Tab (currently "Inputs"):**
```
┌─────────────────────────────┐
│  Kitchen Garden Grid        │  ← NEW: 3-col illustrated garden
│  (card-sized, scrollable)   │
├─────────────────────────────┤
│  [Filter pills: Pending /   │  ← EXISTING: filter mode toggle
│   Completed / Available]    │
├─────────────────────────────┤
│  Habit list by pillar       │  ← EXISTING: pillar section cards
│  (filtered when garden bed  │     (filters to tapped pillar)
│   is tapped)                │
└─────────────────────────────┘
```

**Progress Tab (currently "Outcomes"):**
```
┌─────────────────────────────┐
│  Harvest Table Grid         │  ← NEW: 3-col illustrated table
│  (card-sized, scrollable)   │
├─────────────────────────────┤
│  Pillar outcome check-in    │  ← NEW: replaces/augments current
│  (filtered when table       │     morning check-in
│   section is tapped)        │
├─────────────────────────────┤
│  7-day trend details        │  ← EVOLVED: per-pillar trend view
│  (existing trend charts     │     (filtered to tapped pillar)
│   adapted for pillar data)  │
└─────────────────────────────┘
```

**Global lens integration:**
- Tapping a garden bed or table section calls `setHealthLensPillar()` on the AppViewModel
- This filters both tabs simultaneously via `HealthLensState`
- The My Map (Situation) tab also respects this filter, focusing the graph on that pillar's neighborhood
- Clearing the selection calls `selectAllHealthLensPillars()`

---

## Technical Approach

**Replacing SceneKit with 2D illustration:**
- Current: `GardenPlotView` renders 3D SceneKit plants in a 110x100pt frame
- New: Pre-rendered PNG assets per pillar per growth stage (10 pillars x 10 stages = 100 garden assets + 100 table assets)
- Each asset is a flat top-down illustrated scene at the card size
- Growth stage selected by mapping adherence percentage to stage 1-10
- Lottie animations layered on top for ambient motion (swaying, sparkle at stage 10)

**Grid layout change:**
- Current: 2-column grid via `GardenGridLayout`
- New: 3-column grid
- Card dimensions will be smaller per card (3 columns vs 2), so illustrations must read clearly at ~110pt wide

**Asset production pipeline:**
- Design: Procreate or Illustrator, Ghibli-inspired hand-painted style
- Export: PNG @1x/@2x/@3x per growth stage per pillar
- Animation: Lottie for growth transitions and ambient motion
- Bundle: Standard Xcode asset catalog

**Data flow:**
- Garden bed state: computed from `InputStatus` adherence data per pillar (existing `bloomLevel` logic adapted)
- Table food state: computed from new pillar-specific outcome scores (7-day rolling average)
- Table flower state: mirrors garden bed state (same adherence data)

---

## Key Design Decisions & Reasoning

| Decision | Reasoning |
|----------|-----------|
| Kitchen garden, not flower garden | Flowers don't produce a natural "harvest." Kitchen gardens produce food AND can include flowers. |
| Harvest table, not charts | A table with food is emotionally readable. Charts are analytical. The metaphor supports pride and curiosity, not just data consumption. |
| Two independent signals on the table | Separating effort (flowers) from outcomes (food) prevents the demoralizing "I'm trying hard but the number is bad" problem. Users see their effort acknowledged visually. |
| Same grid layout for both views | Visual parallel reinforces the cause→effect relationship. Same position, same colors, different content. |
| Flat top-down aerial | Simpler to render at card size. More diagrammatic. Avoids the complexity of isometric perspective at small scales. |
| 10 growth stages | Enough granularity that daily habit changes produce visible progress. Each stage is distinct, creating clear "level up" moments. |
| 7-day rolling for food, daily for flowers | Food (outcomes) smooths over daily noise — a bad day doesn't empty the table. Flowers (effort) respond to today's actions — immediate feedback for tending. |
| Tap to filter + set global lens | Leverages existing `HealthLensState` infrastructure. Creates a consistent "focus on one pillar" gesture across the entire app. |
| Ghibli + high saturation | Warm, organic, calming. High saturation makes the 10 pillar colors distinct at small card sizes. The painterly quality communicates care and craft. |
| 2D illustrated, not 3D | Matches the cozy game aesthetic. Lighter to render than SceneKit. More artistic control over the Ghibli feel. Pre-rendered assets are performant. |
| Pillar-specific outcome questions | Required for the table to show per-pillar food abundance. Current symptom-based metrics don't map cleanly to pillars. |
| Read-only visualizations | Keeps the garden and table as motivational summaries. Habit management stays in the list below. Reduces interaction complexity. |

---

## Open Items for Future Consideration

- **Exact outcome questions per pillar** — needs clinical/product input
- **Onboarding** — how to introduce the garden/table metaphor to new users
- **Empty states** — what the garden and table look like before any data exists
- **Custom pillars** — users can add pillars; they'd need a default color palette and generic plant/food assets
- **Accessibility** — ensure the visual metaphor has text alternatives; color-blind safe palettes
- **Animation details** — exact Lottie specs for growth transitions, ambient motion, and the stage-10 "magic moment"
- **Asset production timeline** — 200+ illustrated assets is significant art production work
