#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const DEFAULT_SUPABASE_URL = 'https://aocndwnnkffumisprifx.supabase.co';
const BATCH_SIZE = 500;

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

function parseLimit(raw) {
  if (!raw) {
    return null;
  }

  const parsed = Number(raw);
  if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 100000) {
    throw new Error(`Invalid --limit value: ${raw}`);
  }

  return parsed;
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

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function loadCatalogInterventions(interventions) {
  const canonicalByAlias = new Map();
  const doseDefaults = {};

  for (const intervention of interventions) {
    const canonicalID = intervention.id;

    const aliases = [canonicalID, ...(Array.isArray(intervention.legacyIds) ? intervention.legacyIds : [])];
    for (const alias of aliases) {
      if (typeof alias !== 'string' || alias.trim().length === 0) {
        continue;
      }

      if (canonicalByAlias.has(alias) && canonicalByAlias.get(alias) !== canonicalID) {
        throw new Error(
          `Alias collision for ${alias}: ${canonicalByAlias.get(alias)} and ${canonicalID}`
        );
      }

      canonicalByAlias.set(alias, canonicalID);
    }

    if (intervention.trackingType === 'dose' && isRecord(intervention.doseConfig)) {
      const goal = Number(intervention.doseConfig.defaultDailyGoal);
      const increment = Number(intervention.doseConfig.defaultIncrement);

      if (!Number.isFinite(goal) || !Number.isFinite(increment) || goal <= 0 || increment <= 0) {
        throw new Error(`Invalid doseConfig for ${canonicalID}`);
      }

      doseDefaults[canonicalID] = {
        dailyGoal: goal,
        increment,
      };
    }
  }

  return {
    canonicalByAlias,
    doseDefaults,
  };
}

function canonicalizeIDs(ids, canonicalByAlias, counters) {
  const seen = new Set();
  const ordered = [];

  for (const id of ids) {
    if (typeof id !== 'string') {
      continue;
    }

    const canonicalID = canonicalByAlias.get(id) ?? id;
    if (canonicalID !== id) {
      counters.aliasReplacements += 1;
    }

    if (seen.has(canonicalID)) {
      counters.duplicateRemovals += 1;
      continue;
    }

    seen.add(canonicalID);
    ordered.push(canonicalID);
  }

  return ordered;
}

function canonicalizeDailyCheckIns(value, canonicalByAlias, counters) {
  if (!isRecord(value)) {
    return {};
  }

  const next = {};
  for (const [dateKey, ids] of Object.entries(value)) {
    if (!Array.isArray(ids)) {
      continue;
    }

    next[dateKey] = canonicalizeIDs(ids, canonicalByAlias, counters);
  }

  return next;
}

function canonicalizeInterventionArray(
  entries,
  idKey,
  canonicalByAlias,
  counters,
  dedupeByCanonical = false
) {
  if (!Array.isArray(entries)) {
    return [];
  }

  const seen = new Set();
  const next = [];

  for (const entry of entries) {
    if (!isRecord(entry) || typeof entry[idKey] !== 'string') {
      continue;
    }

    const canonicalID = canonicalByAlias.get(entry[idKey]) ?? entry[idKey];
    if (canonicalID !== entry[idKey]) {
      counters.aliasReplacements += 1;
    }

    const normalized = { ...entry, [idKey]: canonicalID };

    if (dedupeByCanonical) {
      if (seen.has(canonicalID)) {
        counters.duplicateRemovals += 1;
        continue;
      }
      seen.add(canonicalID);
    }

    next.push(normalized);
  }

  return next;
}

function canonicalizeDailyDoseProgress(value, canonicalByAlias, counters) {
  if (!isRecord(value)) {
    return {};
  }

  const next = {};
  for (const [dateKey, entry] of Object.entries(value)) {
    if (!isRecord(entry)) {
      continue;
    }

    const normalized = {};
    for (const [id, rawValue] of Object.entries(entry)) {
      const numericValue = Number(rawValue);
      if (!Number.isFinite(numericValue) || numericValue <= 0) {
        continue;
      }

      const canonicalID = canonicalByAlias.get(id) ?? id;
      if (canonicalID !== id) {
        counters.aliasReplacements += 1;
      }

      normalized[canonicalID] = (normalized[canonicalID] ?? 0) + numericValue;
    }

    next[dateKey] = normalized;
  }

  return next;
}

function canonicalizeDoseSettings(value, canonicalByAlias, counters) {
  if (!isRecord(value)) {
    return {};
  }

  const next = {};
  for (const [id, settings] of Object.entries(value)) {
    if (!isRecord(settings)) {
      continue;
    }

    const dailyGoal = Number(settings.dailyGoal);
    const increment = Number(settings.increment);
    if (!Number.isFinite(dailyGoal) || !Number.isFinite(increment) || dailyGoal <= 0 || increment <= 0) {
      continue;
    }

    const canonicalID = canonicalByAlias.get(id) ?? id;
    if (canonicalID !== id) {
      counters.aliasReplacements += 1;
    }

    next[canonicalID] = {
      dailyGoal,
      increment,
    };
  }

  return next;
}

function mergeDoseDefaults(existingSettings, defaults) {
  const next = { ...existingSettings };

  for (const [id, settings] of Object.entries(defaults)) {
    if (!isRecord(next[id])) {
      next[id] = clone(settings);
      continue;
    }

    if (!Number.isFinite(next[id].dailyGoal) || next[id].dailyGoal <= 0) {
      next[id].dailyGoal = settings.dailyGoal;
    }

    if (!Number.isFinite(next[id].increment) || next[id].increment <= 0) {
      next[id].increment = settings.increment;
    }
  }

  return next;
}

function hasDoseProgressEntries(value) {
  if (!isRecord(value)) {
    return false;
  }

  for (const entry of Object.values(value)) {
    if (!isRecord(entry)) {
      continue;
    }

    if (Object.keys(entry).length > 0) {
      return true;
    }
  }

  return false;
}

function normalizeStore(store, canonicalByAlias, doseDefaults, counters) {
  const normalized = isRecord(store) ? clone(store) : {};

  normalized.dailyCheckIns = canonicalizeDailyCheckIns(
    normalized.dailyCheckIns,
    canonicalByAlias,
    counters
  );

  normalized.hiddenInterventions = canonicalizeIDs(
    Array.isArray(normalized.hiddenInterventions) ? normalized.hiddenInterventions : [],
    canonicalByAlias,
    counters
  );

  normalized.interventionRatings = canonicalizeInterventionArray(
    normalized.interventionRatings,
    'interventionId',
    canonicalByAlias,
    counters,
    true
  );

  normalized.habitClassifications = canonicalizeInterventionArray(
    normalized.habitClassifications,
    'interventionId',
    canonicalByAlias,
    counters,
    true
  );

  normalized.habitTrials = canonicalizeInterventionArray(
    normalized.habitTrials,
    'interventionId',
    canonicalByAlias,
    counters,
    false
  );

  normalized.nightExposures = canonicalizeInterventionArray(
    normalized.nightExposures,
    'interventionId',
    canonicalByAlias,
    counters,
    false
  );

  normalized.experiments = canonicalizeInterventionArray(
    normalized.experiments,
    'interventionId',
    canonicalByAlias,
    counters,
    false
  );

  if (hasDoseProgressEntries(normalized.dailyDoseProgress)) {
    counters.doseResets += 1;
  }
  normalized.dailyDoseProgress = {};

  const currentDoseSettings = canonicalizeDoseSettings(
    normalized.interventionDoseSettings,
    canonicalByAlias,
    counters
  );
  normalized.interventionDoseSettings = mergeDoseDefaults(
    currentDoseSettings,
    doseDefaults
  );

  return normalized;
}

function printSummary(summary) {
  console.log('Normalization summary');
  console.log(`  mode: ${summary.apply ? 'apply' : 'dry-run'}`);
  console.log(`  scanned: ${summary.rowsScanned}`);
  console.log(`  changed: ${summary.rowsChanged}`);
  console.log(`  updated: ${summary.rowsUpdated}`);
  console.log(`  alias replacements: ${summary.aliasReplacements}`);
  console.log(`  duplicate removals: ${summary.duplicateRemovals}`);
  console.log(`  dose resets: ${summary.doseResets}`);
}

async function fetchRows(supabase, userID, limit) {
  if (userID) {
    const { data, error } = await supabase
      .from('user_data')
      .select('user_id,data')
      .eq('user_id', userID)
      .limit(1);

    if (error) {
      throw new Error(`Supabase query failed: ${error.message}`);
    }

    return Array.isArray(data) ? data : [];
  }

  const rows = [];
  let offset = 0;

  while (true) {
    let query = supabase
      .from('user_data')
      .select('user_id,data')
      .order('user_id', { ascending: true })
      .range(offset, offset + BATCH_SIZE - 1);

    if (Number.isFinite(limit)) {
      const remaining = limit - rows.length;
      if (remaining <= 0) {
        break;
      }

      if (remaining < BATCH_SIZE) {
        query = query.range(offset, offset + remaining - 1);
      }
    }

    const { data, error } = await query;
    if (error) {
      throw new Error(`Supabase query failed: ${error.message}`);
    }

    const batch = Array.isArray(data) ? data : [];
    rows.push(...batch);

    if (batch.length < BATCH_SIZE) {
      break;
    }

    offset += batch.length;
  }

  return rows;
}

async function main() {
  const apply = hasFlag('apply');
  const userID = getArg('user-id');
  const limit = parseLimit(getArg('limit'));

  const scriptDir = path.dirname(fileURLToPath(import.meta.url));
  const repoRoot = path.resolve(scriptDir, '..');
  const interventionsFile = path.join(repoRoot, 'data/interventions.json');

  const interventionsJSON = JSON.parse(await readFile(interventionsFile, 'utf8'));
  const interventions = Array.isArray(interventionsJSON.interventions)
    ? interventionsJSON.interventions
    : [];

  const { canonicalByAlias, doseDefaults } = loadCatalogInterventions(interventions);

  const supabaseURL = process.env.SUPABASE_URL?.trim() || DEFAULT_SUPABASE_URL;
  const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');

  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const rows = await fetchRows(supabase, userID, limit);

  const summary = {
    apply,
    rowsScanned: 0,
    rowsChanged: 0,
    rowsUpdated: 0,
    aliasReplacements: 0,
    duplicateRemovals: 0,
    doseResets: 0,
  };

  for (const row of rows) {
    summary.rowsScanned += 1;

    const counters = {
      aliasReplacements: 0,
      duplicateRemovals: 0,
      doseResets: 0,
    };

    const currentStore = isRecord(row.data) ? row.data : {};
    const nextStore = normalizeStore(currentStore, canonicalByAlias, doseDefaults, counters);

    const changed = JSON.stringify(currentStore) !== JSON.stringify(nextStore);

    summary.aliasReplacements += counters.aliasReplacements;
    summary.duplicateRemovals += counters.duplicateRemovals;
    summary.doseResets += counters.doseResets;

    if (!changed) {
      continue;
    }

    summary.rowsChanged += 1;

    if (!apply) {
      console.log(`DRY-RUN changed user_id=${row.user_id}`);
      continue;
    }

    const { error } = await supabase
      .from('user_data')
      .update({ data: nextStore })
      .eq('user_id', row.user_id);

    if (error) {
      throw new Error(`Failed to update ${row.user_id}: ${error.message}`);
    }

    summary.rowsUpdated += 1;
    console.log(`Updated user_id=${row.user_id}`);
  }

  printSummary(summary);
}

const isMainModule =
  process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isMainModule) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}

export {
  canonicalizeDailyCheckIns,
  canonicalizeDailyDoseProgress,
  canonicalizeDoseSettings,
  canonicalizeIDs,
  canonicalizeInterventionArray,
  loadCatalogInterventions,
  mergeDoseDefaults,
  normalizeStore,
};
