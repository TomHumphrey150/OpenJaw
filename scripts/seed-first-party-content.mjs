#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const CONTENT_TYPE = Object.freeze({
  graph: 'graph',
  inputs: 'inputs',
  outcomes: 'outcomes',
  planning: 'planning',
  citations: 'citations',
  info: 'info',
});

const CONTENT_KEY = Object.freeze({
  canonicalGraph: 'canonical_causal_graph',
  interventionsCatalog: 'interventions_catalog',
  outcomesMetadata: 'outcomes_metadata',
  foundationCatalog: 'foundation_v1_catalog',
  planningPolicy: 'planner_policy_v1',
  citationsCatalog: 'citations_catalog',
  bruxismInfo: 'bruxism_info',
});

function requiredEnv(...names) {
  for (const name of names) {
    const value = process.env[name];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }

  throw new Error(`Missing environment variable. Provide one of: ${names.join(', ')}`);
}

async function loadJSON(filePath) {
  const text = await readFile(filePath, 'utf8');
  return JSON.parse(text);
}

function isRecord(value) {
  return typeof value === 'object' && value !== null;
}

function isGraphData(value) {
  if (!isRecord(value)) {
    return false;
  }

  return Array.isArray(value.nodes) && Array.isArray(value.edges);
}

function firstLine(value) {
  if (typeof value !== 'string') {
    return '';
  }

  const index = value.indexOf('\n');
  if (index < 0) {
    return value;
  }

  return value.slice(0, index);
}

function buildOutcomesMetadata(graphData) {
  const outcomeMetricDefinitions = [
    {
      id: 'microArousalRatePerHour',
      label: 'Microarousal rate per hour',
      unit: 'events/hour',
      direction: 'lower_better',
      description: 'Frequency of microarousal events during sleep. Lower values indicate calmer sleep continuity.',
    },
    {
      id: 'microArousalCount',
      label: 'Microarousal count',
      unit: 'events/night',
      direction: 'lower_better',
      description: 'Total microarousal events observed during the recorded night.',
    },
    {
      id: 'confidence',
      label: 'Outcome confidence',
      unit: '0_to_1',
      direction: 'higher_better',
      description: 'Model confidence for the recorded outcome estimate.',
    },
  ];

  const outcomeNodes = graphData.nodes
    .filter((node) => {
      if (!isRecord(node) || !isRecord(node.data)) {
        return false;
      }

      const styleClass = node.data.styleClass;
      const id = node.data.id;

      if (typeof styleClass !== 'string' || typeof id !== 'string') {
        return false;
      }

      if (styleClass === 'symptom') {
        return true;
      }

      return id === 'MICRO' || id === 'RMMA';
    })
    .map((node) => {
      const data = node.data;
      const tooltip = isRecord(data.tooltip) ? data.tooltip : {};

      return {
        id: data.id,
        label: firstLine(data.label),
        styleClass: typeof data.styleClass === 'string' ? data.styleClass : 'unknown',
        evidence: typeof tooltip.evidence === 'string' ? tooltip.evidence : null,
        stat: typeof tooltip.stat === 'string' ? tooltip.stat : null,
        citation: typeof tooltip.citation === 'string' ? tooltip.citation : null,
        mechanism: typeof tooltip.mechanism === 'string' ? tooltip.mechanism : null,
      };
    });

  return {
    metrics: outcomeMetricDefinitions,
    nodes: outcomeNodes,
    updatedAt: new Date().toISOString(),
  };
}

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');
const graphSourceFile = path.join(repoRoot, 'public/js/causalEditor/defaultGraphData.js');
const interventionsFile = path.join(repoRoot, 'data/interventions.json');
const bruxismInfoFile = path.join(repoRoot, 'data/bruxism-info.json');
const foundationCatalogFile = path.join(
  repoRoot,
  'ios/Telocare/Telocare/Resources/Foundation/foundation-v1-catalog.json'
);
const plannerPolicyFile = path.join(
  repoRoot,
  'ios/Telocare/Telocare/Resources/Foundation/planner-policy-v1.json'
);

const graphSourceURL = pathToFileURL(graphSourceFile).href;
const graphModule = await import(graphSourceURL);
const graphData = graphModule.DEFAULT_GRAPH_DATA;

if (!isGraphData(graphData)) {
  throw new Error('DEFAULT_GRAPH_DATA is invalid. Expected { nodes: [], edges: [] }.');
}

const interventionsData = await loadJSON(interventionsFile);
const bruxismInfoData = await loadJSON(bruxismInfoFile);
const foundationCatalogData = await loadJSON(foundationCatalogFile);
const plannerPolicyData = await loadJSON(plannerPolicyFile);
const citations = isRecord(bruxismInfoData) && Array.isArray(bruxismInfoData.citations)
  ? bruxismInfoData.citations
  : [];
const outcomesMetadata = buildOutcomesMetadata(graphData);

const supabaseURL = requiredEnv('SUPABASE_URL');
const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');

const supabase = createClient(supabaseURL, supabaseSecretKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

const rows = [
  {
    content_type: CONTENT_TYPE.graph,
    content_key: CONTENT_KEY.canonicalGraph,
    data: graphData,
    version: 1,
  },
  {
    content_type: CONTENT_TYPE.inputs,
    content_key: CONTENT_KEY.interventionsCatalog,
    data: interventionsData,
    version: 1,
  },
  {
    content_type: CONTENT_TYPE.outcomes,
    content_key: CONTENT_KEY.outcomesMetadata,
    data: outcomesMetadata,
    version: 1,
  },
  {
    content_type: CONTENT_TYPE.planning,
    content_key: CONTENT_KEY.foundationCatalog,
    data: foundationCatalogData,
    version: 1,
  },
  {
    content_type: CONTENT_TYPE.planning,
    content_key: CONTENT_KEY.planningPolicy,
    data: plannerPolicyData,
    version: 1,
  },
  {
    content_type: CONTENT_TYPE.citations,
    content_key: CONTENT_KEY.citationsCatalog,
    data: { citations },
    version: 1,
  },
  {
    content_type: CONTENT_TYPE.info,
    content_key: CONTENT_KEY.bruxismInfo,
    data: bruxismInfoData,
    version: 1,
  },
];

const { data, error } = await supabase
  .from('first_party_content')
  .upsert(rows, { onConflict: 'content_type,content_key' })
  .select('content_type,content_key');

if (error) {
  throw new Error(`Supabase upsert failed: ${error.message}`);
}

const insertedCount = Array.isArray(data) ? data.length : 0;
console.log(`Seeded first_party_content rows: ${insertedCount}`);
rows.forEach((row) => {
  console.log(`- ${row.content_type}/${row.content_key}`);
});
