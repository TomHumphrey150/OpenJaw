import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { test } from 'node:test';

const require = createRequire(import.meta.url);
require('ts-node/register');

const {
  buildPillarIntegrityReport,
  edgeSignature,
  parseGraphData,
} = require('../scripts/pillar-integrity-lib.ts');

function makeGraph(nodes, edges) {
  return parseGraphData({
    nodes: nodes.map((id) => ({ data: { id, label: id } })),
    edges: edges.map((edge) => ({ data: edge })),
  });
}

test('buildPillarIntegrityReport computes intervention and active coverage by pillar', () => {
  const canonicalGraph = makeGraph(
    ['SOCIAL_TX', 'SOCIAL_ISOLATION', 'RELATIONSHIP_TX', 'RELATIONSHIP_STRAIN', 'MINDFULNESS_TX', 'STRESS'],
    [
      { source: 'SOCIAL_TX', target: 'SOCIAL_ISOLATION', edgeType: 'forward' },
      { source: 'RELATIONSHIP_TX', target: 'RELATIONSHIP_STRAIN', edgeType: 'forward' },
      { source: 'MINDFULNESS_TX', target: 'STRESS', edgeType: 'forward' },
    ],
  );

  const userGraph = makeGraph(
    ['SOCIAL_TX', 'SOCIAL_ISOLATION', 'MINDFULNESS_TX', 'STRESS'],
    [
      { source: 'SOCIAL_TX', target: 'SOCIAL_ISOLATION', edgeType: 'forward' },
      { source: 'MINDFULNESS_TX', target: 'STRESS', edgeType: 'forward' },
    ],
  );

  const report = buildPillarIntegrityReport({
    userID: 'test-user',
    interventions: [
      { id: 'social_connection', graphNodeID: 'SOCIAL_TX', pillars: ['socialLife'], planningTags: ['foundation'] },
      { id: 'relationship_care', graphNodeID: 'RELATIONSHIP_TX', pillars: ['socialLife'], planningTags: ['foundation'] },
      { id: 'mindfulness_minutes', graphNodeID: 'MINDFULNESS_TX', pillars: ['stressManagement'], planningTags: ['foundation'] },
    ],
    activeInterventionIDs: ['social_connection', 'mindfulness_minutes'],
    userGraph,
    canonicalGraph,
    policyPillars: [
      { id: 'socialLife', title: 'Social Life', rank: 1 },
      { id: 'stressManagement', title: 'Stress Management', rank: 2 },
    ],
    pillarFilter: null,
  });

  const socialRow = report.rows.find((row) => row.pillar.id === 'socialLife');
  const stressRow = report.rows.find((row) => row.pillar.id === 'stressManagement');

  assert.ok(socialRow);
  assert.ok(stressRow);

  assert.equal(socialRow.interventions.length, 2);
  assert.equal(socialRow.activeInterventions.length, 1);
  assert.equal(stressRow.interventions.length, 1);
  assert.equal(stressRow.activeInterventions.length, 1);
});

test('buildPillarIntegrityReport detects missing pillar nodes and canonical edges', () => {
  const canonicalGraph = makeGraph(
    ['SOCIAL_TX', 'SOCIAL_ISOLATION', 'RELATIONSHIP_TX', 'RELATIONSHIP_STRAIN', 'STRESS'],
    [
      { source: 'SOCIAL_TX', target: 'SOCIAL_ISOLATION', edgeType: 'forward' },
      { source: 'RELATIONSHIP_TX', target: 'RELATIONSHIP_STRAIN', edgeType: 'forward' },
      { source: 'RELATIONSHIP_STRAIN', target: 'STRESS', edgeType: 'feedback' },
    ],
  );

  const userGraph = makeGraph(
    ['SOCIAL_TX', 'SOCIAL_ISOLATION', 'STRESS'],
    [
      { source: 'SOCIAL_TX', target: 'SOCIAL_ISOLATION', edgeType: 'forward' },
    ],
  );

  const report = buildPillarIntegrityReport({
    userID: 'test-user',
    interventions: [
      { id: 'social_connection', graphNodeID: 'SOCIAL_TX', pillars: ['socialLife'], planningTags: ['foundation'] },
      { id: 'relationship_care', graphNodeID: 'RELATIONSHIP_TX', pillars: ['socialLife'], planningTags: ['foundation'] },
    ],
    activeInterventionIDs: ['social_connection'],
    userGraph,
    canonicalGraph,
    policyPillars: [
      { id: 'socialLife', title: 'Social Life', rank: 1 },
    ],
    pillarFilter: null,
  });

  const socialRow = report.rows[0];
  assert.deepEqual(socialRow.missingNodeIDs, ['RELATIONSHIP_TX']);

  const expectedMissingEdge = edgeSignature({
    source: 'RELATIONSHIP_TX',
    target: 'RELATIONSHIP_STRAIN',
    edgeType: 'forward',
    label: '',
  });

  assert.ok(socialRow.missingCanonicalEdgeSignatures.includes(expectedMissingEdge));
  assert.deepEqual(socialRow.connectivity.disconnectedNodeIDs, ['RELATIONSHIP_TX']);
  assert.deepEqual(report.overallMissingNodeIDs, ['RELATIONSHIP_TX']);
});
