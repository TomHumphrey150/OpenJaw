import process from 'node:process';
import path from 'node:path';
import { existsSync, writeFileSync } from 'node:fs';
import { createClient } from '@supabase/supabase-js';
import {
  buildPillarIntegrityReport,
  GraphData,
  isUnknownRecord,
  loadGraphFromPath,
  loadGraphFromUnknown,
  parseInterventionsCatalog,
  parsePlanningPolicyPillars,
} from './pillar-integrity-lib';

interface ParsedArgs {
  userID: string | null;
  reportOut: string | null;
  raw: boolean;
  pillar: string | null;
  strict: boolean;
}

interface ContentSourceSummary {
  source: 'user_content' | 'first_party_content';
  updatedAt: string | null;
  version: number | null;
}

interface ContentPayload {
  data: unknown;
  source: ContentSourceSummary;
}

const CANONICAL_GRAPH_PATHS = [
  'data/default-graph.json',
  'ios/Telocare/Telocare/Resources/Graph/default-graph.json',
];

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
  return {
    userID: getArg('user-id') ?? process.env.SUPABASE_DEBUG_USER_ID ?? null,
    reportOut: getArg('report-out'),
    raw: hasFlag('raw'),
    pillar: getArg('pillar'),
    strict: hasFlag('strict'),
  };
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const values = new Set<string>();
  for (const entry of value) {
    if (typeof entry !== 'string') {
      continue;
    }

    const trimmed = entry.trim();
    if (trimmed.length > 0) {
      values.add(trimmed);
    }
  }

  return [...values].sort((left, right) => left.localeCompare(right));
}

function resolveUserGraph(store: Record<string, unknown>): GraphData {
  const customDiagram = isUnknownRecord(store.customCausalDiagram) ? store.customCausalDiagram : null;
  if (customDiagram === null) {
    return { nodes: [], edges: [] };
  }

  if (isUnknownRecord(customDiagram.graphData)) {
    return loadGraphFromUnknown(customDiagram.graphData);
  }

  if (Array.isArray(customDiagram.nodes) || Array.isArray(customDiagram.edges)) {
    return loadGraphFromUnknown({
      nodes: customDiagram.nodes,
      edges: customDiagram.edges,
    });
  }

  return { nodes: [], edges: [] };
}

function printUsageAndExit(): never {
  console.error('Usage: npm run debug:pillar-integrity -- --user-id <uuid> [--pillar <pillar-id>] [--strict] [--report-out <path>] [--raw]');
  process.exit(1);
}

function printReport(report: ReturnType<typeof buildPillarIntegrityReport>, userUpdatedAt: string | null): void {
  console.log('Pillar Integrity Report');
  console.log(`User ID: ${report.userID}`);
  console.log(`user_data.updated_at: ${userUpdatedAt ?? '(missing)'}`);
  console.log(
    `Graph nodes ${report.userGraphNodeCount}/${report.canonicalGraphNodeCount} | edges ${report.userGraphEdgeCount}/${report.canonicalGraphEdgeCount}`,
  );
  console.log(`Interventions total: ${report.totalInterventionCount}`);
  console.log(`Active interventions: ${report.activeInterventionCount}`);

  if (report.requestedPillarFilter !== null) {
    console.log(`Pillar filter: ${report.requestedPillarFilter}`);
  }

  console.log('');

  for (const row of report.rows) {
    console.log(`${row.pillar.title} (${row.pillar.id})`);
    console.log(`  interventions: ${row.interventions.length}`);
    console.log(`  active interventions: ${row.activeInterventions.length}`);
    console.log(`  graph nodes from interventions: ${row.nodeIDs.length}`);
    console.log(`  missing node IDs in user graph: ${row.missingNodeIDs.length}`);
    console.log(`  missing canonical edges in user graph: ${row.missingCanonicalEdgeSignatures.length}`);
    console.log(`  connectivity edge touches: ${row.connectivity.edgeTouchCount}`);
    console.log(`  disconnected node IDs: ${row.connectivity.disconnectedNodeIDs.length}`);
    console.log(`  external connections: ${row.connectivity.connectedToOutsideNodeCount}`);

    if (row.missingNodeIDs.length > 0) {
      console.log(`  missing node list: ${row.missingNodeIDs.join(', ')}`);
    }

    if (row.missingCanonicalEdgeSignatures.length > 0) {
      console.log(`  missing edge signatures: ${row.missingCanonicalEdgeSignatures.join(', ')}`);
    }

    if (row.connectivity.disconnectedNodeIDs.length > 0) {
      console.log(`  disconnected node list: ${row.connectivity.disconnectedNodeIDs.join(', ')}`);
    }

    console.log('');
  }

  console.log(`Overall missing node IDs: ${report.overallMissingNodeIDs.length}`);
  if (report.overallMissingNodeIDs.length > 0) {
    console.log(`  ${report.overallMissingNodeIDs.join(', ')}`);
  }

  console.log(`Overall missing canonical edge signatures: ${report.overallMissingCanonicalEdgeSignatures.length}`);
  if (report.overallMissingCanonicalEdgeSignatures.length > 0) {
    console.log(`  ${report.overallMissingCanonicalEdgeSignatures.join(', ')}`);
  }
}

function shouldFailStrict(report: ReturnType<typeof buildPillarIntegrityReport>): boolean {
  return report.rows.some((row) => {
    return (
      row.missingNodeIDs.length > 0
      || row.missingCanonicalEdgeSignatures.length > 0
      || row.connectivity.disconnectedNodeIDs.length > 0
    );
  });
}

async function run(): Promise<void> {
  const args = parseArgs();
  if (args.userID === null) {
    printUsageAndExit();
  }

  const supabaseURL = requiredEnv('SUPABASE_URL');
  const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');

  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const fetchContentData = async (
    userID: string,
    contentType: string,
    contentKey: string,
  ): Promise<ContentPayload | null> => {
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
      return {
        data: userQuery.data.data,
        source: {
          source: 'user_content',
          updatedAt: userQuery.data.updated_at,
          version: userQuery.data.version,
        },
      };
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
      return {
        data: firstPartyQuery.data.data,
        source: {
          source: 'first_party_content',
          updatedAt: firstPartyQuery.data.updated_at,
          version: firstPartyQuery.data.version,
        },
      };
    }

    return null;
  };

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

  const interventionsCatalog = await fetchContentData(args.userID, 'inputs', 'interventions_catalog');
  if (interventionsCatalog === null) {
    throw new Error('Missing interventions catalog row (inputs/interventions_catalog)');
  }

  const planningPolicy = await fetchContentData(args.userID, 'planning', 'planner_policy_v1');
  if (planningPolicy === null) {
    throw new Error('Missing planning policy row (planning/planner_policy_v1)');
  }

  const userStore = isUnknownRecord(userRowQuery.data.data) ? userRowQuery.data.data : {};
  const activeInterventionIDs = readStringArray(userStore.activeInterventions);
  const userGraph = resolveUserGraph(userStore);

  const canonicalGraphPath = CANONICAL_GRAPH_PATHS
    .map((entry) => path.resolve(process.cwd(), entry))
    .find((entry) => existsSync(entry))
    ?? path.resolve(process.cwd(), CANONICAL_GRAPH_PATHS[0]);
  const canonicalGraph = loadGraphFromPath(canonicalGraphPath);

  const report = buildPillarIntegrityReport({
    userID: args.userID,
    interventions: parseInterventionsCatalog(interventionsCatalog.data),
    activeInterventionIDs,
    userGraph,
    canonicalGraph,
    policyPillars: parsePlanningPolicyPillars(planningPolicy.data),
    pillarFilter: args.pillar,
  });

  printReport(report, userRowQuery.data.updated_at);

  const envelope = {
    report,
    sources: {
      interventionsCatalog: interventionsCatalog.source,
      planningPolicy: planningPolicy.source,
      canonicalGraphPath,
      userDataUpdatedAt: userRowQuery.data.updated_at,
    },
  };

  if (args.reportOut !== null) {
    const outputPath = path.isAbsolute(args.reportOut)
      ? args.reportOut
      : path.resolve(process.cwd(), args.reportOut);
    writeFileSync(outputPath, JSON.stringify(envelope, null, 2));
    console.log('');
    console.log(`Wrote report: ${outputPath}`);
  }

  if (args.raw) {
    console.log('');
    console.log(JSON.stringify(envelope, null, 2));
  }

  if (args.strict && shouldFailStrict(report)) {
    process.exit(2);
  }
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
