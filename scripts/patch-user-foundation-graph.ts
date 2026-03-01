import process from 'node:process';
import path from 'node:path';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import {
  edgeSignature,
  GraphData,
  GraphEdgeElement,
  GraphNodeElement,
  isUnknownRecord,
  loadGraphFromUnknown,
} from './pillar-integrity-lib';
import { AUTHORIZED_USER_ID } from './user-graph-patch-lib';

const MAP_FILE_PATH = 'data/health-report-habit-map.v1.json';
const REPORT_FILE_PATH = 'docs/health_graph_report.md';

interface ParsedArgs {
  userID: string | null;
  write: boolean;
  dryRun: boolean;
  traceOut: string | null;
}

interface MentionCoverageRow {
  mention: string;
  canonicalHabitId: string;
  source: string;
  section: string;
  line: number;
}

interface MentionTraceRow {
  mention: string;
  source: string;
  section: string;
  line: number;
}

interface StateNodeTemplate {
  id: string;
  label: string;
  styleClass: string;
  confirmed: string;
  tier: number;
}

interface PreferredWindow {
  startMinutes: number;
  endMinutes: number;
}

interface CanonicalHabitTemplate {
  id: string;
  slug: string;
  name: string;
  aliases: string[];
  mentionTrace: MentionTraceRow[];
  pillars: string[];
  planningTags: string[];
  targetNodeIds: string[];
  targetEdgeIds: string[];
  existingInterventionId: string | null;
  foundationRole: 'blocker' | 'maintenance';
  defaultMinutes: number;
  ladderTemplateID: string;
  preferredWindows: PreferredWindow[];
}

interface LoopEdgeSpec {
  source: string;
  target: string;
  edgeType: string;
  label: string;
}

interface LoopTemplate {
  id: string;
  title: string;
  line: number;
  phrases: string[];
  edgeSpecs: LoopEdgeSpec[];
}

interface LoopTemplateGroups {
  virtuous: LoopTemplate[];
  vicious: LoopTemplate[];
  compound: LoopTemplate[];
}

interface HabitMapFile {
  schemaVersion: string;
  sourceReportPath: string;
  parseCoverage: {
    totalMentions: number;
    uniqueMentionCount: number;
    canonicalHabitCount: number;
  };
  mentionCoverage: MentionCoverageRow[];
  stateNodeTemplates: StateNodeTemplate[];
  canonicalHabits: CanonicalHabitTemplate[];
  loopTemplates: LoopTemplateGroups;
}

interface ResolvedUserGraph {
  graph: GraphData;
  hadWrappedGraphData: boolean;
  currentGraphVersion: string | null;
}

interface ContentPayload {
  data: unknown;
  source: 'user_content' | 'first_party_content';
  userContentVersion: number | null;
}

interface ParsedIntervention {
  id: string;
  value: Record<string, unknown>;
}

interface EdgeRow {
  edgeID: string;
  source: string;
  target: string;
}

interface EdgeIndex {
  idsBySignature: Map<string, string>;
  duplicateCounterByBase: Map<string, number>;
}

interface HabitResolution {
  habitID: string;
  habitName: string;
  interventionID: string;
  graphNodeID: string;
  targetNodeIDs: string[];
  graphEdgeIDs: string[];
  reusedIntervention: boolean;
  addedIntervention: boolean;
}

interface TraceReport {
  generatedAt: string;
  userID: string;
  mapSchemaVersion: string;
  reportMentionsParsed: number;
  mentionCoverageCount: number;
  canonicalHabitCount: number;
  reusedInterventionCount: number;
  addedInterventionCount: number;
  graphNodeCountBefore: number;
  graphNodeCountAfter: number;
  graphEdgeCountBefore: number;
  graphEdgeCountAfter: number;
  addedNodeIDs: string[];
  addedEdgeIDs: string[];
  interventionsBefore: number;
  interventionsAfter: number;
  pendingQuestionsBefore: number;
  pendingQuestionsAfter: number;
  foundationQuestionIDs: string[];
  nextGraphVersion: string;
  dataChanged: boolean;
  userContentChanged: boolean;
  habitResolutions: HabitResolution[];
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

function parseArgs(): ParsedArgs {
  const write = hasFlag('write');
  const dryRunFlag = hasFlag('dry-run');

  if (write && dryRunFlag) {
    throw new Error('Choose either --dry-run or --write, not both.');
  }

  return {
    userID: getArg('user-id') ?? process.env.SUPABASE_DEBUG_USER_ID ?? null,
    write,
    dryRun: dryRunFlag || !write,
    traceOut: getArg('trace-out'),
  };
}

function printUsageAndExit(): never {
  console.error('Usage: npm run patch:user-foundation-graph -- --user-id <uuid> [--dry-run|--write] [--trace-out <path>]');
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

function readNumber(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return null;
  }

  return value;
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

function uniqueSorted(values: string[]): string[] {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

function ensureRecord(parent: Record<string, unknown>, key: string): Record<string, unknown> {
  const current = parent[key];
  if (isUnknownRecord(current)) {
    return current;
  }

  const created: Record<string, unknown> = {};
  parent[key] = created;
  return created;
}

function normalizeAlias(value: string): string {
  return value
    .toLowerCase()
    .replace(/\*\*/g, '')
    .replace(/[^a-z0-9+\s/-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeForLabel(value: string): string {
  return value
    .replace(/_/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function titleCaseWords(value: string): string {
  return value
    .split(' ')
    .map((word) => {
      if (word.length === 0) {
        return word;
      }
      return `${word[0].toUpperCase()}${word.slice(1).toLowerCase()}`;
    })
    .join(' ');
}

function normalizeNodeLabel(value: string): string {
  const withoutLoopPrefix = value.replace(/^loop\s*state\b[\s:.-]*/i, '');
  const withoutFoundationPrefix = withoutLoopPrefix.replace(/^foundation:\s*/i, '');
  const compact = withoutFoundationPrefix.replace(/\s+/g, ' ').trim();
  if (compact.length === 0) {
    return value.replace(/\s+/g, ' ').trim();
  }
  if (/^[a-z]/.test(compact)) {
    return `${compact[0].toUpperCase()}${compact.slice(1)}`;
  }
  return compact;
}

function labelFromNodeID(nodeID: string): string {
  const compact = normalizeForLabel(nodeID)
    .replace(/^FND LOOP /i, '')
    .replace(/^FND HABIT /i, '')
    .replace(/^FND /i, '');
  const normalized = compact
    .replace(/ IL 6 /gi, ' IL-6 ')
    .replace(/ TNF A /gi, ' TNF-a ')
    .replace(/\s+/g, ' ')
    .trim();
  return normalizeNodeLabel(titleCaseWords(normalized));
}

function stableBucket(value: string, bucketCount: number): number {
  if (bucketCount <= 1) {
    return 0;
  }

  let hash = 0x811c9dc5;
  for (const byte of Buffer.from(value, 'utf8')) {
    hash ^= byte;
    hash = Math.imul(hash, 0x01000193);
  }

  return (hash >>> 0) % bucketCount;
}

function clampTier(value: number): number {
  return Math.max(1, Math.min(10, value));
}

function resolveNodeTier(nodeID: string, styleClass: string, fallbackTier: number): number {
  if (!nodeID.startsWith('FND_')) {
    return clampTier(fallbackTier);
  }

  if (nodeID.startsWith('FND_HABIT_')) {
    return 2 + stableBucket(nodeID, 2);
  }

  if (nodeID.startsWith('FND_LOOP_')) {
    return 3 + stableBucket(nodeID, 6);
  }

  if (styleClass === 'foundation') {
    return 2 + stableBucket(nodeID, 4);
  }

  if (styleClass === 'intervention') {
    return 2 + stableBucket(nodeID, 2);
  }

  return 4 + stableBucket(nodeID, 4);
}

function tooltipEvidence(styleClass: string): string {
  if (styleClass === 'foundation') {
    return 'Foundational';
  }
  if (styleClass === 'intervention') {
    return 'Intervention';
  }
  if (styleClass === 'mechanism') {
    return 'Mechanism';
  }
  if (styleClass === 'symptom') {
    return 'Symptom';
  }
  return 'Mapped';
}

function buildNodeTooltip(nodeID: string, label: string, styleClass: string): Record<string, unknown> {
  const citation = 'docs/health_graph_report.md';
  if (nodeID.startsWith('FND_HABIT_')) {
    return {
      evidence: 'Habit',
      stat: 'Foundation action',
      citation,
      mechanism: `${label} is a report-derived habit linked to upstream foundation pathways.`,
    };
  }

  if (nodeID.startsWith('FND_LOOP_')) {
    return {
      evidence: 'Loop',
      stat: 'Feedback state',
      citation,
      mechanism: `${label} is a foundational feedback loop linked to related causes and outcomes.`,
    };
  }

  return {
    evidence: tooltipEvidence(styleClass),
    stat: styleClass === 'foundation' ? 'Foundation determinant' : 'Mapped node',
    citation,
    mechanism: `${label} is mapped from the foundational report and connected to the causal graph.`,
  };
}

function tooltipMatches(left: unknown, right: Record<string, unknown>): boolean {
  if (!isUnknownRecord(left)) {
    return false;
  }

  const keys = ['evidence', 'stat', 'citation', 'mechanism'];
  for (const key of keys) {
    const leftValue = readOptionalString(left[key]);
    const rightValue = readOptionalString(right[key]);
    if (leftValue !== rightValue) {
      return false;
    }
  }

  return true;
}

function normalizeNodeLabelsAndTooltips(
  nodes: GraphNodeElement[],
  tooltipRequiredNodeIDs: Set<string>,
): boolean {
  let changed = false;

  for (const node of nodes) {
    const nodeID = readOptionalString(node.data.id);
    if (nodeID === null) {
      continue;
    }

    const currentLabel = readOptionalString(node.data.label) ?? labelFromNodeID(nodeID);
    const normalizedLabel = normalizeNodeLabel(currentLabel);
    if (currentLabel !== normalizedLabel) {
      node.data.label = normalizedLabel;
      changed = true;
    }

    const requiresTooltip = nodeID.startsWith('FND_') || tooltipRequiredNodeIDs.has(nodeID);
    if (!requiresTooltip) {
      continue;
    }

    const styleClass = readOptionalString(node.data.styleClass) ?? 'mechanism';
    const fallbackTooltip = buildNodeTooltip(nodeID, normalizedLabel, styleClass);
    const tooltip = isUnknownRecord(node.data.tooltip) ? node.data.tooltip : {};

    for (const key of ['evidence', 'stat', 'citation', 'mechanism']) {
      const existingValue = readOptionalString(tooltip[key]);
      const fallbackValue = readOptionalString(fallbackTooltip[key]);
      if (existingValue === null && fallbackValue !== null) {
        tooltip[key] = fallbackValue;
        changed = true;
      }
    }

    if (!isUnknownRecord(node.data.tooltip) || node.data.tooltip !== tooltip) {
      node.data.tooltip = tooltip;
      changed = true;
    }
  }

  return changed;
}

interface NodeUpsertInput {
  id: string;
  label: string;
  styleClass: string;
  confirmed: string;
  tier: number;
}

function upsertNode(
  nodes: GraphNodeElement[],
  nodeIDs: Set<string>,
  nodeIndexByID: Map<string, number>,
  spec: NodeUpsertInput,
): { added: boolean; changed: boolean } {
  const label = normalizeNodeLabel(spec.label);
  const resolvedTier = resolveNodeTier(spec.id, spec.styleClass, spec.tier);
  const tooltip = buildNodeTooltip(spec.id, label, spec.styleClass);

  const existingIndex = nodeIndexByID.get(spec.id);
  if (existingIndex === undefined) {
    nodes.push({
      data: {
        id: spec.id,
        label,
        styleClass: spec.styleClass,
        confirmed: spec.confirmed,
        tier: resolvedTier,
        tooltip,
      },
    });
    nodeIDs.add(spec.id);
    nodeIndexByID.set(spec.id, nodes.length - 1);
    return { added: true, changed: true };
  }

  const existing = nodes[existingIndex];
  const existingData = existing.data;
  let changed = false;

  if (readOptionalString(existingData.label) !== label) {
    existingData.label = label;
    changed = true;
  }

  if (readOptionalString(existingData.styleClass) !== spec.styleClass) {
    existingData.styleClass = spec.styleClass;
    changed = true;
  }

  if (readOptionalString(existingData.confirmed) !== spec.confirmed) {
    existingData.confirmed = spec.confirmed;
    changed = true;
  }

  if (readNumber(existingData.tier) !== resolvedTier) {
    existingData.tier = resolvedTier;
    changed = true;
  }

  if (!tooltipMatches(existingData.tooltip, tooltip)) {
    existingData.tooltip = tooltip;
    changed = true;
  }

  return { added: false, changed };
}

function edgeBaseKey(source: string, target: string, edgeType: string, label: string): string {
  return `edge:${source}|${target}|${edgeType}|${label}`;
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
  return `${edgeBaseKey(source, target, edgeType, label)}#${duplicateIndex}`;
}

function buildEdgeRows(edges: GraphEdgeElement[]): EdgeRow[] {
  const duplicateCounter = new Map<string, number>();
  const rows: EdgeRow[] = [];

  for (const edge of edges) {
    const edgeType = readOptionalString(edge.data.edgeType) ?? '';
    const label = readOptionalString(edge.data.label) ?? '';
    const base = edgeBaseKey(edge.data.source, edge.data.target, edgeType, label);
    const duplicateIndex = duplicateCounter.get(base) ?? 0;
    duplicateCounter.set(base, duplicateIndex + 1);

    rows.push({
      edgeID: deriveEdgeID(edge, duplicateIndex),
      source: edge.data.source,
      target: edge.data.target,
    });
  }

  return rows;
}

function buildEdgeIndex(edges: GraphEdgeElement[]): EdgeIndex {
  const idsBySignature = new Map<string, string>();
  const duplicateCounterByBase = new Map<string, number>();

  for (const edge of edges) {
    const edgeType = readOptionalString(edge.data.edgeType) ?? '';
    const label = readOptionalString(edge.data.label) ?? '';
    const base = edgeBaseKey(edge.data.source, edge.data.target, edgeType, label);
    const duplicateIndex = duplicateCounterByBase.get(base) ?? 0;
    duplicateCounterByBase.set(base, duplicateIndex + 1);

    const edgeID = deriveEdgeID(edge, duplicateIndex);
    const signature = edgeSignature(edge.data);
    if (!idsBySignature.has(signature)) {
      idsBySignature.set(signature, edgeID);
    }
  }

  return {
    idsBySignature,
    duplicateCounterByBase,
  };
}

function upsertStateTemplateNode(
  nodes: GraphNodeElement[],
  nodeIDs: Set<string>,
  nodeIndexByID: Map<string, number>,
  node: StateNodeTemplate,
): { added: boolean; changed: boolean } {
  return upsertNode(nodes, nodeIDs, nodeIndexByID, {
    id: node.id,
    label: node.label,
    styleClass: node.styleClass,
    confirmed: node.confirmed,
    tier: node.tier,
  });
}

function upsertPlaceholderNode(
  nodes: GraphNodeElement[],
  nodeIDs: Set<string>,
  nodeIndexByID: Map<string, number>,
  nodeID: string,
): { added: boolean; changed: boolean } {
  if (!nodeID.startsWith('FND_') && nodeIndexByID.has(nodeID)) {
    return { added: false, changed: false };
  }

  return upsertNode(nodes, nodeIDs, nodeIndexByID, {
    id: nodeID,
    label: labelFromNodeID(nodeID),
    styleClass: nodeID.startsWith('FND_') ? 'foundation' : 'mechanism',
    confirmed: 'yes',
    tier: 4,
  });
}

function addOrReuseEdge(
  edges: GraphEdgeElement[],
  edgeIndex: EdgeIndex,
  candidate: {
    source: string;
    target: string;
    edgeType: string;
    label: string;
    edgeColor: string;
    tooltip: string;
    strength: number;
  },
): { edgeID: string; added: boolean } {
  const signature = edgeSignature({
    source: candidate.source,
    target: candidate.target,
    edgeType: candidate.edgeType,
    label: candidate.label,
  });

  const existingID = edgeIndex.idsBySignature.get(signature);
  if (existingID !== undefined) {
    return {
      edgeID: existingID,
      added: false,
    };
  }

  const base = edgeBaseKey(candidate.source, candidate.target, candidate.edgeType, candidate.label);
  const duplicateIndex = edgeIndex.duplicateCounterByBase.get(base) ?? 0;
  edgeIndex.duplicateCounterByBase.set(base, duplicateIndex + 1);

  const edgeID = `${base}#${duplicateIndex}`;

  const nextEdge: GraphEdgeElement = {
    data: {
      id: edgeID,
      source: candidate.source,
      target: candidate.target,
      edgeType: candidate.edgeType,
      label: candidate.label,
      edgeColor: candidate.edgeColor,
      tooltip: candidate.tooltip,
      strength: candidate.strength,
    },
  };

  edges.push(nextEdge);
  edgeIndex.idsBySignature.set(signature, edgeID);

  return {
    edgeID,
    added: true,
  };
}

function normalizeLoopAnchorEdgeLabels(edges: GraphEdgeElement[]): boolean {
  let changed = false;

  for (const edge of edges) {
    const tooltip = readOptionalString(edge.data.tooltip);
    if (tooltip === null || !tooltip.startsWith('Loop anchor')) {
      continue;
    }

    if (readOptionalString(edge.data.label) !== null) {
      edge.data.label = '';
      changed = true;
    }
  }

  return changed;
}

function computeGraphVersion(graph: GraphData): string {
  let fingerprint = graph.nodes
    .map((node) => {
      const styleClass = readOptionalString(node.data.styleClass) ?? '';
      const confirmed = readOptionalString(node.data.confirmed) ?? '';
      const tier = readNumber(node.data.tier) ?? -1;
      return `${node.data.id}|${styleClass}|${confirmed}|${tier}`;
    })
    .sort((left, right) => left.localeCompare(right))
    .join(';');

  fingerprint += '|';
  fingerprint += graph.edges
    .map((edge) => {
      const edgeType = readOptionalString(edge.data.edgeType) ?? '';
      const label = readOptionalString(edge.data.label) ?? '';
      const strength = readNumber(edge.data.strength) ?? 0;
      return `${edge.data.source}|${edge.data.target}|${edgeType}|${label}|${strength}`;
    })
    .sort((left, right) => left.localeCompare(right))
    .join(';');

  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;

  for (const byte of Buffer.from(fingerprint, 'utf8')) {
    hash ^= BigInt(byte);
    hash = (hash * prime) & 0xffffffffffffffffn;
  }

  const hex = hash.toString(16).padStart(16, '0');
  return `graph-${hex}`;
}

function resolveUserGraph(store: Record<string, unknown>): ResolvedUserGraph {
  const customDiagram = isUnknownRecord(store.customCausalDiagram) ? store.customCausalDiagram : null;
  if (customDiagram === null) {
    return {
      graph: { nodes: [], edges: [] },
      hadWrappedGraphData: false,
      currentGraphVersion: null,
    };
  }

  const currentGraphVersion = readOptionalString(customDiagram.graphVersion);

  if (isUnknownRecord(customDiagram.graphData)) {
    return {
      graph: loadGraphFromUnknown(customDiagram.graphData),
      hadWrappedGraphData: true,
      currentGraphVersion,
    };
  }

  if (Array.isArray(customDiagram.nodes) || Array.isArray(customDiagram.edges)) {
    return {
      graph: loadGraphFromUnknown({
        nodes: customDiagram.nodes,
        edges: customDiagram.edges,
      }),
      hadWrappedGraphData: false,
      currentGraphVersion,
    };
  }

  return {
    graph: { nodes: [], edges: [] },
    hadWrappedGraphData: false,
    currentGraphVersion,
  };
}

function parseStateNodeTemplates(value: unknown): StateNodeTemplate[] {
  if (!Array.isArray(value)) {
    throw new Error('stateNodeTemplates must be an array.');
  }

  const rows: StateNodeTemplate[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const entry = value[index];
    if (!isUnknownRecord(entry)) {
      throw new Error(`stateNodeTemplates[${index}] must be an object.`);
    }

    const id = readOptionalString(entry.id);
    const label = readOptionalString(entry.label);
    const styleClass = readOptionalString(entry.styleClass);
    const confirmed = readOptionalString(entry.confirmed);
    const tier = readNumber(entry.tier);

    if (id === null || label === null || styleClass === null || confirmed === null || tier === null) {
      throw new Error(`stateNodeTemplates[${index}] has invalid fields.`);
    }

    rows.push({
      id,
      label,
      styleClass,
      confirmed,
      tier,
    });
  }

  return rows;
}

function parseMentionCoverageRows(value: unknown): MentionCoverageRow[] {
  if (!Array.isArray(value)) {
    throw new Error('mentionCoverage must be an array.');
  }

  const rows: MentionCoverageRow[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const entry = value[index];
    if (!isUnknownRecord(entry)) {
      throw new Error(`mentionCoverage[${index}] must be an object.`);
    }

    const mention = readOptionalString(entry.mention);
    const canonicalHabitID = readOptionalString(entry.canonicalHabitId);
    const source = readOptionalString(entry.source);
    const section = readOptionalString(entry.section);
    const line = readNumber(entry.line);

    if (mention === null || canonicalHabitID === null || source === null || section === null || line === null) {
      throw new Error(`mentionCoverage[${index}] has invalid fields.`);
    }

    rows.push({
      mention,
      canonicalHabitId: canonicalHabitID,
      source,
      section,
      line,
    });
  }

  return rows;
}

function parsePreferredWindows(value: unknown): PreferredWindow[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const windows: PreferredWindow[] = [];
  for (const entry of value) {
    if (!isUnknownRecord(entry)) {
      continue;
    }

    const startMinutes = readNumber(entry.startMinutes);
    const endMinutes = readNumber(entry.endMinutes);
    if (startMinutes === null || endMinutes === null) {
      continue;
    }

    windows.push({
      startMinutes,
      endMinutes,
    });
  }

  return windows;
}

function parseCanonicalHabits(value: unknown): CanonicalHabitTemplate[] {
  if (!Array.isArray(value)) {
    throw new Error('canonicalHabits must be an array.');
  }

  const rows: CanonicalHabitTemplate[] = [];

  for (let index = 0; index < value.length; index += 1) {
    const entry = value[index];
    if (!isUnknownRecord(entry)) {
      throw new Error(`canonicalHabits[${index}] must be an object.`);
    }

    const id = readOptionalString(entry.id);
    const slug = readOptionalString(entry.slug);
    const name = readOptionalString(entry.name);
    const aliases = readStringArray(entry.aliases);
    const mentionTrace = parseMentionTraceRows(entry.mentionTrace ?? []);
    const pillars = readStringArray(entry.pillars);
    const planningTags = readStringArray(entry.planningTags);
    const targetNodeIds = readStringArray(entry.targetNodeIds);
    const targetEdgeIds = readStringArray(entry.targetEdgeIds);
    const existingInterventionID = readOptionalString(entry.existingInterventionId);
    const foundationRoleRaw = readOptionalString(entry.foundationRole);
    const defaultMinutes = readNumber(entry.defaultMinutes);
    const ladderTemplateID = readOptionalString(entry.ladderTemplateID);
    const preferredWindows = parsePreferredWindows(entry.preferredWindows);

    if (
      id === null
      || slug === null
      || name === null
      || aliases.length === 0
      || pillars.length === 0
      || planningTags.length === 0
      || targetNodeIds.length === 0
      || targetEdgeIds.length === 0
      || defaultMinutes === null
      || ladderTemplateID === null
      || (foundationRoleRaw !== 'blocker' && foundationRoleRaw !== 'maintenance')
    ) {
      throw new Error(`canonicalHabits[${index}] has invalid fields.`);
    }

    rows.push({
      id,
      slug,
      name,
      aliases,
      mentionTrace,
      pillars,
      planningTags,
      targetNodeIds,
      targetEdgeIds,
      existingInterventionId: existingInterventionID,
      foundationRole: foundationRoleRaw,
      defaultMinutes,
      ladderTemplateID,
      preferredWindows,
    });
  }

  return rows;
}

function parseMentionTraceRows(value: unknown): MentionTraceRow[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const rows: MentionTraceRow[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const entry = value[index];
    if (!isUnknownRecord(entry)) {
      throw new Error(`mentionTrace[${index}] must be an object.`);
    }

    const mention = readOptionalString(entry.mention);
    const source = readOptionalString(entry.source);
    const section = readOptionalString(entry.section);
    const line = readNumber(entry.line);

    if (mention === null || source === null || section === null || line === null) {
      throw new Error(`mentionTrace[${index}] has invalid fields.`);
    }

    rows.push({
      mention,
      source,
      section,
      line,
    });
  }

  return rows;
}

function parseLoopTemplateRows(value: unknown): LoopTemplate[] {
  if (!Array.isArray(value)) {
    throw new Error('loop template section must be an array.');
  }

  const rows: LoopTemplate[] = [];
  for (let index = 0; index < value.length; index += 1) {
    const entry = value[index];
    if (!isUnknownRecord(entry)) {
      throw new Error(`loop template row at index ${index} must be an object.`);
    }

    const id = readOptionalString(entry.id);
    const title = readOptionalString(entry.title);
    const line = readNumber(entry.line);
    const phrases = readStringArray(entry.phrases);

    if (id === null || title === null || line === null || phrases.length === 0) {
      throw new Error(`loop template row at index ${index} missing required fields.`);
    }

    const edgeSpecsValue = entry.edgeSpecs;
    if (!Array.isArray(edgeSpecsValue)) {
      throw new Error(`loop template row ${id} must contain edgeSpecs array.`);
    }

    const edgeSpecs: LoopEdgeSpec[] = [];
    for (let edgeIndex = 0; edgeIndex < edgeSpecsValue.length; edgeIndex += 1) {
      const edgeEntry = edgeSpecsValue[edgeIndex];
      if (!isUnknownRecord(edgeEntry)) {
        throw new Error(`loop template row ${id} edgeSpecs[${edgeIndex}] must be an object.`);
      }

      const source = readOptionalString(edgeEntry.source);
      const target = readOptionalString(edgeEntry.target);
      const edgeType = readOptionalString(edgeEntry.edgeType);
      const label = readOptionalString(edgeEntry.label);

      if (source === null || target === null || edgeType === null || label === null) {
        throw new Error(`loop template row ${id} edgeSpecs[${edgeIndex}] has invalid fields.`);
      }

      edgeSpecs.push({
        source,
        target,
        edgeType,
        label,
      });
    }

    rows.push({
      id,
      title,
      line,
      phrases,
      edgeSpecs,
    });
  }

  return rows;
}

function parseLoopTemplates(value: unknown): LoopTemplateGroups {
  if (!isUnknownRecord(value)) {
    throw new Error('loopTemplates must be an object.');
  }

  return {
    virtuous: parseLoopTemplateRows(value.virtuous),
    vicious: parseLoopTemplateRows(value.vicious),
    compound: parseLoopTemplateRows(value.compound),
  };
}

function parseHabitMap(raw: unknown): HabitMapFile {
  if (!isUnknownRecord(raw)) {
    throw new Error('health-report-habit-map payload must be an object.');
  }

  const schemaVersion = readOptionalString(raw.schemaVersion);
  const sourceReportPath = readOptionalString(raw.sourceReportPath);

  if (schemaVersion === null || sourceReportPath === null) {
    throw new Error('health-report-habit-map missing schemaVersion/sourceReportPath.');
  }

  const parseCoverageRecord = isUnknownRecord(raw.parseCoverage) ? raw.parseCoverage : null;
  if (parseCoverageRecord === null) {
    throw new Error('health-report-habit-map parseCoverage is missing or invalid.');
  }

  const totalMentions = readNumber(parseCoverageRecord.totalMentions);
  const uniqueMentionCount = readNumber(parseCoverageRecord.uniqueMentionCount);
  const canonicalHabitCount = readNumber(parseCoverageRecord.canonicalHabitCount);

  if (totalMentions === null || uniqueMentionCount === null || canonicalHabitCount === null) {
    throw new Error('health-report-habit-map parseCoverage has invalid fields.');
  }

  const mentionCoverage = parseMentionCoverageRows(raw.mentionCoverage);
  const stateNodeTemplates = parseStateNodeTemplates(raw.stateNodeTemplates);
  const canonicalHabits = parseCanonicalHabits(raw.canonicalHabits);
  const loopTemplates = parseLoopTemplates(raw.loopTemplates);

  return {
    schemaVersion,
    sourceReportPath,
    parseCoverage: {
      totalMentions,
      uniqueMentionCount,
      canonicalHabitCount,
    },
    mentionCoverage,
    stateNodeTemplates,
    canonicalHabits,
    loopTemplates,
  };
}

function parseReportHabitMentions(reportText: string): string[] {
  const lines = reportText.split(/\r?\n/);
  const mentions: string[] = [];

  let mode: '' | 'tier' | 'per' = '';

  for (const line of lines) {
    if (line.startsWith('## Tier 1:')) {
      mode = 'tier';
    }
    if (line.startsWith('## Per-Pillar Habit Breakdowns')) {
      mode = 'per';
    }
    if (line.startsWith('# Part III:')) {
      break;
    }

    if (mode === 'tier' && /^\|\s*\d+\s*\|/.test(line)) {
      const columns = line.split('|').map((value) => value.trim());
      if (columns.length < 3) {
        continue;
      }

      const habitRaw = columns[2] ?? '';
      const match = habitRaw.match(/\*\*(.+?)\*\*/);
      const mention = (match ? match[1] : habitRaw).trim();
      if (mention.length > 0) {
        mentions.push(mention);
      }
      continue;
    }

    if (mode === 'per') {
      const actionMatch = line.match(/^\d+\.\s+\*\*(.+?)\*\*/);
      if (actionMatch) {
        const mention = actionMatch[1].trim();
        if (mention.length > 0) {
          mentions.push(mention);
        }
      }
    }
  }

  return mentions;
}

function keywordAnchorTargets(text: string): string[] {
  const lower = text.toLowerCase();
  const targets = new Set<string>();

  if (/(sleep|wake|nap|bed|circadian|light|screen|melatonin)/.test(lower)) {
    targets.add('FND_SLEEP_QUALITY');
    targets.add('SLEEP_DEP');
  }
  if (/(exercise|activity|walking|fitness|cardio|strength|movement|sedentary|pain)/.test(lower)) {
    targets.add('FND_PHYSICAL_ACTIVITY');
  }
  if (/(mood|anxiety|stress|cortisol|gratitude|rumination|insomnia|hyperarousal)/.test(lower)) {
    targets.add('FND_STRESS_RESILIENCE');
    targets.add('STRESS');
  }
  if (/(nutrition|gut|microbiome|scfa|diet|food|eating|metabolic|hydration|dehydration|caffeine)/.test(lower)) {
    targets.add('FND_NUTRITION_QUALITY');
    targets.add('FND_METABOLIC_HEALTH');
  }
  if (/(social|loneliness|isolation|oxytocin|prosocial|volunteer|comparison)/.test(lower)) {
    targets.add('FND_SOCIAL_CONNECTEDNESS');
    targets.add('SOCIAL_ISOLATION');
  }
  if (/(financial|income|productivity|work|security)/.test(lower)) {
    targets.add('FND_FINANCIAL_RESILIENCE');
    targets.add('FINANCIAL_STRAIN');
  }
  if (/(oral|periodontal|dental|floss|inflammation|cardiovascular)/.test(lower)) {
    targets.add('FND_ORAL_HEALTH');
    targets.add('TOOTH');
  }
  if (/(aging|ageing|telomere|longevity|cognition|memory)/.test(lower)) {
    targets.add('FND_COGNITIVE_RESERVE');
  }

  if (targets.size === 0) {
    targets.add('FND_STRESS_RESILIENCE');
  }

  return [...targets].sort((left, right) => left.localeCompare(right));
}

function readInterventionsFromCatalog(catalogData: Record<string, unknown>): ParsedIntervention[] {
  const entries = Array.isArray(catalogData.interventions) ? catalogData.interventions : [];
  const interventions: ParsedIntervention[] = [];

  for (const entry of entries) {
    if (!isUnknownRecord(entry)) {
      continue;
    }

    const id = readOptionalString(entry.id);
    if (id === null) {
      continue;
    }

    interventions.push({
      id,
      value: structuredClone(entry),
    });
  }

  interventions.sort((left, right) => left.id.localeCompare(right.id));
  return interventions;
}

function parseTimeOfDay(value: unknown): string[] {
  return readStringArray(value).filter((entry) => {
    return (
      entry === 'morning'
      || entry === 'afternoon'
      || entry === 'evening'
      || entry === 'preBed'
      || entry === 'anytime'
    );
  });
}

interface MorningQuestionSpec {
  id: string;
  title: string;
  nodeIDs: string[];
}

function buildLinkedQuestion(
  id: string,
  title: string,
  nodeIDs: string[],
  edgeRows: EdgeRow[],
): Record<string, unknown> {
  const nodeIDSet = new Set(nodeIDs);
  const sourceEdgeIDs = edgeRows
    .filter((row) => nodeIDSet.has(row.source) || nodeIDSet.has(row.target))
    .map((row) => row.edgeID);

  return {
    id,
    title,
    sourceNodeIDs: uniqueSorted(nodeIDs),
    sourceEdgeIDs: uniqueSorted(sourceEdgeIDs),
  };
}

function buildFoundationQuestion(
  id: string,
  title: string,
  nodeIDs: string[],
  edgeRows: EdgeRow[],
): Record<string, unknown> {
  return buildLinkedQuestion(id, title, nodeIDs, edgeRows);
}

function buildMorningQuestion(
  spec: MorningQuestionSpec,
  edgeRows: EdgeRow[],
): Record<string, unknown> {
  return buildLinkedQuestion(spec.id, spec.title, spec.nodeIDs, edgeRows);
}

function firstDiffPath(left: unknown, right: unknown, prefix: string = ''): string | null {
  if (Object.is(left, right)) {
    return null;
  }

  if (Array.isArray(left) && Array.isArray(right)) {
    if (left.length !== right.length) {
      return `${prefix}.length`;
    }

    for (let index = 0; index < left.length; index += 1) {
      const nextPrefix = `${prefix}[${index}]`;
      const diff = firstDiffPath(left[index], right[index], nextPrefix);
      if (diff !== null) {
        return diff;
      }
    }

    return null;
  }

  if (isUnknownRecord(left) && isUnknownRecord(right)) {
    const leftKeys = Object.keys(left).sort((lhs, rhs) => lhs.localeCompare(rhs));
    const rightKeys = Object.keys(right).sort((lhs, rhs) => lhs.localeCompare(rhs));
    if (leftKeys.length !== rightKeys.length) {
      return `${prefix}.{keys}`;
    }

    for (let index = 0; index < leftKeys.length; index += 1) {
      if (leftKeys[index] !== rightKeys[index]) {
        return `${prefix}.{keys}`;
      }
    }

    for (const key of leftKeys) {
      const nextPrefix = prefix.length > 0 ? `${prefix}.${key}` : key;
      const diff = firstDiffPath(left[key], right[key], nextPrefix);
      if (diff !== null) {
        return diff;
      }
    }

    return null;
  }

  return prefix;
}

async function run(): Promise<void> {
  const args = parseArgs();
  if (args.userID === null) {
    printUsageAndExit();
  }

  if (args.userID !== AUTHORIZED_USER_ID) {
    throw new Error(`Patch script is restricted to ${AUTHORIZED_USER_ID}. Refusing user_id=${args.userID}.`);
  }

  const mapText = readFileSync(path.resolve(process.cwd(), MAP_FILE_PATH), 'utf8');
  const mapFile = parseHabitMap(JSON.parse(mapText));

  const reportText = readFileSync(path.resolve(process.cwd(), REPORT_FILE_PATH), 'utf8');
  const reportMentions = parseReportHabitMentions(reportText);

  const canonicalByAlias = new Map<string, string>();
  for (const habit of mapFile.canonicalHabits) {
    for (const alias of habit.aliases) {
      const key = normalizeAlias(alias);
      const existing = canonicalByAlias.get(key);
      if (existing !== undefined && existing !== habit.id) {
        throw new Error(`Alias collision for "${alias}" between ${existing} and ${habit.id}.`);
      }
      canonicalByAlias.set(key, habit.id);
    }
  }

  const unresolvedMentions: string[] = [];
  for (const mention of reportMentions) {
    const key = normalizeAlias(mention);
    if (!canonicalByAlias.has(key)) {
      unresolvedMentions.push(mention);
    }
  }

  if (unresolvedMentions.length > 0) {
    throw new Error(`Habit coverage failure: ${unresolvedMentions.length} report mentions are not mapped.`);
  }

  const supabaseURL = requiredEnv('SUPABASE_URL');
  const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');

  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const userDataQuery = await supabase
    .from('user_data')
    .select('user_id,data,updated_at')
    .eq('user_id', args.userID)
    .maybeSingle();

  if (userDataQuery.error) {
    throw new Error(`user_data query failed: ${userDataQuery.error.message}`);
  }

  if (!userDataQuery.data) {
    throw new Error(`No user_data row found for user_id=${args.userID}`);
  }

  const currentStore = isUnknownRecord(userDataQuery.data.data)
    ? structuredClone(userDataQuery.data.data)
    : {};

  const resolvedGraph = resolveUserGraph(currentStore);
  const currentGraph = resolvedGraph.graph;
  const currentGraphVersion = resolvedGraph.currentGraphVersion ?? computeGraphVersion(currentGraph);

  const userCatalogQuery = await supabase
    .from('user_content')
    .select('data,version')
    .eq('user_id', args.userID)
    .eq('content_type', 'inputs')
    .eq('content_key', 'interventions_catalog')
    .limit(1)
    .maybeSingle();

  if (userCatalogQuery.error) {
    throw new Error(`user_content inputs/interventions_catalog query failed: ${userCatalogQuery.error.message}`);
  }

  let catalogPayload: ContentPayload;
  if (userCatalogQuery.data) {
    catalogPayload = {
      data: userCatalogQuery.data.data,
      source: 'user_content',
      userContentVersion: userCatalogQuery.data.version,
    };
  } else {
    const firstPartyCatalogQuery = await supabase
      .from('first_party_content')
      .select('data')
      .eq('content_type', 'inputs')
      .eq('content_key', 'interventions_catalog')
      .limit(1)
      .maybeSingle();

    if (firstPartyCatalogQuery.error) {
      throw new Error(`first_party_content inputs/interventions_catalog query failed: ${firstPartyCatalogQuery.error.message}`);
    }

    if (!firstPartyCatalogQuery.data) {
      throw new Error('Missing interventions_catalog in user_content and first_party_content.');
    }

    catalogPayload = {
      data: firstPartyCatalogQuery.data.data,
      source: 'first_party_content',
      userContentVersion: null,
    };
  }

  const currentCatalogRecord = isUnknownRecord(catalogPayload.data)
    ? structuredClone(catalogPayload.data)
    : {};

  const parsedInterventions = readInterventionsFromCatalog(currentCatalogRecord);
  const interventions: Record<string, unknown>[] = parsedInterventions.map((entry) => structuredClone(entry.value));
  const interventionIndexByID = new Map<string, number>();

  for (let index = 0; index < interventions.length; index += 1) {
    const id = readOptionalString(interventions[index].id);
    if (id === null) {
      continue;
    }
    if (!interventionIndexByID.has(id)) {
      interventionIndexByID.set(id, index);
    }
  }

  const existingNodeIDs = new Set(currentGraph.nodes.map((node) => node.data.id));
  const nextNodes = currentGraph.nodes.map((node) => structuredClone(node));
  const nodeIndexByID = new Map<string, number>();
  for (let index = 0; index < nextNodes.length; index += 1) {
    nodeIndexByID.set(nextNodes[index].data.id, index);
  }
  const nextEdges = currentGraph.edges.map((edge) => structuredClone(edge));
  const addedNodeIDs: string[] = [];
  const addedEdgeIDs: string[] = [];

  for (const template of mapFile.stateNodeTemplates) {
    const result = upsertStateTemplateNode(nextNodes, existingNodeIDs, nodeIndexByID, template);
    if (result.added) {
      addedNodeIDs.push(template.id);
    }
  }

  const edgeIndex = buildEdgeIndex(nextEdges);

  const stateLabelByID = new Map<string, string>();
  for (const template of mapFile.stateNodeTemplates) {
    stateLabelByID.set(template.id, template.label);
  }

  const habitResolutions: HabitResolution[] = [];
  let nextDefaultOrder = 1;
  for (const intervention of interventions) {
    const defaultOrder = readNumber(intervention.defaultOrder);
    if (defaultOrder !== null) {
      nextDefaultOrder = Math.max(nextDefaultOrder, defaultOrder + 1);
    }
  }

  for (const habit of mapFile.canonicalHabits) {
    const hasExisting = habit.existingInterventionId !== null && interventionIndexByID.has(habit.existingInterventionId);
    const interventionID = hasExisting ? habit.existingInterventionId ?? habit.id : habit.id;
    const interventionIndex = interventionIndexByID.get(interventionID);

    let graphNodeID: string;
    if (interventionIndex !== undefined) {
      const existingGraphNodeID = readOptionalString(interventions[interventionIndex].graphNodeId);
      graphNodeID = existingGraphNodeID ?? `FND_HABIT_${habit.slug.toUpperCase()}`;
    } else {
      graphNodeID = `FND_HABIT_${habit.slug.toUpperCase()}`;
    }

    const habitNodeResult = upsertNode(nextNodes, existingNodeIDs, nodeIndexByID, {
      id: graphNodeID,
      label: habit.name,
      styleClass: 'intervention',
      confirmed: 'yes',
      tier: 2,
    });
    if (habitNodeResult.added) {
      addedNodeIDs.push(graphNodeID);
    }

    const targetNodeIDs = habit.targetNodeIds.length > 0
      ? uniqueSorted(habit.targetNodeIds)
      : ['FND_STRESS_RESILIENCE'];

    for (const targetNodeID of targetNodeIDs) {
      const result = upsertPlaceholderNode(nextNodes, existingNodeIDs, nodeIndexByID, targetNodeID);
      if (result.added) {
        addedNodeIDs.push(targetNodeID);
      }
    }

    const graphEdgeIDs: string[] = [];
    for (const targetNodeID of targetNodeIDs) {
      const edgeResult = addOrReuseEdge(nextEdges, edgeIndex, {
        source: graphNodeID,
        target: targetNodeID,
        edgeType: 'forward',
        label: '',
        edgeColor: '#0f766e',
        tooltip: `Foundation habit link: ${habit.name}`,
        strength: 0.65,
      });

      graphEdgeIDs.push(edgeResult.edgeID);
      if (edgeResult.added) {
        addedEdgeIDs.push(edgeResult.edgeID);
      }
    }

    habitResolutions.push({
      habitID: habit.id,
      habitName: habit.name,
      interventionID,
      graphNodeID,
      targetNodeIDs,
      graphEdgeIDs: uniqueSorted(graphEdgeIDs),
      reusedIntervention: interventionIndex !== undefined,
      addedIntervention: interventionIndex === undefined,
    });

    if (interventionIndex === undefined) {
      const newIntervention: Record<string, unknown> = {
        id: interventionID,
        name: habit.name,
        icon: 'leaf.fill',
        description: `Foundation habit from ${mapFile.sourceReportPath}.`,
        detailedDescription: `Mapped report habit: ${habit.aliases.join('; ')}`,
        tier: 3,
        frequency: 'daily',
        trackingType: 'binary',
        isRemindable: false,
        defaultReminderMinutes: null,
        externalLink: null,
        evidenceLevel: 'Report synthesis',
        evidenceSummary: 'Mapped from evidence-based habit report.',
        citationIds: [],
        roiTier: 'B',
        easeScore: 6,
        costRange: '$0',
        timeOfDay: ['anytime'],
        defaultOrder: nextDefaultOrder,
        estimatedDurationMinutes: habit.defaultMinutes,
        energyLevel: 'low',
        targetCondition: 'foundation',
        causalPathway: 'upstream',
        legacyIds: [],
        graphNodeId: graphNodeID,
        pillars: habit.pillars,
        planningTags: habit.planningTags,
        acuteTargets: targetNodeIDs,
        graphEdgeIds: uniqueSorted(graphEdgeIDs),
        foundationRole: habit.foundationRole,
        defaultMinutes: habit.defaultMinutes,
        ladderTemplateID: habit.ladderTemplateID,
        preferredWindows: habit.preferredWindows,
      };

      interventions.push(newIntervention);
      interventionIndexByID.set(interventionID, interventions.length - 1);
      nextDefaultOrder += 1;
      continue;
    }

    const current = interventions[interventionIndex];

    const mergedPillars = uniqueSorted([
      ...readStringArray(current.pillars),
      ...habit.pillars,
    ]);

    const mergedPlanningTags = uniqueSorted([
      ...readStringArray(current.planningTags),
      ...habit.planningTags,
    ]);

    const mergedTargets = uniqueSorted([
      ...readStringArray(current.acuteTargets),
      ...targetNodeIDs,
    ]);

    const mergedEdgeIDs = uniqueSorted([
      ...readStringArray(current.graphEdgeIds),
      ...graphEdgeIDs,
    ]);

    current.graphNodeId = graphNodeID;
    current.pillars = mergedPillars;
    current.planningTags = mergedPlanningTags;
    current.acuteTargets = mergedTargets;
    current.graphEdgeIds = mergedEdgeIDs;
    current.foundationRole = habit.foundationRole;

    if (readNumber(current.defaultMinutes) === null) {
      current.defaultMinutes = habit.defaultMinutes;
    }

    if (readOptionalString(current.ladderTemplateID) === null) {
      current.ladderTemplateID = habit.ladderTemplateID;
    }

    const currentWindows = Array.isArray(current.preferredWindows) ? current.preferredWindows : [];
    if (currentWindows.length === 0 && habit.preferredWindows.length > 0) {
      current.preferredWindows = habit.preferredWindows;
    }

    const currentTimeOfDay = parseTimeOfDay(current.timeOfDay);
    if (currentTimeOfDay.length === 0) {
      current.timeOfDay = ['anytime'];
    }

    if (readOptionalString(current.trackingType) === null) {
      current.trackingType = 'binary';
    }

    if (readOptionalString(current.frequency) === null) {
      current.frequency = 'daily';
    }
  }

  const loopColorByType = {
    virtuous: '#0f766e',
    vicious: '#b91c1c',
    compound: '#a16207',
  };

  const loopGroups: Array<{ type: keyof LoopTemplateGroups; rows: LoopTemplate[] }> = [
    { type: 'virtuous', rows: mapFile.loopTemplates.virtuous },
    { type: 'vicious', rows: mapFile.loopTemplates.vicious },
    { type: 'compound', rows: mapFile.loopTemplates.compound },
  ];

  for (const group of loopGroups) {
    for (const loop of group.rows) {
      for (const edgeSpec of loop.edgeSpecs) {
        const sourceResult = upsertPlaceholderNode(nextNodes, existingNodeIDs, nodeIndexByID, edgeSpec.source);
        if (sourceResult.added) {
          addedNodeIDs.push(edgeSpec.source);
        }

        const targetResult = upsertPlaceholderNode(nextNodes, existingNodeIDs, nodeIndexByID, edgeSpec.target);
        if (targetResult.added) {
          addedNodeIDs.push(edgeSpec.target);
        }

        const edgeResult = addOrReuseEdge(nextEdges, edgeIndex, {
          source: edgeSpec.source,
          target: edgeSpec.target,
          edgeType: edgeSpec.edgeType,
          label: edgeSpec.label,
          edgeColor: loopColorByType[group.type],
          tooltip: `Feedback loop ${loop.id}: ${loop.title}`,
          strength: group.type === 'vicious' ? 0.7 : 0.6,
        });

        if (edgeResult.added) {
          addedEdgeIDs.push(edgeResult.edgeID);
        }
      }
    }
  }

  for (const template of mapFile.stateNodeTemplates) {
    if (!template.id.startsWith('FND_LOOP_')) {
      continue;
    }

    const label = stateLabelByID.get(template.id) ?? template.label;
    const anchors = keywordAnchorTargets(label);
    const primaryAnchor = anchors[0];
    if (primaryAnchor === undefined) {
      continue;
    }

    const anchorResult = upsertPlaceholderNode(nextNodes, existingNodeIDs, nodeIndexByID, primaryAnchor);
    if (anchorResult.added) {
      addedNodeIDs.push(primaryAnchor);
    }

    const edgeResult = addOrReuseEdge(nextEdges, edgeIndex, {
      source: template.id,
      target: primaryAnchor,
      edgeType: 'dashed',
      label: '',
      edgeColor: '#6b7280',
      tooltip: `Loop anchor from ${template.id} to ${primaryAnchor}`,
      strength: 0.4,
    });

    if (edgeResult.added) {
      addedEdgeIDs.push(edgeResult.edgeID);
    }
  }

  const bridgeEdges = [
    { source: 'FND_SLEEP_QUALITY', target: 'SLEEP_DEP', edgeType: 'protective', label: 'foundation buffer' },
    { source: 'FND_STRESS_RESILIENCE', target: 'STRESS', edgeType: 'protective', label: 'foundation buffer' },
    { source: 'FND_SOCIAL_CONNECTEDNESS', target: 'SOCIAL_ISOLATION', edgeType: 'protective', label: 'foundation buffer' },
    { source: 'FND_FINANCIAL_RESILIENCE', target: 'FINANCIAL_STRAIN', edgeType: 'protective', label: 'foundation buffer' },
    { source: 'FND_NUTRITION_QUALITY', target: 'GERD', edgeType: 'protective', label: 'foundation buffer' },
    { source: 'FND_ORAL_HEALTH', target: 'TOOTH', edgeType: 'protective', label: 'foundation buffer' },
    { source: 'FND_CIRCADIAN_ALIGNMENT', target: 'SLEEP_DEP', edgeType: 'protective', label: 'foundation buffer' },
    { source: 'FND_PHYSICAL_ACTIVITY', target: 'STRESS', edgeType: 'protective', label: 'foundation buffer' },
    { source: 'FND_METABOLIC_HEALTH', target: 'GERD', edgeType: 'protective', label: 'foundation buffer' },
  ];

  for (const bridge of bridgeEdges) {
    const sourceResult = upsertPlaceholderNode(nextNodes, existingNodeIDs, nodeIndexByID, bridge.source);
    if (sourceResult.added) {
      addedNodeIDs.push(bridge.source);
    }

    const targetResult = upsertPlaceholderNode(nextNodes, existingNodeIDs, nodeIndexByID, bridge.target);
    if (targetResult.added) {
      addedNodeIDs.push(bridge.target);
    }

    const edgeResult = addOrReuseEdge(nextEdges, edgeIndex, {
      source: bridge.source,
      target: bridge.target,
      edgeType: bridge.edgeType,
      label: bridge.label,
      edgeColor: '#1d4ed8',
      tooltip: 'Foundation to acute bridge',
      strength: 0.55,
    });

    if (edgeResult.added) {
      addedEdgeIDs.push(edgeResult.edgeID);
    }
  }

  const tooltipRequiredNodeIDs = new Set<string>();
  for (const stateNode of mapFile.stateNodeTemplates) {
    tooltipRequiredNodeIDs.add(stateNode.id);
  }
  for (const habit of mapFile.canonicalHabits) {
    for (const nodeID of habit.targetNodeIds) {
      tooltipRequiredNodeIDs.add(nodeID);
    }
  }
  normalizeNodeLabelsAndTooltips(nextNodes, tooltipRequiredNodeIDs);
  normalizeLoopAnchorEdgeLabels(nextEdges);

  interventions.sort((left, right) => {
    const leftOrder = readNumber(left.defaultOrder) ?? Number.POSITIVE_INFINITY;
    const rightOrder = readNumber(right.defaultOrder) ?? Number.POSITIVE_INFINITY;

    if (leftOrder !== rightOrder) {
      return leftOrder - rightOrder;
    }

    const leftID = readOptionalString(left.id) ?? '';
    const rightID = readOptionalString(right.id) ?? '';
    return leftID.localeCompare(rightID);
  });

  const nextGraph: GraphData = {
    nodes: nextNodes,
    edges: nextEdges,
  };

  const graphFirstDiff = firstDiffPath(currentGraph, nextGraph);
  const nextGraphVersion = computeGraphVersion(nextGraph);
  const graphChanged = (
    graphFirstDiff !== null
    || nextGraphVersion !== currentGraphVersion
    || !resolvedGraph.hadWrappedGraphData
  );
  const nowISO = new Date().toISOString();

  const nextCatalogRecord: Record<string, unknown> = structuredClone(currentCatalogRecord);
  nextCatalogRecord.interventions = interventions;

  const nextStore: Record<string, unknown> = structuredClone(currentStore);
  const customDiagram = ensureRecord(nextStore, 'customCausalDiagram');
  customDiagram.graphData = nextGraph;
  customDiagram.graphVersion = nextGraphVersion;
  customDiagram.baseGraphVersion = readOptionalString(customDiagram.baseGraphVersion)
    ?? currentGraphVersion
    ?? nextGraphVersion;
  if (graphChanged) {
    customDiagram.lastModified = nowISO;
  } else if (readOptionalString(customDiagram.lastModified) === null) {
    customDiagram.lastModified = nowISO;
  }

  const progressState = ensureRecord(nextStore, 'progressQuestionSetState');
  const activeBeforeSnapshot = Array.isArray(progressState.activeQuestions)
    ? structuredClone(progressState.activeQuestions)
    : null;
  const pendingBeforeSnapshot = isUnknownRecord(progressState.pendingProposal)
    ? structuredClone(progressState.pendingProposal)
    : null;
  const existingPendingCreatedAt = isUnknownRecord(progressState.pendingProposal)
    ? readOptionalString(progressState.pendingProposal.createdAt)
    : null;

  const existingQuestionsRaw = Array.isArray(progressState.activeQuestions)
    ? progressState.activeQuestions
    : (
      isUnknownRecord(progressState.pendingProposal) && Array.isArray(progressState.pendingProposal.questions)
    )
      ? progressState.pendingProposal.questions
      : [];
  const existingQuestionRecords: Record<string, unknown>[] = [];

  for (const entry of existingQuestionsRaw) {
    if (!isUnknownRecord(entry)) {
      continue;
    }

    const id = readOptionalString(entry.id);
    if (id === null) {
      continue;
    }

    existingQuestionRecords.push(structuredClone(entry));
  }

  const finalEdgeRows = buildEdgeRows(nextGraph.edges);
  const morningQuestionSpecs: MorningQuestionSpec[] = [
    { id: 'morning.globalSensation', title: 'How is globalSensation this morning?', nodeIDs: ['MICRO'] },
    { id: 'morning.neckTightness', title: 'How is neckTightness this morning?', nodeIDs: ['NECK_TIGHTNESS'] },
    { id: 'morning.jawSoreness', title: 'How is jawSoreness this morning?', nodeIDs: ['TMD'] },
    { id: 'morning.earFullness', title: 'How is earFullness this morning?', nodeIDs: ['EAR'] },
    { id: 'morning.healthAnxiety', title: 'How is healthAnxiety this morning?', nodeIDs: ['HEALTH_ANXIETY'] },
    { id: 'morning.stressLevel', title: 'How is stressLevel this morning?', nodeIDs: ['STRESS'] },
    { id: 'morning.morningHeadache', title: 'How is morningHeadache this morning?', nodeIDs: ['HEADACHES'] },
    { id: 'morning.dryMouth', title: 'How is dryMouth this morning?', nodeIDs: ['SALIVA'] },
  ];

  const morningQuestions = morningQuestionSpecs.map((spec) => buildMorningQuestion(spec, finalEdgeRows));
  const foundationQuestions = [
    buildFoundationQuestion(
      'foundation.sleepRegularity',
      'How steady was your sleep foundation today?',
      ['FND_SLEEP_REGULARITY', 'FND_SLEEP_QUALITY'],
      finalEdgeRows,
    ),
    buildFoundationQuestion(
      'foundation.metabolicHealth',
      'How stable was your metabolic foundation today?',
      ['FND_METABOLIC_HEALTH', 'FND_NUTRITION_QUALITY'],
      finalEdgeRows,
    ),
    buildFoundationQuestion(
      'foundation.socialConnectedness',
      'How connected did you feel today?',
      ['FND_SOCIAL_CONNECTEDNESS'],
      finalEdgeRows,
    ),
    buildFoundationQuestion(
      'foundation.financialResilience',
      'How secure did your financial foundation feel today?',
      ['FND_FINANCIAL_RESILIENCE'],
      finalEdgeRows,
    ),
  ];

  const questionReplacementByID = new Map<string, Record<string, unknown>>();
  for (const question of [...morningQuestions, ...foundationQuestions]) {
    const id = readOptionalString(question.id);
    if (id === null) {
      continue;
    }
    questionReplacementByID.set(id, question);
  }

  const nextQuestions: Record<string, unknown>[] = [];
  const consumedQuestionIDs = new Set<string>();

  for (const question of existingQuestionRecords) {
    const id = readOptionalString(question.id);
    if (id === null) {
      continue;
    }

    const replacement = questionReplacementByID.get(id);
    if (replacement !== undefined) {
      nextQuestions.push(replacement);
      consumedQuestionIDs.add(id);
      continue;
    }

    nextQuestions.push(question);
    consumedQuestionIDs.add(id);
  }

  const desiredQuestionOrder = [...morningQuestions, ...foundationQuestions];
  for (const question of desiredQuestionOrder) {
    const id = readOptionalString(question.id);
    if (id === null) {
      continue;
    }
    if (consumedQuestionIDs.has(id)) {
      continue;
    }
    nextQuestions.push(question);
    consumedQuestionIDs.add(id);
  }

  const foundationQuestionIDsInOrder: string[] = foundationQuestions
    .map((question) => readOptionalString(question.id))
    .filter((id): id is string => id !== null);

  const legacyQuestionSetVersion = `questions-${nextGraphVersion}`;
  const foundationQuestionSetVersion = `questions-foundation-${nextGraphVersion}`;

  if (readOptionalString(progressState.activeQuestionSetVersion) === null) {
    progressState.activeQuestionSetVersion = legacyQuestionSetVersion;
  }

  if (readOptionalString(progressState.activeSourceGraphVersion) === null) {
    progressState.activeSourceGraphVersion = nextGraphVersion;
  }

  if (!Array.isArray(progressState.declinedGraphVersions)) {
    progressState.declinedGraphVersions = [];
  }

  const activeQuestionSetVersion = readOptionalString(progressState.activeQuestionSetVersion);
  const activeQuestionsCurrent = Array.isArray(progressState.activeQuestions)
    ? progressState.activeQuestions
    : [];
  const activeQuestionsMatchFoundation = (
    Array.isArray(progressState.activeQuestions)
    && firstDiffPath(activeQuestionsCurrent, nextQuestions) === null
  );
  const hasAcceptedFoundationQuestions = (
    activeQuestionSetVersion === foundationQuestionSetVersion
    && activeQuestionsMatchFoundation
  );
  const shouldAttachPendingProposal = !hasAcceptedFoundationQuestions;

  if (shouldAttachPendingProposal) {
    const pendingProposal = isUnknownRecord(progressState.pendingProposal)
      ? progressState.pendingProposal
      : {};
    pendingProposal.questions = nextQuestions;
    pendingProposal.sourceGraphVersion = nextGraphVersion;
    pendingProposal.proposedQuestionSetVersion = foundationQuestionSetVersion;
    pendingProposal.createdAt = existingPendingCreatedAt ?? nowISO;
    progressState.pendingProposal = pendingProposal;
  } else {
    progressState.pendingProposal = null;
  }

  if (shouldAttachPendingProposal) {
    if (!Array.isArray(progressState.activeQuestions)) {
      progressState.activeQuestions = morningQuestions;
    }
  } else {
    progressState.activeQuestionSetVersion = foundationQuestionSetVersion;
    progressState.activeSourceGraphVersion = nextGraphVersion;
    progressState.activeQuestions = nextQuestions;
  }

  const morningFieldIDs = [
    'globalSensation',
    'neckTightness',
    'jawSoreness',
    'earFullness',
    'healthAnxiety',
    'stressLevel',
    'morningHeadache',
    'dryMouth',
  ];
  const morningQuestionnaire = ensureRecord(nextStore, 'morningQuestionnaire');
  morningQuestionnaire.enabledFields = morningFieldIDs;
  morningQuestionnaire.requiredFields = morningFieldIDs;

  const pendingChanged = firstDiffPath(pendingBeforeSnapshot, progressState.pendingProposal) !== null;
  const activeQuestionsChanged = firstDiffPath(activeBeforeSnapshot, progressState.activeQuestions) !== null;
  if (pendingChanged || activeQuestionsChanged || graphChanged || readOptionalString(progressState.updatedAt) === null) {
    progressState.updatedAt = nowISO;
  }

  const beforeQuestionCount = existingQuestionRecords.length;
  const afterQuestionCount = Array.isArray(progressState.activeQuestions) ? progressState.activeQuestions.length : 0;

  const userDataFirstDiff = firstDiffPath(currentStore, nextStore);
  const userContentFirstDiff = firstDiffPath(currentCatalogRecord, nextCatalogRecord);
  const userDataChanged = userDataFirstDiff !== null;
  const userContentChanged = userContentFirstDiff !== null;
  const changed = userDataChanged || userContentChanged || !resolvedGraph.hadWrappedGraphData;

  const existingInterventionCount = parsedInterventions.length;
  const nextInterventionCount = interventions.length;
  const reusedInterventionCount = habitResolutions.filter((row) => row.reusedIntervention).length;
  const addedInterventionCount = habitResolutions.filter((row) => row.addedIntervention).length;

  const trace: TraceReport = {
    generatedAt: nowISO,
    userID: args.userID,
    mapSchemaVersion: mapFile.schemaVersion,
    reportMentionsParsed: reportMentions.length,
    mentionCoverageCount: mapFile.mentionCoverage.length,
    canonicalHabitCount: mapFile.canonicalHabits.length,
    reusedInterventionCount,
    addedInterventionCount,
    graphNodeCountBefore: currentGraph.nodes.length,
    graphNodeCountAfter: nextGraph.nodes.length,
    graphEdgeCountBefore: currentGraph.edges.length,
    graphEdgeCountAfter: nextGraph.edges.length,
    addedNodeIDs: uniqueSorted(addedNodeIDs),
    addedEdgeIDs: uniqueSorted(addedEdgeIDs),
    interventionsBefore: existingInterventionCount,
    interventionsAfter: nextInterventionCount,
    pendingQuestionsBefore: beforeQuestionCount,
    pendingQuestionsAfter: afterQuestionCount,
    foundationQuestionIDs: foundationQuestionIDsInOrder,
    nextGraphVersion,
    dataChanged: changed,
    userContentChanged,
    habitResolutions,
  };

  if (args.traceOut !== null) {
    const outputPath = path.isAbsolute(args.traceOut)
      ? args.traceOut
      : path.resolve(process.cwd(), args.traceOut);

    mkdirSync(path.dirname(outputPath), { recursive: true });
    writeFileSync(outputPath, `${JSON.stringify(trace, null, 2)}\n`, 'utf8');
  }

  console.log(`Mode: ${args.write ? 'write' : 'dry-run'}`);
  console.log(`User ID: ${args.userID}`);
  console.log(`Report mentions parsed: ${reportMentions.length}`);
  console.log(`Mapping mention coverage: ${mapFile.mentionCoverage.length}`);
  console.log(`Canonical habits: ${mapFile.canonicalHabits.length}`);
  console.log(`Reused interventions: ${reusedInterventionCount}`);
  console.log(`Added interventions: ${addedInterventionCount}`);
  console.log(`Graph nodes: ${currentGraph.nodes.length} -> ${nextGraph.nodes.length} (added ${uniqueSorted(addedNodeIDs).length})`);
  console.log(`Graph edges: ${currentGraph.edges.length} -> ${nextGraph.edges.length} (added ${uniqueSorted(addedEdgeIDs).length})`);
  console.log(`Interventions catalog entries: ${existingInterventionCount} -> ${nextInterventionCount}`);
  console.log(`Pending proposal questions: ${beforeQuestionCount} -> ${afterQuestionCount}`);
  console.log(`Current graph version: ${currentGraphVersion}`);
  console.log(`Next graph version: ${nextGraphVersion}`);
  if (graphFirstDiff !== null) {
    console.log(`Graph first diff path: ${graphFirstDiff}`);
  }
  console.log(`User data changed: ${userDataChanged ? 'yes' : 'no'}`);
  if (userDataFirstDiff !== null) {
    console.log(`User data first diff path: ${userDataFirstDiff}`);
  }
  console.log(`User content changed: ${userContentChanged ? 'yes' : 'no'}`);
  if (userContentFirstDiff !== null) {
    console.log(`User content first diff path: ${userContentFirstDiff}`);
  }
  console.log(`Overall changed: ${changed ? 'yes' : 'no'}`);

  if (args.dryRun) {
    return;
  }

  if (!changed) {
    console.log('No update required.');
    return;
  }

  if (userContentChanged) {
    const upsertVersion = (catalogPayload.userContentVersion ?? 0) + 1;
    const contentUpsert = await supabase
      .from('user_content')
      .upsert(
        {
          user_id: args.userID,
          content_type: 'inputs',
          content_key: 'interventions_catalog',
          data: nextCatalogRecord,
          version: upsertVersion,
        },
        {
          onConflict: 'user_id,content_type,content_key',
        },
      );

    if (contentUpsert.error) {
      throw new Error(`Failed to upsert user_content interventions_catalog: ${contentUpsert.error.message}`);
    }
  }

  if (userDataChanged || !resolvedGraph.hadWrappedGraphData) {
    const userDataUpdate = await supabase
      .from('user_data')
      .update({ data: nextStore })
      .eq('user_id', args.userID);

    if (userDataUpdate.error) {
      throw new Error(`Failed to update user_data: ${userDataUpdate.error.message}`);
    }
  }

  console.log('Update applied.');
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
