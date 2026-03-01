import process from 'node:process';
import path from 'node:path';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import {
  edgeSignature,
  GraphData,
  GraphEdgeData,
  GraphNodeData,
  isUnknownRecord,
  loadGraphFromPath,
} from './pillar-integrity-lib';

interface ParsedArgs {
  graphPath: string;
  interventionsPath: string;
  planningPolicyPath: string;
  overridesPath: string | null;
  outPath: string;
  pretty: boolean;
}

interface PlanningPillar {
  id: string;
  title: string;
  rank: number;
}

interface InterventionMapping {
  interventionId: string;
  pillars: string[];
  maxDetailNodeIds: string[];
  maxDetailEdgeIds: string[];
}

interface CurationNodeRow {
  id: string;
  disclosureLevel: number;
  pillarIds: string[];
}

interface CurationEdgeRow {
  id: string;
  source: string;
  target: string;
  disclosureLevel: number;
  edgeType: string | null;
  label: string | null;
}

interface CurationDisclosureMappingRow {
  sourceId: string;
  targetId: string;
  sourceLevel: number;
  targetLevel: number;
}

interface PillarConnectivityRow {
  pillarId: string;
  title: string;
  rank: number;
  nodeCount: number;
  edgeCount: number;
  disconnectedNodeIds: string[];
}

interface CurationOutput {
  version: string;
  generatedAt: string;
  sourceGraphPath: string;
  sourceInterventionsPath: string;
  sourcePlanningPolicyPath: string;
  nodes: CurationNodeRow[];
  edges: CurationEdgeRow[];
  disclosureMappings: CurationDisclosureMappingRow[];
  interventionMappings: InterventionMapping[];
  pillarConnectivity: PillarConnectivityRow[];
}

interface CurationOverrides {
  nodes?: CurationNodeRow[];
  edges?: CurationEdgeRow[];
  disclosureMappings?: CurationDisclosureMappingRow[];
  interventionMappings?: InterventionMapping[];
}

function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
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

function parseArgs(): ParsedArgs {
  const graphPathRaw = getArg('graph-path') ?? 'ios/Telocare/Telocare/Resources/Graph/default-graph.json';
  const interventionsPathRaw = getArg('interventions-path') ?? 'data/interventions.json';
  const planningPolicyPathRaw = getArg('planning-policy-path') ?? 'ios/Telocare/Telocare/Resources/Foundation/planner-policy-v1.json';
  const overridesPathRaw = getArg('overrides') ?? 'data/disclosure-curation.overrides.json';
  const outPathRaw = getArg('out') ?? 'data/disclosure-curation.v1.json';

  return {
    graphPath: path.isAbsolute(graphPathRaw) ? graphPathRaw : path.resolve(process.cwd(), graphPathRaw),
    interventionsPath: path.isAbsolute(interventionsPathRaw) ? interventionsPathRaw : path.resolve(process.cwd(), interventionsPathRaw),
    planningPolicyPath: path.isAbsolute(planningPolicyPathRaw) ? planningPolicyPathRaw : path.resolve(process.cwd(), planningPolicyPathRaw),
    overridesPath: path.isAbsolute(overridesPathRaw) ? overridesPathRaw : path.resolve(process.cwd(), overridesPathRaw),
    outPath: path.isAbsolute(outPathRaw) ? outPathRaw : path.resolve(process.cwd(), outPathRaw),
    pretty: !hasFlag('no-pretty'),
  };
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

function readOptionalNumber(value: unknown): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    return null;
  }
  return value;
}

function resolvedNodeDisclosureLevel(node: GraphNodeData): number {
  const explicit = readOptionalNumber(node.disclosureLevel);
  if (explicit !== null) {
    return clampDisclosureLevel(explicit);
  }
  const styleClass = readOptionalString(node.styleClass);
  if (styleClass === 'intervention') {
    return 3;
  }
  const tier = readOptionalNumber(node.tier);
  if (tier === null) {
    return 2;
  }
  if (tier <= 3) {
    return 1;
  }
  if (tier <= 7) {
    return 2;
  }
  return 3;
}

function resolvedEdgeDisclosureLevel(
  edge: GraphEdgeData,
  nodeLevelByID: Map<string, number>,
): number {
  const explicit = readOptionalNumber(edge.disclosureLevel);
  if (explicit !== null) {
    return clampDisclosureLevel(explicit);
  }
  const sourceLevel = nodeLevelByID.get(edge.source) ?? 2;
  const targetLevel = nodeLevelByID.get(edge.target) ?? 2;
  return clampDisclosureLevel(Math.max(sourceLevel, targetLevel));
}

function clampDisclosureLevel(level: number): number {
  return Math.max(1, Math.min(10, Math.round(level)));
}

function parsePlanningPillars(pathToPolicy: string): PlanningPillar[] {
  const raw = readFileSync(pathToPolicy, 'utf8');
  const parsed: unknown = JSON.parse(raw);
  if (!isUnknownRecord(parsed) || !Array.isArray(parsed.pillars)) {
    return [];
  }

  const rows: PlanningPillar[] = [];
  for (let index = 0; index < parsed.pillars.length; index += 1) {
    const entry = parsed.pillars[index];
    if (!isUnknownRecord(entry)) {
      continue;
    }
    const id = readOptionalString(entry.id);
    if (id === null) {
      continue;
    }
    const title = readOptionalString(entry.title) ?? id;
    const rankRaw = readOptionalNumber(entry.rank);
    const rank = rankRaw === null ? index + 1 : Math.max(1, Math.round(rankRaw));
    rows.push({ id, title, rank });
  }

  return rows.sort((left, right) => {
    if (left.rank !== right.rank) {
      return left.rank - right.rank;
    }
    return left.id.localeCompare(right.id);
  });
}

function parseInterventionMappings(interventionsPath: string, edgeRows: CurationEdgeRow[]): InterventionMapping[] {
  const raw = readFileSync(interventionsPath, 'utf8');
  const parsed: unknown = JSON.parse(raw);
  if (!isUnknownRecord(parsed) || !Array.isArray(parsed.interventions)) {
    return [];
  }

  const edgeIDsBySourceTarget = new Map<string, string[]>();
  for (const edge of edgeRows) {
    const key = `${edge.source}|${edge.target}`;
    const current = edgeIDsBySourceTarget.get(key) ?? [];
    current.push(edge.id);
    edgeIDsBySourceTarget.set(key, current);
  }

  const mappings: InterventionMapping[] = [];
  for (const entry of parsed.interventions) {
    if (!isUnknownRecord(entry)) {
      continue;
    }
    const interventionId = readOptionalString(entry.id);
    if (interventionId === null) {
      continue;
    }
    const graphNodeId = readOptionalString(entry.graphNodeId) ?? readOptionalString(entry.graphNodeID);
    if (graphNodeId === null) {
      continue;
    }

    const pillars = readStringArray(entry.pillars);
    const acuteTargetsFromLegacy = readStringArray(entry.acuteTargetNodeIDs);
    const acuteTargets = acuteTargetsFromLegacy.length > 0
      ? acuteTargetsFromLegacy
      : readStringArray(entry.acuteTargets);
    const maxDetailNodeIds = new Set<string>([graphNodeId, ...acuteTargets]);
    const maxDetailEdgeIds = new Set<string>();
    for (const targetId of acuteTargets) {
      const direct = edgeIDsBySourceTarget.get(`${graphNodeId}|${targetId}`) ?? [];
      const reverse = edgeIDsBySourceTarget.get(`${targetId}|${graphNodeId}`) ?? [];
      for (const edgeId of direct) {
        maxDetailEdgeIds.add(edgeId);
      }
      for (const edgeId of reverse) {
        maxDetailEdgeIds.add(edgeId);
      }
    }

    mappings.push({
      interventionId,
      pillars,
      maxDetailNodeIds: [...maxDetailNodeIds].sort((left, right) => left.localeCompare(right)),
      maxDetailEdgeIds: [...maxDetailEdgeIds].sort((left, right) => left.localeCompare(right)),
    });
  }

  return mappings.sort((left, right) => left.interventionId.localeCompare(right.interventionId));
}

function resolvedEdgeRows(graph: GraphData): CurationEdgeRow[] {
  const countByPrefix = new Map<string, number>();
  const rows: CurationEdgeRow[] = [];

  for (const edgeElement of graph.edges) {
    const edge = edgeElement.data;
    const edgeType = readOptionalString(edge.edgeType);
    const label = readOptionalString(edge.label);
    const prefix = edgeSignature({
      source: edge.source,
      target: edge.target,
      edgeType: edgeType ?? '',
      label: label ?? '',
    });
    const count = countByPrefix.get(prefix) ?? 0;
    countByPrefix.set(prefix, count + 1);
    const explicitID = readOptionalString(edge.id);
    const id = explicitID ?? `edge:${prefix}#${count}`;
    rows.push({
      id,
      source: edge.source,
      target: edge.target,
      disclosureLevel: 1,
      edgeType,
      label,
    });
  }

  return rows;
}

function buildDisclosureMappings(
  graph: GraphData,
  nodeLevelByID: Map<string, number>,
): CurationDisclosureMappingRow[] {
  const mappings: CurationDisclosureMappingRow[] = [];
  for (const nodeElement of graph.nodes) {
    const node = nodeElement.data;
    const sourceLevel = nodeLevelByID.get(node.id) ?? 2;
    const parentIDsFromArray = readStringArray(node.parentIds);
    const parentIDFromSingle = readOptionalString(node.parentId);
    const parentIDs = parentIDsFromArray.length > 0
      ? parentIDsFromArray
      : parentIDFromSingle === null
        ? []
        : [parentIDFromSingle];

    for (const parentID of parentIDs) {
      const targetLevel = nodeLevelByID.get(parentID) ?? 1;
      mappings.push({
        sourceId: node.id,
        targetId: parentID,
        sourceLevel: sourceLevel,
        targetLevel: targetLevel,
      });
    }
  }

  return mappings.sort((left, right) => {
    if (left.sourceId !== right.sourceId) {
      return left.sourceId.localeCompare(right.sourceId);
    }
    return left.targetId.localeCompare(right.targetId);
  });
}

function buildPillarConnectivity(
  pillars: PlanningPillar[],
  nodeRows: CurationNodeRow[],
  edgeRows: CurationEdgeRow[],
  interventionMappings: InterventionMapping[],
): PillarConnectivityRow[] {
  const nodeByID = new Map(nodeRows.map((node) => [node.id, node]));
  const interventionNodeIDsByPillarID = new Map<string, Set<string>>();

  for (const mapping of interventionMappings) {
    for (const pillarID of mapping.pillars) {
      const current = interventionNodeIDsByPillarID.get(pillarID) ?? new Set<string>();
      for (const nodeID of mapping.maxDetailNodeIds) {
        current.add(nodeID);
      }
      interventionNodeIDsByPillarID.set(pillarID, current);
    }
  }

  return pillars.map((pillar) => {
    const nodeIDs = new Set<string>();
    for (const nodeRow of nodeRows) {
      if (nodeRow.pillarIds.includes(pillar.id)) {
        nodeIDs.add(nodeRow.id);
      }
    }
    for (const nodeID of interventionNodeIDsByPillarID.get(pillar.id) ?? []) {
      if (nodeByID.has(nodeID)) {
        nodeIDs.add(nodeID);
      }
    }

    const touchedNodeIDs = new Set<string>();
    let edgeCount = 0;
    for (const edge of edgeRows) {
      if (!nodeIDs.has(edge.source) || !nodeIDs.has(edge.target)) {
        continue;
      }
      edgeCount += 1;
      touchedNodeIDs.add(edge.source);
      touchedNodeIDs.add(edge.target);
    }

    const disconnectedNodeIds = [...nodeIDs]
      .filter((nodeID) => !touchedNodeIDs.has(nodeID))
      .sort((left, right) => left.localeCompare(right));

    return {
      pillarId: pillar.id,
      title: pillar.title,
      rank: pillar.rank,
      nodeCount: nodeIDs.size,
      edgeCount,
      disconnectedNodeIds,
    };
  });
}

function loadOverrides(pathToOverrides: string | null): CurationOverrides {
  if (pathToOverrides === null || !existsSync(pathToOverrides)) {
    return {};
  }

  const raw = readFileSync(pathToOverrides, 'utf8');
  const parsed: unknown = JSON.parse(raw);
  if (!isUnknownRecord(parsed)) {
    return {};
  }

  return {
    nodes: Array.isArray(parsed.nodes) ? parsed.nodes.filter(isCurationNodeRow) : undefined,
    edges: Array.isArray(parsed.edges) ? parsed.edges.filter(isCurationEdgeRow) : undefined,
    disclosureMappings: Array.isArray(parsed.disclosureMappings)
      ? parsed.disclosureMappings.filter(isCurationDisclosureMappingRow)
      : undefined,
    interventionMappings: Array.isArray(parsed.interventionMappings)
      ? parsed.interventionMappings.filter(isInterventionMapping)
      : undefined,
  };
}

function isCurationNodeRow(value: unknown): value is CurationNodeRow {
  if (!isUnknownRecord(value)) {
    return false;
  }
  return typeof value.id === 'string'
    && typeof value.disclosureLevel === 'number'
    && Array.isArray(value.pillarIds);
}

function isCurationEdgeRow(value: unknown): value is CurationEdgeRow {
  if (!isUnknownRecord(value)) {
    return false;
  }
  return typeof value.id === 'string'
    && typeof value.source === 'string'
    && typeof value.target === 'string'
    && typeof value.disclosureLevel === 'number';
}

function isCurationDisclosureMappingRow(value: unknown): value is CurationDisclosureMappingRow {
  if (!isUnknownRecord(value)) {
    return false;
  }
  return typeof value.sourceId === 'string'
    && typeof value.targetId === 'string'
    && typeof value.sourceLevel === 'number'
    && typeof value.targetLevel === 'number';
}

function isInterventionMapping(value: unknown): value is InterventionMapping {
  if (!isUnknownRecord(value)) {
    return false;
  }
  return typeof value.interventionId === 'string'
    && Array.isArray(value.pillars)
    && Array.isArray(value.maxDetailNodeIds)
    && Array.isArray(value.maxDetailEdgeIds);
}

function applyOverridesToNodes(
  nodes: CurationNodeRow[],
  overrides: CurationNodeRow[] | undefined,
): CurationNodeRow[] {
  if (overrides === undefined || overrides.length === 0) {
    return nodes;
  }

  const byID = new Map(nodes.map((node) => [node.id, node]));
  for (const override of overrides) {
    const current = byID.get(override.id);
    if (current === undefined) {
      byID.set(override.id, {
        id: override.id,
        disclosureLevel: clampDisclosureLevel(override.disclosureLevel),
        pillarIds: readStringArray(override.pillarIds),
      });
      continue;
    }
    byID.set(override.id, {
      id: current.id,
      disclosureLevel: clampDisclosureLevel(override.disclosureLevel),
      pillarIds: readStringArray(override.pillarIds).length > 0
        ? readStringArray(override.pillarIds)
        : current.pillarIds,
    });
  }

  return [...byID.values()].sort((left, right) => left.id.localeCompare(right.id));
}

function applyOverridesToEdges(
  edges: CurationEdgeRow[],
  overrides: CurationEdgeRow[] | undefined,
): CurationEdgeRow[] {
  if (overrides === undefined || overrides.length === 0) {
    return edges;
  }

  const byID = new Map(edges.map((edge) => [edge.id, edge]));
  for (const override of overrides) {
    const current = byID.get(override.id);
    if (current === undefined) {
      byID.set(override.id, {
        id: override.id,
        source: override.source,
        target: override.target,
        disclosureLevel: clampDisclosureLevel(override.disclosureLevel),
        edgeType: readOptionalString(override.edgeType),
        label: readOptionalString(override.label),
      });
      continue;
    }
    byID.set(override.id, {
      ...current,
      disclosureLevel: clampDisclosureLevel(override.disclosureLevel),
      edgeType: readOptionalString(override.edgeType) ?? current.edgeType,
      label: readOptionalString(override.label) ?? current.label,
    });
  }

  return [...byID.values()].sort((left, right) => left.id.localeCompare(right.id));
}

function applyOverridesToMappings(
  mappings: CurationDisclosureMappingRow[],
  overrides: CurationDisclosureMappingRow[] | undefined,
): CurationDisclosureMappingRow[] {
  if (overrides === undefined || overrides.length === 0) {
    return mappings;
  }

  const keyFor = (row: CurationDisclosureMappingRow): string => {
    return `${row.sourceId}|${row.targetId}|${row.sourceLevel}|${row.targetLevel}`;
  };

  const dedupedByKey = new Map(mappings.map((mapping) => [keyFor(mapping), mapping]));
  for (const override of overrides) {
    const normalized: CurationDisclosureMappingRow = {
      sourceId: override.sourceId,
      targetId: override.targetId,
      sourceLevel: clampDisclosureLevel(override.sourceLevel),
      targetLevel: clampDisclosureLevel(override.targetLevel),
    };
    dedupedByKey.set(keyFor(normalized), normalized);
  }

  return [...dedupedByKey.values()].sort((left, right) => {
    if (left.sourceId !== right.sourceId) {
      return left.sourceId.localeCompare(right.sourceId);
    }
    if (left.targetId !== right.targetId) {
      return left.targetId.localeCompare(right.targetId);
    }
    if (left.sourceLevel !== right.sourceLevel) {
      return left.sourceLevel - right.sourceLevel;
    }
    return left.targetLevel - right.targetLevel;
  });
}

function applyOverridesToInterventionMappings(
  mappings: InterventionMapping[],
  overrides: InterventionMapping[] | undefined,
): InterventionMapping[] {
  if (overrides === undefined || overrides.length === 0) {
    return mappings;
  }

  const byID = new Map(mappings.map((mapping) => [mapping.interventionId, mapping]));
  for (const override of overrides) {
    byID.set(override.interventionId, {
      interventionId: override.interventionId,
      pillars: readStringArray(override.pillars),
      maxDetailNodeIds: readStringArray(override.maxDetailNodeIds),
      maxDetailEdgeIds: readStringArray(override.maxDetailEdgeIds),
    });
  }

  return [...byID.values()].sort((left, right) => left.interventionId.localeCompare(right.interventionId));
}

function run(): void {
  const args = parseArgs();
  const graph = loadGraphFromPath(args.graphPath);
  if (graph.nodes.length === 0 || graph.edges.length === 0) {
    throw new Error(`Graph is empty at ${args.graphPath}`);
  }

  const nodeRows = graph.nodes
    .map((nodeElement) => nodeElement.data)
    .filter((node): node is GraphNodeData => typeof node.id === 'string' && node.id.trim().length > 0)
    .sort((left, right) => left.id.localeCompare(right.id));

  const nodeLevelByID = new Map<string, number>();
  const generatedNodes: CurationNodeRow[] = nodeRows.map((node) => {
    const level = resolvedNodeDisclosureLevel(node);
    nodeLevelByID.set(node.id, level);
    return {
      id: node.id,
      disclosureLevel: level,
      pillarIds: readStringArray(node.pillarIds),
    };
  });

  const generatedEdges = resolvedEdgeRows(graph).map((edge) => ({
    ...edge,
    disclosureLevel: resolvedEdgeDisclosureLevel(
      {
        source: edge.source,
        target: edge.target,
        edgeType: edge.edgeType ?? undefined,
        label: edge.label ?? undefined,
      },
      nodeLevelByID,
    ),
  }));

  const generatedMappings = buildDisclosureMappings(graph, nodeLevelByID);
  const generatedInterventionMappings = parseInterventionMappings(args.interventionsPath, generatedEdges);
  const overrides = loadOverrides(args.overridesPath);
  const curatedNodes = applyOverridesToNodes(generatedNodes, overrides.nodes);
  const curatedEdges = applyOverridesToEdges(generatedEdges, overrides.edges);
  const mappings = applyOverridesToMappings(generatedMappings, overrides.disclosureMappings);
  const interventionMappings = applyOverridesToInterventionMappings(
    generatedInterventionMappings,
    overrides.interventionMappings
  );
  const pillars = parsePlanningPillars(args.planningPolicyPath);
  const connectivity = buildPillarConnectivity(pillars, curatedNodes, curatedEdges, interventionMappings);

  const output: CurationOutput = {
    version: 'disclosure-curation.v1.seed',
    generatedAt: new Date().toISOString(),
    sourceGraphPath: path.relative(process.cwd(), args.graphPath),
    sourceInterventionsPath: path.relative(process.cwd(), args.interventionsPath),
    sourcePlanningPolicyPath: path.relative(process.cwd(), args.planningPolicyPath),
    nodes: curatedNodes,
    edges: curatedEdges,
    disclosureMappings: mappings,
    interventionMappings,
    pillarConnectivity: connectivity,
  };

  writeFileSync(args.outPath, JSON.stringify(output, null, args.pretty ? 2 : 0), 'utf8');

  const disconnectedSummary = connectivity
    .map((row) => `${row.pillarId}:${row.disconnectedNodeIds.length}`)
    .join(', ');
  console.log(`Wrote disclosure curation seed: ${args.outPath}`);
  console.log(`Pillar disconnected-node counts: ${disconnectedSummary}`);
}

try {
  run();
} catch (error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
}
