import process from 'node:process';
import path from 'node:path';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import {
  edgeSignature,
  GraphData,
  GraphEdgeElement,
  GraphNodeElement,
  isUnknownRecord,
  loadGraphFromPath,
  loadGraphFromUnknown,
  UnknownRecord,
} from './pillar-integrity-lib';

const AUDIT_VERSION = 'user-graph-audit.v2';
const DEFAULT_CANONICAL_GRAPH_PATHS = [
  'data/default-graph.json',
  'ios/Telocare/Telocare/Resources/Graph/default-graph.json',
];

const REF_USER_DATA_ROW = 'ref_user_data_row';
const REF_USER_GRAPH_NODES = 'ref_user_graph_nodes';
const REF_USER_GRAPH_EDGES = 'ref_user_graph_edges';
const REF_INTERVENTIONS_CATALOG = 'ref_interventions_catalog';
const REF_OUTCOMES_METADATA = 'ref_outcomes_metadata';
const REF_PROGRESS_QUESTIONS = 'ref_progress_question_links';
const REF_CANONICAL_GRAPH = 'ref_canonical_graph';
const REF_PLANNING_POLICY = 'ref_planning_policy';

interface ParsedArgs {
  userID: string | null;
  reportOut: string | null;
  raw: boolean;
  pretty: boolean;
}

interface ProvenanceRef {
  table_or_file: string;
  selector: Record<string, string>;
  updated_at: string | null;
  version: number | null;
  fallback_used: boolean;
  path_hint: string;
}

interface ProvenanceSectionRefs {
  summary: string[];
  details: {
    graph_nodes: string[];
    graph_edges: string[];
    habit_links: string[];
    outcome_question_links: string[];
    canonical_baseline: string[];
  };
  validation: string[];
}

interface ProvenanceBlock {
  refs: Record<string, ProvenanceRef>;
  sections: ProvenanceSectionRefs;
}

type ValidationSeverity = 'error' | 'warning';

interface ValidationViolation {
  code: string;
  severity: ValidationSeverity;
  message: string;
  section: string;
  source_ref: string;
}

interface ValidationBlock {
  status: 'pass' | 'fail';
  violations: ValidationViolation[];
}

interface GraphNodeRow {
  node_id: string;
  label: string;
  style_class: string;
  tier: number | null;
  is_deactivated: boolean;
  parent_ids: string[];
  source_ref: string;
}

interface GraphEdgeRow {
  edge_id: string;
  source_node_id: string;
  target_node_id: string;
  edge_type: string;
  edge_color: string;
  label: string;
  is_deactivated: boolean;
  source_ref: string;
}

interface HabitLinkRow {
  intervention_id: string;
  name: string;
  graph_node_id: string | null;
  graph_edge_ids: string[];
  is_active: boolean;
  is_hidden: boolean;
  pillars: string[];
  planning_tags: string[];
  source_node_exists: boolean;
  source_edges_exist: boolean;
  missing_graph_edge_ids: string[];
  outgoing_edge_ids: string[];
  target_node_ids: string[];
  missing_reasons: string[];
  source_ref: string;
}

interface OutcomeQuestionLinkRow {
  question_id: string;
  title: string;
  source_node_ids: string[];
  source_edge_ids: string[];
  missing_node_ids: string[];
  missing_edge_ids: string[];
  link_status: 'linked' | 'missing_sources';
  source_ref: string;
}

interface CanonicalBaselineDetails {
  canonical_node_count: number;
  canonical_edge_count: number;
  missing_user_node_ids: string[];
  missing_user_edge_signatures: string[];
  source_ref: string;
}

interface DetailsBlock {
  graph_nodes: GraphNodeRow[];
  graph_edges: GraphEdgeRow[];
  habit_links: HabitLinkRow[];
  outcome_question_links: OutcomeQuestionLinkRow[];
  canonical_baseline: CanonicalBaselineDetails;
}

interface SourceRecencyEntry {
  updated_at: string | null;
  version: number | null;
  source: string;
}

interface SummaryBlock {
  user_graph_node_count: number;
  user_graph_edge_count: number;
  canonical_graph_node_count: number;
  canonical_graph_edge_count: number;
  interventions_total: number;
  interventions_with_graph_node_id: number;
  interventions_with_graph_edge_ids: number;
  habits_linked_count: number;
  habits_unlinked_count: number;
  habits_missing_edge_links_count: number;
  outcome_questions_total: number;
  outcome_questions_linked_count: number;
  outcome_questions_unlinked_count: number;
  missing_source_node_count: number;
  missing_source_edge_count: number;
  outcome_questions_reason: string | null;
  source_row_recency: {
    user_data: SourceRecencyEntry;
    interventions_catalog: SourceRecencyEntry;
    outcomes_metadata: SourceRecencyEntry;
    canonical_graph: SourceRecencyEntry;
    planning_policy: SourceRecencyEntry;
  };
}

interface UserGraphAuditReport {
  audit_version: string;
  generated_at: string;
  input: {
    user_id: string;
  };
  summary: SummaryBlock;
  details: DetailsBlock;
  provenance: ProvenanceBlock;
  validation: ValidationBlock;
}

interface ContentPayload {
  data: unknown;
  source: 'user_content' | 'first_party_content';
  updatedAt: string | null;
  version: number | null;
}

interface CanonicalGraphResolution {
  graphRaw: unknown;
  source: 'first_party_content' | 'local_file';
  updatedAt: string | null;
  version: number | null;
  fallbackUsed: boolean;
  sourcePathOrSelector: string;
}

interface ParsedInterventionRow {
  id: string;
  name: string;
  graphNodeID: string | null;
  graphEdgeIDs: string[];
  pillars: string[];
  planningTags: string[];
}

interface ParsedQuestionRow {
  id: string;
  title: string;
  sourceNodeIDs: string[];
  sourceEdgeIDs: string[];
}

interface ParsedQuestions {
  rows: ParsedQuestionRow[];
  reason: string | null;
}

interface BuildAuditInput {
  userID: string;
  userDataUpdatedAt: string | null;
  userStore: UnknownRecord;
  userGraphRaw: unknown;
  canonicalGraphRaw: unknown;
  interventionsCatalogData: unknown;
  outcomesMetadataData: unknown;
  planningPolicyData: unknown | null;
  provenance: ProvenanceBlock;
}

function requiredEnv(...names: string[]): string {
  for (const name of names) {
    const value = process.env[name];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }

  throw new Error(`Missing environment variable. Provide one of: ${names.join(', ')}`);
}

function getArg(name: string): string | null {
  const needle = `--${name}`;
  const index = process.argv.indexOf(needle);
  if (index < 0) {
    return null;
  }

  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) {
    return null;
  }

  return value;
}

function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

function parsePrettyOption(): boolean {
  const rawValue = getArg('pretty');
  if (rawValue === null) {
    return !hasFlag('no-pretty');
  }

  const normalized = rawValue.trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
    return true;
  }
  if (normalized === 'false' || normalized === '0' || normalized === 'no') {
    return false;
  }

  throw new Error(`Invalid --pretty value: ${rawValue}. Use true/false.`);
}

function parseArgs(): ParsedArgs {
  return {
    userID: getArg('user-id') ?? process.env.SUPABASE_DEBUG_USER_ID ?? null,
    reportOut: getArg('report-out'),
    raw: hasFlag('raw'),
    pretty: parsePrettyOption(),
  };
}

function printUsageAndExit(): never {
  console.error('Usage: npm run debug:user-graph-audit -- --user-id <uuid> [--report-out <path>] [--raw] [--pretty true|false]');
  process.exit(1);
}

function readOptionalString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }

  return trimmed;
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const values = new Set<string>();
  for (const entry of value) {
    const parsed = readOptionalString(entry);
    if (parsed !== null) {
      values.add(parsed);
    }
  }

  return [...values].sort((left, right) => left.localeCompare(right));
}

function addViolation(
  violations: ValidationViolation[],
  violation: ValidationViolation,
): void {
  violations.push(violation);
}

function validateRawGraphShape(
  graphRaw: unknown,
  section: string,
  sourceRef: string,
  violations: ValidationViolation[],
): void {
  const graph = isUnknownRecord(graphRaw) ? graphRaw : null;
  if (graph === null) {
    addViolation(violations, {
      code: 'GRAPH_ROOT_INVALID',
      severity: 'error',
      message: `${section} graph payload must be an object containing nodes and edges arrays.`,
      section,
      source_ref: sourceRef,
    });
    return;
  }

  const nodesRaw = graph.nodes;
  if (!Array.isArray(nodesRaw)) {
    addViolation(violations, {
      code: 'GRAPH_NODES_NOT_ARRAY',
      severity: 'error',
      message: `${section} graph nodes must be an array.`,
      section,
      source_ref: sourceRef,
    });
  } else {
    for (let index = 0; index < nodesRaw.length; index += 1) {
      const node = nodesRaw[index];
      if (!isUnknownRecord(node) || !isUnknownRecord(node.data) || readOptionalString(node.data.id) === null) {
        addViolation(violations, {
          code: 'GRAPH_NODE_MISSING_ID',
          severity: 'error',
          message: `${section} graph node at index ${index} must include data.id string.`,
          section,
          source_ref: sourceRef,
        });
      }
    }
  }

  const edgesRaw = graph.edges;
  if (!Array.isArray(edgesRaw)) {
    addViolation(violations, {
      code: 'GRAPH_EDGES_NOT_ARRAY',
      severity: 'error',
      message: `${section} graph edges must be an array.`,
      section,
      source_ref: sourceRef,
    });
  } else {
    for (let index = 0; index < edgesRaw.length; index += 1) {
      const edge = edgesRaw[index];
      const isValid = isUnknownRecord(edge)
        && isUnknownRecord(edge.data)
        && readOptionalString(edge.data.source) !== null
        && readOptionalString(edge.data.target) !== null;
      if (!isValid) {
        addViolation(violations, {
          code: 'GRAPH_EDGE_MISSING_ENDPOINT',
          severity: 'error',
          message: `${section} graph edge at index ${index} must include data.source and data.target strings.`,
          section,
          source_ref: sourceRef,
        });
      }
    }
  }
}

function normalizeGraphRaw(value: unknown): unknown {
  if (!isUnknownRecord(value)) {
    return value;
  }

  if (isUnknownRecord(value.graphData)) {
    return value.graphData;
  }

  if (Array.isArray(value.nodes) || Array.isArray(value.edges)) {
    return {
      nodes: value.nodes,
      edges: value.edges,
    };
  }

  return value;
}

function deriveEdgeID(edge: GraphEdgeElement, duplicateIndex: number): string {
  const explicitID = readOptionalString(edge.data.id);
  if (explicitID !== null) {
    return explicitID;
  }

  const source = edge.data.source;
  const target = edge.data.target;
  const edgeType = readOptionalString(edge.data.edgeType) ?? '';
  const label = readOptionalString(edge.data.label) ?? '';
  return `edge:${source}|${target}|${edgeType}|${label}#${duplicateIndex}`;
}

function buildEdgeRows(edges: GraphEdgeElement[]): GraphEdgeRow[] {
  const duplicateCounter = new Map<string, number>();
  const rows: GraphEdgeRow[] = [];

  for (const edge of edges) {
    const base = `edge:${edge.data.source}|${edge.data.target}|${readOptionalString(edge.data.edgeType) ?? ''}|${readOptionalString(edge.data.label) ?? ''}`;
    const duplicateIndex = duplicateCounter.get(base) ?? 0;
    duplicateCounter.set(base, duplicateIndex + 1);

    rows.push({
      edge_id: deriveEdgeID(edge, duplicateIndex),
      source_node_id: edge.data.source,
      target_node_id: edge.data.target,
      edge_type: readOptionalString(edge.data.edgeType) ?? '',
      edge_color: readOptionalString(edge.data.edgeColor) ?? '',
      label: readOptionalString(edge.data.label) ?? '',
      is_deactivated: edge.data.isDeactivated === true,
      source_ref: REF_USER_GRAPH_EDGES,
    });
  }

  return rows;
}

function buildNodeRows(nodes: GraphNodeElement[]): GraphNodeRow[] {
  return nodes.map((node) => {
    const parentIDs = readStringArray(node.data.parentIds);
    if (parentIDs.length > 0) {
      return {
        node_id: node.data.id,
        label: readOptionalString(node.data.label) ?? '',
        style_class: readOptionalString(node.data.styleClass) ?? '',
        tier: typeof node.data.tier === 'number' && Number.isFinite(node.data.tier) ? node.data.tier : null,
        is_deactivated: node.data.isDeactivated === true,
        parent_ids: parentIDs,
        source_ref: REF_USER_GRAPH_NODES,
      };
    }

    const parentID = readOptionalString(node.data.parentId);
    return {
      node_id: node.data.id,
      label: readOptionalString(node.data.label) ?? '',
      style_class: readOptionalString(node.data.styleClass) ?? '',
      tier: typeof node.data.tier === 'number' && Number.isFinite(node.data.tier) ? node.data.tier : null,
      is_deactivated: node.data.isDeactivated === true,
      parent_ids: parentID === null ? [] : [parentID],
      source_ref: REF_USER_GRAPH_NODES,
    };
  });
}

function parseInterventions(
  interventionsCatalogData: unknown,
  violations: ValidationViolation[],
): ParsedInterventionRow[] {
  if (!isUnknownRecord(interventionsCatalogData)) {
    addViolation(violations, {
      code: 'INTERVENTIONS_CATALOG_INVALID',
      severity: 'error',
      message: 'interventions_catalog payload must be an object.',
      section: 'details.habit_links',
      source_ref: REF_INTERVENTIONS_CATALOG,
    });
    return [];
  }

  if (!Array.isArray(interventionsCatalogData.interventions)) {
    addViolation(violations, {
      code: 'INTERVENTIONS_NOT_ARRAY',
      severity: 'error',
      message: 'interventions_catalog.interventions must be an array.',
      section: 'details.habit_links',
      source_ref: REF_INTERVENTIONS_CATALOG,
    });
    return [];
  }

  const rows: ParsedInterventionRow[] = [];
  for (let index = 0; index < interventionsCatalogData.interventions.length; index += 1) {
    const entry = interventionsCatalogData.interventions[index];
    if (!isUnknownRecord(entry)) {
      addViolation(violations, {
        code: 'INTERVENTION_ENTRY_INVALID',
        severity: 'error',
        message: `interventions_catalog.interventions[${index}] must be an object.`,
        section: 'details.habit_links',
        source_ref: REF_INTERVENTIONS_CATALOG,
      });
      continue;
    }

    const id = readOptionalString(entry.id);
    if (id === null) {
      addViolation(violations, {
        code: 'INTERVENTION_ID_INVALID',
        severity: 'error',
        message: `interventions_catalog.interventions[${index}] must include id string.`,
        section: 'details.habit_links',
        source_ref: REF_INTERVENTIONS_CATALOG,
      });
      continue;
    }

    let graphNodeID: string | null = null;
    if (Object.prototype.hasOwnProperty.call(entry, 'graphNodeId')) {
      const parsed = readOptionalString(entry.graphNodeId);
      if (parsed === null && entry.graphNodeId !== null) {
        addViolation(violations, {
          code: 'INTERVENTION_GRAPH_NODE_INVALID',
          severity: 'error',
          message: `interventions_catalog.interventions[${index}].graphNodeId must be a string when present.`,
          section: 'details.habit_links',
          source_ref: REF_INTERVENTIONS_CATALOG,
        });
      }
      graphNodeID = parsed;
    }

    let pillars = readStringArray(entry.pillars);
    if (Object.prototype.hasOwnProperty.call(entry, 'pillars') && !Array.isArray(entry.pillars)) {
      addViolation(violations, {
        code: 'INTERVENTION_PILLARS_INVALID',
        severity: 'error',
        message: `interventions_catalog.interventions[${index}].pillars must be an array when present.`,
        section: 'details.habit_links',
        source_ref: REF_INTERVENTIONS_CATALOG,
      });
      pillars = [];
    }

    let planningTags = readStringArray(entry.planningTags);
    if (Object.prototype.hasOwnProperty.call(entry, 'planningTags') && !Array.isArray(entry.planningTags)) {
      addViolation(violations, {
        code: 'INTERVENTION_PLANNING_TAGS_INVALID',
        severity: 'error',
        message: `interventions_catalog.interventions[${index}].planningTags must be an array when present.`,
        section: 'details.habit_links',
        source_ref: REF_INTERVENTIONS_CATALOG,
      });
      planningTags = [];
    }

    let graphEdgeIDs = readStringArray(entry.graphEdgeIds);
    if (Object.prototype.hasOwnProperty.call(entry, 'graphEdgeIds') && !Array.isArray(entry.graphEdgeIds)) {
      addViolation(violations, {
        code: 'INTERVENTION_GRAPH_EDGE_IDS_INVALID',
        severity: 'error',
        message: `interventions_catalog.interventions[${index}].graphEdgeIds must be an array when present.`,
        section: 'details.habit_links',
        source_ref: REF_INTERVENTIONS_CATALOG,
      });
      graphEdgeIDs = [];
    }

    rows.push({
      id,
      name: readOptionalString(entry.name) ?? id,
      graphNodeID,
      graphEdgeIDs,
      pillars,
      planningTags,
    });
  }

  return rows;
}

function parseProgressQuestions(
  userStore: UnknownRecord,
  violations: ValidationViolation[],
): ParsedQuestions {
  const progressState = isUnknownRecord(userStore.progressQuestionSetState)
    ? userStore.progressQuestionSetState
    : null;

  if (progressState === null) {
    addViolation(violations, {
      code: 'PROGRESS_QUESTION_STATE_MISSING',
      severity: 'warning',
      message: 'progressQuestionSetState missing in user_data; outcome question links unavailable.',
      section: 'details.outcome_question_links',
      source_ref: REF_PROGRESS_QUESTIONS,
    });
    return {
      rows: [],
      reason: 'progressQuestionSetState missing',
    };
  }

  const parseQuestionRows = (
    questions: unknown[],
    contextLabel: string,
  ): ParsedQuestionRow[] => {
    const rows: ParsedQuestionRow[] = [];

    for (let index = 0; index < questions.length; index += 1) {
      const question = questions[index];
      if (!isUnknownRecord(question)) {
        addViolation(violations, {
          code: 'PROGRESS_QUESTION_ENTRY_INVALID',
          severity: 'error',
          message: `${contextLabel}[${index}] must be an object.`,
          section: 'details.outcome_question_links',
          source_ref: REF_PROGRESS_QUESTIONS,
        });
        continue;
      }

      const id = readOptionalString(question.id);
      const title = readOptionalString(question.title);
      const sourceNodeIDs = readStringArray(question.sourceNodeIDs);
      const sourceEdgeIDs = readStringArray(question.sourceEdgeIDs);

      if (id === null || title === null) {
        addViolation(violations, {
          code: 'PROGRESS_QUESTION_ID_OR_TITLE_INVALID',
          severity: 'error',
          message: `${contextLabel}[${index}] must include id and title strings.`,
          section: 'details.outcome_question_links',
          source_ref: REF_PROGRESS_QUESTIONS,
        });
        continue;
      }

      if (!Array.isArray(question.sourceNodeIDs) || !Array.isArray(question.sourceEdgeIDs)) {
        addViolation(violations, {
          code: 'PROGRESS_QUESTION_SOURCES_INVALID',
          severity: 'error',
          message: `${contextLabel}[${index}] must include sourceNodeIDs[] and sourceEdgeIDs[].`,
          section: 'details.outcome_question_links',
          source_ref: REF_PROGRESS_QUESTIONS,
        });
        continue;
      }

      rows.push({
        id,
        title,
        sourceNodeIDs,
        sourceEdgeIDs,
      });
    }

    return rows;
  };

  if (Object.prototype.hasOwnProperty.call(progressState, 'activeQuestions') && !Array.isArray(progressState.activeQuestions)) {
    addViolation(violations, {
      code: 'PROGRESS_ACTIVE_QUESTION_LIST_INVALID',
      severity: 'error',
      message: 'activeQuestions must be an array when present.',
      section: 'details.outcome_question_links',
      source_ref: REF_PROGRESS_QUESTIONS,
    });
  }

  const activeQuestions = Array.isArray(progressState.activeQuestions) ? progressState.activeQuestions : [];
  if (activeQuestions.length > 0) {
    return {
      rows: parseQuestionRows(activeQuestions, 'activeQuestions'),
      reason: null,
    };
  }

  const proposal = isUnknownRecord(progressState.pendingProposal)
    ? progressState.pendingProposal
    : null;
  if (proposal === null) {
    addViolation(violations, {
      code: 'PROGRESS_QUESTION_SOURCES_MISSING',
      severity: 'warning',
      message: 'Both activeQuestions and pendingProposal are missing in progressQuestionSetState.',
      section: 'details.outcome_question_links',
      source_ref: REF_PROGRESS_QUESTIONS,
    });
    return {
      rows: [],
      reason: 'activeQuestions and pendingProposal missing',
    };
  }

  if (!Array.isArray(proposal.questions)) {
    addViolation(violations, {
      code: 'PROGRESS_QUESTION_LIST_INVALID',
      severity: 'error',
      message: 'pendingProposal.questions must be an array.',
      section: 'details.outcome_question_links',
      source_ref: REF_PROGRESS_QUESTIONS,
    });
    return {
      rows: [],
      reason: 'pendingProposal.questions invalid',
    };
  }

  addViolation(violations, {
    code: 'PROGRESS_QUESTION_ACTIVE_FALLBACK_PENDING',
    severity: 'warning',
    message: 'Using pendingProposal.questions because activeQuestions is empty.',
    section: 'details.outcome_question_links',
    source_ref: REF_PROGRESS_QUESTIONS,
  });
  return {
    rows: parseQuestionRows(proposal.questions, 'pendingProposal.questions'),
    reason: 'activeQuestions empty; using pendingProposal',
  };
}

function createSourceRecencyEntry(ref: ProvenanceRef): SourceRecencyEntry {
  return {
    updated_at: ref.updated_at,
    version: ref.version,
    source: ref.table_or_file,
  };
}

function buildHabitLinks(
  interventions: ParsedInterventionRow[],
  activeIDs: Set<string>,
  hiddenIDs: Set<string>,
  graphNodeIDSet: Set<string>,
  graphEdgeIDSet: Set<string>,
  outgoingEdgesBySource: Map<string, GraphEdgeRow[]>,
): HabitLinkRow[] {
  return interventions.map((intervention) => {
    const graphNodeID = intervention.graphNodeID;
    const graphEdgeIDs = intervention.graphEdgeIDs;
    const sourceExists = graphNodeID !== null && graphNodeIDSet.has(graphNodeID);
    const outgoingEdges = graphNodeID === null ? [] : outgoingEdgesBySource.get(graphNodeID) ?? [];
    const targetNodeIDs = [...new Set(outgoingEdges.map((edge) => edge.target_node_id))]
      .sort((left, right) => left.localeCompare(right));
    const missingGraphEdgeIDs = graphEdgeIDs
      .filter((edgeID) => !graphEdgeIDSet.has(edgeID))
      .sort((left, right) => left.localeCompare(right));
    const sourceEdgesExist = missingGraphEdgeIDs.length === 0;

    const missingReasons: string[] = [];
    if (graphNodeID === null) {
      missingReasons.push('missing_graph_node_id');
    } else if (!sourceExists) {
      missingReasons.push('source_node_not_in_user_graph');
    }
    if (graphEdgeIDs.length > 0 && !sourceEdgesExist) {
      missingReasons.push('graph_edge_id_not_in_user_graph');
    }

    return {
      intervention_id: intervention.id,
      name: intervention.name,
      graph_node_id: graphNodeID,
      graph_edge_ids: graphEdgeIDs,
      is_active: activeIDs.has(intervention.id),
      is_hidden: hiddenIDs.has(intervention.id),
      pillars: intervention.pillars,
      planning_tags: intervention.planningTags,
      source_node_exists: sourceExists,
      source_edges_exist: sourceEdgesExist,
      missing_graph_edge_ids: missingGraphEdgeIDs,
      outgoing_edge_ids: outgoingEdges.map((edge) => edge.edge_id),
      target_node_ids: targetNodeIDs,
      missing_reasons: missingReasons,
      source_ref: REF_INTERVENTIONS_CATALOG,
    };
  });
}

function buildOutcomeQuestionLinks(
  questions: ParsedQuestionRow[],
  graphNodeIDSet: Set<string>,
  graphEdgeIDSet: Set<string>,
): OutcomeQuestionLinkRow[] {
  return questions.map((question) => {
    const missingNodeIDs = question.sourceNodeIDs
      .filter((id) => !graphNodeIDSet.has(id))
      .sort((left, right) => left.localeCompare(right));

    const missingEdgeIDs = question.sourceEdgeIDs
      .filter((id) => !graphEdgeIDSet.has(id))
      .sort((left, right) => left.localeCompare(right));

    return {
      question_id: question.id,
      title: question.title,
      source_node_ids: question.sourceNodeIDs,
      source_edge_ids: question.sourceEdgeIDs,
      missing_node_ids: missingNodeIDs,
      missing_edge_ids: missingEdgeIDs,
      link_status: missingNodeIDs.length === 0 && missingEdgeIDs.length === 0
        ? 'linked'
        : 'missing_sources',
      source_ref: REF_PROGRESS_QUESTIONS,
    };
  });
}

function ensureRefExists(
  refs: Record<string, ProvenanceRef>,
  token: string,
): void {
  if (!Object.prototype.hasOwnProperty.call(refs, token)) {
    throw new Error(`Missing provenance ref token: ${token}`);
  }
}

function validateSourceRefs(
  report: UserGraphAuditReport,
): void {
  const refs = report.provenance.refs;

  for (const row of report.details.graph_nodes) {
    ensureRefExists(refs, row.source_ref);
  }

  for (const row of report.details.graph_edges) {
    ensureRefExists(refs, row.source_ref);
  }

  for (const row of report.details.habit_links) {
    ensureRefExists(refs, row.source_ref);
  }

  for (const row of report.details.outcome_question_links) {
    ensureRefExists(refs, row.source_ref);
  }

  ensureRefExists(refs, report.details.canonical_baseline.source_ref);
}

export function buildAuditReport(input: BuildAuditInput): UserGraphAuditReport {
  const violations: ValidationViolation[] = [];

  const normalizedUserGraphRaw = normalizeGraphRaw(input.userGraphRaw);
  validateRawGraphShape(
    normalizedUserGraphRaw,
    'details.user_graph',
    REF_USER_GRAPH_NODES,
    violations,
  );

  const normalizedCanonicalGraphRaw = normalizeGraphRaw(input.canonicalGraphRaw);
  validateRawGraphShape(
    normalizedCanonicalGraphRaw,
    'details.canonical_graph',
    REF_CANONICAL_GRAPH,
    violations,
  );

  const userGraph = loadGraphFromUnknown(normalizedUserGraphRaw);
  const canonicalGraph = loadGraphFromUnknown(normalizedCanonicalGraphRaw);

  const graphNodeRows = buildNodeRows(userGraph.nodes);
  const graphEdgeRows = buildEdgeRows(userGraph.edges);

  const graphNodeIDSet = new Set(graphNodeRows.map((row) => row.node_id));
  const graphEdgeIDSet = new Set(graphEdgeRows.map((row) => row.edge_id));
  const userEdgeSignatureSet = new Set(userGraph.edges.map((edge) => edgeSignature(edge.data)));

  const outgoingEdgesBySource = new Map<string, GraphEdgeRow[]>();
  for (const edge of graphEdgeRows) {
    const current = outgoingEdgesBySource.get(edge.source_node_id) ?? [];
    current.push(edge);
    outgoingEdgesBySource.set(edge.source_node_id, current);
  }

  const interventions = parseInterventions(input.interventionsCatalogData, violations);
  const activeIDs = new Set(readStringArray(input.userStore.activeInterventions));
  const hiddenIDs = new Set(readStringArray(input.userStore.hiddenInterventions));
  const habitLinks = buildHabitLinks(
    interventions,
    activeIDs,
    hiddenIDs,
    graphNodeIDSet,
    graphEdgeIDSet,
    outgoingEdgesBySource,
  );

  const parsedQuestions = parseProgressQuestions(input.userStore, violations);
  const outcomeQuestionLinks = buildOutcomeQuestionLinks(parsedQuestions.rows, graphNodeIDSet, graphEdgeIDSet);

  for (const habitLink of habitLinks) {
    if (habitLink.missing_graph_edge_ids.length === 0) {
      continue;
    }

    addViolation(violations, {
      code: 'HABIT_GRAPH_EDGE_MISSING',
      severity: 'error',
      message: `Habit ${habitLink.intervention_id} references missing graphEdgeIds: ${habitLink.missing_graph_edge_ids.join(', ')}`,
      section: 'details.habit_links',
      source_ref: REF_INTERVENTIONS_CATALOG,
    });
  }

  if (!isUnknownRecord(input.outcomesMetadataData) || !Array.isArray(input.outcomesMetadataData.nodes)) {
    addViolation(violations, {
      code: 'OUTCOMES_METADATA_MISSING_OR_INVALID',
      severity: 'warning',
      message: 'outcomes_metadata missing or invalid; report uses progress proposal links only.',
      section: 'summary.source_row_recency',
      source_ref: REF_OUTCOMES_METADATA,
    });
  }

  if (input.planningPolicyData === null) {
    addViolation(violations, {
      code: 'PLANNING_POLICY_MISSING',
      severity: 'warning',
      message: 'planning_policy_v1 missing; summary uses raw pillar IDs from catalog.',
      section: 'summary',
      source_ref: REF_PLANNING_POLICY,
    });
  }

  const missingCanonicalNodeIDs = canonicalGraph.nodes
    .map((node) => node.data.id)
    .filter((nodeID) => !graphNodeIDSet.has(nodeID))
    .sort((left, right) => left.localeCompare(right));

  const missingCanonicalEdgeSignatures = canonicalGraph.edges
    .map((edge) => edgeSignature(edge.data))
    .filter((signature) => !userEdgeSignatureSet.has(signature))
    .filter((signature, index, list) => list.indexOf(signature) === index)
    .sort((left, right) => left.localeCompare(right));

  const habitsLinkedCount = habitLinks.filter((row) => row.source_node_exists).length;
  const habitsUnlinkedCount = habitLinks.length - habitsLinkedCount;
  const habitsMissingEdgeLinksCount = habitLinks.filter((row) => row.missing_graph_edge_ids.length > 0).length;

  const outcomeQuestionsLinkedCount = outcomeQuestionLinks.filter((row) => row.link_status === 'linked').length;
  const outcomeQuestionsUnlinkedCount = outcomeQuestionLinks.length - outcomeQuestionsLinkedCount;

  const missingHabitSourceNodeCount = habitLinks.filter((row) => row.source_node_exists === false).length;
  const missingHabitSourceEdgeCount = habitLinks.reduce((total, row) => total + row.missing_graph_edge_ids.length, 0);
  const missingQuestionNodeCount = outcomeQuestionLinks.reduce((total, row) => total + row.missing_node_ids.length, 0);
  const missingQuestionEdgeCount = outcomeQuestionLinks.reduce((total, row) => total + row.missing_edge_ids.length, 0);

  const summary: SummaryBlock = {
    user_graph_node_count: graphNodeRows.length,
    user_graph_edge_count: graphEdgeRows.length,
    canonical_graph_node_count: canonicalGraph.nodes.length,
    canonical_graph_edge_count: canonicalGraph.edges.length,
    interventions_total: interventions.length,
    interventions_with_graph_node_id: interventions.filter((row) => row.graphNodeID !== null).length,
    interventions_with_graph_edge_ids: interventions.filter((row) => row.graphEdgeIDs.length > 0).length,
    habits_linked_count: habitsLinkedCount,
    habits_unlinked_count: habitsUnlinkedCount,
    habits_missing_edge_links_count: habitsMissingEdgeLinksCount,
    outcome_questions_total: outcomeQuestionLinks.length,
    outcome_questions_linked_count: outcomeQuestionsLinkedCount,
    outcome_questions_unlinked_count: outcomeQuestionsUnlinkedCount,
    missing_source_node_count: missingHabitSourceNodeCount + missingQuestionNodeCount,
    missing_source_edge_count: missingHabitSourceEdgeCount + missingQuestionEdgeCount,
    outcome_questions_reason: parsedQuestions.reason,
    source_row_recency: {
      user_data: createSourceRecencyEntry(input.provenance.refs[REF_USER_DATA_ROW]),
      interventions_catalog: createSourceRecencyEntry(input.provenance.refs[REF_INTERVENTIONS_CATALOG]),
      outcomes_metadata: createSourceRecencyEntry(input.provenance.refs[REF_OUTCOMES_METADATA]),
      canonical_graph: createSourceRecencyEntry(input.provenance.refs[REF_CANONICAL_GRAPH]),
      planning_policy: createSourceRecencyEntry(input.provenance.refs[REF_PLANNING_POLICY]),
    },
  };

  const details: DetailsBlock = {
    graph_nodes: graphNodeRows,
    graph_edges: graphEdgeRows,
    habit_links: habitLinks,
    outcome_question_links: outcomeQuestionLinks,
    canonical_baseline: {
      canonical_node_count: canonicalGraph.nodes.length,
      canonical_edge_count: canonicalGraph.edges.length,
      missing_user_node_ids: missingCanonicalNodeIDs,
      missing_user_edge_signatures: missingCanonicalEdgeSignatures,
      source_ref: REF_CANONICAL_GRAPH,
    },
  };

  const validation: ValidationBlock = {
    status: violations.some((violation) => violation.severity === 'error') ? 'fail' : 'pass',
    violations,
  };

  const report: UserGraphAuditReport = {
    audit_version: AUDIT_VERSION,
    generated_at: new Date().toISOString(),
    input: {
      user_id: input.userID,
    },
    summary,
    details,
    provenance: input.provenance,
    validation,
  };

  validateSourceRefs(report);

  return report;
}

export function resolveCanonicalGraphFromSources(input: {
  firstPartyGraphData: unknown | null;
  firstPartyUpdatedAt: string | null;
  firstPartyVersion: number | null;
  fallbackLocalPath?: string;
  fallbackLocalPaths?: string[];
}): CanonicalGraphResolution {
  if (input.firstPartyGraphData !== null) {
    return {
      graphRaw: input.firstPartyGraphData,
      source: 'first_party_content',
      updatedAt: input.firstPartyUpdatedAt,
      version: input.firstPartyVersion,
      fallbackUsed: false,
      sourcePathOrSelector: 'first_party_content(graph/canonical_causal_graph)',
    };
  }

  const fallbackLocalPaths = Array.isArray(input.fallbackLocalPaths)
    ? input.fallbackLocalPaths
    : input.fallbackLocalPath === undefined
      ? []
      : [input.fallbackLocalPath];

  if (fallbackLocalPaths.length === 0) {
    throw new Error('No fallback canonical graph path configured.');
  }

  const resolvedPath = fallbackLocalPaths.find((entry) => existsSync(entry))
    ?? fallbackLocalPaths[0];
  const graphData = loadGraphFromPath(resolvedPath);
  return {
    graphRaw: graphData,
    source: 'local_file',
    updatedAt: null,
    version: null,
    fallbackUsed: true,
    sourcePathOrSelector: resolvedPath,
  };
}

function buildDefaultOutputPath(userID: string): string {
  const timestamp = new Date().toISOString().replace(/[:]/g, '-');
  return path.resolve(process.cwd(), 'artifacts', 'user-graph-audit', `${userID}-${timestamp}.json`);
}

function makeProvenance(
  userID: string,
  userDataUpdatedAt: string | null,
  interventions: ContentPayload,
  outcomesMetadata: ContentPayload,
  canonicalGraph: CanonicalGraphResolution,
  planningPolicy: ContentPayload | null,
): ProvenanceBlock {
  const refs: Record<string, ProvenanceRef> = {
    [REF_USER_DATA_ROW]: {
      table_or_file: 'public.user_data',
      selector: { user_id: userID },
      updated_at: userDataUpdatedAt,
      version: null,
      fallback_used: false,
      path_hint: 'data',
    },
    [REF_USER_GRAPH_NODES]: {
      table_or_file: 'public.user_data',
      selector: { user_id: userID },
      updated_at: userDataUpdatedAt,
      version: null,
      fallback_used: false,
      path_hint: 'data.customCausalDiagram.graphData.nodes',
    },
    [REF_USER_GRAPH_EDGES]: {
      table_or_file: 'public.user_data',
      selector: { user_id: userID },
      updated_at: userDataUpdatedAt,
      version: null,
      fallback_used: false,
      path_hint: 'data.customCausalDiagram.graphData.edges',
    },
    [REF_INTERVENTIONS_CATALOG]: {
      table_or_file: interventions.source === 'user_content' ? 'public.user_content' : 'public.first_party_content',
      selector: interventions.source === 'user_content'
        ? { user_id: userID, content_type: 'inputs', content_key: 'interventions_catalog' }
        : { content_type: 'inputs', content_key: 'interventions_catalog' },
      updated_at: interventions.updatedAt,
      version: interventions.version,
      fallback_used: interventions.source === 'first_party_content',
      path_hint: 'data.interventions',
    },
    [REF_OUTCOMES_METADATA]: {
      table_or_file: outcomesMetadata.source === 'user_content' ? 'public.user_content' : 'public.first_party_content',
      selector: outcomesMetadata.source === 'user_content'
        ? { user_id: userID, content_type: 'outcomes', content_key: 'outcomes_metadata' }
        : { content_type: 'outcomes', content_key: 'outcomes_metadata' },
      updated_at: outcomesMetadata.updatedAt,
      version: outcomesMetadata.version,
      fallback_used: outcomesMetadata.source === 'first_party_content',
      path_hint: 'data.nodes',
    },
    [REF_PROGRESS_QUESTIONS]: {
      table_or_file: 'public.user_data',
      selector: { user_id: userID },
      updated_at: userDataUpdatedAt,
      version: null,
      fallback_used: false,
      path_hint: 'data.progressQuestionSetState.pendingProposal.questions',
    },
    [REF_CANONICAL_GRAPH]: {
      table_or_file: canonicalGraph.source === 'first_party_content' ? 'public.first_party_content' : canonicalGraph.sourcePathOrSelector,
      selector: canonicalGraph.source === 'first_party_content'
        ? { content_type: 'graph', content_key: 'canonical_causal_graph' }
        : { path: canonicalGraph.sourcePathOrSelector },
      updated_at: canonicalGraph.updatedAt,
      version: canonicalGraph.version,
      fallback_used: canonicalGraph.fallbackUsed,
      path_hint: canonicalGraph.source === 'first_party_content' ? 'data.nodes,data.edges' : 'nodes,edges',
    },
    [REF_PLANNING_POLICY]: {
      table_or_file: planningPolicy === null
        ? 'missing'
        : planningPolicy.source === 'user_content'
          ? 'public.user_content'
          : 'public.first_party_content',
      selector: planningPolicy === null
        ? { content_type: 'planning', content_key: 'planner_policy_v1' }
        : planningPolicy.source === 'user_content'
          ? { user_id: userID, content_type: 'planning', content_key: 'planner_policy_v1' }
          : { content_type: 'planning', content_key: 'planner_policy_v1' },
      updated_at: planningPolicy?.updatedAt ?? null,
      version: planningPolicy?.version ?? null,
      fallback_used: planningPolicy === null || planningPolicy.source === 'first_party_content',
      path_hint: 'data.pillars',
    },
  };

  return {
    refs,
    sections: {
      summary: [
        REF_USER_DATA_ROW,
        REF_INTERVENTIONS_CATALOG,
        REF_OUTCOMES_METADATA,
        REF_CANONICAL_GRAPH,
        REF_PLANNING_POLICY,
      ],
      details: {
        graph_nodes: [REF_USER_GRAPH_NODES],
        graph_edges: [REF_USER_GRAPH_EDGES],
        habit_links: [REF_INTERVENTIONS_CATALOG, REF_USER_GRAPH_NODES, REF_USER_GRAPH_EDGES],
        outcome_question_links: [REF_PROGRESS_QUESTIONS, REF_USER_GRAPH_NODES, REF_USER_GRAPH_EDGES],
        canonical_baseline: [REF_CANONICAL_GRAPH, REF_USER_GRAPH_NODES, REF_USER_GRAPH_EDGES],
      },
      validation: [
        REF_USER_GRAPH_NODES,
        REF_USER_GRAPH_EDGES,
        REF_INTERVENTIONS_CATALOG,
        REF_PROGRESS_QUESTIONS,
        REF_CANONICAL_GRAPH,
      ],
    },
  };
}

function printSummary(report: UserGraphAuditReport, outputPath: string): void {
  console.log('User Graph Audit Report');
  console.log(`User ID: ${report.input.user_id}`);
  console.log(`Generated at: ${report.generated_at}`);
  console.log(
    `Graph nodes ${report.summary.user_graph_node_count}/${report.summary.canonical_graph_node_count} | edges ${report.summary.user_graph_edge_count}/${report.summary.canonical_graph_edge_count}`,
  );
  console.log(`Habits linked/unlinked: ${report.summary.habits_linked_count}/${report.summary.habits_unlinked_count}`);
  console.log(`Habits with missing graphEdgeIds: ${report.summary.habits_missing_edge_links_count}`);
  console.log(`Outcome questions linked/unlinked: ${report.summary.outcome_questions_linked_count}/${report.summary.outcome_questions_unlinked_count}`);
  console.log(`Missing source nodes: ${report.summary.missing_source_node_count}`);
  console.log(`Missing source edges: ${report.summary.missing_source_edge_count}`);
  console.log(`Validation status: ${report.validation.status}`);
  console.log(`Output: ${outputPath}`);
}

async function run(): Promise<void> {
  const args = parseArgs();
  if (args.userID === null) {
    printUsageAndExit();
  }

  const supabaseURL = requiredEnv('SUPABASE_URL');
  const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');

  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const fetchUserOrFirstPartyContent = async (
    userID: string,
    contentType: string,
    contentKey: string,
  ): Promise<ContentPayload | null> => {
    const userQuery = await supabase
      .from('user_content')
      .select('data,updated_at,version')
      .eq('user_id', userID)
      .eq('content_type', contentType)
      .eq('content_key', contentKey)
      .limit(1)
      .maybeSingle();

    if (userQuery.error) {
      throw new Error(`user_content ${contentType}/${contentKey} query failed: ${userQuery.error.message}`);
    }

    if (userQuery.data) {
      return {
        data: userQuery.data.data,
        source: 'user_content',
        updatedAt: userQuery.data.updated_at,
        version: userQuery.data.version,
      };
    }

    const firstPartyQuery = await supabase
      .from('first_party_content')
      .select('data,updated_at,version')
      .eq('content_type', contentType)
      .eq('content_key', contentKey)
      .limit(1)
      .maybeSingle();

    if (firstPartyQuery.error) {
      throw new Error(`first_party_content ${contentType}/${contentKey} query failed: ${firstPartyQuery.error.message}`);
    }

    if (firstPartyQuery.data) {
      return {
        data: firstPartyQuery.data.data,
        source: 'first_party_content',
        updatedAt: firstPartyQuery.data.updated_at,
        version: firstPartyQuery.data.version,
      };
    }

    return null;
  };

  const userDataQuery = await supabase
    .from('user_data')
    .select('user_id,updated_at,data')
    .eq('user_id', args.userID)
    .maybeSingle();

  if (userDataQuery.error) {
    throw new Error(`user_data query failed: ${userDataQuery.error.message}`);
  }

  if (!userDataQuery.data) {
    throw new Error(`No user_data row found for user_id=${args.userID}`);
  }

  const userStore = isUnknownRecord(userDataQuery.data.data) ? userDataQuery.data.data : {};
  const customDiagram = isUnknownRecord(userStore.customCausalDiagram) ? userStore.customCausalDiagram : {};
  const userGraphRaw = normalizeGraphRaw(customDiagram);

  const interventionsCatalog = await fetchUserOrFirstPartyContent(
    args.userID,
    'inputs',
    'interventions_catalog',
  );
  if (interventionsCatalog === null) {
    throw new Error('Missing interventions_catalog in user_content and first_party_content.');
  }

  const outcomesMetadata = await fetchUserOrFirstPartyContent(
    args.userID,
    'outcomes',
    'outcomes_metadata',
  );
  if (outcomesMetadata === null) {
    throw new Error('Missing outcomes_metadata in user_content and first_party_content.');
  }

  const planningPolicy = await fetchUserOrFirstPartyContent(
    args.userID,
    'planning',
    'planner_policy_v1',
  );

  const firstPartyGraphQuery = await supabase
    .from('first_party_content')
    .select('data,updated_at,version')
    .eq('content_type', 'graph')
    .eq('content_key', 'canonical_causal_graph')
    .limit(1)
    .maybeSingle();

  if (firstPartyGraphQuery.error) {
    throw new Error(`first_party_content graph/canonical_causal_graph query failed: ${firstPartyGraphQuery.error.message}`);
  }

  const canonicalGraph = resolveCanonicalGraphFromSources({
    firstPartyGraphData: firstPartyGraphQuery.data?.data ?? null,
    firstPartyUpdatedAt: firstPartyGraphQuery.data?.updated_at ?? null,
    firstPartyVersion: firstPartyGraphQuery.data?.version ?? null,
    fallbackLocalPaths: DEFAULT_CANONICAL_GRAPH_PATHS.map((entry) => path.resolve(process.cwd(), entry)),
  });

  const provenance = makeProvenance(
    args.userID,
    userDataQuery.data.updated_at,
    interventionsCatalog,
    outcomesMetadata,
    canonicalGraph,
    planningPolicy,
  );

  const report = buildAuditReport({
    userID: args.userID,
    userDataUpdatedAt: userDataQuery.data.updated_at,
    userStore,
    userGraphRaw,
    canonicalGraphRaw: canonicalGraph.graphRaw,
    interventionsCatalogData: interventionsCatalog.data,
    outcomesMetadataData: outcomesMetadata.data,
    planningPolicyData: planningPolicy?.data ?? null,
    provenance,
  });

  const outputPath = args.reportOut === null
    ? buildDefaultOutputPath(args.userID)
    : path.isAbsolute(args.reportOut)
      ? args.reportOut
      : path.resolve(process.cwd(), args.reportOut);

  mkdirSync(path.dirname(outputPath), { recursive: true });
  const spacing = args.pretty ? 2 : 0;
  writeFileSync(outputPath, JSON.stringify(report, null, spacing));

  printSummary(report, outputPath);

  if (args.raw) {
    console.log('');
    console.log(JSON.stringify(report, null, spacing));
  }

  if (report.validation.status === 'fail') {
    process.exit(2);
  }
}

const invokedPath = process.argv[1] ?? '';
const isMainModule = invokedPath.endsWith('debug-user-graph-audit.ts');

if (isMainModule) {
  run().catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    process.exit(1);
  });
}
