#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';

async function main() {
  const inputPath = process.argv[2];
  if (!inputPath) {
    console.error('Usage: node scripts/muse-diagnostics-summary.mjs <path-to-decisions.ndjson>');
    process.exit(1);
  }

  const absolutePath = path.resolve(inputPath);
  const content = await fs.readFile(absolutePath, 'utf8');
  const lines = content.split('\n').filter((line) => line.trim().length > 0);

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
    schemaVersion: lines.length > 0 ? JSON.parse(lines[0]).schemaVersion ?? null : null,
    decisionCount: decisions.length,
    countedEventCount: countedEvents,
    averageAwakeEvidence: Number(averageAwakeEvidence.toFixed(4)),
    summary,
    serviceEvents
  };

  console.log(JSON.stringify(output, null, 2));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
