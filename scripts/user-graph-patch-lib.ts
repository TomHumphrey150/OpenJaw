import {
  edgeSignature,
  GraphData,
  GraphEdgeElement,
  GraphNodeElement,
} from './pillar-integrity-lib';

export const AUTHORIZED_USER_ID = '58a2c2cf-d04f-42d6-b7ff-5a44ba47ac14';

interface RequiredEdgeRule {
  source: string;
  target: string;
  edgeType: string;
  label: string;
}

const REQUIRED_NODE_IDS: readonly string[] = [
  'SOCIAL_ISOLATION',
  'RELATIONSHIP_STRAIN',
  'FINANCIAL_STRAIN',
  'SOCIAL_TX',
  'RELATIONSHIP_TX',
  'FINANCIAL_TX',
];

const REQUIRED_EDGE_RULES: RequiredEdgeRule[] = [
  { source: 'SOCIAL_ISOLATION', target: 'STRESS', edgeType: 'feedback', label: '' },
  { source: 'RELATIONSHIP_STRAIN', target: 'STRESS', edgeType: 'feedback', label: '' },
  { source: 'FINANCIAL_STRAIN', target: 'STRESS', edgeType: 'feedback', label: '' },
  { source: 'FINANCIAL_STRAIN', target: 'SLEEP_DEP', edgeType: 'feedback', label: '' },
  { source: 'SOCIAL_TX', target: 'SOCIAL_ISOLATION', edgeType: 'forward', label: '' },
  { source: 'RELATIONSHIP_TX', target: 'RELATIONSHIP_STRAIN', edgeType: 'forward', label: '' },
  { source: 'FINANCIAL_TX', target: 'FINANCIAL_STRAIN', edgeType: 'forward', label: '' },
];

export interface GraphMergeResult {
  nextGraph: GraphData;
  addedNodeIDs: string[];
  addedEdgeSignatures: string[];
  requiredNodeIDs: string[];
  requiredEdgeSignatures: string[];
  missingCanonicalNodeIDs: string[];
  missingCanonicalEdgeRules: string[];
  changed: boolean;
}

function normalize(value: string): string {
  return value.trim().toLowerCase();
}

function normalizeOptional(value: string | undefined): string {
  if (value === undefined) {
    return '';
  }

  return normalize(value);
}

function ruleSignature(rule: RequiredEdgeRule): string {
  return [
    rule.source,
    rule.target,
    normalize(rule.edgeType),
    normalize(rule.label),
  ].join('|');
}

function edgeMatchesRule(edge: GraphEdgeElement, rule: RequiredEdgeRule): boolean {
  return (
    edge.data.source === rule.source
    && edge.data.target === rule.target
    && normalizeOptional(edge.data.edgeType) === normalize(rule.edgeType)
    && normalizeOptional(edge.data.label) === normalize(rule.label)
  );
}

function cloneNodes(nodes: GraphNodeElement[]): GraphNodeElement[] {
  return nodes.map((node) => structuredClone(node));
}

function cloneEdges(edges: GraphEdgeElement[]): GraphEdgeElement[] {
  return edges.map((edge) => structuredClone(edge));
}

export function mergeUserGraphWithCanonicalTargets(userGraph: GraphData, canonicalGraph: GraphData): GraphMergeResult {
  const canonicalNodesByID = new Map<string, GraphNodeElement>();
  for (const node of canonicalGraph.nodes) {
    canonicalNodesByID.set(node.data.id, node);
  }

  const requiredNodes: GraphNodeElement[] = [];
  const missingCanonicalNodeIDs: string[] = [];
  for (const nodeID of REQUIRED_NODE_IDS) {
    const matched = canonicalNodesByID.get(nodeID);
    if (matched === undefined) {
      missingCanonicalNodeIDs.push(nodeID);
      continue;
    }
    requiredNodes.push(matched);
  }

  const requiredEdges: GraphEdgeElement[] = [];
  const missingCanonicalEdgeRules: string[] = [];
  for (const rule of REQUIRED_EDGE_RULES) {
    const matched = canonicalGraph.edges.find((edge) => edgeMatchesRule(edge, rule));
    if (matched === undefined) {
      missingCanonicalEdgeRules.push(ruleSignature(rule));
      continue;
    }
    requiredEdges.push(matched);
  }

  const requiredNodeIDs = requiredNodes
    .map((node) => node.data.id)
    .sort((left, right) => left.localeCompare(right));

  const requiredEdgeSignatures = requiredEdges
    .map((edge) => edgeSignature(edge.data))
    .sort((left, right) => left.localeCompare(right));

  const nextNodes = cloneNodes(userGraph.nodes);
  const nextEdges = cloneEdges(userGraph.edges);

  const existingNodeIDs = new Set(nextNodes.map((node) => node.data.id));
  const existingEdgeSignatures = new Set(nextEdges.map((edge) => edgeSignature(edge.data)));

  const addedNodes: GraphNodeElement[] = [];
  for (const node of requiredNodes) {
    if (existingNodeIDs.has(node.data.id)) {
      continue;
    }

    const clonedNode = structuredClone(node);
    nextNodes.push(clonedNode);
    addedNodes.push(clonedNode);
    existingNodeIDs.add(node.data.id);
  }

  const addedEdges: GraphEdgeElement[] = [];
  for (const edge of requiredEdges) {
    const signature = edgeSignature(edge.data);
    if (existingEdgeSignatures.has(signature)) {
      continue;
    }

    const clonedEdge = structuredClone(edge);
    nextEdges.push(clonedEdge);
    addedEdges.push(clonedEdge);
    existingEdgeSignatures.add(signature);
  }

  const addedNodeIDs = addedNodes
    .map((node) => node.data.id)
    .sort((left, right) => left.localeCompare(right));

  const addedEdgeSignatures = addedEdges
    .map((edge) => edgeSignature(edge.data))
    .sort((left, right) => left.localeCompare(right));

  return {
    nextGraph: {
      nodes: nextNodes,
      edges: nextEdges,
    },
    addedNodeIDs,
    addedEdgeSignatures,
    requiredNodeIDs,
    requiredEdgeSignatures,
    missingCanonicalNodeIDs: missingCanonicalNodeIDs.sort((left, right) => left.localeCompare(right)),
    missingCanonicalEdgeRules: missingCanonicalEdgeRules.sort((left, right) => left.localeCompare(right)),
    changed: addedNodeIDs.length > 0 || addedEdgeSignatures.length > 0,
  };
}
