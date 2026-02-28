import { readFileSync } from 'node:fs';

export type UnknownRecord = Record<string, unknown>;

export interface GraphNodeData extends UnknownRecord {
  id: string;
}

export interface GraphNodeElement extends UnknownRecord {
  data: GraphNodeData;
}

export interface GraphEdgeData extends UnknownRecord {
  source: string;
  target: string;
  edgeType?: string;
  label?: string;
}

export interface GraphEdgeElement extends UnknownRecord {
  data: GraphEdgeData;
}

export interface GraphData {
  nodes: GraphNodeElement[];
  edges: GraphEdgeElement[];
}

export interface InterventionDefinition {
  id: string;
  graphNodeID: string;
  pillars: string[];
  planningTags: string[];
}

export interface PillarDefinition {
  id: string;
  title: string;
  rank: number;
}

export interface PillarConnectivity {
  nodeCount: number;
  edgeTouchCount: number;
  connectedNodeIDs: string[];
  disconnectedNodeIDs: string[];
  connectedToOutsideNodeCount: number;
}

export interface PillarIntegrityRow {
  pillar: PillarDefinition;
  interventions: string[];
  activeInterventions: string[];
  nodeIDs: string[];
  missingNodeIDs: string[];
  missingCanonicalEdgeSignatures: string[];
  connectivity: PillarConnectivity;
}

export interface PillarIntegrityReport {
  userID: string;
  generatedAt: string;
  requestedPillarFilter: string | null;
  totalInterventionCount: number;
  activeInterventionCount: number;
  userGraphNodeCount: number;
  userGraphEdgeCount: number;
  canonicalGraphNodeCount: number;
  canonicalGraphEdgeCount: number;
  rows: PillarIntegrityRow[];
  overallMissingNodeIDs: string[];
  overallMissingCanonicalEdgeSignatures: string[];
}

function isRecord(value: unknown): value is UnknownRecord {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readNonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }

  return trimmed;
}

function readOptionalString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  return value.trim();
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const values = new Set<string>();
  for (const entry of value) {
    const parsed = readNonEmptyString(entry);
    if (parsed !== null) {
      values.add(parsed);
    }
  }

  return [...values].sort();
}

function parseGraphNode(entry: unknown): GraphNodeElement | null {
  if (!isRecord(entry)) {
    return null;
  }

  const dataRaw = entry.data;
  if (!isRecord(dataRaw)) {
    return null;
  }

  const id = readNonEmptyString(dataRaw.id);
  if (id === null) {
    return null;
  }

  const data: GraphNodeData = { id };
  for (const [key, value] of Object.entries(dataRaw)) {
    if (key === 'id') {
      continue;
    }
    data[key] = value;
  }

  const node: GraphNodeElement = { data };
  for (const [key, value] of Object.entries(entry)) {
    if (key === 'data') {
      continue;
    }
    node[key] = value;
  }

  return node;
}

function parseGraphEdge(entry: unknown): GraphEdgeElement | null {
  if (!isRecord(entry)) {
    return null;
  }

  const dataRaw = entry.data;
  if (!isRecord(dataRaw)) {
    return null;
  }

  const source = readNonEmptyString(dataRaw.source);
  const target = readNonEmptyString(dataRaw.target);
  if (source === null || target === null) {
    return null;
  }

  const edgeType = readOptionalString(dataRaw.edgeType);
  const label = readOptionalString(dataRaw.label);

  const data: GraphEdgeData = {
    source,
    target,
  };

  if (edgeType !== null) {
    data.edgeType = edgeType;
  }

  if (label !== null) {
    data.label = label;
  }

  for (const [key, value] of Object.entries(dataRaw)) {
    if (key === 'source' || key === 'target' || key === 'edgeType' || key === 'label') {
      continue;
    }
    data[key] = value;
  }

  const edge: GraphEdgeElement = { data };
  for (const [key, value] of Object.entries(entry)) {
    if (key === 'data') {
      continue;
    }
    edge[key] = value;
  }

  return edge;
}

function parseNodeArray(value: unknown): GraphNodeElement[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const nodes: GraphNodeElement[] = [];
  for (const entry of value) {
    const parsed = parseGraphNode(entry);
    if (parsed !== null) {
      nodes.push(parsed);
    }
  }

  return nodes;
}

function parseEdgeArray(value: unknown): GraphEdgeElement[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const edges: GraphEdgeElement[] = [];
  for (const entry of value) {
    const parsed = parseGraphEdge(entry);
    if (parsed !== null) {
      edges.push(parsed);
    }
  }

  return edges;
}

export function parseGraphData(value: unknown): GraphData {
  if (!isRecord(value)) {
    return { nodes: [], edges: [] };
  }

  return {
    nodes: parseNodeArray(value.nodes),
    edges: parseEdgeArray(value.edges),
  };
}

export function parseInterventionsCatalog(value: unknown): InterventionDefinition[] {
  if (!isRecord(value) || !Array.isArray(value.interventions)) {
    return [];
  }

  const interventions = new Map<string, InterventionDefinition>();
  for (const entry of value.interventions) {
    if (!isRecord(entry)) {
      continue;
    }

    const id = readNonEmptyString(entry.id);
    if (id === null) {
      continue;
    }

    const graphNodeID = readNonEmptyString(entry.graphNodeId) ?? readNonEmptyString(entry.graphNodeID);
    if (graphNodeID === null) {
      continue;
    }

    const pillars = readStringArray(entry.pillars);
    if (pillars.length === 0) {
      continue;
    }

    const planningTags = readStringArray(entry.planningTags);
    interventions.set(id, {
      id,
      graphNodeID,
      pillars,
      planningTags,
    });
  }

  return [...interventions.values()].sort((left, right) => left.id.localeCompare(right.id));
}

export function parsePlanningPolicyPillars(value: unknown): PillarDefinition[] {
  if (!isRecord(value) || !Array.isArray(value.pillars)) {
    return [];
  }

  const byID = new Map<string, PillarDefinition>();
  for (let index = 0; index < value.pillars.length; index += 1) {
    const entry = value.pillars[index];

    if (typeof entry === 'string') {
      const id = readNonEmptyString(entry);
      if (id === null) {
        continue;
      }

      if (!byID.has(id)) {
        byID.set(id, {
          id,
          title: id,
          rank: index + 1,
        });
      }
      continue;
    }

    if (!isRecord(entry)) {
      continue;
    }

    const id = readNonEmptyString(entry.id);
    if (id === null) {
      continue;
    }

    const title = readNonEmptyString(entry.title) ?? id;
    const rank = typeof entry.rank === 'number' && Number.isFinite(entry.rank)
      ? entry.rank
      : index + 1;

    if (!byID.has(id)) {
      byID.set(id, {
        id,
        title,
        rank,
      });
    }
  }

  return [...byID.values()].sort((left, right) => {
    if (left.rank === right.rank) {
      return left.id.localeCompare(right.id);
    }
    return left.rank - right.rank;
  });
}

function fallbackPillars(interventions: InterventionDefinition[]): PillarDefinition[] {
  const pillarIDs = new Set<string>();
  for (const intervention of interventions) {
    for (const pillarID of intervention.pillars) {
      pillarIDs.add(pillarID);
    }
  }

  return [...pillarIDs]
    .sort((left, right) => left.localeCompare(right))
    .map((id, index) => ({
      id,
      title: id,
      rank: index + 1,
    }));
}

function normalizeForSignature(value: string | undefined): string {
  if (value === undefined) {
    return '';
  }

  return value.trim().toLowerCase();
}

export function edgeSignature(edge: Pick<GraphEdgeData, 'source' | 'target' | 'edgeType' | 'label'>): string {
  return [
    edge.source,
    edge.target,
    normalizeForSignature(edge.edgeType),
    normalizeForSignature(edge.label),
  ].join('|');
}

function uniqueSorted(values: string[]): string[] {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right));
}

function buildInterventionsByPillar(interventions: InterventionDefinition[]): Map<string, string[]> {
  const byPillar = new Map<string, string[]>();

  for (const intervention of interventions) {
    for (const pillarID of intervention.pillars) {
      const current = byPillar.get(pillarID) ?? [];
      current.push(intervention.id);
      byPillar.set(pillarID, current);
    }
  }

  return byPillar;
}

function buildNodeIDsByPillar(interventions: InterventionDefinition[]): Map<string, string[]> {
  const byPillar = new Map<string, string[]>();

  for (const intervention of interventions) {
    for (const pillarID of intervention.pillars) {
      const current = byPillar.get(pillarID) ?? [];
      current.push(intervention.graphNodeID);
      byPillar.set(pillarID, current);
    }
  }

  return byPillar;
}

function buildConnectivity(nodeIDSet: Set<string>, edges: GraphEdgeElement[]): PillarConnectivity {
  const connectedNodeIDs = new Set<string>();
  const outsideNodeIDs = new Set<string>();
  let edgeTouchCount = 0;

  for (const edgeElement of edges) {
    const source = edgeElement.data.source;
    const target = edgeElement.data.target;
    const sourceInSet = nodeIDSet.has(source);
    const targetInSet = nodeIDSet.has(target);

    if (!sourceInSet && !targetInSet) {
      continue;
    }

    edgeTouchCount += 1;

    if (sourceInSet) {
      connectedNodeIDs.add(source);
    } else {
      outsideNodeIDs.add(source);
    }

    if (targetInSet) {
      connectedNodeIDs.add(target);
    } else {
      outsideNodeIDs.add(target);
    }
  }

  const disconnectedNodeIDs = [...nodeIDSet]
    .filter((nodeID) => !connectedNodeIDs.has(nodeID))
    .sort((left, right) => left.localeCompare(right));

  return {
    nodeCount: nodeIDSet.size,
    edgeTouchCount,
    connectedNodeIDs: [...connectedNodeIDs].sort((left, right) => left.localeCompare(right)),
    disconnectedNodeIDs,
    connectedToOutsideNodeCount: outsideNodeIDs.size,
  };
}

export function buildPillarIntegrityReport(input: {
  userID: string;
  interventions: InterventionDefinition[];
  activeInterventionIDs: string[];
  userGraph: GraphData;
  canonicalGraph: GraphData;
  policyPillars: PillarDefinition[];
  pillarFilter: string | null;
}): PillarIntegrityReport {
  const activeInterventionSet = new Set(uniqueSorted(input.activeInterventionIDs));
  const userNodeIDSet = new Set(input.userGraph.nodes.map((node) => node.data.id));
  const userEdgeSignatureSet = new Set(input.userGraph.edges.map((edge) => edgeSignature(edge.data)));
  const interventionsByPillar = buildInterventionsByPillar(input.interventions);
  const nodeIDsByPillar = buildNodeIDsByPillar(input.interventions);

  const pillars = input.policyPillars.length > 0
    ? input.policyPillars
    : fallbackPillars(input.interventions);

  const selectedPillars = input.pillarFilter === null
    ? pillars
    : pillars.filter((pillar) => pillar.id === input.pillarFilter);

  const rows: PillarIntegrityRow[] = selectedPillars.map((pillar) => {
    const interventionIDs = uniqueSorted(interventionsByPillar.get(pillar.id) ?? []);
    const activeInterventions = interventionIDs.filter((id) => activeInterventionSet.has(id));
    const nodeIDs = uniqueSorted(nodeIDsByPillar.get(pillar.id) ?? []);
    const nodeIDSet = new Set(nodeIDs);
    const missingNodeIDs = nodeIDs.filter((nodeID) => !userNodeIDSet.has(nodeID));

    const canonicalEdgeSignatures = uniqueSorted(
      input.canonicalGraph.edges
        .filter((edge) => nodeIDSet.has(edge.data.source) || nodeIDSet.has(edge.data.target))
        .map((edge) => edgeSignature(edge.data)),
    );

    const missingCanonicalEdgeSignatures = canonicalEdgeSignatures
      .filter((signature) => !userEdgeSignatureSet.has(signature))
      .sort((left, right) => left.localeCompare(right));

    return {
      pillar,
      interventions: interventionIDs,
      activeInterventions,
      nodeIDs,
      missingNodeIDs,
      missingCanonicalEdgeSignatures,
      connectivity: buildConnectivity(nodeIDSet, input.userGraph.edges),
    };
  });

  const overallMissingNodeIDs = uniqueSorted(rows.flatMap((row) => row.missingNodeIDs));
  const overallMissingCanonicalEdgeSignatures = uniqueSorted(
    rows.flatMap((row) => row.missingCanonicalEdgeSignatures),
  );

  return {
    userID: input.userID,
    generatedAt: new Date().toISOString(),
    requestedPillarFilter: input.pillarFilter,
    totalInterventionCount: input.interventions.length,
    activeInterventionCount: activeInterventionSet.size,
    userGraphNodeCount: input.userGraph.nodes.length,
    userGraphEdgeCount: input.userGraph.edges.length,
    canonicalGraphNodeCount: input.canonicalGraph.nodes.length,
    canonicalGraphEdgeCount: input.canonicalGraph.edges.length,
    rows,
    overallMissingNodeIDs,
    overallMissingCanonicalEdgeSignatures,
  };
}

export function loadGraphFromPath(path: string): GraphData {
  const text = readFileSync(path, 'utf8');
  const parsed: unknown = JSON.parse(text);
  return parseGraphData(parsed);
}

export function loadGraphFromUnknown(value: unknown): GraphData {
  return parseGraphData(value);
}

export function isUnknownRecord(value: unknown): value is UnknownRecord {
  return isRecord(value);
}
