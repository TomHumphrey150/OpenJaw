import process from 'node:process';
import path from 'node:path';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import {
  collectPillarIDs,
  filterAuditToPillar,
  parseUserGraphAuditReportSubset,
} from './user-pillar-audit-lib';

interface ParsedArgs {
  userID: string | null;
  pillarID: string | null;
  reportOut: string | null;
  raw: boolean;
  pretty: boolean;
}

function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
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

function parsePrettyOption(): boolean {
  const rawValue = getArg('pretty');
  if (rawValue === null) {
    return !hasFlag('no-pretty');
  }

  const normalized = rawValue.trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') {
    return true;
  }
  if (normalized === 'false' || normalized === '0' || normalized === 'no') {
    return false;
  }

  throw new Error(`Invalid --pretty value: ${rawValue}. Use true/false.`);
}

function parseArgs(): ParsedArgs {
  return {
    userID: getArg('user-id') ?? process.env.SUPABASE_DEBUG_USER_ID ?? null,
    pillarID: getArg('pillar'),
    reportOut: getArg('report-out'),
    raw: hasFlag('raw'),
    pretty: parsePrettyOption(),
  };
}

function printUsageAndExit(): never {
  console.error(
    'Usage: npm run debug:user-pillar-audit -- --user-id <uuid> --pillar <pillar-id> [--report-out <path>] [--raw] [--pretty true|false]',
  );
  process.exit(1);
}

function sanitizeFileSegment(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, '-');
  if (normalized.length === 0) {
    return 'pillar';
  }
  return normalized.replace(/^-+|-+$/g, '');
}

function buildDefaultOutputPath(userID: string, pillarID: string): string {
  const timestamp = new Date().toISOString().replace(/[:]/g, '-');
  return path.resolve(
    process.cwd(),
    'artifacts',
    'user-pillar-audit',
    `${sanitizeFileSegment(userID)}-${sanitizeFileSegment(pillarID)}-${timestamp}.json`,
  );
}

function runFullAuditToPath(userID: string, outputPath: string): void {
  const scriptPath = path.resolve(process.cwd(), 'scripts/debug-user-graph-audit.ts');
  const result = spawnSync(
    process.execPath,
    [
      '-r',
      'ts-node/register',
      scriptPath,
      '--user-id',
      userID,
      '--report-out',
      outputPath,
      '--pretty',
      'false',
    ],
    {
      cwd: process.cwd(),
      env: process.env,
      encoding: 'utf8',
    },
  );

  if (result.status === 0) {
    return;
  }

  const stderr = typeof result.stderr === 'string' ? result.stderr.trim() : '';
  const stdout = typeof result.stdout === 'string' ? result.stdout.trim() : '';
  const detail = stderr.length > 0 ? stderr : stdout;
  if (detail.length > 0) {
    throw new Error(`Full audit command failed: ${detail}`);
  }
  throw new Error('Full audit command failed without stderr/stdout output.');
}

function printSummary(
  userID: string,
  pillarID: string,
  outputPath: string,
  availablePillarIDs: string[],
  report: ReturnType<typeof filterAuditToPillar>,
): void {
  console.log('User Pillar Audit Report');
  console.log(`User ID: ${userID}`);
  console.log(`Pillar ID: ${pillarID}`);
  console.log(`Available pillars in source audit: ${availablePillarIDs.join(', ') || '(none detected)'}`);
  console.log(`Graph nodes: ${report.summary.graph_node_count}`);
  console.log(`Graph edges: ${report.summary.graph_edge_count}`);
  console.log(`Habits linked/unlinked: ${report.summary.habits_linked_count}/${report.summary.habits_unlinked_count}`);
  console.log(`Habits with missing graphEdgeIds: ${report.summary.habits_missing_edge_links_count}`);
  console.log(
    `Outcome questions linked/unlinked: ${report.summary.outcome_questions_linked_count}/${report.summary.outcome_questions_unlinked_count}`,
  );
  console.log(`Missing source nodes: ${report.summary.missing_source_node_count}`);
  console.log(`Missing source edges: ${report.summary.missing_source_edge_count}`);
  console.log(`Output: ${outputPath}`);
}

async function run(): Promise<void> {
  const args = parseArgs();
  if (args.userID === null || args.pillarID === null) {
    printUsageAndExit();
  }

  const tempDirectory = mkdtempSync(path.join(tmpdir(), 'openjaw-user-audit-'));
  const tempAuditPath = path.join(tempDirectory, 'full-audit.json');

  try {
    runFullAuditToPath(args.userID, tempAuditPath);

    const auditRawText = readFileSync(tempAuditPath, 'utf8');
    const auditJson: unknown = JSON.parse(auditRawText);
    const audit = parseUserGraphAuditReportSubset(auditJson);

    const availablePillars = collectPillarIDs(audit);
    const pillarReport = filterAuditToPillar(audit, args.pillarID);

    const outputPath = args.reportOut === null
      ? buildDefaultOutputPath(args.userID, args.pillarID)
      : path.isAbsolute(args.reportOut)
        ? args.reportOut
        : path.resolve(process.cwd(), args.reportOut);

    mkdirSync(path.dirname(outputPath), { recursive: true });
    const spacing = args.pretty ? 2 : 0;
    writeFileSync(outputPath, JSON.stringify(pillarReport, null, spacing));

    printSummary(args.userID, args.pillarID, outputPath, availablePillars, pillarReport);

    if (args.raw) {
      console.log('');
      console.log(JSON.stringify(pillarReport, null, spacing));
    }
  } finally {
    rmSync(tempDirectory, { recursive: true, force: true });
  }
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
