import process from 'node:process';
import path from 'node:path';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { createClient } from '@supabase/supabase-js';
import { chromium } from 'playwright';
import {
  GraphData,
  GraphEdgeData,
  GraphNodeData,
  isUnknownRecord,
  loadGraphFromUnknown,
} from './pillar-integrity-lib';
import {
  collectPillarIDs,
  filterAuditToPillar,
  parseUserGraphAuditReportSubset,
  toRenderableGraphData,
} from './user-pillar-audit-lib';

interface ParsedArgs {
  graphPath: string | null;
  userID: string | null;
  pillarID: string | null;
  outPath: string | null;
  validate: boolean;
  direction: 'LR' | 'TD';
  title: string;
}

interface MermaidParseSuccess {
  ok: true;
}

interface MermaidParseFailure {
  ok: false;
  message: string;
  line: number | null;
  column: number | null;
  token: string | null;
  expected: string[];
}

type MermaidParseResult = MermaidParseSuccess | MermaidParseFailure;

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

function printUsageAndExit(): never {
  console.error(
    'Usage: npm run graph:to-mermaid -- [--graph-path <path> | --user-id <uuid>] [--pillar <pillar-id>] [--out <path>] [--direction LR|TD] [--title <text>] [--no-validate]',
  );
  process.exit(1);
}

function parseArgs(): ParsedArgs {
  const graphPath = getArg('graph-path');
  const explicitUserID = getArg('user-id');
  const userID = explicitUserID
    ?? (graphPath === null ? process.env.SUPABASE_DEBUG_USER_ID ?? null : null);
  const outPathRaw = getArg('out');
  const outPath = outPathRaw === null
    ? null
    : path.isAbsolute(outPathRaw)
      ? outPathRaw
      : path.resolve(process.cwd(), outPathRaw);

  const directionRaw = getArg('direction');
  let direction: 'LR' | 'TD' = 'LR';
  if (directionRaw !== null) {
    const normalized = directionRaw.trim().toUpperCase();
    if (normalized !== 'LR' && normalized !== 'TD') {
      throw new Error(`Invalid --direction value "${directionRaw}". Use LR or TD.`);
    }
    direction = normalized;
  }

  const title = getArg('title') ?? 'Causal Graph';
  const rawPillarID = getArg('pillar');
  const pillarID = rawPillarID === null
    ? null
    : rawPillarID.trim().length === 0
      ? null
      : rawPillarID.trim();
  const validate = !hasFlag('no-validate');
  return {
    graphPath,
    userID,
    pillarID,
    outPath,
    validate,
    direction,
    title,
  };
}

function resolveGraphFromUnknown(value: unknown): GraphData {
  if (!isUnknownRecord(value)) {
    return { nodes: [], edges: [] };
  }

  const directNodes = value.nodes;
  const directEdges = value.edges;
  if (Array.isArray(directNodes) && Array.isArray(directEdges)) {
    return loadGraphFromUnknown(value);
  }

  const graphData = readNestedRecord(value, ['graphData']);
  if (graphData !== null) {
    return loadGraphFromUnknown(graphData);
  }

  const customDiagram = readNestedRecord(value, ['customCausalDiagram']);
  if (customDiagram !== null) {
    const innerGraphData = readNestedRecord(customDiagram, ['graphData']);
    if (innerGraphData !== null) {
      return loadGraphFromUnknown(innerGraphData);
    }

    const nestedNodes = customDiagram.nodes;
    const nestedEdges = customDiagram.edges;
    if (Array.isArray(nestedNodes) && Array.isArray(nestedEdges)) {
      return loadGraphFromUnknown(customDiagram);
    }
  }

  const dataRecord = readNestedRecord(value, ['data']);
  if (dataRecord !== null) {
    return resolveGraphFromUnknown(dataRecord);
  }

  return { nodes: [], edges: [] };
}

function readNestedRecord(root: Record<string, unknown>, keys: string[]): Record<string, unknown> | null {
  let current: unknown = root;
  for (const key of keys) {
    if (!isUnknownRecord(current)) {
      return null;
    }
    current = current[key];
  }
  if (!isUnknownRecord(current)) {
    return null;
  }
  return current;
}

async function fetchUserGraph(userID: string): Promise<GraphData> {
  const supabaseURL = process.env.SUPABASE_URL ?? 'https://aocndwnnkffumisprifx.supabase.co';
  const supabaseSecretKey = process.env.SUPABASE_SECRET_KEY
    ?? process.env.SUPABASE_SERVICE_ROLE_KEY
    ?? process.env.SUPABASE_SECRET;
  if (typeof supabaseSecretKey !== 'string' || supabaseSecretKey.trim().length == 0) {
    throw new Error('Missing SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY).');
  }

  const client = createClient(supabaseURL, supabaseSecretKey.trim(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data, error } = await client
    .from('user_data')
    .select('data')
    .eq('user_id', userID)
    .maybeSingle();

  if (error) {
    throw new Error(`Supabase query failed: ${error.message}`);
  }
  if (!data) {
    throw new Error(`No row found for user_id=${userID}`);
  }

  return resolveGraphFromUnknown(data);
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

function fetchPillarScopedGraph(userID: string, pillarID: string): GraphData {
  const tempDirectory = mkdtempSync(path.join(tmpdir(), 'openjaw-graph-to-mermaid-'));
  const auditPath = path.join(tempDirectory, 'full-audit.json');

  try {
    runFullAuditToPath(userID, auditPath);

    const auditRawText = readFileSync(auditPath, 'utf8');
    const auditJSON: unknown = JSON.parse(auditRawText);
    const audit = parseUserGraphAuditReportSubset(auditJSON);
    const availablePillarIDs = collectPillarIDs(audit);
    if (!availablePillarIDs.includes(pillarID)) {
      const available = availablePillarIDs.length === 0 ? '(none)' : availablePillarIDs.join(', ');
      throw new Error(`Pillar "${pillarID}" was not found. Available pillars: ${available}`);
    }

    const pillarReport = filterAuditToPillar(audit, pillarID);
    const renderableGraph = toRenderableGraphData(pillarReport);
    return loadGraphFromUnknown(renderableGraph);
  } finally {
    rmSync(tempDirectory, { recursive: true, force: true });
  }
}

function sanitizeIdentifier(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return 'node_unknown';
  }
  const normalized = trimmed.replace(/[^A-Za-z0-9_]/g, '_');
  if (/^[A-Za-z_]/.test(normalized)) {
    return normalized;
  }
  return `node_${normalized}`;
}

function collapseWhitespace(value: string): string {
  return value.replace(/\r/g, ' ').replace(/\n+/g, ' ').replace(/\s+/g, ' ').trim();
}

function sanitizeMermaidLabel(value: string): string {
  const collapsed = collapseWhitespace(value);
  if (collapsed.length === 0) {
    return '';
  }
  return collapsed.replace(/"/g, '\'');
}

function nodeStyleClass(node: GraphNodeData): string {
  const raw = node.styleClass;
  if (typeof raw !== 'string' || raw.trim().length === 0) {
    return 'default';
  }
  return raw.trim().toLowerCase().replace(/[^a-z0-9_]/g, '_');
}

function edgeType(edge: GraphEdgeData): string {
  const raw = edge.edgeType;
  if (typeof raw !== 'string' || raw.trim().length === 0) {
    return 'causal';
  }
  return raw.trim().toLowerCase();
}

function arrowForEdgeType(type: string): string {
  if (type === 'protective' || type === 'inhibits') {
    return '-.->';
  }
  if (type === 'feedback') {
    return '--o';
  }
  return '-->';
}

function classDefForStyleClass(styleClass: string): string {
  if (styleClass === 'foundation') {
    return 'fill:#eef7ff,stroke:#2d6aa6,stroke-width:2px,color:#1f1f1f';
  }
  if (styleClass === 'robust') {
    return 'fill:#f9fff5,stroke:#2f7d32,stroke-width:2px,color:#1f1f1f';
  }
  if (styleClass === 'moderate') {
    return 'fill:#fff9ef,stroke:#b26a00,stroke-width:2px,color:#1f1f1f';
  }
  if (styleClass === 'preliminary') {
    return 'fill:#fbf5ff,stroke:#7e57c2,stroke-width:2px,color:#1f1f1f';
  }
  if (styleClass === 'mechanism') {
    return 'fill:#f3fbff,stroke:#1d6fa5,stroke-width:2px,color:#1f1f1f';
  }
  if (styleClass === 'symptom') {
    return 'fill:#fff5f5,stroke:#c62828,stroke-width:2px,color:#1f1f1f';
  }
  if (styleClass === 'intervention') {
    return 'fill:#f4fff7,stroke:#1b8a5a,stroke-width:2px,stroke-dasharray:6 4,color:#1f1f1f';
  }
  return 'fill:#ffffff,stroke:#666666,stroke-width:1.5px,color:#1f1f1f';
}

function buildMermaid(graph: GraphData, args: ParsedArgs): string {
  const nodes = graph.nodes.map((nodeElement) => nodeElement.data).filter((node): node is GraphNodeData => {
    return typeof node.id === 'string' && node.id.trim().length > 0;
  });

  const edges = graph.edges.map((edgeElement) => edgeElement.data).filter((edge): edge is GraphEdgeData => {
    return typeof edge.source === 'string' && edge.source.trim().length > 0
      && typeof edge.target === 'string' && edge.target.trim().length > 0;
  });

  const symbolByNodeID = new Map<string, string>();
  const seenSymbols = new Set<string>();
  for (const node of nodes) {
    const base = sanitizeIdentifier(node.id);
    let symbol = base;
    let suffix = 1;
    while (seenSymbols.has(symbol)) {
      symbol = `${base}_${suffix}`;
      suffix += 1;
    }
    seenSymbols.add(symbol);
    symbolByNodeID.set(node.id, symbol);
  }

  const styleClasses = new Set<string>();
  const edgeTypes = new Set<string>();
  const lines: string[] = [];
  lines.push(`%% ${args.title}`);
  lines.push('%% Auto-generated by scripts/graph-to-mermaid.ts');
  lines.push('%% Node style classes and edge types are annotated for AI-readable graph inspection.');
  lines.push(`flowchart ${args.direction}`);
  lines.push('');
  lines.push('%% Nodes');

  const sortedNodes = nodes.slice().sort((left, right) => left.id.localeCompare(right.id));
  for (const node of sortedNodes) {
    const symbol = symbolByNodeID.get(node.id);
    if (symbol === undefined) {
      continue;
    }
    const labelFromNode = typeof node.label === 'string' ? node.label : node.id;
    const label = sanitizeMermaidLabel(labelFromNode);
    const safeLabel = label.length === 0 ? sanitizeMermaidLabel(node.id) : label;
    const styleClass = nodeStyleClass(node);
    styleClasses.add(styleClass);
    const disclosureLevel = typeof node.disclosureLevel === 'number' ? node.disclosureLevel : 1;
    lines.push(`  ${symbol}["${safeLabel}"]:::${styleClass}`);
    lines.push(`  %% node id=${node.id} class=${styleClass} disclosureLevel=${disclosureLevel}`);
  }

  lines.push('');
  lines.push('%% Edges');

  let edgeIndex = 0;
  for (const edge of edges) {
    const sourceSymbol = symbolByNodeID.get(edge.source);
    const targetSymbol = symbolByNodeID.get(edge.target);
    if (sourceSymbol === undefined || targetSymbol === undefined) {
      edgeIndex += 1;
      continue;
    }
    const type = edgeType(edge);
    edgeTypes.add(type);
    const arrow = arrowForEdgeType(type);
    const labelParts: string[] = [];
    if (typeof edge.label === 'string' && edge.label.trim().length > 0) {
      labelParts.push(sanitizeMermaidLabel(edge.label));
    }
    labelParts.push(`type: ${type}`);
    const edgeLabel = sanitizeMermaidLabel(labelParts.join(' ; '));
    const disclosureLevel = typeof edge.disclosureLevel === 'number' ? edge.disclosureLevel : 1;
    lines.push(`  ${sourceSymbol} ${arrow}|"${edgeLabel}"| ${targetSymbol}`);
    lines.push(
      `  %% edge index=${edgeIndex} source=${edge.source} target=${edge.target} edgeType=${type} disclosureLevel=${disclosureLevel}`,
    );
    edgeIndex += 1;
  }

  lines.push('');
  lines.push('%% Class definitions');
  const sortedStyleClasses = [...styleClasses].sort((left, right) => left.localeCompare(right));
  for (const styleClass of sortedStyleClasses) {
    lines.push(`  classDef ${styleClass} ${classDefForStyleClass(styleClass)};`);
  }

  lines.push('');
  lines.push('%% Edge type legend');
  const sortedEdgeTypes = [...edgeTypes].sort((left, right) => left.localeCompare(right));
  for (const type of sortedEdgeTypes) {
    lines.push(`%% edgeType=${type} arrow=${arrowForEdgeType(type)}`);
  }

  return `${lines.join('\n')}\n`;
}

function summarizeMermaidParseFailure(mermaidText: string, failure: MermaidParseFailure): string {
  const locationParts: string[] = [];
  if (failure.line !== null) {
    locationParts.push(`line ${failure.line}`);
  }
  if (failure.column !== null) {
    locationParts.push(`column ${failure.column}`);
  }
  const location = locationParts.length === 0 ? 'unknown location' : locationParts.join(', ');

  const lines = mermaidText.split('\n');
  const excerpt = failure.line !== null && failure.line >= 1 && failure.line <= lines.length
    ? lines[failure.line - 1]
    : null;

  const expected = failure.expected.length === 0
    ? ''
    : `\nExpected tokens: ${failure.expected.slice(0, 12).join(', ')}`;
  const token = failure.token === null ? '' : `\nToken: ${failure.token}`;
  const snippet = excerpt === null ? '' : `\nSource line: ${excerpt}`;

  return `Mermaid syntax validation failed at ${location}.${token}${snippet}${expected}\n${failure.message}`;
}

async function validateMermaidSyntax(mermaidText: string): Promise<void> {
  const mermaidScriptPath = path.resolve(process.cwd(), 'node_modules/mermaid/dist/mermaid.min.js');
  if (!existsSync(mermaidScriptPath)) {
    throw new Error(
      `Mermaid parser is not installed. Missing file: ${mermaidScriptPath}. Run npm install to restore dependencies.`,
    );
  }

  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.setContent('<html><body></body></html>');
    await page.addScriptTag({ path: mermaidScriptPath });

    const parseResult = await page.evaluate<MermaidParseResult, string>(async (input) => {
      const isRecord = (value: unknown): value is Record<string, unknown> => {
        return typeof value === 'object' && value !== null && !Array.isArray(value);
      };

      const mermaidValue = Reflect.get(globalThis, 'mermaid');
      if (!isRecord(mermaidValue)) {
        return {
          ok: false,
          message: 'mermaid global was not found in browser context.',
          line: null,
          column: null,
          token: null,
          expected: [],
        };
      }

      const parseValue = mermaidValue.parse;
      if (typeof parseValue !== 'function') {
        return {
          ok: false,
          message: 'mermaid.parse was not found in browser context.',
          line: null,
          column: null,
          token: null,
          expected: [],
        };
      }

      const initializeValue = mermaidValue.initialize;
      if (typeof initializeValue === 'function') {
        initializeValue({ startOnLoad: false, maxEdges: 20000 });
      }

      try {
        await parseValue(input);
        return { ok: true };
      } catch (error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        let line: number | null = null;
        let column: number | null = null;
        let token: string | null = null;
        let expected: string[] = [];

        if (isRecord(error)) {
          const hashValue = error.hash;
          if (isRecord(hashValue)) {
            const lineValue = hashValue.line;
            if (typeof lineValue === 'number' && Number.isFinite(lineValue)) {
              line = lineValue + 1;
            }

            const tokenValue = hashValue.token;
            if (typeof tokenValue === 'string' && tokenValue.trim().length > 0) {
              token = tokenValue;
            }

            const expectedValue = hashValue.expected;
            if (Array.isArray(expectedValue)) {
              const parsed: string[] = [];
              for (const item of expectedValue) {
                if (typeof item === 'string' && item.trim().length > 0) {
                  parsed.push(item);
                }
              }
              expected = parsed;
            }

            const locValue = hashValue.loc;
            if (isRecord(locValue)) {
              const firstLineValue = locValue.first_line;
              if (typeof firstLineValue === 'number' && Number.isFinite(firstLineValue)) {
                line = firstLineValue;
              }

              const firstColumnValue = locValue.first_column;
              if (typeof firstColumnValue === 'number' && Number.isFinite(firstColumnValue)) {
                column = firstColumnValue;
              }
            }
          }
        }

        return {
          ok: false,
          message,
          line,
          column,
          token,
          expected,
        };
      }
    }, mermaidText);

    if (!parseResult.ok) {
      throw new Error(summarizeMermaidParseFailure(mermaidText, parseResult));
    }
  } finally {
    await browser.close();
  }
}

async function run(): Promise<void> {
  const args = parseArgs();
  if (hasFlag('help')) {
    printUsageAndExit();
  }

  if (args.pillarID !== null && args.graphPath !== null) {
    throw new Error('Cannot use --pillar with --graph-path. Use --user-id with --pillar.');
  }

  if (args.pillarID !== null && args.userID === null) {
    throw new Error('Using --pillar requires --user-id (or SUPABASE_DEBUG_USER_ID).');
  }

  const sourceCount = Number(args.graphPath !== null) + Number(args.userID !== null);
  if (sourceCount !== 1) {
    printUsageAndExit();
  }

  let graph: GraphData;
  if (args.pillarID !== null && args.userID !== null) {
    graph = fetchPillarScopedGraph(args.userID, args.pillarID);
  } else if (args.graphPath !== null) {
    const graphPath = path.isAbsolute(args.graphPath)
      ? args.graphPath
      : path.resolve(process.cwd(), args.graphPath);
    const raw = readFileSync(graphPath, 'utf8');
    const parsed: unknown = JSON.parse(raw);
    graph = resolveGraphFromUnknown(parsed);
  } else if (args.userID !== null) {
    graph = await fetchUserGraph(args.userID);
  } else {
    printUsageAndExit();
  }

  if (graph.nodes.length === 0 && graph.edges.length === 0) {
    throw new Error('No graph data resolved from input.');
  }

  const mermaid = buildMermaid(graph, args);
  if (args.validate) {
    await validateMermaidSyntax(mermaid);
  }
  if (args.outPath !== null) {
    writeFileSync(args.outPath, mermaid, 'utf8');
    console.log(`Wrote Mermaid graph: ${args.outPath}`);
    return;
  }

  process.stdout.write(mermaid);
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
