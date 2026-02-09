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
  customCausalDiagram: undefined
};
