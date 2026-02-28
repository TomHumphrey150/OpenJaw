#!/usr/bin/env node

import process from 'node:process';
import path from 'node:path';
import { writeFileSync, readFileSync, rmSync, mkdirSync, existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createClient } from '@supabase/supabase-js';

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

function printUsageAndExit() {
  console.error('Usage:');
  console.error('  npm run debug:graph-clusters -- [--user-id <uuid>] [--max-depth <n>] [--report-out <path>] [--list-users] [--limit <n>]');
  process.exit(1);
}

function printClusterTree(clusters, depth = 0) {
  const prefix = '  '.repeat(depth);
  for (const cluster of clusters) {
    const names = Array.isArray(cluster.memberNames) ? cluster.memberNames : [];
    const preview = names.slice(0, 4).join(', ');
    const more = names.length - Math.min(names.length, 4);
    const suffix = more > 0 ? ` (+${more} more)` : '';
    console.log(`${prefix}- ${cluster.title} | members=${cluster.memberCount}${preview ? ` | ${preview}${suffix}` : ''}`);
    printClusterTree(cluster.children || [], depth + 1);
  }
}

function previewList(values, limit = 5) {
  const list = Array.isArray(values) ? values : [];
  const head = list.slice(0, limit);
  const suffix = list.length > limit ? ` (+${list.length - limit} more)` : '';
  return `${head.join(', ')}${suffix}`;
}

const repoRoot = process.cwd();
const iosDirectory = path.join(repoRoot, 'ios', 'Telocare');
const inputPath = resolvePathArg('input-path', '/tmp/telocare-cluster-user-row.json');
const catalogPath = resolvePathArg('catalog-path', '/tmp/telocare-cluster-interventions-catalog.json');
const configPath = resolvePathArg('config-path', '/tmp/telocare-cluster-config.json');
const runtimeReportPath = '/tmp/telocare-cluster-report.json';
const requestedReportPath = resolvePathArg('report-out', runtimeReportPath);
const maxDepthRaw = getArg('max-depth') || '4';
const maxDepth = Number(maxDepthRaw);
const listUsers = hasFlag('list-users');
const limitRaw = getArg('limit') || '10';
const limit = Number(limitRaw);

function resolvePathArg(argName, defaultPath) {
  const rawPath = getArg(argName);
  if (!rawPath) {
    return defaultPath;
  }
  return path.isAbsolute(rawPath) ? rawPath : path.resolve(repoRoot, rawPath);
}

if (!Number.isFinite(maxDepth) || maxDepth < 1 || maxDepth > 12) {
  console.error(`Invalid --max-depth value: ${maxDepthRaw}. Use 1..12.`);
  process.exit(1);
}

if (!Number.isFinite(limit) || limit < 1 || limit > 200) {
  console.error(`Invalid --limit value: ${limitRaw}. Use 1..200.`);
  process.exit(1);
}

const supabaseUrl = process.env.SUPABASE_URL || 'https://aocndwnnkffumisprifx.supabase.co';
const supabaseSecretKey =
  process.env.SUPABASE_SECRET_KEY ||
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  process.env.SUPABASE_SECRET;

if (!supabaseSecretKey) {
  console.error('Missing SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY).');
  process.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseSecretKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

if (listUsers) {
  const { data, error } = await supabase
    .from('user_data')
    .select('user_id, updated_at')
    .order('updated_at', { ascending: false })
    .limit(limit);

  if (error) {
    console.error(`Supabase query failed: ${error.message}`);
    process.exit(1);
  }

  const rows = Array.isArray(data) ? data : [];
  console.log(`Recent users from public.user_data (limit ${limit})`);
  for (const [index, row] of rows.entries()) {
    console.log(`  ${index + 1}. ${row.user_id} | updated_at=${row.updated_at || '(missing)'}`);
  }
  process.exit(0);
}

const userId = getArg('user-id') || process.env.SUPABASE_DEBUG_USER_ID;
if (!userId) {
  printUsageAndExit();
}

const { data: userRow, error: userError } = await supabase
  .from('user_data')
  .select('user_id, updated_at, data')
  .eq('user_id', userId)
  .maybeSingle();

if (userError) {
  console.error(`Supabase user_data query failed: ${userError.message}`);
  process.exit(1);
}

if (!userRow) {
  console.error(`No user_data row found for user_id=${userId}`);
  process.exit(1);
}

const { data: catalogRow, error: catalogError } = await supabase
  .from('first_party_content')
  .select('content_key, updated_at, data')
  .eq('content_key', 'interventions_catalog')
  .order('updated_at', { ascending: false })
  .limit(1)
  .maybeSingle();

if (catalogError) {
  console.error(`Supabase first_party_content query failed: ${catalogError.message}`);
  process.exit(1);
}

if (!catalogRow) {
  console.error('No first_party_content row found for content_key=interventions_catalog');
  process.exit(1);
}

mkdirSync(path.dirname(inputPath), { recursive: true });
mkdirSync(path.dirname(catalogPath), { recursive: true });
mkdirSync(path.dirname(configPath), { recursive: true });
mkdirSync(path.dirname(runtimeReportPath), { recursive: true });
writeFileSync(inputPath, JSON.stringify(userRow, null, 2));
writeFileSync(catalogPath, JSON.stringify(catalogRow, null, 2));
writeFileSync(
  configPath,
  JSON.stringify(
    {
      inputPath,
      catalogPath,
      reportPath: runtimeReportPath,
      maxDepth,
    },
    null,
    2
  )
);

const xcodebuildArgs = [
  '-workspace',
  'Telocare.xcworkspace',
  '-scheme',
  'Telocare',
  '-destination',
  "platform=iOS Simulator,name=iPhone 17",
  '-only-testing:TelocareTests/GraphClusterCLITests',
  'test',
];

console.log(`Fetched user row to ${inputPath}`);
console.log(`Fetched interventions catalog to ${catalogPath}`);
console.log(`Wrote runner config to ${configPath}`);
console.log('Running Swift clustering logic via GraphClusterCLITests...');

const testRun = spawnSync('xcodebuild', xcodebuildArgs, {
  cwd: iosDirectory,
  stdio: 'inherit',
  env: {
    ...process.env,
    TELOCARE_CLUSTER_CONFIG_PATH: configPath,
  },
});

if (testRun.status !== 0) {
  rmSync(configPath, { force: true });
  process.exit(testRun.status ?? 1);
}

if (!existsSync(runtimeReportPath)) {
  rmSync(configPath, { force: true });
  console.error(`Swift cluster test did not emit a report file: ${runtimeReportPath}`);
  process.exit(1);
}

const report = JSON.parse(readFileSync(runtimeReportPath, 'utf8'));
let outputReportPath = runtimeReportPath;
if (requestedReportPath !== runtimeReportPath) {
  mkdirSync(path.dirname(requestedReportPath), { recursive: true });
  writeFileSync(requestedReportPath, JSON.stringify(report, null, 2));
  outputReportPath = requestedReportPath;
}
rmSync(configPath, { force: true });

console.log('');
console.log('Graph Cluster Report');
console.log(`User ID: ${report.userID}`);
console.log(`Row updated_at: ${report.rowUpdatedAt || '(missing)'}`);
console.log(`Graph version: ${report.graphVersion || '(missing)'}`);
console.log(`Nodes: ${report.graphNodeCount} | Edges: ${report.graphEdgeCount}`);
console.log(`Active inputs: ${report.activeInputCount}`);
console.log(`Top-level clusters: ${report.topLevelClusterCount}`);

if (Array.isArray(report.unresolvedActiveInputs) && report.unresolvedActiveInputs.length > 0) {
  console.log('Unresolved active inputs:');
  for (const item of report.unresolvedActiveInputs) {
    console.log(`  - ${item.inputID} (${item.reason}, source=${item.sourceNodeID})`);
  }
}

const habitMappings = Array.isArray(report.habitMappings) ? report.habitMappings : [];
const activeHabitMappings = habitMappings.filter((item) => item.isActive === true);
const habitsMissingSourceNode = activeHabitMappings.filter((item) => item.sourceNodeExists !== true);
const habitsWithoutAttachments = activeHabitMappings.filter((item) => (item.attachedEdgeIDs || []).length === 0);
const habitsWithoutClusterPaths = activeHabitMappings.filter((item) => (item.clusterPaths || []).length === 0);

console.log('');
console.log('Habit Graph Attachments');
console.log(`Total habits: ${habitMappings.length} | Active habits: ${activeHabitMappings.length}`);
console.log(`Active habits missing source node: ${habitsMissingSourceNode.length}`);
console.log(`Active habits with no attached cluster edges: ${habitsWithoutAttachments.length}`);
console.log(`Active habits with no cluster path: ${habitsWithoutClusterPaths.length}`);
if (habitsMissingSourceNode.length > 0) {
  console.log(`Missing source node IDs: ${previewList(habitsMissingSourceNode.map((item) => item.inputID))}`);
}
if (habitsWithoutAttachments.length > 0) {
  console.log(`No-attachment habits: ${previewList(habitsWithoutAttachments.map((item) => item.inputID))}`);
}

const outcomeQuestionMappings = Array.isArray(report.outcomeQuestionMappings) ? report.outcomeQuestionMappings : [];
const questionsMissingNodes = outcomeQuestionMappings.filter((item) => (item.missingNodeIDs || []).length > 0);
const questionsMissingEdges = outcomeQuestionMappings.filter((item) => (item.missingEdgeIDs || []).length > 0);
const questionsWithoutClusterPaths = outcomeQuestionMappings.filter((item) => (item.clusterPaths || []).length === 0);

console.log('');
console.log('Outcome Question Graph Attachments');
console.log(`Questions: ${outcomeQuestionMappings.length}`);
console.log(`Questions missing source nodes: ${questionsMissingNodes.length}`);
console.log(`Questions missing source edges: ${questionsMissingEdges.length}`);
console.log(`Questions with no cluster path: ${questionsWithoutClusterPaths.length}`);

const edgeCoverage = report.edgeCoverage || null;
if (edgeCoverage) {
  console.log('');
  console.log('Cluster Tree Edge Coverage');
  console.log(`Referenced edges: ${edgeCoverage.referencedEdgeCount}`);
  console.log(`Covered by cluster tree: ${edgeCoverage.coveredEdgeCount}`);
  console.log(`Uncovered edges: ${edgeCoverage.uncoveredEdgeCount}`);
  if (Array.isArray(edgeCoverage.uncoveredEdgeIDs) && edgeCoverage.uncoveredEdgeIDs.length > 0) {
    console.log(`Uncovered edge IDs: ${previewList(edgeCoverage.uncoveredEdgeIDs)}`);
  }
}

console.log('');
printClusterTree(report.topLevelClusters || []);
console.log('');
console.log(`Full report: ${outputReportPath}`);
