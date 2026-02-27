#!/usr/bin/env node

import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const SETUP_DIAGNOSIS_WINDOW_SECONDS = 30;
const SETUP_THRESHOLDS = {
  minimumReceivingPacketsForHealthyTransport: 0.90,
  contactLikelyMaximumEegGood3: 0.10,
  contactLikelyMinimumHsiGood3: 0.40,
  contactLikelyMaximumQualityGate: 0.10,
  artifactHighThreshold: 0.50,
  transportWarningHighCount: 3
};

export async function summarizeDiagnostics(inputPath) {
  if (!inputPath) {
    throw new Error(
      'Usage: node scripts/muse-diagnostics-summary.mjs <path-to-decisions.ndjson-or-export.json-or-diagnostics-directory>'
    );
  }

  const absoluteInputPath = path.resolve(inputPath);
  const resolvedInput = await resolveInputPath(absoluteInputPath);
  const inputBuffer = await fs.readFile(resolvedInput.filePath);
  const diagnosticsFile = await resolveDiagnosticsFile(inputBuffer, resolvedInput.filePath);
  const lines = diagnosticsFile.content.split('\n').filter((line) => line.trim().length > 0);

  const parsedLines = lines.map((line) => JSON.parse(line));
  const decisions = [];
  let summary = null;
  const serviceEvents = [];
  const fitSnapshots = [];

  for (const parsed of parsedLines) {
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
    if (parsed.type === 'fit_snapshot' && parsed.fitSnapshot) {
      fitSnapshots.push(parsed.fitSnapshot);
    }
  }

  const countedEvents = decisions.filter((decision) => decision.eventCounted).length;
  const averageAwakeEvidence = decisions.length === 0
    ? 0
    : decisions.reduce((total, decision) => total + (decision.awakeEvidence ?? 0), 0) / decisions.length;
  const blockerFrequency = computeBlockerFrequency(fitSnapshots);
  const sensorFailRates = computeSensorFailRates(fitSnapshots);
  const droppedPacketHistogram = computeDroppedPacketHistogram(fitSnapshots);
  const setupDiagnosis = computeSetupDiagnosis({
    fitSnapshots,
    decisions,
    serviceEvents
  });

  return {
    file: absoluteInputPath,
    resolvedInputFile: resolvedInput.filePath,
    sourceFile: diagnosticsFile.source,
    exportedFiles: diagnosticsFile.exportedFiles,
    schemaVersion: parsedLines.length > 0 ? parsedLines[0].schemaVersion ?? null : null,
    decisionCount: decisions.length,
    fitSnapshotCount: fitSnapshots.length,
    countedEventCount: countedEvents,
    averageAwakeEvidence: Number(averageAwakeEvidence.toFixed(4)),
    blockerFrequency,
    sensorFailRates,
    droppedPacketHistogram,
    setupDiagnosis,
    summary,
    serviceEvents
  };
}

async function resolveInputPath(absoluteInputPath) {
  const stats = await fs.stat(absoluteInputPath);
  if (!stats.isDirectory()) {
    return {
      filePath: absoluteInputPath
    };
  }

  const decisionsPath = path.join(absoluteInputPath, 'decisions.ndjson');
  const decisionsStats = await fs.stat(decisionsPath).catch(() => null);
  if (decisionsStats?.isFile()) {
    return {
      filePath: decisionsPath
    };
  }

  throw new Error(`No decisions.ndjson found in directory ${absoluteInputPath}`);
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

function computeBlockerFrequency(fitSnapshots) {
  const counts = new Map();
  for (const snapshot of fitSnapshots) {
    const blockers = Array.isArray(snapshot.fitReadiness?.blockers)
      ? snapshot.fitReadiness.blockers
      : [];

    for (const blocker of blockers) {
      counts.set(blocker, (counts.get(blocker) ?? 0) + 1);
    }
  }

  return Array.from(counts.entries())
    .map(([blocker, count]) => ({ blocker, count }))
    .sort((left, right) => {
      if (left.count === right.count) {
        return left.blocker.localeCompare(right.blocker);
      }
      return right.count - left.count;
    });
}

function computeSensorFailRates(fitSnapshots) {
  const totals = new Map();
  const fails = new Map();

  for (const snapshot of fitSnapshots) {
    const sensorStatuses = Array.isArray(snapshot.sensorStatuses)
      ? snapshot.sensorStatuses
      : [];

    for (const status of sensorStatuses) {
      const key = status.sensor ?? 'unknown';
      totals.set(key, (totals.get(key) ?? 0) + 1);
      const failed = status.passesIsGood !== true || status.passesHsi !== true;
      if (failed) {
        fails.set(key, (fails.get(key) ?? 0) + 1);
      }
    }
  }

  return Array.from(totals.entries())
    .map(([sensor, total]) => {
      const failed = fails.get(sensor) ?? 0;
      const failRate = total === 0 ? 0 : failed / total;
      return {
        sensor,
        sampleCount: total,
        failCount: failed,
        failRate: Number(failRate.toFixed(4))
      };
    })
    .sort((left, right) => compareSensorKey(left.sensor, right.sensor));
}

function compareSensorKey(left, right) {
  const leftNumber = normalizeNumeric(left);
  const rightNumber = normalizeNumeric(right);
  if (leftNumber !== null && rightNumber !== null) {
    return leftNumber - rightNumber;
  }

  if (leftNumber !== null) {
    return -1;
  }
  if (rightNumber !== null) {
    return 1;
  }

  return String(left).localeCompare(String(right));
}

function normalizeNumeric(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string' && value.trim().length > 0) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return null;
}

function computeDroppedPacketHistogram(fitSnapshots) {
  const counts = new Map();

  for (const snapshot of fitSnapshots) {
    const droppedTypes = Array.isArray(snapshot.droppedPacketTypes)
      ? snapshot.droppedPacketTypes
      : [];

    for (const droppedType of droppedTypes) {
      const code = droppedType.code;
      if (typeof code !== 'number') {
        continue;
      }
      const label = typeof droppedType.label === 'string'
        ? droppedType.label
        : `type_${code}`;
      const count = typeof droppedType.count === 'number' ? droppedType.count : 0;
      const key = `${code}:${label}`;
      counts.set(key, (counts.get(key) ?? 0) + count);
    }
  }

  return Array.from(counts.entries())
    .map(([key, count]) => {
      const [codeText, label] = key.split(':');
      return {
        code: Number(codeText),
        label,
        count
      };
    })
    .sort((left, right) => {
      if (left.count === right.count) {
        return left.code - right.code;
      }
      return right.count - left.count;
    });
}

function computeSetupDiagnosis({ fitSnapshots, decisions, serviceEvents }) {
  const latestFitSnapshot = fitSnapshots.at(-1) ?? null;
  const passRates = extractWindowPassRates(latestFitSnapshot, fitSnapshots);
  const artifactRates = extractArtifactRates(latestFitSnapshot, decisions);
  const sdkWarningCounts = extractSdkWarningCounts(latestFitSnapshot);
  const transportWarningCount = countTransportWarnings(sdkWarningCounts);
  const hasRecentDisconnectOrTimeoutEvent = serviceEvents.some((event) => {
    const message = String(event.message ?? '').toLowerCase();
    return message.includes('connection_state=disconnected') || message.includes('timeout');
  });

  const diagnosis = classifySetupIssue({
    passRates,
    artifactRates,
    hasRecentDisconnectOrTimeoutEvent,
    transportWarningCount
  });

  return {
    diagnosis,
    displayText: diagnosisDisplayText(diagnosis),
    rationaleText: diagnosisRationaleText(diagnosis),
    input: {
      passRates,
      artifactRates,
      hasRecentDisconnectOrTimeoutEvent,
      transportWarningCount
    },
    thresholds: SETUP_THRESHOLDS
  };
}

function extractWindowPassRates(latestFitSnapshot, fitSnapshots) {
  if (latestFitSnapshot?.windowPassRates) {
    return latestFitSnapshot.windowPassRates;
  }

  const window = fitSnapshots.slice(-SETUP_DIAGNOSIS_WINDOW_SECONDS);
  const sampleCount = window.length;

  return {
    receivingPackets: rate(
      window.filter((snapshot) => {
        const age = snapshot.lastPacketAgeSeconds;
        return typeof age === 'number' && age <= 3;
      }).length,
      sampleCount
    ),
    headbandCoverage: rate(
      window.filter((snapshot) => (snapshot.headbandOnCoverage ?? 0) >= 0.8).length,
      sampleCount
    ),
    hsiGood3: rate(
      window.filter((snapshot) => (snapshot.fitReadiness?.hsiGoodChannelCount ?? 0) >= 3).length,
      sampleCount
    ),
    eegGood3: rate(
      window.filter((snapshot) => (snapshot.fitReadiness?.goodChannelCount ?? 0) >= 3).length,
      sampleCount
    ),
    qualityGate: rate(
      window.filter((snapshot) => (snapshot.qualityGateCoverage ?? 0) >= 0.6).length,
      sampleCount
    )
  };
}

function extractArtifactRates(latestFitSnapshot, decisions) {
  if (latestFitSnapshot?.artifactRates) {
    return latestFitSnapshot.artifactRates;
  }

  const windowDecisions = decisions.slice(-SETUP_DIAGNOSIS_WINDOW_SECONDS);
  const sampleCount = windowDecisions.length;
  return {
    blinkTrueRate: rate(
      windowDecisions.filter((decision) => decision.blinkDetected === true).length,
      sampleCount
    ),
    jawClenchTrueRate: rate(
      windowDecisions.filter((decision) => decision.jawClenchDetected === true).length,
      sampleCount
    )
  };
}

function extractSdkWarningCounts(latestFitSnapshot) {
  if (!Array.isArray(latestFitSnapshot?.sdkWarningCounts)) {
    return [];
  }

  return latestFitSnapshot.sdkWarningCounts
    .filter((warning) => typeof warning?.count === 'number' && warning.count > 0)
    .map((warning) => ({
      code: Number(warning.code),
      label: typeof warning.label === 'string' ? warning.label : `type_${warning.code}`,
      count: Number(warning.count)
    }))
    .filter((warning) => Number.isFinite(warning.code) && Number.isFinite(warning.count));
}

function countTransportWarnings(sdkWarningCounts) {
  return sdkWarningCounts.reduce((total, warning) => {
    if (warning.label === 'optics' || warning.code === 41) {
      return total;
    }

    return total + warning.count;
  }, 0);
}

function classifySetupIssue({
  passRates,
  artifactRates,
  hasRecentDisconnectOrTimeoutEvent,
  transportWarningCount
}) {
  const transportHealthy = passRates.receivingPackets
      >= SETUP_THRESHOLDS.minimumReceivingPacketsForHealthyTransport
    && !hasRecentDisconnectOrTimeoutEvent;

  const contactLikely = passRates.eegGood3 < SETUP_THRESHOLDS.contactLikelyMaximumEegGood3
    && passRates.hsiGood3 >= SETUP_THRESHOLDS.contactLikelyMinimumHsiGood3
    && passRates.qualityGate < SETUP_THRESHOLDS.contactLikelyMaximumQualityGate;

  const artifactHigh = artifactRates.blinkTrueRate >= SETUP_THRESHOLDS.artifactHighThreshold
    || artifactRates.jawClenchTrueRate >= SETUP_THRESHOLDS.artifactHighThreshold;

  const transportWarningsHigh = transportWarningCount >= SETUP_THRESHOLDS.transportWarningHighCount;

  if (contactLikely && transportWarningsHigh) {
    return 'mixedContactAndTransport';
  }

  if (!transportHealthy && !contactLikely) {
    return 'transportUnstable';
  }

  if (contactLikely && artifactHigh) {
    return 'contactOrArtifact';
  }

  if (contactLikely) {
    return 'contactOrDrySkin';
  }

  if (!transportHealthy) {
    return 'transportUnstable';
  }

  return 'unknown';
}

function diagnosisDisplayText(diagnosis) {
  switch (diagnosis) {
    case 'contactOrArtifact':
      return 'Contact and artifact issue';
    case 'contactOrDrySkin':
      return 'Likely contact or dry skin issue';
    case 'transportUnstable':
      return 'Transport issue';
    case 'mixedContactAndTransport':
      return 'Mixed contact and transport issue';
    default:
      return 'Unknown';
  }
}

function diagnosisRationaleText(diagnosis) {
  switch (diagnosis) {
    case 'contactOrArtifact':
      return 'Connection is stable, but EEG quality remains poor and artifact indicators are high.';
    case 'contactOrDrySkin':
      return 'Connection is stable, but EEG quality remains poor despite acceptable HSI fit.';
    case 'transportUnstable':
      return 'Packet continuity or timeout/disconnect events indicate unstable transport.';
    case 'mixedContactAndTransport':
      return 'Both contact-quality and transport-warning signals are present.';
    default:
      return 'Not enough evidence yet to classify the setup issue.';
  }
}

function rate(passCount, sampleCount) {
  if (sampleCount <= 0) {
    return 0;
  }

  return passCount / sampleCount;
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

async function main() {
  const output = await summarizeDiagnostics(process.argv[2]);
  console.log(JSON.stringify(output, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
