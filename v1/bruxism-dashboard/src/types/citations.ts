// Study design types
export type StudyDesign =
  | "rct"
  | "systematic_review"
  | "meta_analysis"
  | "cohort"
  | "case_control"
  | "cross_sectional"
  | "case_series"
  | "case_report"
  | "mechanistic"
  | "guideline";

// Effect size types
export type EffectSizeType =
  | "cohens_d"
  | "odds_ratio"
  | "risk_ratio"
  | "hazard_ratio"
  | "smd"
  | "percentage"
  | "other";

// Effect size specification
export interface EffectSize {
  type: EffectSizeType;
  value: number | null;
  ci95Lower?: number;
  ci95Upper?: number;
  description?: string;
}

// Population characteristics
export interface Population {
  ageRange?: string;
  demographics?: string;
  inclusionCriteria?: string;
  exclusionCriteria?: string;
}

// Causality classification
export type CausalityType = "causal" | "correlational" | "mechanistic";

// Replication status
export type ReplicationStatus = "replicated" | "single_study" | "conflicting";

// Citation type (matches existing)
export type CitationType =
  | "cochrane"
  | "systematicReview"
  | "metaAnalysis"
  | "rct"
  | "review"
  | "guideline"
  | "observational";

// Extended citation interface (all new fields optional for backward compat)
export interface ExtendedCitation {
  // Core fields (existing)
  id: string;
  title: string;
  source: string;
  year: number;
  url: string;
  type: CitationType;

  // Study design metadata
  studyDesign?: StudyDesign;
  sampleSize?: number | null;
  sampleSizeNote?: string;

  // Statistical results
  effectSize?: EffectSize | null;
  pValue?: number | null;
  confidenceInterval?: string;

  // Evidence quality
  causalityType?: CausalityType;
  replicationStatus?: ReplicationStatus;

  // Study context
  population?: Population;
  comparisonGroup?: string;
  primaryOutcome?: string;
  secondaryOutcomes?: string[];

  // Provenance
  fundingSource?: string;
  conflictOfInterest?: string;

  // Summary
  keyFindings?: string;
  limitations?: string;
}

// Backward compatible Citation type (extends ExtendedCitation)
export interface Citation extends Partial<Omit<ExtendedCitation, 'id' | 'title' | 'source' | 'year' | 'url' | 'type'>> {
  id: string;
  title: string;
  source: string;
  year: number;
  url: string;
  type: CitationType;
}
