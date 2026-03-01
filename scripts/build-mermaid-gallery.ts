import process from 'node:process';
import path from 'node:path';
import {
  copyFileSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';

interface ParsedArgs {
  inputDir: string;
  outDir: string;
  recursive: boolean;
}

interface MermaidDiagramEntry {
  id: string;
  relativePath: string;
  modifiedAt: string;
  createdAt: string;
  modifiedAtMs: number;
  createdAtMs: number;
  sizeBytes: number;
  content: string;
}

interface MermaidDiagramManifestEntry {
  id: string;
  relativePath: string;
  modifiedAt: string;
  createdAt: string;
  modifiedAtMs: number;
  createdAtMs: number;
  sizeBytes: number;
}

interface MermaidGalleryManifest {
  generatedAt: string;
  sourceDirectory: string;
  outputDirectory: string;
  diagramCount: number;
  diagrams: MermaidDiagramManifestEntry[];
}

function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

function getArg(name: string): string | null {
  const key = `--${name}`;
  const index = process.argv.indexOf(key);
  if (index < 0) {
    return null;
  }
  const value = process.argv[index + 1];
  if (value === undefined || value.startsWith('--')) {
    return null;
  }
  return value;
}

function printUsageAndExit(): never {
  console.error(
    'Usage: npm run mermaid:gallery -- [--input-dir <path>] [--out-dir <path>] [--no-recursive]',
  );
  process.exit(1);
}

function resolveAbsolutePath(value: string): string {
  if (path.isAbsolute(value)) {
    return value;
  }
  return path.resolve(process.cwd(), value);
}

function parseArgs(): ParsedArgs {
  if (hasFlag('help')) {
    printUsageAndExit();
  }

  const inputRaw = getArg('input-dir') ?? path.join('artifacts');
  const outRaw = getArg('out-dir') ?? path.join('artifacts', 'mermaid-gallery');

  return {
    inputDir: resolveAbsolutePath(inputRaw),
    outDir: resolveAbsolutePath(outRaw),
    recursive: !hasFlag('no-recursive'),
  };
}

function toPosixPath(value: string): string {
  return value.split(path.sep).join('/');
}

function listMermaidFiles(rootDir: string, recursive: boolean): string[] {
  const queue: string[] = [rootDir];
  const files: string[] = [];

  while (queue.length > 0) {
    const currentDir = queue.shift();
    if (currentDir === undefined) {
      continue;
    }
    const entries = readdirSync(currentDir, { withFileTypes: true });
    for (const entry of entries) {
      const absolutePath = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        if (recursive) {
          queue.push(absolutePath);
        }
        continue;
      }
      if (!entry.isFile()) {
        continue;
      }
      if (!entry.name.toLowerCase().endsWith('.mmd')) {
        continue;
      }
      files.push(absolutePath);
    }
  }

  return files;
}

function buildDiagramEntries(paths: string[], sourceDir: string): MermaidDiagramEntry[] {
  const entries: MermaidDiagramEntry[] = [];
  for (const absolutePath of paths) {
    const stats = statSync(absolutePath);
    const content = readFileSync(absolutePath, 'utf8');
    const relativePath = toPosixPath(path.relative(sourceDir, absolutePath));
    entries.push({
      id: relativePath,
      relativePath,
      modifiedAt: stats.mtime.toISOString(),
      createdAt: stats.birthtime.toISOString(),
      modifiedAtMs: stats.mtimeMs,
      createdAtMs: stats.birthtimeMs,
      sizeBytes: stats.size,
      content,
    });
  }

  entries.sort((left, right) => {
    if (right.modifiedAtMs !== left.modifiedAtMs) {
      return right.modifiedAtMs - left.modifiedAtMs;
    }
    if (right.createdAtMs !== left.createdAtMs) {
      return right.createdAtMs - left.createdAtMs;
    }
    return left.relativePath.localeCompare(right.relativePath);
  });

  return entries;
}

function safeInlineScriptJSON(value: string): string {
  return value
    .replace(/<\/script/gi, '<\\/script')
    .replace(/<!--/g, '<\\!--');
}

function buildViewerHTML(diagrams: MermaidDiagramEntry[]): string {
  const payload = diagrams.map((entry) => ({
    id: entry.id,
    relativePath: entry.relativePath,
    modifiedAt: entry.modifiedAt,
    createdAt: entry.createdAt,
    modifiedAtMs: entry.modifiedAtMs,
    createdAtMs: entry.createdAtMs,
    sizeBytes: entry.sizeBytes,
    content: entry.content,
  }));
  const payloadJSON = safeInlineScriptJSON(JSON.stringify(payload));

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Mermaid Diagram Gallery</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f7f8fb;
      --surface: #ffffff;
      --text: #1b2430;
      --muted: #576275;
      --line: #dce1ea;
      --accent: #2959d6;
      --error: #a21f2b;
    }
    * {
      box-sizing: border-box;
    }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font-family: "SF Mono", "Fira Code", Menlo, Consolas, monospace;
      line-height: 1.45;
    }
    main {
      min-height: 100dvh;
      padding: 16px;
      display: grid;
      grid-template-rows: auto auto auto 1fr auto;
      gap: 12px;
    }
    .controls {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 12px;
      display: grid;
      gap: 10px;
    }
    .control-row {
      display: flex;
      gap: 8px;
      flex-wrap: wrap;
      align-items: center;
    }
    select, button {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: #fff;
      color: var(--text);
      font: inherit;
      padding: 8px 10px;
    }
    button {
      cursor: pointer;
    }
    button:hover {
      border-color: var(--accent);
    }
    .meta {
      font-size: 13px;
      color: var(--muted);
      white-space: pre-wrap;
    }
    .status {
      font-size: 13px;
      color: var(--muted);
      min-height: 20px;
    }
    .error {
      background: #fff1f2;
      color: var(--error);
      border: 1px solid #f4c9cd;
      border-radius: 10px;
      padding: 10px;
      min-height: 18px;
      white-space: pre-wrap;
    }
    .canvas-wrap {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 10px;
      overflow: auto;
      padding: 12px;
    }
    #diagram-canvas svg {
      max-width: none;
    }
    details {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 10px;
    }
    pre {
      margin: 0;
      white-space: pre;
      overflow: auto;
      font-size: 12px;
    }
  </style>
  <script src="./mermaid.min.js"></script>
</head>
<body>
  <main>
    <section class="controls" aria-label="Diagram controls">
      <div class="control-row">
        <label for="diagram-select">Diagram</label>
        <select id="diagram-select"></select>
        <button id="prev-button" type="button">Previous</button>
        <button id="next-button" type="button">Next</button>
        <button id="rerender-button" type="button">Re-render</button>
      </div>
      <div id="diagram-meta" class="meta"></div>
      <div id="status" class="status" aria-live="polite"></div>
      <div id="error" class="error" aria-live="polite"></div>
    </section>
    <section class="canvas-wrap" aria-label="Rendered Mermaid diagram">
      <div id="diagram-canvas"></div>
    </section>
    <details>
      <summary>Source Mermaid</summary>
      <pre id="source-view"></pre>
    </details>
  </main>
  <script>
    const diagrams = ${payloadJSON};
    const selectEl = document.getElementById('diagram-select');
    const prevButton = document.getElementById('prev-button');
    const nextButton = document.getElementById('next-button');
    const rerenderButton = document.getElementById('rerender-button');
    const metaEl = document.getElementById('diagram-meta');
    const statusEl = document.getElementById('status');
    const errorEl = document.getElementById('error');
    const canvasEl = document.getElementById('diagram-canvas');
    const sourceEl = document.getElementById('source-view');
    const dateFormatter = new Intl.DateTimeFormat(undefined, {
      dateStyle: 'medium',
      timeStyle: 'medium',
    });
    let currentIndex = 0;
    let renderCounter = 0;

    function setStatus(message) {
      statusEl.textContent = message;
    }

    function setError(message) {
      errorEl.textContent = message;
    }

    function formatDate(iso) {
      const time = Date.parse(iso);
      if (!Number.isFinite(time)) {
        return iso;
      }
      return dateFormatter.format(new Date(time));
    }

    function kbText(sizeBytes) {
      return (sizeBytes / 1024).toFixed(1) + ' KB';
    }

    function setSelection(index) {
      if (diagrams.length === 0) {
        return;
      }
      const safeIndex = Math.max(0, Math.min(diagrams.length - 1, index));
      currentIndex = safeIndex;
      selectEl.value = String(safeIndex);
      updateMeta();
      renderCurrent().catch((error) => {
        const message = error instanceof Error ? error.message : String(error);
        setError(message);
        setStatus('Render failed');
      });
    }

    function updateMeta() {
      if (diagrams.length === 0) {
        metaEl.textContent = 'No Mermaid files found.';
        sourceEl.textContent = '';
        return;
      }
      const entry = diagrams[currentIndex];
      metaEl.textContent =
        'Path: ' + entry.relativePath +
        '\\nModified: ' + formatDate(entry.modifiedAt) +
        '\\nCreated: ' + formatDate(entry.createdAt) +
        '\\nSize: ' + kbText(entry.sizeBytes) +
        '\\nOrder: newest modified first';
      sourceEl.textContent = entry.content;
    }

    async function renderCurrent() {
      if (diagrams.length === 0) {
        canvasEl.innerHTML = '';
        setError('');
        setStatus('No diagrams to render.');
        return;
      }

      const entry = diagrams[currentIndex];
      setError('');
      setStatus('Rendering ' + entry.relativePath + ' ...');
      renderCounter += 1;
      const renderID = 'diagram_' + String(renderCounter);
      const result = await mermaid.render(renderID, entry.content);
      canvasEl.innerHTML = result.svg;
      setStatus('Rendered ' + entry.relativePath);
    }

    function handleSelectChange() {
      const selected = Number.parseInt(selectEl.value, 10);
      if (!Number.isFinite(selected)) {
        return;
      }
      setSelection(selected);
    }

    function handlePrev() {
      if (diagrams.length === 0) {
        return;
      }
      setSelection((currentIndex - 1 + diagrams.length) % diagrams.length);
    }

    function handleNext() {
      if (diagrams.length === 0) {
        return;
      }
      setSelection((currentIndex + 1) % diagrams.length);
    }

    function setup() {
      mermaid.initialize({
        startOnLoad: false,
        maxEdges: 20000,
        maxTextSize: 2000000,
        securityLevel: 'strict',
      });

      selectEl.innerHTML = '';
      for (let index = 0; index < diagrams.length; index += 1) {
        const entry = diagrams[index];
        const option = document.createElement('option');
        option.value = String(index);
        option.textContent = entry.relativePath + ' [' + formatDate(entry.modifiedAt) + ']';
        selectEl.appendChild(option);
      }

      selectEl.addEventListener('change', handleSelectChange);
      prevButton.addEventListener('click', handlePrev);
      nextButton.addEventListener('click', handleNext);
      rerenderButton.addEventListener('click', () => {
        renderCurrent().catch((error) => {
          const message = error instanceof Error ? error.message : String(error);
          setError(message);
          setStatus('Render failed');
        });
      });

      if (diagrams.length === 0) {
        updateMeta();
        setStatus('No diagrams found in source directory.');
        return;
      }

      setSelection(0);
    }

    setup();
  </script>
</body>
</html>
`;
}

function buildManifest(
  diagrams: MermaidDiagramEntry[],
  sourceDirectory: string,
  outputDirectory: string,
): MermaidGalleryManifest {
  const manifestEntries: MermaidDiagramManifestEntry[] = diagrams.map((entry) => ({
    id: entry.id,
    relativePath: entry.relativePath,
    modifiedAt: entry.modifiedAt,
    createdAt: entry.createdAt,
    modifiedAtMs: entry.modifiedAtMs,
    createdAtMs: entry.createdAtMs,
    sizeBytes: entry.sizeBytes,
  }));

  return {
    generatedAt: new Date().toISOString(),
    sourceDirectory,
    outputDirectory,
    diagramCount: manifestEntries.length,
    diagrams: manifestEntries,
  };
}

function run(): void {
  const args = parseArgs();
  mkdirSync(args.outDir, { recursive: true });

  const diagramPaths = listMermaidFiles(args.inputDir, args.recursive);
  const diagrams = buildDiagramEntries(diagramPaths, args.inputDir);

  const mermaidSource = path.resolve(process.cwd(), 'node_modules', 'mermaid', 'dist', 'mermaid.min.js');
  const mermaidTarget = path.join(args.outDir, 'mermaid.min.js');
  copyFileSync(mermaidSource, mermaidTarget);

  const html = buildViewerHTML(diagrams);
  const htmlPath = path.join(args.outDir, 'index.html');
  writeFileSync(htmlPath, html, 'utf8');

  const manifest = buildManifest(diagrams, args.inputDir, args.outDir);
  const manifestPath = path.join(args.outDir, 'manifest.json');
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');

  console.log(`Wrote Mermaid gallery: ${htmlPath}`);
  console.log(`Copied Mermaid runtime: ${mermaidTarget}`);
  console.log(`Wrote manifest: ${manifestPath}`);
  console.log(`Diagram count: ${manifest.diagramCount}`);
}

try {
  run();
} catch (error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
}
