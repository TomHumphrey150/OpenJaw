import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { test } from 'node:test';

const require = createRequire(import.meta.url);
require('ts-node/register');

const {
  buildAuditReport,
  resolveCanonicalGraphFromSources,
} = require('../scripts/debug-user-graph-audit.ts');

function buildProvenance() {
  const refs = {
    ref_user_data_row: {
      table_or_file: 'public.user_data',
      selector: { user_id: 'test-user' },
      updated_at: '2026-02-28T00:00:00Z',
      version: null,
      fallback_used: false,
      path_hint: 'data',
    },
    ref_user_graph_nodes: {
      table_or_file: 'public.user_data',
      selector: { user_id: 'test-user' },
      updated_at: '2026-02-28T00:00:00Z',
      version: null,
      fallback_used: false,
      path_hint: 'data.customCausalDiagram.graphData.nodes',
    },
    ref_user_graph_edges: {
      table_or_file: 'public.user_data',
      selector: { user_id: 'test-user' },
      updated_at: '2026-02-28T00:00:00Z',
      version: null,
      fallback_used: false,
      path_hint: 'data.customCausalDiagram.graphData.edges',
    },
    ref_interventions_catalog: {
      table_or_file: 'public.first_party_content',
      selector: { content_type: 'inputs', content_key: 'interventions_catalog' },
      updated_at: '2026-02-28T00:00:00Z',
      version: 1,
      fallback_used: true,
      path_hint: 'data.interventions',
    },
    ref_outcomes_metadata: {
      table_or_file: 'public.first_party_content',
      selector: { content_type: 'outcomes', content_key: 'outcomes_metadata' },
      updated_at: '2026-02-28T00:00:00Z',
      version: 1,
      fallback_used: true,
      path_hint: 'data.nodes',
    },
    ref_progress_question_links: {
      table_or_file: 'public.user_data',
      selector: { user_id: 'test-user' },
      updated_at: '2026-02-28T00:00:00Z',
      version: null,
      fallback_used: false,
      path_hint: 'data.progressQuestionSetState.pendingProposal.questions',
    },
    ref_canonical_graph: {
      table_or_file: 'public.first_party_content',
      selector: { content_type: 'graph', content_key: 'canonical_causal_graph' },
      updated_at: '2026-02-28T00:00:00Z',
      version: 1,
      fallback_used: false,
      path_hint: 'data.nodes,data.edges',
    },
    ref_planning_policy: {
      table_or_file: 'public.first_party_content',
      selector: { content_type: 'planning', content_key: 'planner_policy_v1' },
      updated_at: '2026-02-28T00:00:00Z',
      version: 1,
      fallback_used: true,
      path_hint: 'data.pillars',
    },
  };

  return {
    refs,
    sections: {
      summary: Object.keys(refs),
      details: {
        graph_nodes: ['ref_user_graph_nodes'],
        graph_edges: ['ref_user_graph_edges'],
        habit_links: ['ref_interventions_catalog', 'ref_user_graph_nodes', 'ref_user_graph_edges'],
        outcome_question_links: ['ref_progress_question_links', 'ref_user_graph_nodes', 'ref_user_graph_edges'],
        canonical_baseline: ['ref_canonical_graph', 'ref_user_graph_nodes', 'ref_user_graph_edges'],
      },
      validation: ['ref_user_graph_nodes', 'ref_user_graph_edges'],
    },
  };
}

function buildBaseInput() {
  return {
    userID: 'test-user',
    userDataUpdatedAt: '2026-02-28T00:00:00Z',
    userStore: {
      activeInterventions: ['habit_social'],
      hiddenInterventions: ['habit_missing'],
      progressQuestionSetState: {
        pendingProposal: {
          questions: [
            {
              id: 'q_stress',
              title: 'Stress trend',
              sourceNodeIDs: ['STRESS'],
              sourceEdgeIDs: ['edge:SOCIAL_TX|STRESS|forward|#0'],
            },
          ],
        },
      },
    },
    userGraphRaw: {
      nodes: [
        {
          data: {
            id: 'SOCIAL_TX',
            label: 'Social Check-In',
            styleClass: 'intervention',
            tooltip: { evidence: 'x' },
          },
        },
        {
          data: {
            id: 'STRESS',
            label: 'Stress',
            styleClass: 'moderate',
          },
        },
      ],
      edges: [
        {
          data: {
            source: 'SOCIAL_TX',
            target: 'STRESS',
            edgeType: 'forward',
            label: '',
            tooltip: 'not exported',
          },
        },
      ],
    },
    canonicalGraphRaw: {
      nodes: [
        { data: { id: 'SOCIAL_TX', label: 'Social Check-In', styleClass: 'intervention' } },
        { data: { id: 'STRESS', label: 'Stress', styleClass: 'moderate' } },
        { data: { id: 'SLEEP_DEP', label: 'Sleep Debt', styleClass: 'moderate' } },
      ],
      edges: [
        { data: { source: 'SOCIAL_TX', target: 'STRESS', edgeType: 'forward', label: '' } },
        { data: { source: 'STRESS', target: 'SLEEP_DEP', edgeType: 'forward', label: 'hyperarousal' } },
      ],
    },
    interventionsCatalogData: {
      interventions: [
        {
          id: 'habit_social',
          name: 'Social Habit',
          graphNodeId: 'SOCIAL_TX',
          pillars: ['socialLife'],
          planningTags: ['foundation'],
        },
        {
          id: 'habit_missing',
          name: 'Missing Habit',
          graphNodeId: 'DOES_NOT_EXIST',
          pillars: ['socialLife'],
          planningTags: ['acute'],
        },
      ],
    },
    outcomesMetadataData: {
      metrics: [],
      nodes: [],
      updatedAt: '2026-02-28T00:00:00Z',
    },
    planningPolicyData: {
      pillars: [
        { id: 'socialLife', title: 'Social Life', rank: 1 },
      ],
    },
    provenance: buildProvenance(),
  };
}

test('buildAuditReport returns required top-level and detail shape', () => {
  const report = buildAuditReport(buildBaseInput());

  assert.equal(report.audit_version, 'user-graph-audit.v1');
  assert.equal(report.input.user_id, 'test-user');
  assert.ok(report.generated_at);

  assert.ok(report.summary);
  assert.ok(report.details);
  assert.ok(report.provenance);
  assert.ok(report.validation);

  assert.equal(Array.isArray(report.details.graph_nodes), true);
  assert.equal(Array.isArray(report.details.graph_edges), true);
  assert.equal(Array.isArray(report.details.habit_links), true);
  assert.equal(Array.isArray(report.details.outcome_question_links), true);
  assert.equal(typeof report.details.canonical_baseline, 'object');
});

test('every detail row source_ref resolves to provenance.refs token', () => {
  const report = buildAuditReport(buildBaseInput());
  const refs = report.provenance.refs;

  for (const row of report.details.graph_nodes) {
    assert.ok(refs[row.source_ref]);
  }

  for (const row of report.details.graph_edges) {
    assert.ok(refs[row.source_ref]);
  }

  for (const row of report.details.habit_links) {
    assert.ok(refs[row.source_ref]);
  }

  for (const row of report.details.outcome_question_links) {
    assert.ok(refs[row.source_ref]);
  }

  assert.ok(refs[report.details.canonical_baseline.source_ref]);
});

test('malformed graph input fails strict validation semantics', () => {
  const input = buildBaseInput();
  input.userGraphRaw = {
    nodes: [{ data: { label: 'Missing id' } }],
    edges: [{ data: { source: 'A' } }],
  };

  const report = buildAuditReport(input);

  assert.equal(report.validation.status, 'fail');
  const codes = report.validation.violations.map((violation) => violation.code);
  assert.ok(codes.includes('GRAPH_NODE_MISSING_ID'));
  assert.ok(codes.includes('GRAPH_EDGE_MISSING_ENDPOINT'));
});

test('habit links report missing graph source node without crashing', () => {
  const report = buildAuditReport(buildBaseInput());
  const missingHabit = report.details.habit_links.find((row) => row.intervention_id === 'habit_missing');

  assert.ok(missingHabit);
  assert.equal(missingHabit.source_node_exists, false);
  assert.ok(missingHabit.missing_reasons.includes('source_node_not_in_user_graph'));
});

test('outcome question links use pending proposal and report missing edge IDs', () => {
  const input = buildBaseInput();
  input.userStore.progressQuestionSetState.pendingProposal.questions[0].sourceEdgeIDs = ['edge:does-not-exist#0'];
  const report = buildAuditReport(input);

  assert.equal(report.details.outcome_question_links.length, 1);
  const row = report.details.outcome_question_links[0];
  assert.equal(row.question_id, 'q_stress');
  assert.deepEqual(row.missing_node_ids, []);
  assert.equal(row.link_status, 'missing_sources');
  assert.equal(row.missing_edge_ids.length, 1);
});

test('missing progress question proposal emits explicit summary reason', () => {
  const input = buildBaseInput();
  input.userStore = {
    activeInterventions: ['habit_social'],
    hiddenInterventions: [],
  };

  const report = buildAuditReport(input);

  assert.equal(report.details.outcome_question_links.length, 0);
  assert.ok(report.summary.outcome_questions_reason);
  assert.equal(report.validation.status, 'pass');
});

test('canonical fallback uses local file when first-party row is missing', async () => {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'graph-audit-fallback-'));
  const graphPath = path.join(tempRoot, 'default-graph.json');
  await fs.writeFile(
    graphPath,
    JSON.stringify({
      nodes: [{ data: { id: 'N1', label: 'Node 1' } }],
      edges: [{ data: { source: 'N1', target: 'N1', edgeType: 'forward', label: '' } }],
    }),
    'utf8',
  );

  try {
    const resolved = resolveCanonicalGraphFromSources({
      firstPartyGraphData: null,
      firstPartyUpdatedAt: null,
      firstPartyVersion: null,
      fallbackLocalPath: graphPath,
    });

    assert.equal(resolved.source, 'local_file');
    assert.equal(resolved.fallbackUsed, true);

    const graph = resolved.graphRaw;
    assert.equal(Array.isArray(graph.nodes), true);
    assert.equal(Array.isArray(graph.edges), true);
  } finally {
    await fs.rm(tempRoot, { recursive: true, force: true });
  }
});

test('details remain compact and do not duplicate raw tooltip payloads', () => {
  const report = buildAuditReport(buildBaseInput());

  assert.equal('tooltip' in report.details.graph_nodes[0], false);
  assert.equal('tooltip' in report.details.graph_edges[0], false);

  const serialized = JSON.stringify(report);
  assert.equal(serialized.includes('"tooltip"'), false);
});
