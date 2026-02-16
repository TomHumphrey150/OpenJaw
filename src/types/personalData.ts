import { ExtendedCitation, CausalityType, ReplicationStatus } from './citations';

// Personal effectiveness rating for interventions
export type PersonalEffectiveness = "works_for_me" | "doesnt_work" | "untested" | "inconclusive";

// Personal note on any entity (citation, intervention, causal node)
export interface PersonalNote {
  id: string;
  targetType: "citation" | "intervention" | "causal_node" | "general";
  targetId: string;
  content: string;
  createdAt: string;
  updatedAt: string;
}

// Personal study (user-added, same schema as citation)
export interface PersonalStudy extends ExtendedCitation {
  isPersonal: true;
  addedAt: string;
  personalNotes?: string;
}

// Single observation in an experiment
export interface ExperimentObservation {
  id: string;
  date: string;
  note: string;
  rating?: number; // 1-5 scale
  metrics?: Record<string, number | string>;
}

// Experiment status
export type ExperimentStatus = "active" | "completed" | "abandoned";

// Personal experiment tracking
export interface PersonalExperiment {
  id: string;
  interventionId: string;
  interventionName: string;
  startDate: string;
  endDate?: string;
  status: ExperimentStatus;

  // Tracking
  observations: ExperimentObservation[];

  // Outcome
  effectiveness?: PersonalEffectiveness;
  summary?: string;
}

// Personal intervention rating
export interface PersonalInterventionRating {
  interventionId: string;
  effectiveness: PersonalEffectiveness;
  notes?: string;
  lastUpdated: string;
}

// Custom causal chain node
export interface CustomCausalNode {
  id: string;
  label: string;
  description?: string;
  parentId?: string;
  linkedInterventionIds: string[];
  linkedCitationIds: string[];
  position: { x: number; y: number };
  color?: string;
}

// Custom causal chain edge
export interface CustomCausalEdge {
  id: string;
  sourceId: string;
  targetId: string;
  label?: string;
}

// Custom causal diagram
export interface CustomCausalDiagram {
  nodes: CustomCausalNode[];
  edges: CustomCausalEdge[];
  lastModified: string;
}

// Simple one-variable experimentation status for a habit/intervention.
export type HabitEffectStatus = "helpful" | "neutral" | "harmful" | "unknown";

// A single nightly habit exposure record.
export interface NightExposure {
  nightId: string; // YYYY-MM-DD
  interventionId: string;
  enabled: boolean;
  intensity?: number; // optional normalized intensity (0-1 or app-defined)
  tags?: string[];
  createdAt: string;
}

// Objective overnight outcomes, primarily anchored on micro-arousals.
export interface NightOutcome {
  nightId: string; // YYYY-MM-DD
  microArousalCount?: number;
  microArousalRatePerHour?: number;
  confidence?: number; // 0-1
  totalSleepMinutes?: number;
  source?: string;
  createdAt: string;
}

// Morning self-report state captured after a night.
export interface MorningState {
  nightId: string; // YYYY-MM-DD
  globalSensation?: number; // 0-10
  neckTightness?: number; // 0-10
  jawSoreness?: number; // 0-10
  earFullness?: number; // 0-10
  healthAnxiety?: number; // 0-10
  createdAt: string;
}

// Trial metadata for one-variable-at-a-time experimentation windows.
export interface HabitTrialWindow {
  id: string;
  interventionId: string;
  startNightId: string;
  endNightId?: string;
  status: "active" | "completed" | "abandoned";
}

// Derived simple classification record for an intervention.
export interface HabitClassification {
  interventionId: string;
  status: HabitEffectStatus;
  nightsOn: number;
  nightsOff: number;
  microArousalDeltaPct?: number;
  morningStateDelta?: number;
  windowQuality?: "clean_one_variable" | "confounded" | "insufficient_data";
  updatedAt: string;
}

// Complete personal data store (saved to localStorage)
export interface PersonalDataStore {
  version: number;
  lastExport?: string;

  // Personal studies
  personalStudies: PersonalStudy[];

  // Notes on any entity
  notes: PersonalNote[];

  // Experiment tracking
  experiments: PersonalExperiment[];

  // Intervention ratings
  interventionRatings: PersonalInterventionRating[];

  // Simple V1 protocol records
  nightExposures?: NightExposure[];
  nightOutcomes?: NightOutcome[];
  morningStates?: MorningState[];
  habitTrials?: HabitTrialWindow[];
  habitClassifications?: HabitClassification[];

  // Custom causal diagram
  customCausalDiagram?: CustomCausalDiagram;
}

// Default empty store
export const EMPTY_PERSONAL_DATA_STORE: PersonalDataStore = {
  version: 1,
  personalStudies: [],
  notes: [],
  experiments: [],
  interventionRatings: [],
  nightExposures: [],
  nightOutcomes: [],
  morningStates: [],
  habitTrials: [],
  habitClassifications: [],
  customCausalDiagram: undefined
};
