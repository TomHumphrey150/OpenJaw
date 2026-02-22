export type InterventionTrackingType =
  | "binary"
  | "timer"
  | "counter"
  | "checklist"
  | "appointment"
  | "dose";

export type DoseUnit = "minutes" | "hours" | "milliliters" | "reps" | "breaths";

export interface DoseConfig {
  unit: DoseUnit;
  defaultDailyGoal: number;
  defaultIncrement: number;
}

export interface Intervention {
  id: string;
  name: string;
  emoji: string;
  icon: string;
  description: string;
  detailedDescription: string;
  tier: number;
  frequency: "daily" | "weekly" | "hourly" | "asNeeded" | "quarterly" | "continuous";
  trackingType: InterventionTrackingType;
  legacyIds: string[];
  graphNodeId: string | null;
  doseConfig?: DoseConfig;
  isRemindable: boolean;
  defaultReminderMinutes: number | null;
  externalLink: string | null;
  evidenceLevel: string;
  evidenceSummary: string;
  citationIds: string[];
  roiTier: "A" | "B" | "C" | "D" | "E";
  easeScore: number;
  costRange: string;
  timeOfDay: string[];
  defaultOrder: number;
  estimatedDurationMinutes: number;
  energyLevel: "low" | "medium" | "high";
  liteVariantDurationMinutes?: number;
  targetCondition: "bruxism" | "reflux" | "both" | "general";
  causalPathway: "upstream" | "midstream" | "downstream";
}

export interface Citation {
  id: string;
  title: string;
  source: string;
  year: number;
  url: string;
  type: "cochrane" | "systematicReview" | "metaAnalysis" | "rct" | "review" | "guideline";
}

export interface InterventionsData {
  interventions: Intervention[];
  citations: Citation[];
}
