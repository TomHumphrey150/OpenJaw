#!/usr/bin/env node

import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..');
const sourceFile = path.join(repoRoot, 'public/js/causalEditor/defaultGraphData.js');
const outputFile = path.join(repoRoot, 'ios/Telocare/Telocare/Resources/Graph/default-graph.json');

const sourceURL = pathToFileURL(sourceFile).href;
const graphModule = await import(sourceURL);
const canonicalGraph = graphModule.DEFAULT_GRAPH_DATA;

if (!canonicalGraph || !Array.isArray(canonicalGraph.nodes) || !Array.isArray(canonicalGraph.edges)) {
    throw new Error('DEFAULT_GRAPH_DATA must contain nodes and edges arrays.');
}

await mkdir(path.dirname(outputFile), { recursive: true });
await writeFile(outputFile, `${JSON.stringify(canonicalGraph, null, 2)}\n`, 'utf8');

console.log(`Synced canonical graph to ${outputFile}`);
