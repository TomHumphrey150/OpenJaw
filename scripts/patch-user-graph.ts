import process from 'node:process';
import path from 'node:path';
import { createClient } from '@supabase/supabase-js';
import {
  GraphData,
  isUnknownRecord,
  loadGraphFromPath,
  loadGraphFromUnknown,
} from './pillar-integrity-lib';
import {
  AUTHORIZED_USER_ID,
  mergeUserGraphWithCanonicalTargets,
} from './user-graph-patch-lib';

interface ParsedArgs {
  userID: string | null;
  write: boolean;
  dryRun: boolean;
}

interface ResolvedUserGraph {
  graph: GraphData;
  hadWrappedGraphData: boolean;
}

function requiredEnv(...names: string[]): string {
  for (const name of names) {
    const value = process.env[name];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }

  throw new Error(`Missing environment variable. Provide one of: ${names.join(', ')}`);
}

function getArg(name: string): string | null {
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

function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

function parseArgs(): ParsedArgs {
  const write = hasFlag('write');
  const dryRunFlag = hasFlag('dry-run');

  if (write && dryRunFlag) {
    throw new Error('Choose either --dry-run or --write, not both.');
  }

  return {
    userID: getArg('user-id') ?? process.env.SUPABASE_DEBUG_USER_ID ?? null,
    write,
    dryRun: dryRunFlag || !write,
  };
}

function ensureRecord(parent: Record<string, unknown>, key: string): Record<string, unknown> {
  const current = parent[key];
  if (isUnknownRecord(current)) {
    return current;
  }

  const created: Record<string, unknown> = {};
  parent[key] = created;
  return created;
}

function resolveUserGraph(store: Record<string, unknown>): ResolvedUserGraph {
  const customDiagram = isUnknownRecord(store.customCausalDiagram) ? store.customCausalDiagram : null;
  if (customDiagram === null) {
    return {
      graph: { nodes: [], edges: [] },
      hadWrappedGraphData: false,
    };
  }

  if (isUnknownRecord(customDiagram.graphData)) {
    return {
      graph: loadGraphFromUnknown(customDiagram.graphData),
      hadWrappedGraphData: true,
    };
  }

  if (Array.isArray(customDiagram.nodes) || Array.isArray(customDiagram.edges)) {
    return {
      graph: loadGraphFromUnknown({
        nodes: customDiagram.nodes,
        edges: customDiagram.edges,
      }),
      hadWrappedGraphData: false,
    };
  }

  return {
    graph: { nodes: [], edges: [] },
    hadWrappedGraphData: false,
  };
}

function printUsageAndExit(): never {
  console.error('Usage: npm run patch:user-graph -- --user-id <uuid> [--dry-run|--write]');
  process.exit(1);
}

async function run(): Promise<void> {
  const args = parseArgs();
  if (args.userID === null) {
    printUsageAndExit();
  }

  if (args.userID !== AUTHORIZED_USER_ID) {
    throw new Error(`Patch script is restricted to ${AUTHORIZED_USER_ID}. Refusing user_id=${args.userID}.`);
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
    .eq('user_id', args.userID)
    .maybeSingle();

  if (userRowQuery.error) {
    throw new Error(`user_data query failed: ${userRowQuery.error.message}`);
  }

  if (!userRowQuery.data) {
    throw new Error(`No user_data row found for user_id=${args.userID}`);
  }

  const currentStore = isUnknownRecord(userRowQuery.data.data) ? userRowQuery.data.data : {};
  const resolvedGraph = resolveUserGraph(currentStore);
  const currentGraph = resolvedGraph.graph;

  const canonicalGraphPath = path.resolve(
    process.cwd(),
    'ios/Telocare/Telocare/Resources/Graph/default-graph.json',
  );
  const canonicalGraph = loadGraphFromPath(canonicalGraphPath);

  const mergeResult = mergeUserGraphWithCanonicalTargets(currentGraph, canonicalGraph);

  const nextStore = structuredClone(currentStore);
  const nextCustomDiagram = ensureRecord(nextStore, 'customCausalDiagram');
  nextCustomDiagram.graphData = mergeResult.nextGraph;
  if (mergeResult.changed) {
    nextCustomDiagram.lastModified = new Date().toISOString();
  }

  const changed = mergeResult.changed || !resolvedGraph.hadWrappedGraphData;

  console.log(`Mode: ${args.write ? 'write' : 'dry-run'}`);
  console.log(`User ID: ${args.userID}`);
  console.log(`user_data.updated_at: ${userRowQuery.data.updated_at ?? '(missing)'}`);
  console.log(`Current graph nodes: ${currentGraph.nodes.length}`);
  console.log(`Current graph edges: ${currentGraph.edges.length}`);
  console.log(`Required canonical nodes: ${mergeResult.requiredNodeIDs.length}`);
  console.log(`Required canonical edges: ${mergeResult.requiredEdgeSignatures.length}`);
  console.log(`Added nodes: ${mergeResult.addedNodeIDs.length}`);
  console.log(`Added edges: ${mergeResult.addedEdgeSignatures.length}`);

  if (mergeResult.addedNodeIDs.length > 0) {
    console.log(`  ${mergeResult.addedNodeIDs.join(', ')}`);
  }

  if (mergeResult.addedEdgeSignatures.length > 0) {
    console.log(`  ${mergeResult.addedEdgeSignatures.join(', ')}`);
  }

  if (mergeResult.missingCanonicalNodeIDs.length > 0) {
    console.log(`Missing canonical patch nodes: ${mergeResult.missingCanonicalNodeIDs.join(', ')}`);
  }

  if (mergeResult.missingCanonicalEdgeRules.length > 0) {
    console.log(`Missing canonical patch edge rules: ${mergeResult.missingCanonicalEdgeRules.join(', ')}`);
  }

  console.log(`Data changed: ${changed ? 'yes' : 'no'}`);

  if (args.dryRun) {
    return;
  }

  if (!changed) {
    console.log('No update required.');
    return;
  }

  const updateQuery = await supabase
    .from('user_data')
    .update({ data: nextStore })
    .eq('user_id', args.userID);

  if (updateQuery.error) {
    throw new Error(`Failed to update user_data: ${updateQuery.error.message}`);
  }

  console.log('Update applied.');
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
