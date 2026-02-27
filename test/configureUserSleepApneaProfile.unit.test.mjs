import test from 'node:test';
import assert from 'node:assert/strict';
import {
  MORNING_PROFILE_ENABLED_FIELDS,
  MORNING_PROFILE_REQUIRED_FIELDS,
  buildUpdatedStore,
  computeDownstreamNodeIDs,
  reactivateOsaBranch,
} from '../scripts/configure-user-sleep-apnea-profile.mjs';

test('computeDownstreamNodeIDs follows directed edges from OSA roots', () => {
  const graphData = {
    nodes: [
      { data: { id: 'OSA' } },
      { data: { id: 'AIRWAY_OBS' } },
      { data: { id: 'MICRO' } },
      { data: { id: 'RMMA' } },
      { data: { id: 'UNRELATED' } },
    ],
    edges: [
      { data: { source: 'OSA', target: 'AIRWAY_OBS' } },
      { data: { source: 'AIRWAY_OBS', target: 'MICRO' } },
      { data: { source: 'MICRO', target: 'RMMA' } },
      { data: { source: 'UNRELATED', target: 'OSA' } },
    ],
  };

  const downstream = computeDownstreamNodeIDs(graphData);

  assert.deepEqual(
    [...downstream].sort(),
    ['AIRWAY_OBS', 'MICRO', 'OSA', 'RMMA']
  );
});

test('reactivateOsaBranch reactivates only OSA branch and treatment link', () => {
  const graphData = {
    nodes: [
      { data: { id: 'OSA', isDeactivated: true } },
      { data: { id: 'AIRWAY_OBS', isDeactivated: true } },
      { data: { id: 'MICRO', isDeactivated: true } },
      { data: { id: 'RMMA', isDeactivated: true } },
      { data: { id: 'OSA_TX', isDeactivated: true } },
      { data: { id: 'UNRELATED', isDeactivated: true } },
      { data: { id: 'X', isDeactivated: true } },
    ],
    edges: [
      { data: { source: 'OSA', target: 'AIRWAY_OBS', isDeactivated: true } },
      { data: { source: 'AIRWAY_OBS', target: 'MICRO', isDeactivated: true } },
      { data: { source: 'MICRO', target: 'RMMA', isDeactivated: true } },
      { data: { source: 'OSA_TX', target: 'OSA', isDeactivated: true } },
      { data: { source: 'UNRELATED', target: 'X', isDeactivated: true } },
    ],
  };

  const result = reactivateOsaBranch(graphData);
  const nextNodes = result.graphData.nodes.map((entry) => entry.data);
  const nextEdges = result.graphData.edges.map((entry) => entry.data);

  assert.equal(result.nodeReactivations, 5);
  assert.equal(result.edgeReactivations, 4);
  assert.equal(result.branchEdgeCount, 4);

  assert.equal(nextNodes.find((node) => node.id === 'OSA')?.isDeactivated, false);
  assert.equal(nextNodes.find((node) => node.id === 'AIRWAY_OBS')?.isDeactivated, false);
  assert.equal(nextNodes.find((node) => node.id === 'MICRO')?.isDeactivated, false);
  assert.equal(nextNodes.find((node) => node.id === 'RMMA')?.isDeactivated, false);
  assert.equal(nextNodes.find((node) => node.id === 'OSA_TX')?.isDeactivated, false);
  assert.equal(nextNodes.find((node) => node.id === 'UNRELATED')?.isDeactivated, true);

  assert.equal(
    nextEdges.find((edge) => edge.source === 'OSA' && edge.target === 'AIRWAY_OBS')?.isDeactivated,
    false
  );
  assert.equal(
    nextEdges.find((edge) => edge.source === 'AIRWAY_OBS' && edge.target === 'MICRO')?.isDeactivated,
    false
  );
  assert.equal(
    nextEdges.find((edge) => edge.source === 'MICRO' && edge.target === 'RMMA')?.isDeactivated,
    false
  );
  assert.equal(
    nextEdges.find((edge) => edge.source === 'OSA_TX' && edge.target === 'OSA')?.isDeactivated,
    false
  );
  assert.equal(
    nextEdges.find((edge) => edge.source === 'UNRELATED' && edge.target === 'X')?.isDeactivated,
    true
  );
});

test('buildUpdatedStore writes morning questionnaire and leaves missing graph untouched', () => {
  const currentStore = {};
  const result = buildUpdatedStore(currentStore);

  assert.deepEqual(result.nextStore.morningQuestionnaire, {
    enabledFields: [...MORNING_PROFILE_ENABLED_FIELDS],
    requiredFields: [...MORNING_PROFILE_REQUIRED_FIELDS],
  });
  assert.equal(result.reactivation.nodeReactivations, 0);
  assert.equal(result.reactivation.edgeReactivations, 0);
  assert.equal(result.reactivation.branchEdgeCount, 0);
});
