import { isUnknownRecord } from './pillar-integrity-lib';

export interface GraphNodeAuditRow {
  node_id: string;
  label: string;
  style_class: string;
  tier: number | null;
  is_deactivated: boolean;
  parent_ids: string[];
  source_ref: string;
}

export interface GraphEdgeAuditRow {
  edge_id: string;
  source_node_id: string;
  target_node_id: string;
  edge_type: string;
  edge_color: string;
  label: string;
  is_deactivated: boolean;
  source_ref: string;
}

export interface HabitLinkAuditRow {
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

export interface OutcomeQuestionLinkAuditRow {
  question_id: string;
  title: string;
  source_node_ids: string[];
  source_edge_ids: string[];
  missing_node_ids: string[];
  missing_edge_ids: string[];
  link_status: 'linked' | 'missing_sources';
  source_ref: string;
}

export interface UserGraphAuditReportSubset {
  audit_version: string;
  generated_at: string;
  input: {
    user_id: string;
  };
  details: {
    graph_nodes: GraphNodeAuditRow[];
    graph_edges: GraphEdgeAuditRow[];
    habit_links: HabitLinkAuditRow[];
    outcome_question_links: OutcomeQuestionLinkAuditRow[];
  };
}

export interface PillarScopedAuditReport {
  audit_version: 'user-pillar-audit.v1';
  generated_at: string;
  input: {
    user_id: string;
    pillar_id: string;
    source_audit_version: string;
    source_generated_at: string;
  };
  summary: {
    graph_node_count: number;
    graph_edge_count: number;
    habits_total: number;
    habits_linked_count: number;
    habits_unlinked_count: number;
    habits_missing_edge_links_count: number;
    outcome_questions_total: number;
    outcome_questions_linked_count: number;
    outcome_questions_unlinked_count: number;
    missing_source_node_count: number;
    missing_source_edge_count: number;
  };
  details: {
    graph_nodes: GraphNodeAuditRow[];
    graph_edges: GraphEdgeAuditRow[];
    habit_links: HabitLinkAuditRow[];
    outcome_question_links: OutcomeQuestionLinkAuditRow[];
  };
}

export interface RenderableGraphData {
  nodes: Array<{
    data: {
      id: string;
      label: string;
      styleClass: string;
      tier?: number;
      isDeactivated: boolean;
      parentIds?: string[];
    };
  }>;
  edges: Array<{
    data: {
      id: string;
      source: string;
      target: string;
      edgeType: string;
      edgeColor?: string;
      label: string;
      isDeactivated: boolean;
    };
  }>;
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

function parseGraphNodeRow(value: unknown): GraphNodeAuditRow | null {
  if (!isUnknownRecord(value)) {
    return null;
  }

  const nodeID = readOptionalString(value.node_id);
  const label = readOptionalString(value.label);
  const styleClass = readOptionalString(value.style_class);
  const sourceRef = readOptionalString(value.source_ref);
  if (nodeID === null || label === null || styleClass === null || sourceRef === null) {
    return null;
  }
  const tier = typeof value.tier === 'number' && Number.isFinite(value.tier) ? value.tier : null;

  return {
    node_id: nodeID,
    label,
    style_class: styleClass,
    tier,
    is_deactivated: value.is_deactivated === true,
    parent_ids: readStringArray(value.parent_ids),
    source_ref: sourceRef,
  };
}

function parseGraphEdgeRow(value: unknown): GraphEdgeAuditRow | null {
  if (!isUnknownRecord(value)) {
    return null;
  }

  const edgeID = readOptionalString(value.edge_id);
  const sourceNodeID = readOptionalString(value.source_node_id);
  const targetNodeID = readOptionalString(value.target_node_id);
  const edgeType = readOptionalString(value.edge_type);
  const edgeColor = readOptionalString(value.edge_color);
  const label = readOptionalString(value.label);
  const sourceRef = readOptionalString(value.source_ref);
  if (
    edgeID === null
    || sourceNodeID === null
    || targetNodeID === null
    || edgeType === null
    || label === null
    || sourceRef === null
  ) {
    return null;
  }

  return {
    edge_id: edgeID,
    source_node_id: sourceNodeID,
    target_node_id: targetNodeID,
    edge_type: edgeType,
    edge_color: edgeColor ?? '',
    label,
    is_deactivated: value.is_deactivated === true,
    source_ref: sourceRef,
  };
}

function parseHabitLinkRow(value: unknown): HabitLinkAuditRow | null {
  if (!isUnknownRecord(value)) {
    return null;
  }

  const interventionID = readOptionalString(value.intervention_id);
  const name = readOptionalString(value.name);
  const sourceRef = readOptionalString(value.source_ref);
  if (interventionID === null || name === null || sourceRef === null) {
    return null;
  }

  const graphNodeIDRaw = value.graph_node_id;
  const graphNodeID = graphNodeIDRaw === null ? null : readOptionalString(graphNodeIDRaw);
  if (graphNodeIDRaw !== null && graphNodeID === null) {
    return null;
  }

  return {
    intervention_id: interventionID,
    name,
    graph_node_id: graphNodeID,
    graph_edge_ids: readStringArray(value.graph_edge_ids),
    is_active: value.is_active === true,
    is_hidden: value.is_hidden === true,
    pillars: readStringArray(value.pillars),
    planning_tags: readStringArray(value.planning_tags),
    source_node_exists: value.source_node_exists === true,
    source_edges_exist: value.source_edges_exist === true,
    missing_graph_edge_ids: readStringArray(value.missing_graph_edge_ids),
    outgoing_edge_ids: readStringArray(value.outgoing_edge_ids),
    target_node_ids: readStringArray(value.target_node_ids),
    missing_reasons: readStringArray(value.missing_reasons),
    source_ref: sourceRef,
  };
}

function parseOutcomeQuestionLinkRow(value: unknown): OutcomeQuestionLinkAuditRow | null {
  if (!isUnknownRecord(value)) {
    return null;
  }

  const questionID = readOptionalString(value.question_id);
  const title = readOptionalString(value.title);
  const sourceRef = readOptionalString(value.source_ref);
  if (questionID === null || title === null || sourceRef === null) {
    return null;
  }

  const linkStatus = readOptionalString(value.link_status);
  if (linkStatus !== 'linked' && linkStatus !== 'missing_sources') {
    return null;
  }

  return {
    question_id: questionID,
    title,
    source_node_ids: readStringArray(value.source_node_ids),
    source_edge_ids: readStringArray(value.source_edge_ids),
    missing_node_ids: readStringArray(value.missing_node_ids),
    missing_edge_ids: readStringArray(value.missing_edge_ids),
    link_status: linkStatus,
    source_ref: sourceRef,
  };
}

function parseRows<T>(
  value: unknown,
  parser: (entry: unknown) => T | null,
): T[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const rows: T[] = [];
  for (const entry of value) {
    const parsed = parser(entry);
    if (parsed !== null) {
      rows.push(parsed);
    }
  }
  return rows;
}

function intersects(values: string[], candidates: Set<string>): boolean {
  for (const value of values) {
    if (candidates.has(value)) {
      return true;
    }
  }
  return false;
}

function uniqueByID<T>(rows: T[], readID: (row: T) => string): T[] {
  const byID = new Map<string, T>();
  for (const row of rows) {
    byID.set(readID(row), row);
  }
  return [...byID.values()].sort((left, right) => readID(left).localeCompare(readID(right)));
}

export function parseUserGraphAuditReportSubset(value: unknown): UserGraphAuditReportSubset {
  if (!isUnknownRecord(value)) {
    throw new Error('Audit payload must be an object.');
  }

  const auditVersion = readOptionalString(value.audit_version);
  const generatedAt = readOptionalString(value.generated_at);
  if (auditVersion === null || generatedAt === null) {
    throw new Error('Audit payload missing audit_version or generated_at.');
  }

  const input = isUnknownRecord(value.input) ? value.input : null;
  const userID = input === null ? null : readOptionalString(input.user_id);
  if (userID === null) {
    throw new Error('Audit payload missing input.user_id.');
  }

  const details = isUnknownRecord(value.details) ? value.details : null;
  if (details === null) {
    throw new Error('Audit payload missing details object.');
  }

  return {
    audit_version: auditVersion,
    generated_at: generatedAt,
    input: {
      user_id: userID,
    },
    details: {
      graph_nodes: parseRows(details.graph_nodes, parseGraphNodeRow),
      graph_edges: parseRows(details.graph_edges, parseGraphEdgeRow),
      habit_links: parseRows(details.habit_links, parseHabitLinkRow),
      outcome_question_links: parseRows(details.outcome_question_links, parseOutcomeQuestionLinkRow),
    },
  };
}

export function collectPillarIDs(report: UserGraphAuditReportSubset): string[] {
  const pillarIDs = new Set<string>();

  for (const habit of report.details.habit_links) {
    for (const pillarID of habit.pillars) {
      pillarIDs.add(pillarID);
    }
  }

  for (const question of report.details.outcome_question_links) {
    if (!question.question_id.startsWith('pillar.')) {
      continue;
    }
    const pillarID = question.question_id.slice('pillar.'.length).trim();
    if (pillarID.length > 0) {
      pillarIDs.add(pillarID);
    }
  }

  return [...pillarIDs].sort((left, right) => left.localeCompare(right));
}

export function filterAuditToPillar(
  report: UserGraphAuditReportSubset,
  pillarID: string,
): PillarScopedAuditReport {
  const normalizedPillarID = pillarID.trim();
  if (normalizedPillarID.length === 0) {
    throw new Error('Pillar ID cannot be empty.');
  }

  const ownedNodeIDs = new Set<string>();
  const ownedEdgeIDs = new Set<string>();

  const primaryHabitLinks = report.details.habit_links.filter((habit) => habit.pillars.includes(normalizedPillarID));
  for (const habit of primaryHabitLinks) {
    if (habit.graph_node_id !== null) {
      ownedNodeIDs.add(habit.graph_node_id);
    }
    for (const nodeID of habit.target_node_ids) {
      ownedNodeIDs.add(nodeID);
    }
    for (const edgeID of habit.graph_edge_ids) {
      ownedEdgeIDs.add(edgeID);
    }
    for (const edgeID of habit.outgoing_edge_ids) {
      ownedEdgeIDs.add(edgeID);
    }
  }

  const graphEdges = report.details.graph_edges.filter((edge) => {
    if (ownedEdgeIDs.has(edge.edge_id)) {
      return true;
    }
    return ownedNodeIDs.has(edge.source_node_id) && ownedNodeIDs.has(edge.target_node_id);
  });
  for (const edge of graphEdges) {
    ownedEdgeIDs.add(edge.edge_id);
    ownedNodeIDs.add(edge.source_node_id);
    ownedNodeIDs.add(edge.target_node_id);
  }

  const graphNodes = report.details.graph_nodes.filter((node) => ownedNodeIDs.has(node.node_id));

  const expandedHabitLinks = report.details.habit_links.filter((habit) => {
    if (habit.pillars.includes(normalizedPillarID)) {
      return true;
    }
    if (habit.pillars.length > 0) {
      return false;
    }
    if (habit.graph_node_id !== null && ownedNodeIDs.has(habit.graph_node_id)) {
      return true;
    }
    return intersects(habit.graph_edge_ids, ownedEdgeIDs);
  });

  const habitLinks = uniqueByID(expandedHabitLinks, (habit) => habit.intervention_id);
  const questionLinks = uniqueByID(
    report.details.outcome_question_links.filter((question) => question.question_id === `pillar.${normalizedPillarID}`),
    (question) => question.question_id,
  );
  const filteredEdges = uniqueByID(graphEdges, (edge) => edge.edge_id);
  const filteredNodes = uniqueByID(graphNodes, (node) => node.node_id);

  const habitsLinkedCount = habitLinks.filter((habit) => habit.source_node_exists).length;
  const habitsMissingEdgeLinksCount = habitLinks.filter((habit) => habit.missing_graph_edge_ids.length > 0).length;
  const outcomeQuestionsLinkedCount = questionLinks.filter((question) => question.link_status === 'linked').length;
  const missingHabitSourceNodeCount = habitLinks.filter((habit) => habit.source_node_exists === false).length;
  const missingHabitSourceEdgeCount = habitLinks.reduce(
    (total, habit) => total + habit.missing_graph_edge_ids.length,
    0,
  );
  const missingQuestionNodeCount = questionLinks.reduce(
    (total, question) => total + question.missing_node_ids.length,
    0,
  );
  const missingQuestionEdgeCount = questionLinks.reduce(
    (total, question) => total + question.missing_edge_ids.length,
    0,
  );

  return {
    audit_version: 'user-pillar-audit.v1',
    generated_at: new Date().toISOString(),
    input: {
      user_id: report.input.user_id,
      pillar_id: normalizedPillarID,
      source_audit_version: report.audit_version,
      source_generated_at: report.generated_at,
    },
    summary: {
      graph_node_count: filteredNodes.length,
      graph_edge_count: filteredEdges.length,
      habits_total: habitLinks.length,
      habits_linked_count: habitsLinkedCount,
      habits_unlinked_count: habitLinks.length - habitsLinkedCount,
      habits_missing_edge_links_count: habitsMissingEdgeLinksCount,
      outcome_questions_total: questionLinks.length,
      outcome_questions_linked_count: outcomeQuestionsLinkedCount,
      outcome_questions_unlinked_count: questionLinks.length - outcomeQuestionsLinkedCount,
      missing_source_node_count: missingHabitSourceNodeCount + missingQuestionNodeCount,
      missing_source_edge_count: missingHabitSourceEdgeCount + missingQuestionEdgeCount,
    },
    details: {
      graph_nodes: filteredNodes,
      graph_edges: filteredEdges,
      habit_links: habitLinks,
      outcome_question_links: questionLinks,
    },
  };
}

export function toRenderableGraphData(report: PillarScopedAuditReport): RenderableGraphData {
  const nodes = report.details.graph_nodes.map((node) => {
    if (node.parent_ids.length > 0) {
      if (node.tier !== null) {
        return {
          data: {
            id: node.node_id,
            label: node.label,
            styleClass: node.style_class,
            tier: node.tier,
            isDeactivated: node.is_deactivated,
            parentIds: node.parent_ids,
          },
        };
      }
      return {
        data: {
          id: node.node_id,
          label: node.label,
          styleClass: node.style_class,
          isDeactivated: node.is_deactivated,
          parentIds: node.parent_ids,
        },
      };
    }

    return {
      data: {
        id: node.node_id,
        label: node.label,
        styleClass: node.style_class,
        ...(node.tier === null ? {} : { tier: node.tier }),
        isDeactivated: node.is_deactivated,
      },
    };
  });

  const edges = report.details.graph_edges.map((edge) => {
    if (edge.edge_color.length > 0) {
      return {
        data: {
          id: edge.edge_id,
          source: edge.source_node_id,
          target: edge.target_node_id,
          edgeType: edge.edge_type,
          edgeColor: edge.edge_color,
          label: edge.label,
          isDeactivated: edge.is_deactivated,
        },
      };
    }
    return {
      data: {
        id: edge.edge_id,
        source: edge.source_node_id,
        target: edge.target_node_id,
        edgeType: edge.edge_type,
        label: edge.label,
        isDeactivated: edge.is_deactivated,
      },
    };
  });

  return { nodes, edges };
}
