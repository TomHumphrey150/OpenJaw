import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { test } from 'node:test';

const require = createRequire(import.meta.url);
require('ts-node/register');

const { parseGraphData } = require('../scripts/pillar-integrity-lib.ts');
const {
  mergeUserGraphWithCanonicalTargets,
} = require('../scripts/user-graph-patch-lib.ts');

function makeGraph(nodes, edges) {
  return parseGraphData({
    nodes: nodes.map((node) => ({ data: node })),
    edges: edges.map((edge) => ({ data: edge })),
  });
}

test('mergeUserGraphWithCanonicalTargets additively merges missing social graph targets', () => {
  const canonicalGraph = makeGraph(
    [
      { id: 'STRESS', label: 'Stress' },
      { id: 'SLEEP_DEP', label: 'Sleep Debt' },
      { id: 'SOCIAL_ISOLATION', label: 'Social Isolation' },
      { id: 'RELATIONSHIP_STRAIN', label: 'Relationship Strain' },
      { id: 'FINANCIAL_STRAIN', label: 'Financial Strain' },
      { id: 'SOCIAL_TX', label: 'Social Check-In' },
      { id: 'RELATIONSHIP_TX', label: 'Relationship Care' },
      { id: 'FINANCIAL_TX', label: 'Financial Check-In' },
    ],
    [
      { source: 'SOCIAL_ISOLATION', target: 'STRESS', edgeType: 'feedback' },
      { source: 'RELATIONSHIP_STRAIN', target: 'STRESS', edgeType: 'feedback' },
      { source: 'FINANCIAL_STRAIN', target: 'STRESS', edgeType: 'feedback' },
      { source: 'FINANCIAL_STRAIN', target: 'SLEEP_DEP', edgeType: 'feedback' },
      { source: 'SOCIAL_TX', target: 'SOCIAL_ISOLATION', edgeType: 'forward' },
      { source: 'RELATIONSHIP_TX', target: 'RELATIONSHIP_STRAIN', edgeType: 'forward' },
      { source: 'FINANCIAL_TX', target: 'FINANCIAL_STRAIN', edgeType: 'forward' },
    ],
  );

  const userGraph = makeGraph(
    [
      { id: 'STRESS', label: 'Stress' },
      { id: 'SLEEP_DEP', label: 'Sleep Debt' },
    ],
    [],
  );

  const firstPass = mergeUserGraphWithCanonicalTargets(userGraph, canonicalGraph);

  assert.equal(firstPass.changed, true);
  assert.deepEqual(firstPass.missingCanonicalNodeIDs, []);
  assert.deepEqual(firstPass.missingCanonicalEdgeRules, []);
  assert.deepEqual(firstPass.addedNodeIDs, [
    'FINANCIAL_STRAIN',
    'FINANCIAL_TX',
    'RELATIONSHIP_STRAIN',
    'RELATIONSHIP_TX',
    'SOCIAL_ISOLATION',
    'SOCIAL_TX',
  ]);
  assert.equal(firstPass.addedEdgeSignatures.length, 7);

  const socialNode = firstPass.nextGraph.nodes.find((node) => node.data.id === 'SOCIAL_ISOLATION');
  assert.ok(socialNode);
  assert.equal(socialNode.data.label, 'Social Isolation');
});

test('mergeUserGraphWithCanonicalTargets is idempotent on repeated runs', () => {
  const canonicalGraph = makeGraph(
    [
      { id: 'STRESS', label: 'Stress' },
      { id: 'SLEEP_DEP', label: 'Sleep Debt' },
      { id: 'SOCIAL_ISOLATION', label: 'Social Isolation' },
      { id: 'RELATIONSHIP_STRAIN', label: 'Relationship Strain' },
      { id: 'FINANCIAL_STRAIN', label: 'Financial Strain' },
      { id: 'SOCIAL_TX', label: 'Social Check-In' },
      { id: 'RELATIONSHIP_TX', label: 'Relationship Care' },
      { id: 'FINANCIAL_TX', label: 'Financial Check-In' },
    ],
    [
      { source: 'SOCIAL_ISOLATION', target: 'STRESS', edgeType: 'feedback' },
      { source: 'RELATIONSHIP_STRAIN', target: 'STRESS', edgeType: 'feedback' },
      { source: 'FINANCIAL_STRAIN', target: 'STRESS', edgeType: 'feedback' },
      { source: 'FINANCIAL_STRAIN', target: 'SLEEP_DEP', edgeType: 'feedback' },
      { source: 'SOCIAL_TX', target: 'SOCIAL_ISOLATION', edgeType: 'forward' },
      { source: 'RELATIONSHIP_TX', target: 'RELATIONSHIP_STRAIN', edgeType: 'forward' },
      { source: 'FINANCIAL_TX', target: 'FINANCIAL_STRAIN', edgeType: 'forward' },
    ],
  );

  const firstPass = mergeUserGraphWithCanonicalTargets(
    makeGraph(
      [
        { id: 'STRESS', label: 'Stress' },
        { id: 'SLEEP_DEP', label: 'Sleep Debt' },
      ],
      [],
    ),
    canonicalGraph,
  );

  const secondPass = mergeUserGraphWithCanonicalTargets(firstPass.nextGraph, canonicalGraph);

  assert.equal(secondPass.changed, false);
  assert.deepEqual(secondPass.addedNodeIDs, []);
  assert.deepEqual(secondPass.addedEdgeSignatures, []);
});
