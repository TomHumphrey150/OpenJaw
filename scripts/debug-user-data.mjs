#!/usr/bin/env node

import process from 'node:process';
import { createClient } from '@supabase/supabase-js';

const EFFECTIVENESS_WEIGHTS = {
  untested: 0.5,
  ineffective: 0.1,
  modest: 0.4,
  effective: 0.75,
  highly_effective: 1.0,
};

function pad2(value) {
  return String(value).padStart(2, '0');
}

function utcDateKey(date) {
  return date.toISOString().split('T')[0];
}

function localDateKey(date) {
  return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}`;
}

function rollingKeys(days, keyFn) {
  const keys = [];
  const now = new Date();
  for (let i = 0; i < days; i += 1) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    keys.push(keyFn(d));
  }
  return keys;
}

function getArg(name) {
  const needle = `--${name}`;
  const idx = process.argv.indexOf(needle);
  if (idx < 0) return null;
  const value = process.argv[idx + 1];
  if (!value || value.startsWith('--')) return null;
  return value;
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function countDaysActive(dailyCheckIns, windowKeys) {
  const counts = new Map();
  windowKeys.forEach((key) => {
    const ids = Array.isArray(dailyCheckIns[key]) ? dailyCheckIns[key] : [];
    const deduped = new Set(ids);
    deduped.forEach((id) => {
      counts.set(id, (counts.get(id) || 0) + 1);
    });
  });
  return counts;
}

function makeRatingMap(store) {
  const map = new Map();
  const ratings = Array.isArray(store?.interventionRatings) ? store.interventionRatings : [];
  ratings.forEach((entry) => {
    if (!entry || typeof entry !== 'object') return;
    const id = entry.interventionId;
    if (!id) return;
    map.set(id, entry.effectiveness || 'untested');
  });
  return map;
}

function summarizeRecentKeys(dailyCheckIns, limit) {
  const keys = Object.keys(dailyCheckIns).sort((a, b) => b.localeCompare(a)).slice(0, limit);
  return keys.map((key) => {
    const value = dailyCheckIns[key];

    if (Array.isArray(value)) {
      return { key, count: new Set(value).size };
    }

    if (value && typeof value === 'object') {
      return { key, count: Object.keys(value).length };
    }

    return { key, count: 0 };
  });
}

function printTable(rows, maxRows = 25) {
  if (rows.length === 0) {
    console.log('  (none)');
    return;
  }
  const visible = rows.slice(0, maxRows);
  visible.forEach((row) => {
    console.log(
      `  ${row.id} | rating=${row.effectiveness} | utc=${row.utcDays}/7 (${Math.round(row.utcStrength * 100)}%) | local=${row.localDays}/7 (${Math.round(row.localStrength * 100)}%)`
    );
  });
  if (rows.length > visible.length) {
    console.log(`  ... ${rows.length - visible.length} more`);
  }
}

function printUsageAndExit() {
  console.error('Usage:');
  console.error('  npm run debug:user-data -- --list-users [--limit 20] [--raw]');
  console.error('  npm run debug:user-data -- --user-id <uuid> [--window-days 7] [--raw]');
  process.exit(1);
}

const supabaseUrl = process.env.SUPABASE_URL || 'https://aocndwnnkffumisprifx.supabase.co';
const supabaseSecretKey =
  process.env.SUPABASE_SECRET_KEY ||
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_SECRET;
const listUsers = hasFlag('list-users');
const limitRaw = getArg('limit') || process.env.SUPABASE_DEBUG_LIST_LIMIT || '20';
const limit = Number(limitRaw);
const userId = getArg('user-id') || process.env.SUPABASE_DEBUG_USER_ID || process.env.SUPABASE_USER_ID;
const raw = hasFlag('raw');
const windowDaysRaw = getArg('window-days') || process.env.SUPABASE_DEBUG_WINDOW_DAYS || '7';
const windowDays = Number(windowDaysRaw);

if (!supabaseSecretKey) {
  console.error('Missing SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY).');
  process.exit(1);
}

if (!listUsers && !userId) {
  printUsageAndExit();
}

if (!Number.isFinite(limit) || limit <= 0 || limit > 500) {
  console.error(`Invalid --limit value: "${limitRaw}". Use a number from 1 to 500.`);
  process.exit(1);
}

if (!Number.isFinite(windowDays) || windowDays <= 0 || windowDays > 365) {
  console.error(`Invalid --window-days value: "${windowDaysRaw}". Use a number from 1 to 365.`);
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseSecretKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

if (listUsers) {
  const { data: rows, error: listError } = await supabase
    .from('user_data')
    .select('user_id, updated_at')
    .order('updated_at', { ascending: false })
    .limit(limit);

  if (listError) {
    console.error(`Supabase query failed: ${listError.message}`);
    process.exit(1);
  }

  const safeRows = Array.isArray(rows) ? rows : [];
  console.log(`Recent users from public.user_data (limit ${limit})`);
  if (safeRows.length === 0) {
    console.log('  (none)');
  } else {
    safeRows.forEach((row, idx) => {
      console.log(`  ${idx + 1}. ${row.user_id} | updated_at=${row.updated_at || '(missing)'}`);
    });
  }

  if (raw) {
    console.log('');
    console.log('Raw rows JSON');
    console.log(JSON.stringify(safeRows, null, 2));
  }
  process.exit(0);
}

const { data: row, error } = await supabase
  .from('user_data')
  .select('user_id, data, updated_at')
  .eq('user_id', userId)
  .maybeSingle();

if (error) {
  console.error(`Supabase query failed: ${error.message}`);
  process.exit(1);
}

if (!row) {
  console.log(`No row found in public.user_data for user_id=${userId}`);
  process.exit(0);
}

const store = row.data && typeof row.data === 'object' ? row.data : {};
const dailyCheckIns =
  store.dailyCheckIns && typeof store.dailyCheckIns === 'object' && !Array.isArray(store.dailyCheckIns)
    ? store.dailyCheckIns
    : {};
const dailyDoseProgress =
  store.dailyDoseProgress && typeof store.dailyDoseProgress === 'object' && !Array.isArray(store.dailyDoseProgress)
    ? store.dailyDoseProgress
    : {};
const interventionDoseSettings =
  store.interventionDoseSettings && typeof store.interventionDoseSettings === 'object' && !Array.isArray(store.interventionDoseSettings)
    ? store.interventionDoseSettings
    : {};
const appleHealthConnections =
  store.appleHealthConnections && typeof store.appleHealthConnections === 'object' && !Array.isArray(store.appleHealthConnections)
    ? store.appleHealthConnections
    : {};
const allKeysAsc = Object.keys(dailyCheckIns).sort((a, b) => a.localeCompare(b));
const doseKeysAsc = Object.keys(dailyDoseProgress).sort((a, b) => a.localeCompare(b));

const now = new Date();
const todayUtc = utcDateKey(now);
const todayLocal = localDateKey(now);
const futureUtc = allKeysAsc.filter((k) => k > todayUtc);
const futureLocal = allKeysAsc.filter((k) => k > todayLocal);

const utcWindowKeys = rollingKeys(windowDays, utcDateKey);
const localWindowKeys = rollingKeys(windowDays, localDateKey);
const utcCounts = countDaysActive(dailyCheckIns, utcWindowKeys);
const localCounts = countDaysActive(dailyCheckIns, localWindowKeys);
const ratingMap = makeRatingMap(store);

const interventionIds = new Set([...utcCounts.keys(), ...localCounts.keys()]);
const strengthRows = [...interventionIds]
  .map((id) => {
    const effectiveness = ratingMap.get(id) || 'untested';
    const weight = EFFECTIVENESS_WEIGHTS[effectiveness] ?? EFFECTIVENESS_WEIGHTS.untested;
    const utcDays = utcCounts.get(id) || 0;
    const localDays = localCounts.get(id) || 0;
    return {
      id,
      effectiveness,
      utcDays,
      localDays,
      utcStrength: weight * (utcDays / windowDays),
      localStrength: weight * (localDays / windowDays),
    };
  })
  .sort((a, b) => {
    if (b.utcStrength !== a.utcStrength) return b.utcStrength - a.utcStrength;
    if (b.utcDays !== a.utcDays) return b.utcDays - a.utcDays;
    return a.id.localeCompare(b.id);
  });

const skewedRows = strengthRows
  .filter((r) => r.utcDays !== r.localDays)
  .sort((a, b) => Math.abs(b.utcDays - b.localDays) - Math.abs(a.utcDays - a.localDays));

const ratings = Array.isArray(store.interventionRatings) ? store.interventionRatings : [];
const active = Array.isArray(store.activeInterventions) ? store.activeInterventions : [];
const hidden = Array.isArray(store.hiddenInterventions) ? store.hiddenInterventions : [];
const notes = Array.isArray(store.notes) ? store.notes : [];
const studies = Array.isArray(store.personalStudies) ? store.personalStudies : [];
const experiments = Array.isArray(store.experiments) ? store.experiments : [];

console.log('Read-only Supabase user_data diagnostics');
console.log(`User ID: ${row.user_id}`);
console.log(`Row updated_at: ${row.updated_at || '(missing)'}`);
console.log(`Now (UTC): ${now.toISOString()}`);
console.log(`Today key (UTC logic): ${todayUtc}`);
console.log(`Today key (local logic): ${todayLocal}`);
console.log('');

console.log('Store counts');
console.log(`  dailyCheckIns keys: ${allKeysAsc.length}`);
console.log(`  dailyDoseProgress keys: ${doseKeysAsc.length}`);
console.log(`  interventionDoseSettings: ${Object.keys(interventionDoseSettings).length}`);
console.log(`  appleHealthConnections: ${Object.keys(appleHealthConnections).length}`);
console.log(`  interventionRatings: ${ratings.length}`);
console.log(`  activeInterventions: ${active.length}`);
console.log(`  hiddenInterventions: ${hidden.length}`);
console.log(`  notes: ${notes.length}`);
console.log(`  personalStudies: ${studies.length}`);
console.log(`  experiments: ${experiments.length}`);
console.log('');

const appleHealthEntries = Object.entries(appleHealthConnections);
const connectedAppleHealth = appleHealthEntries.filter(([, value]) => value?.isConnected === true);
console.log('Apple Health connections');
if (appleHealthEntries.length === 0) {
  console.log('  (none)');
} else {
  connectedAppleHealth.forEach(([interventionId, value]) => {
    console.log(
      `  ${interventionId} | connected=true | status=${value?.lastSyncStatus || 'unknown'} | lastSyncAt=${value?.lastSyncAt || '(never)'}`
    );
  });
  const disconnected = appleHealthEntries.length - connectedAppleHealth.length;
  if (disconnected > 0) {
    console.log(`  disconnected entries: ${disconnected}`);
  }
}
console.log('');

console.log(`Recent check-in dates (latest ${Math.min(21, allKeysAsc.length)})`);
summarizeRecentKeys(dailyCheckIns, 21).forEach((item) => {
  console.log(`  ${item.key}: ${item.count} interventions`);
});
if (allKeysAsc.length === 0) {
  console.log('  (none)');
}
console.log('');

console.log(`Recent dose dates (latest ${Math.min(21, doseKeysAsc.length)})`);
summarizeRecentKeys(dailyDoseProgress, 21).forEach((item) => {
  console.log(`  ${item.key}: ${item.count} dose-tracked interventions`);
});
if (doseKeysAsc.length === 0) {
  console.log('  (none)');
}
console.log('');

console.log(`Future-dated keys vs UTC today (${todayUtc}): ${futureUtc.length}`);
if (futureUtc.length > 0) {
  futureUtc.slice(0, 20).forEach((k) => console.log(`  ${k}`));
  if (futureUtc.length > 20) console.log(`  ... ${futureUtc.length - 20} more`);
}
console.log(`Future-dated keys vs local today (${todayLocal}): ${futureLocal.length}`);
if (futureLocal.length > 0) {
  futureLocal.slice(0, 20).forEach((k) => console.log(`  ${k}`));
  if (futureLocal.length > 20) console.log(`  ... ${futureLocal.length - 20} more`);
}
console.log('');

console.log(`${windowDays}-day window keys (UTC logic)`);
console.log(`  ${utcWindowKeys.join(', ')}`);
console.log(`${windowDays}-day window keys (local logic)`);
console.log(`  ${localWindowKeys.join(', ')}`);
console.log('');

console.log(`Top intervention strengths in last ${windowDays} days`);
printTable(strengthRows, 30);
console.log('');

console.log('UTC vs local day-count differences');
printTable(skewedRows, 30);
console.log('');

if (raw) {
  console.log('Raw row JSON');
  console.log(JSON.stringify(row, null, 2));
}
