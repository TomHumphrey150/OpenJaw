import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import { summarizeDiagnostics } from '../scripts/muse-diagnostics-summary.mjs';

function fitSnapshotLine(overrides = {}) {
  return {
    type: 'fit_snapshot',
    schemaVersion: 2,
    timestampISO8601: '2026-02-23T20:25:00.000Z',
    fitSnapshot: {
      elapsedSeconds: 30,
      signalConfidence: 0.3,
      awakeLikelihood: 0.8,
      headbandOnCoverage: 0.9,
      qualityGateCoverage: 0.0,
      fitGuidance: 'adjustHeadband',
      rawDataPacketCount: 100,
      rawArtifactPacketCount: 10,
      parsedPacketCount: 90,
      droppedPacketCount: 10,
      droppedPacketTypes: [],
      fitReadiness: {
        isReady: false,
        primaryBlocker: 'insufficientGoodChannels',
        blockers: ['insufficientGoodChannels', 'lowQualityCoverage'],
        goodChannelCount: 0,
        hsiGoodChannelCount: 4
      },
      sensorStatuses: [
        { sensor: 2, passesIsGood: false, passesHsi: true },
        { sensor: 0, passesIsGood: false, passesHsi: true },
        { sensor: 3, passesIsGood: false, passesHsi: true },
        { sensor: 1, passesIsGood: false, passesHsi: true }
      ],
      lastPacketAgeSeconds: 0.1,
      setupDiagnosis: 'contactOrArtifact',
      windowPassRates: {
        receivingPackets: 1,
        headbandCoverage: 0.8,
        hsiGood3: 0.7,
        eegGood3: 0,
        qualityGate: 0
      },
      artifactRates: {
        blinkTrueRate: 0.2,
        jawClenchTrueRate: 0.7
      },
      sdkWarningCounts: [{ code: 41, label: 'optics', count: 1 }],
      latestHeadbandOn: true,
      latestHasQualityInputs: true,
      ...overrides
    }
  };
}

async function writeDiagnosticsDirectory(lines) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'muse-diag-test-'));
  const decisionsPath = path.join(root, 'decisions.ndjson');
  const content = `${lines.map((line) => JSON.stringify(line)).join('\n')}\n`;
  await fs.writeFile(decisionsPath, content, 'utf8');
  return root;
}

test('summarizeDiagnostics accepts diagnostics directory and sorts numeric sensors', async () => {
  const root = await writeDiagnosticsDirectory([
    {
      type: 'service_event',
      schemaVersion: 2,
      timestampISO8601: '2026-02-23T20:24:57.575Z',
      message: 'connection_state=connected'
    },
    fitSnapshotLine()
  ]);

  try {
    const summary = await summarizeDiagnostics(root);
    assert.equal(summary.fitSnapshotCount, 1);
    assert.equal(summary.sensorFailRates.length, 4);
    assert.deepEqual(
      summary.sensorFailRates.map((item) => item.sensor),
      [0, 1, 2, 3]
    );
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});

test('summarizeDiagnostics emits setup diagnosis section', async () => {
  const root = await writeDiagnosticsDirectory([
    {
      type: 'service_event',
      schemaVersion: 2,
      timestampISO8601: '2026-02-23T20:24:57.575Z',
      message: 'connection_state=connected'
    },
    fitSnapshotLine({
      setupDiagnosis: 'contactOrArtifact',
      artifactRates: {
        blinkTrueRate: 0.6,
        jawClenchTrueRate: 0.8
      }
    })
  ]);

  try {
    const summary = await summarizeDiagnostics(root);
    assert.equal(summary.setupDiagnosis.diagnosis, 'contactOrArtifact');
    assert.equal(summary.setupDiagnosis.displayText, 'Contact and artifact issue');
    assert.equal(summary.setupDiagnosis.input.transportWarningCount, 0);
  } finally {
    await fs.rm(root, { recursive: true, force: true });
  }
});
