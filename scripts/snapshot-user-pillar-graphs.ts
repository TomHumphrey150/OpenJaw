import process from 'node:process';
import path from 'node:path';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { chromium, Page } from 'playwright';
import {
  collectPillarIDs,
  filterAuditToPillar,
  parseUserGraphAuditReportSubset,
  toRenderableGraphData,
} from './user-pillar-audit-lib';

interface ParsedArgs {
  userID: string | null;
  pillarIDs: string[];
  outDir: string;
  includeIsolated: boolean;
  compactTiers: boolean;
  showInterventions: boolean;
  showFeedbackEdges: boolean;
  showProtectiveEdges: boolean;
  devicePreset: DevicePreset | null;
  width: number;
  height: number;
  scale: number;
  pretty: boolean;
  raw: boolean;
}

interface DevicePreset {
  id: string;
  widthPoints: number;
  heightPoints: number;
  statusBarPoints: number;
  tabBarPoints: number;
  defaultScale: number;
}

interface PillarSnapshotRow {
  pillar_id: string;
  graph_node_count: number;
  graph_edge_count: number;
  rendered_graph_node_count: number;
  rendered_graph_edge_count: number;
  removed_isolated_node_count: number;
  habits_total: number;
  outcome_questions_total: number;
  screenshot_path: string;
}

interface SnapshotManifest {
  generated_at: string;
  user_id: string;
  source_audit_version: string;
  source_generated_at: string;
  output_directory: string;
  display_flags: {
    show_feedback_edges: boolean;
    show_protective_edges: boolean;
    show_intervention_nodes: boolean;
    include_isolated_nodes: boolean;
    compact_tiers: boolean;
  };
  viewport: {
    width: number;
    height: number;
    scale: number;
    device: string | null;
  };
  pillars: PillarSnapshotRow[];
}

const DEVICE_PRESETS: DevicePreset[] = [
  {
    id: 'iPhone-16',
    widthPoints: 393,
    heightPoints: 852,
    statusBarPoints: 54,
    tabBarPoints: 49,
    defaultScale: 3,
  },
  {
    id: 'iPhone-16-Plus',
    widthPoints: 430,
    heightPoints: 932,
    statusBarPoints: 54,
    tabBarPoints: 49,
    defaultScale: 3,
  },
  {
    id: 'iPhone-16-Pro',
    widthPoints: 402,
    heightPoints: 874,
    statusBarPoints: 54,
    tabBarPoints: 49,
    defaultScale: 3,
  },
  {
    id: 'iPhone-16-Pro-Max',
    widthPoints: 440,
    heightPoints: 956,
    statusBarPoints: 54,
    tabBarPoints: 49,
    defaultScale: 3,
  },
];

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
    return true;
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

function parseIntegerArg(name: string, fallback: number): number {
  const raw = getArg(name);
  if (raw === null) {
    return fallback;
  }
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error(`Invalid --${name} value "${raw}". Provide a positive integer.`);
  }
  return parsed;
}

function parseScaleArg(fallback: number): number {
  const raw = getArg('scale');
  if (raw === null) {
    return fallback;
  }
  const parsed = Number.parseFloat(raw);
  if (!Number.isFinite(parsed) || parsed <= 0 || parsed > 4) {
    throw new Error(`Invalid --scale value "${raw}". Provide a number between 0 and 4.`);
  }
  return parsed;
}

function normalizeDeviceKey(value: string): string {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function resolveDevicePreset(rawDevice: string): DevicePreset {
  const normalized = normalizeDeviceKey(rawDevice);
  const matched = DEVICE_PRESETS.find((preset) => normalizeDeviceKey(preset.id) === normalized);
  if (matched === undefined) {
    const available = DEVICE_PRESETS.map((preset) => preset.id).join(', ');
    throw new Error(`Unsupported --device "${rawDevice}". Available presets: ${available}`);
  }
  return matched;
}

function parsePillarIDs(): string[] {
  const ids = new Set<string>();

  for (let index = 0; index < process.argv.length; index += 1) {
    if (process.argv[index] !== '--pillar') {
      continue;
    }
    const next = process.argv[index + 1];
    if (!next || next.startsWith('--')) {
      continue;
    }
    const segments = next.split(',').map((value) => value.trim()).filter((value) => value.length > 0);
    for (const segment of segments) {
      ids.add(segment);
    }
  }

  const listArg = getArg('pillars');
  if (listArg !== null) {
    const segments = listArg.split(',').map((value) => value.trim()).filter((value) => value.length > 0);
    for (const segment of segments) {
      ids.add(segment);
    }
  }

  return [...ids].sort((left, right) => left.localeCompare(right));
}

function parseArgs(): ParsedArgs {
  const userID = getArg('user-id') ?? process.env.SUPABASE_DEBUG_USER_ID ?? null;
  const pillarIDs = parsePillarIDs();
  const timestamp = new Date().toISOString().replace(/[:]/g, '-');
  const out = getArg('out');
  const outDir = out === null
    ? path.resolve(process.cwd(), 'artifacts', 'user-pillar-snapshots', `${userID ?? 'user'}-${timestamp}`)
    : path.isAbsolute(out)
      ? out
      : path.resolve(process.cwd(), out);

  const deviceArg = getArg('device');
  const devicePreset = deviceArg === null ? null : resolveDevicePreset(deviceArg);
  const defaultWidth = devicePreset?.widthPoints ?? 1170;
  const defaultHeight = devicePreset === null
    ? 1400
    : Math.max(1, devicePreset.heightPoints - devicePreset.statusBarPoints - devicePreset.tabBarPoints);
  const defaultScale = devicePreset?.defaultScale ?? 2;

  return {
    userID,
    pillarIDs,
    outDir,
    includeIsolated: hasFlag('include-isolated'),
    compactTiers: !hasFlag('no-compact-tiers'),
    showInterventions: hasFlag('show-interventions'),
    showFeedbackEdges: hasFlag('show-feedback'),
    showProtectiveEdges: hasFlag('show-protective'),
    devicePreset,
    width: parseIntegerArg('width', defaultWidth),
    height: parseIntegerArg('height', defaultHeight),
    scale: parseScaleArg(defaultScale),
    pretty: parsePrettyOption(),
    raw: hasFlag('raw'),
  };
}

function printUsageAndExit(): never {
  console.error(
    'Usage: npm run snapshot:user-pillar-graphs -- --user-id <uuid> [--pillar <pillar-id>] [--pillars <a,b,c>] [--out <path>] [--device <name>] [--include-isolated] [--no-compact-tiers] [--show-interventions] [--show-feedback] [--show-protective] [--width <px>] [--height <px>] [--scale <n>] [--raw]',
  );
  process.exit(1);
}

function sanitizeFileSegment(value: string): string {
  const normalized = value.trim().toLowerCase().replace(/[^a-z0-9._-]+/g, '-');
  const cleaned = normalized.replace(/^-+|-+$/g, '');
  return cleaned.length > 0 ? cleaned : 'pillar';
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

async function sendGraphCommand(page: Page, envelope: unknown): Promise<void> {
  await page.evaluate((payload) => {
    const bridge = Reflect.get(globalThis, 'TelocareGraph');
    if (typeof bridge !== 'object' || bridge === null) {
      throw new Error('globalThis.TelocareGraph bridge is unavailable.');
    }
    const receiver = Reflect.get(bridge, 'receiveSwiftMessage');
    if (typeof receiver !== 'function') {
      throw new Error('TelocareGraph.receiveSwiftMessage is unavailable.');
    }
    receiver(JSON.stringify(payload));
  }, envelope);
}

async function waitForGraphReady(page: Page): Promise<void> {
  await page.waitForFunction(() => {
    const bridge = Reflect.get(globalThis, 'TelocareGraph');
    if (typeof bridge !== 'object' || bridge === null) {
      return false;
    }
    const receiver = Reflect.get(bridge, 'receiveSwiftMessage');
    return typeof receiver === 'function';
  });
  await page.waitForSelector('#graph canvas', { timeout: 20_000 });
}

function pruneIsolatedNodes(
  graphData: ReturnType<typeof toRenderableGraphData>,
  includeIsolated: boolean,
): {
  graphData: ReturnType<typeof toRenderableGraphData>;
  removedIsolatedNodeCount: number;
} {
  if (includeIsolated) {
    return {
      graphData,
      removedIsolatedNodeCount: 0,
    };
  }

  if (graphData.edges.length === 0) {
    return {
      graphData,
      removedIsolatedNodeCount: 0,
    };
  }

  const degreeByNodeID = new Map<string, number>();
  for (const node of graphData.nodes) {
    degreeByNodeID.set(node.data.id, 0);
  }
  for (const edge of graphData.edges) {
    degreeByNodeID.set(edge.data.source, (degreeByNodeID.get(edge.data.source) ?? 0) + 1);
    degreeByNodeID.set(edge.data.target, (degreeByNodeID.get(edge.data.target) ?? 0) + 1);
  }

  const keptNodeIDs = new Set(
    [...degreeByNodeID.entries()]
      .filter((entry) => entry[1] > 0)
      .map((entry) => entry[0]),
  );

  const keptNodes = graphData.nodes.filter((node) => keptNodeIDs.has(node.data.id));
  const keptEdges = graphData.edges.filter((edge) => keptNodeIDs.has(edge.data.source) && keptNodeIDs.has(edge.data.target));

  return {
    graphData: {
      nodes: keptNodes,
      edges: keptEdges,
    },
    removedIsolatedNodeCount: graphData.nodes.length - keptNodes.length,
  };
}

function compactNodeTiers(graphData: ReturnType<typeof toRenderableGraphData>): ReturnType<typeof toRenderableGraphData> {
  const tierValues = new Set<number>();
  for (const node of graphData.nodes) {
    const tier = typeof node.data.tier === 'number' && Number.isFinite(node.data.tier)
      ? node.data.tier
      : 5;
    tierValues.add(Math.max(1, Math.min(10, Math.round(tier))));
  }

  const orderedTiers = [...tierValues].sort((left, right) => left - right);
  const compactTierByOriginal = new Map<number, number>();
  for (let index = 0; index < orderedTiers.length; index += 1) {
    compactTierByOriginal.set(orderedTiers[index], index + 1);
  }

  return {
    nodes: graphData.nodes.map((node) => {
      const originalTier = typeof node.data.tier === 'number' && Number.isFinite(node.data.tier)
        ? Math.max(1, Math.min(10, Math.round(node.data.tier)))
        : 5;
      const compactTier = compactTierByOriginal.get(originalTier) ?? originalTier;
      return {
        data: {
          ...node.data,
          tier: compactTier,
        },
      };
    }),
    edges: graphData.edges,
  };
}

async function run(): Promise<void> {
  const args = parseArgs();
  if (args.userID === null) {
    printUsageAndExit();
  }

  const tempDirectory = mkdtempSync(path.join(tmpdir(), 'openjaw-pillar-snapshot-'));
  const tempAuditPath = path.join(tempDirectory, 'full-audit.json');

  let browser: Awaited<ReturnType<typeof chromium.launch>> | null = null;

  try {
    runFullAuditToPath(args.userID, tempAuditPath);

    const fullAuditRaw = readFileSync(tempAuditPath, 'utf8');
    const audit = parseUserGraphAuditReportSubset(JSON.parse(fullAuditRaw));

    const resolvedPillarIDs = args.pillarIDs.length > 0 ? args.pillarIDs : collectPillarIDs(audit);
    if (resolvedPillarIDs.length === 0) {
      throw new Error('No pillars detected in audit output. Provide --pillar explicitly or ensure habits/questions include pillar ownership.');
    }

    mkdirSync(args.outDir, { recursive: true });

    const graphHTMLPath = path.resolve(process.cwd(), 'ios/Telocare/Telocare/Resources/Graph/index.html');
    const graphHTMLURL = pathToFileURL(graphHTMLPath).href;

    browser = await chromium.launch({
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
      ],
    });

    const context = await browser.newContext({
      viewport: {
        width: args.width,
        height: args.height,
      },
      deviceScaleFactor: args.scale,
    });
    const page = await context.newPage();
    page.on('pageerror', (error) => {
      console.error(`[page error] ${error.message}`);
    });

    await page.goto(graphHTMLURL, { waitUntil: 'load' });
    await waitForGraphReady(page);

    await sendGraphCommand(page, {
      command: 'setDisplayFlags',
      payload: {
        showFeedbackEdges: args.showFeedbackEdges,
        showProtectiveEdges: args.showProtectiveEdges,
        showInterventionNodes: args.showInterventions,
      },
    });

    const manifestRows: PillarSnapshotRow[] = [];
    for (const pillarID of resolvedPillarIDs) {
      const pillarReport = filterAuditToPillar(audit, pillarID);
      const graphData = toRenderableGraphData(pillarReport);
      const compacted = args.compactTiers ? compactNodeTiers(graphData) : graphData;
      const rendered = pruneIsolatedNodes(compacted, args.includeIsolated);

      await sendGraphCommand(page, {
        command: 'setGraphData',
        payload: rendered.graphData,
      });

      await page.waitForSelector('#graph canvas', { timeout: 20_000 });
      await page.waitForTimeout(650);

      const screenshotPath = path.resolve(args.outDir, `${sanitizeFileSegment(pillarID)}.png`);
      await page.locator('#graph').screenshot({
        path: screenshotPath,
        type: 'png',
      });

      manifestRows.push({
        pillar_id: pillarID,
        graph_node_count: pillarReport.summary.graph_node_count,
        graph_edge_count: pillarReport.summary.graph_edge_count,
        rendered_graph_node_count: rendered.graphData.nodes.length,
        rendered_graph_edge_count: rendered.graphData.edges.length,
        removed_isolated_node_count: rendered.removedIsolatedNodeCount,
        habits_total: pillarReport.summary.habits_total,
        outcome_questions_total: pillarReport.summary.outcome_questions_total,
        screenshot_path: screenshotPath,
      });

      console.log(
        `Captured ${pillarID}: nodes=${rendered.graphData.nodes.length}/${pillarReport.summary.graph_node_count}, edges=${rendered.graphData.edges.length}/${pillarReport.summary.graph_edge_count}, file=${screenshotPath}`,
      );
    }

    const manifest: SnapshotManifest = {
      generated_at: new Date().toISOString(),
      user_id: args.userID,
      source_audit_version: audit.audit_version,
      source_generated_at: audit.generated_at,
      output_directory: args.outDir,
      display_flags: {
        show_feedback_edges: args.showFeedbackEdges,
        show_protective_edges: args.showProtectiveEdges,
        show_intervention_nodes: args.showInterventions,
        include_isolated_nodes: args.includeIsolated,
        compact_tiers: args.compactTiers,
      },
      viewport: {
        width: args.width,
        height: args.height,
        scale: args.scale,
        device: args.devicePreset?.id ?? null,
      },
      pillars: manifestRows,
    };

    const manifestPath = path.resolve(args.outDir, 'manifest.json');
    writeFileSync(manifestPath, JSON.stringify(manifest, null, args.pretty ? 2 : 0));

    console.log('');
    console.log(`Wrote manifest: ${manifestPath}`);
    console.log(`Screenshots captured: ${manifestRows.length}`);

    if (args.raw) {
      console.log('');
      console.log(JSON.stringify(manifest, null, args.pretty ? 2 : 0));
    }
  } finally {
    if (browser !== null) {
      await browser.close();
    }
    rmSync(tempDirectory, { recursive: true, force: true });
  }
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
