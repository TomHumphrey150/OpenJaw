#!/usr/bin/env node

import process from 'node:process';
import { writeFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const CONTENT_TYPE = Object.freeze({
  inputs: 'inputs',
  planning: 'planning',
});

const CONTENT_KEY = Object.freeze({
  interventionsCatalog: 'interventions_catalog',
  foundationCatalog: 'foundation_v1_catalog',
  planningPolicy: 'planner_policy_v1',
});

function getArg(name) {
  const needle = `--${name}`;
  const index = process.argv.indexOf(needle);
  if (index < 0) return null;
  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) return null;
  return value;
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function requiredEnv(...names) {
  for (const name of names) {
    const value = process.env[name];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  throw new Error(`Missing environment variable. Provide one of: ${names.join(', ')}`);
}

function isRecord(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function asStringList(value) {
  if (!Array.isArray(value)) return [];
  return value.filter((entry) => typeof entry === 'string');
}

function normalizePillarIDsFromPolicy(policyData) {
  if (!isRecord(policyData)) {
    return [];
  }

  const pillars = Array.isArray(policyData.pillars) ? policyData.pillars : [];
  if (pillars.length > 0) {
    return pillars
      .map((entry) => {
        if (typeof entry === 'string') return entry;
        if (isRecord(entry) && typeof entry.id === 'string') return entry.id;
        return null;
      })
      .filter((entry) => typeof entry === 'string');
  }

  return asStringList(policyData.pillarOrder);
}

function normalizePillarDefinitions(policyData, fallbackCatalog) {
  const pillarIDs = normalizePillarIDsFromPolicy(policyData);
  if (pillarIDs.length > 0) {
    const policyPillars = Array.isArray(policyData?.pillars) ? policyData.pillars : [];
    return pillarIDs.map((pillarID, index) => {
      const fromPolicy = policyPillars.find((entry) => isRecord(entry) && entry.id === pillarID);
      const title =
        isRecord(fromPolicy) && typeof fromPolicy.title === 'string' && fromPolicy.title.trim().length > 0
          ? fromPolicy.title.trim()
          : pillarID;
      return {
        id: pillarID,
        title,
        rank: index + 1,
      };
    });
  }

  const catalogPillars = Array.isArray(fallbackCatalog?.pillars) ? fallbackCatalog.pillars : [];
  return catalogPillars
    .map((entry, index) => {
      if (!isRecord(entry) || typeof entry.id !== 'string') return null;
      return {
        id: entry.id,
        title: typeof entry.title === 'string' && entry.title.trim().length > 0 ? entry.title.trim() : entry.id,
        rank: Number.isFinite(entry.rank) ? entry.rank : index + 1,
      };
    })
    .filter((entry) => entry !== null)
    .sort((lhs, rhs) => lhs.rank - rhs.rank);
}

function buildMetadataMaps(foundationCatalog, interventionsCatalog) {
  const fromFoundation = new Map();
  const fromInterventions = new Map();

  const mappings = Array.isArray(foundationCatalog?.interventionMappings)
    ? foundationCatalog.interventionMappings
    : [];
  for (const mapping of mappings) {
    if (!isRecord(mapping) || typeof mapping.interventionID !== 'string') continue;
    fromFoundation.set(mapping.interventionID, {
      interventionID: mapping.interventionID,
      pillars: asStringList(mapping.pillars),
      tags: asStringList(mapping.tags),
      source: 'foundationCatalog',
    });
  }

  const interventions = Array.isArray(interventionsCatalog?.interventions)
    ? interventionsCatalog.interventions
    : [];
  for (const intervention of interventions) {
    if (!isRecord(intervention) || typeof intervention.id !== 'string') continue;
    const pillars = asStringList(intervention.pillars);
    const tags = asStringList(intervention.planningTags);
    if (pillars.length === 0 && tags.length === 0) continue;
    fromInterventions.set(intervention.id, {
      interventionID: intervention.id,
      pillars,
      tags,
      source: 'interventionsCatalog',
    });
  }

  return { fromFoundation, fromInterventions };
}

function resolveMetadata(interventionID, maps) {
  const fromCatalog = maps.fromFoundation.get(interventionID);
  if (fromCatalog) {
    return fromCatalog;
  }
  const fromIntervention = maps.fromInterventions.get(interventionID);
  if (fromIntervention) {
    return fromIntervention;
  }
  return {
    interventionID,
    pillars: [],
    tags: [],
    source: 'unmapped',
  };
}

async function fetchContentData(supabase, userID, contentType, contentKey) {
  const userQuery = await supabase
    .from('user_content')
    .select('data,updated_at,version')
    .eq('user_id', userID)
    .eq('content_type', contentType)
    .eq('content_key', contentKey)
    .limit(1)
    .maybeSingle();

  if (userQuery.error) {
    throw new Error(`user_content ${contentType}/${contentKey} query failed: ${userQuery.error.message}`);
  }

  if (userQuery.data) {
    return { source: 'user_content', ...userQuery.data };
  }

  const firstPartyQuery = await supabase
    .from('first_party_content')
    .select('data,updated_at,version')
    .eq('content_type', contentType)
    .eq('content_key', contentKey)
    .limit(1)
    .maybeSingle();

  if (firstPartyQuery.error) {
    throw new Error(`first_party_content ${contentType}/${contentKey} query failed: ${firstPartyQuery.error.message}`);
  }

  if (firstPartyQuery.data) {
    return { source: 'first_party_content', ...firstPartyQuery.data };
  }

  return null;
}

function printCoverage(report) {
  console.log('Foundation Coverage Report');
  console.log(`User ID: ${report.userID}`);
  console.log(`user_data.updated_at: ${report.userDataUpdatedAt || '(missing)'}`);
  console.log(`Active interventions: ${report.activeInterventionCount}`);
  console.log(`Mappings resolved: ${report.resolvedMappingCount}`);
  console.log(`Unmapped active interventions: ${report.unmappedActiveInterventionCount}`);

  if (report.unmappedActiveInterventionIDs.length > 0) {
    console.log(`Unmapped IDs: ${report.unmappedActiveInterventionIDs.join(', ')}`);
  }

  console.log('');
  console.log('Content sources');
  console.log(
    `interventions_catalog: ${report.contentSources.interventionsCatalog.source || '(missing)'} (${report.contentSources.interventionsCatalog.updatedAt || 'n/a'})`
  );
  console.log(
    `foundation_v1_catalog: ${report.contentSources.foundationCatalog.source || '(missing)'} (${report.contentSources.foundationCatalog.updatedAt || 'n/a'})`
  );
  console.log(
    `planner_policy_v1: ${report.contentSources.planningPolicy.source || '(missing)'} (${report.contentSources.planningPolicy.updatedAt || 'n/a'})`
  );

  console.log('');
  console.log(`Acute-tagged active interventions: ${report.acuteTaggedActiveCount}`);
  console.log(`Foundation-tagged active interventions: ${report.foundationTaggedActiveCount}`);
  console.log(`Catalog interventions: ${report.catalogInterventionCount}`);
  console.log(`Catalog mapped interventions: ${report.catalogMappedCount}`);

  console.log('');
  console.log('Pillar active coverage');
  for (const pillar of report.pillars) {
    const count = report.activeCountByPillar[pillar.id] || 0;
    console.log(`  - ${pillar.title} (${pillar.id}): ${count}`);
  }

  if (report.missingPillarIDs.length > 0) {
    console.log('');
    console.log(`Missing active coverage for pillars: ${report.missingPillarIDs.join(', ')}`);
  }

  console.log('');
  console.log('Pillar catalog coverage');
  for (const pillar of report.pillars) {
    const count = report.catalogCountByPillar[pillar.id] || 0;
    console.log(`  - ${pillar.title} (${pillar.id}): ${count}`);
  }

  if (report.missingCatalogPillarIDs.length > 0) {
    console.log('');
    console.log(`Missing catalog coverage for pillars: ${report.missingCatalogPillarIDs.join(', ')}`);
  }
}

const userID = getArg('user-id') || process.env.SUPABASE_DEBUG_USER_ID;
const raw = hasFlag('raw');
const reportOut = getArg('report-out');

if (!userID) {
  console.error('Usage: npm run debug:foundation-coverage -- --user-id <uuid> [--report-out <path>] [--raw]');
  process.exit(1);
}

const supabaseURL = requiredEnv('SUPABASE_URL');
const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');

const supabase = createClient(supabaseURL, supabaseSecretKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

const userRowQuery = await supabase
  .from('user_data')
  .select('user_id,data,updated_at')
  .eq('user_id', userID)
  .maybeSingle();

if (userRowQuery.error) {
  console.error(`user_data query failed: ${userRowQuery.error.message}`);
  process.exit(1);
}

if (!userRowQuery.data) {
  console.error(`No user_data row found for user_id=${userID}`);
  process.exit(1);
}

const userDataStore = isRecord(userRowQuery.data.data) ? userRowQuery.data.data : {};
const activeInterventionIDs = asStringList(userDataStore.activeInterventions);

const interventionsCatalogRow = await fetchContentData(
  supabase,
  userID,
  CONTENT_TYPE.inputs,
  CONTENT_KEY.interventionsCatalog
);
const foundationCatalogRow = await fetchContentData(
  supabase,
  userID,
  CONTENT_TYPE.planning,
  CONTENT_KEY.foundationCatalog
);
const planningPolicyRow = await fetchContentData(
  supabase,
  userID,
  CONTENT_TYPE.planning,
  CONTENT_KEY.planningPolicy
);

const interventionsCatalog = interventionsCatalogRow?.data;
const foundationCatalog = foundationCatalogRow?.data;
const planningPolicy = planningPolicyRow?.data;

const metadataMaps = buildMetadataMaps(foundationCatalog, interventionsCatalog);

const resolvedRows = activeInterventionIDs.map((interventionID) => resolveMetadata(interventionID, metadataMaps));
const unresolvedRows = resolvedRows.filter((row) => row.source === 'unmapped');
const acuteTaggedActiveCount = resolvedRows.filter((row) => row.tags.includes('acute')).length;
const foundationTaggedActiveCount = resolvedRows.filter((row) => row.tags.includes('foundation')).length;

const catalogInterventionIDs = Array.isArray(interventionsCatalog?.interventions)
  ? interventionsCatalog.interventions
      .map((entry) => (isRecord(entry) && typeof entry.id === 'string' ? entry.id : null))
      .filter((entry) => typeof entry === 'string')
  : [];
const catalogRows = catalogInterventionIDs.map((interventionID) => resolveMetadata(interventionID, metadataMaps));
const mappedCatalogRows = catalogRows.filter((row) => row.source !== 'unmapped');

const pillars = normalizePillarDefinitions(planningPolicy, foundationCatalog);
const activeCountByPillar = {};
for (const row of resolvedRows) {
  for (const pillarID of row.pillars) {
    activeCountByPillar[pillarID] = (activeCountByPillar[pillarID] || 0) + 1;
  }
}

const catalogCountByPillar = {};
for (const row of mappedCatalogRows) {
  for (const pillarID of row.pillars) {
    catalogCountByPillar[pillarID] = (catalogCountByPillar[pillarID] || 0) + 1;
  }
}

const missingPillarIDs = pillars
  .map((pillar) => pillar.id)
  .filter((pillarID) => (activeCountByPillar[pillarID] || 0) === 0);
const missingCatalogPillarIDs = pillars
  .map((pillar) => pillar.id)
  .filter((pillarID) => (catalogCountByPillar[pillarID] || 0) === 0);

const report = {
  userID,
  userDataUpdatedAt: userRowQuery.data.updated_at || null,
  activeInterventionCount: activeInterventionIDs.length,
  resolvedMappingCount: resolvedRows.length - unresolvedRows.length,
  unmappedActiveInterventionCount: unresolvedRows.length,
  unmappedActiveInterventionIDs: unresolvedRows.map((row) => row.interventionID),
  acuteTaggedActiveCount,
  foundationTaggedActiveCount,
  catalogInterventionCount: catalogRows.length,
  catalogMappedCount: mappedCatalogRows.length,
  pillars,
  activeCountByPillar,
  catalogCountByPillar,
  missingPillarIDs,
  missingCatalogPillarIDs,
  activeInterventionMappings: resolvedRows,
  catalogInterventionMappings: catalogRows,
  contentSources: {
    interventionsCatalog: {
      source: interventionsCatalogRow?.source || null,
      updatedAt: interventionsCatalogRow?.updated_at || null,
      version: interventionsCatalogRow?.version || null,
    },
    foundationCatalog: {
      source: foundationCatalogRow?.source || null,
      updatedAt: foundationCatalogRow?.updated_at || null,
      version: foundationCatalogRow?.version || null,
    },
    planningPolicy: {
      source: planningPolicyRow?.source || null,
      updatedAt: planningPolicyRow?.updated_at || null,
      version: planningPolicyRow?.version || null,
    },
  },
};

printCoverage(report);

if (reportOut) {
  writeFileSync(reportOut, JSON.stringify(report, null, 2));
  console.log('');
  console.log(`Wrote report: ${reportOut}`);
}

if (raw) {
  console.log('');
  console.log(JSON.stringify(report, null, 2));
}
