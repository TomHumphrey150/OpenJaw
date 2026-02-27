#!/usr/bin/env node

import process from 'node:process';
import { createClient } from '@supabase/supabase-js';

const DEFAULT_SUPABASE_URL = 'https://aocndwnnkffumisprifx.supabase.co';

const OSA_ROOT_NODE_IDS = Object.freeze(['OSA', 'AIRWAY_OBS']);
const OSA_TREATMENT_NODE_ID = 'OSA_TX';
const OSA_TREATMENT_EDGE_SOURCE = 'OSA_TX';
const OSA_TREATMENT_EDGE_TARGET = 'OSA';

const MORNING_PROFILE_ENABLED_FIELDS = Object.freeze([
  'neckTightness',
  'jawSoreness',
  'earFullness',
  'stressLevel',
  'morningHeadache',
  'dryMouth',
]);

const MORNING_PROFILE_REQUIRED_FIELDS = Object.freeze([
  'neckTightness',
  'jawSoreness',
  'earFullness',
  'stressLevel',
  'morningHeadache',
  'dryMouth',
]);

function getArg(name) {
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

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function requiredEnv(...keys) {
  for (const key of keys) {
    const value = process.env[key];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }

  throw new Error(`Missing environment variable. Provide one of: ${keys.join(', ')}`);
}

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function buildMorningQuestionnaire() {
  return {
    enabledFields: [...MORNING_PROFILE_ENABLED_FIELDS],
    requiredFields: [...MORNING_PROFILE_REQUIRED_FIELDS],
  };
}

function nodeData(entry) {
  if (!isRecord(entry)) {
    return null;
  }

  const data = entry.data;
  if (!isRecord(data)) {
    return null;
  }

  if (typeof data.id !== 'string' || data.id.length === 0) {
    return null;
  }

  return data;
}

function edgeData(entry) {
  if (!isRecord(entry)) {
    return null;
  }

  const data = entry.data;
  if (!isRecord(data)) {
    return null;
  }

  if (typeof data.source !== 'string' || typeof data.target !== 'string') {
    return null;
  }

  if (data.source.length === 0 || data.target.length === 0) {
    return null;
  }

  return data;
}

function computeDownstreamNodeIDs(graphData, rootNodeIDs = OSA_ROOT_NODE_IDS) {
  if (!isRecord(graphData)) {
    return new Set();
  }

  const nodes = Array.isArray(graphData.nodes) ? graphData.nodes : [];
  const edges = Array.isArray(graphData.edges) ? graphData.edges : [];

  const availableNodeIDs = new Set(
    nodes
      .map(nodeData)
      .filter((data) => data !== null)
      .map((data) => data.id)
  );

  const adjacencyBySource = new Map();
  for (const entry of edges) {
    const data = edgeData(entry);
    if (!data) {
      continue;
    }

    const outgoing = adjacencyBySource.get(data.source) ?? [];
    outgoing.push(data.target);
    adjacencyBySource.set(data.source, outgoing);
  }

  const downstreamNodeIDs = new Set(rootNodeIDs.filter((id) => availableNodeIDs.has(id)));
  const queue = [...downstreamNodeIDs];
  let cursor = 0;

  while (cursor < queue.length) {
    const sourceID = queue[cursor];
    cursor += 1;

    const outgoingTargets = adjacencyBySource.get(sourceID) ?? [];
    for (const targetID of outgoingTargets) {
      if (downstreamNodeIDs.has(targetID)) {
        continue;
      }

      if (!availableNodeIDs.has(targetID)) {
        continue;
      }

      downstreamNodeIDs.add(targetID);
      queue.push(targetID);
    }
  }

  return downstreamNodeIDs;
}

function reactivateOsaBranch(graphData) {
  if (!isRecord(graphData)) {
    return {
      graphData,
      downstreamNodeIDs: new Set(),
      branchEdgeCount: 0,
      nodeReactivations: 0,
      edgeReactivations: 0,
    };
  }

  const nextGraphData = deepClone(graphData);
  const downstreamNodeIDs = computeDownstreamNodeIDs(nextGraphData);
  const targetNodeIDs = new Set([...downstreamNodeIDs, OSA_TREATMENT_NODE_ID]);

  let nodeReactivations = 0;
  const nodes = Array.isArray(nextGraphData.nodes) ? nextGraphData.nodes : [];
  for (const entry of nodes) {
    const data = nodeData(entry);
    if (!data) {
      continue;
    }

    if (!targetNodeIDs.has(data.id)) {
      continue;
    }

    if (data.isDeactivated === true) {
      data.isDeactivated = false;
      nodeReactivations += 1;
    }
  }

  let branchEdgeCount = 0;
  let edgeReactivations = 0;
  const edges = Array.isArray(nextGraphData.edges) ? nextGraphData.edges : [];
  for (const entry of edges) {
    const data = edgeData(entry);
    if (!data) {
      continue;
    }

    const isDownstreamBranchEdge =
      downstreamNodeIDs.has(data.source) && downstreamNodeIDs.has(data.target);
    const isTreatmentLinkEdge =
      data.source == OSA_TREATMENT_EDGE_SOURCE && data.target == OSA_TREATMENT_EDGE_TARGET;
    if (!isDownstreamBranchEdge && !isTreatmentLinkEdge) {
      continue;
    }

    branchEdgeCount += 1;
    if (data.isDeactivated === true) {
      data.isDeactivated = false;
      edgeReactivations += 1;
    }
  }

  return {
    graphData: nextGraphData,
    downstreamNodeIDs,
    branchEdgeCount,
    nodeReactivations,
    edgeReactivations,
  };
}

function buildUpdatedStore(currentStore) {
  const nextStore = isRecord(currentStore) ? deepClone(currentStore) : {};
  nextStore.morningQuestionnaire = buildMorningQuestionnaire();

  const graphData = nextStore.customCausalDiagram?.graphData;
  const reactivation = reactivateOsaBranch(graphData);
  if (isRecord(nextStore.customCausalDiagram) && isRecord(reactivation.graphData)) {
    nextStore.customCausalDiagram.graphData = reactivation.graphData;
  }

  return {
    nextStore,
    reactivation,
  };
}

function printUsageAndExit() {
  console.error('Usage: npm run configure:user-sleep-apnea-profile -- --user-id <uuid> [--apply]');
  process.exit(1);
}

async function main() {
  const userID = getArg('user-id');
  if (!userID) {
    printUsageAndExit();
  }

  const apply = hasFlag('apply');
  const supabaseURL = process.env.SUPABASE_URL?.trim() || DEFAULT_SUPABASE_URL;
  const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');
  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: row, error } = await supabase
    .from('user_data')
    .select('user_id, data')
    .eq('user_id', userID)
    .maybeSingle();

  if (error) {
    throw new Error(`Supabase query failed: ${error.message}`);
  }

  if (!row) {
    throw new Error(`No row found in public.user_data for user_id=${userID}`);
  }

  const currentStore = isRecord(row.data) ? row.data : {};
  const { nextStore, reactivation } = buildUpdatedStore(currentStore);
  const isChanged = JSON.stringify(currentStore) !== JSON.stringify(nextStore);

  console.log(`Mode: ${apply ? 'apply' : 'dry-run'}`);
  console.log(`User ID: ${row.user_id}`);
  console.log(`Morning enabled fields: ${MORNING_PROFILE_ENABLED_FIELDS.join(', ')}`);
  console.log(`Morning required fields: ${MORNING_PROFILE_REQUIRED_FIELDS.join(', ')}`);
  console.log(`OSA downstream node count: ${reactivation.downstreamNodeIDs.size}`);
  console.log(`OSA branch edge count: ${reactivation.branchEdgeCount}`);
  console.log(`Node reactivations: ${reactivation.nodeReactivations}`);
  console.log(`Edge reactivations: ${reactivation.edgeReactivations}`);
  console.log(`Data changed: ${isChanged ? 'yes' : 'no'}`);

  if (!apply) {
    return;
  }

  if (!isChanged) {
    console.log('No update required.');
    return;
  }

  const { error: updateError } = await supabase
    .from('user_data')
    .update({ data: nextStore })
    .eq('user_id', userID);
  if (updateError) {
    throw new Error(`Failed to update ${row.user_id}: ${updateError.message}`);
  }

  console.log('Update applied.');
}

const isMainModule = process.argv[1] && process.argv[1].endsWith('configure-user-sleep-apnea-profile.mjs');
if (isMainModule) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

export {
  MORNING_PROFILE_ENABLED_FIELDS,
  MORNING_PROFILE_REQUIRED_FIELDS,
  buildMorningQuestionnaire,
  buildUpdatedStore,
  computeDownstreamNodeIDs,
  reactivateOsaBranch,
};
