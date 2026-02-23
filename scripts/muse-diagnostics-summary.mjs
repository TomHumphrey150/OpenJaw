#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';

async function main() {
  const inputPath = process.argv[2];
  if (!inputPath) {
    console.error('Usage: node scripts/muse-diagnostics-summary.mjs <path-to-decisions.ndjson-or-export.json>');
    process.exit(1);
  }

  const absolutePath = path.resolve(inputPath);
  const inputBuffer = await fs.readFile(absolutePath);
  const diagnosticsFile = await resolveDiagnosticsFile(inputBuffer, absolutePath);
  const lines = diagnosticsFile.content.split('\n').filter((line) => line.trim().length > 0);

  const decisions = [];
  let summary = null;
  const serviceEvents = [];

  for (const line of lines) {
    const parsed = JSON.parse(line);
    if (parsed.type === 'second' && parsed.decision) {
      decisions.push(parsed.decision);
    }
    if (parsed.type === 'summary' && parsed.summary) {
      summary = parsed.summary;
    }
    if (parsed.type === 'service_event') {
      serviceEvents.push({
        timestampISO8601: parsed.timestampISO8601 ?? null,
        message: parsed.message ?? ''
      });
    }
  }

  const countedEvents = decisions.filter((decision) => decision.eventCounted).length;
  const averageAwakeEvidence = decisions.length === 0
    ? 0
    : decisions.reduce((total, decision) => total + (decision.awakeEvidence ?? 0), 0) / decisions.length;

  const output = {
    file: absolutePath,
    sourceFile: diagnosticsFile.source,
    exportedFiles: diagnosticsFile.exportedFiles,
    schemaVersion: lines.length > 0 ? JSON.parse(lines[0]).schemaVersion ?? null : null,
    decisionCount: decisions.length,
    countedEventCount: countedEvents,
    averageAwakeEvidence: Number(averageAwakeEvidence.toFixed(4)),
    summary,
    serviceEvents
  };

  console.log(JSON.stringify(output, null, 2));
}

async function resolveDiagnosticsFile(inputBuffer, absolutePath) {
  const utf8 = inputBuffer.toString('utf8');
  const parsedContainer = tryParseJSON(utf8);

  if (!isPortableContainer(parsedContainer)) {
    return {
      source: 'decisions.ndjson',
      content: utf8,
      exportedFiles: null
    };
  }

  const decisionsEntry = parsedContainer.files.find((file) => file.fileName === 'decisions.ndjson');
  if (!decisionsEntry) {
    throw new Error(`No decisions.ndjson entry found in ${absolutePath}`);
  }

  const decoded = Buffer.from(decisionsEntry.contentsBase64, 'base64').toString('utf8');
  return {
    source: 'portable-export.json',
    content: decoded,
    exportedFiles: parsedContainer.files.map((file) => ({
      fileName: file.fileName,
      byteCount: file.byteCount
    }))
  };
}

function tryParseJSON(content) {
  try {
    return JSON.parse(content);
  } catch {
    return null;
  }
}

function isPortableContainer(value) {
  if (!value || typeof value !== 'object') {
    return false;
  }

  if (!Array.isArray(value.files)) {
    return false;
  }

  return value.files.every((file) => {
    if (!file || typeof file !== 'object') {
      return false;
    }

    return typeof file.fileName === 'string'
      && typeof file.contentsBase64 === 'string';
  });
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
