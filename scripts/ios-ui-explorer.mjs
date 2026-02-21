#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..');
const iosRoot = path.join(repoRoot, 'ios', 'Telocare');
const outputDir = path.resolve(process.argv[2] ?? path.join(repoRoot, 'artifacts', 'ios-ui-explorer'));
const resultBundlePath = path.resolve(process.argv[3] ?? path.join(repoRoot, 'artifacts', 'ios-ui-explorer.xcresult'));

rmSync(outputDir, { recursive: true, force: true });
rmSync(resultBundlePath, { recursive: true, force: true });
mkdirSync(outputDir, { recursive: true });
mkdirSync(path.dirname(resultBundlePath), { recursive: true });

runCommand('xcodebuild', [
    '-workspace', 'Telocare.xcworkspace',
    '-scheme', 'Telocare',
    '-destination', 'platform=iOS Simulator,name=iPhone 17',
    '-resultBundlePath', resultBundlePath,
    '-only-testing:TelocareUITests/TelocareUIExplorerUITests/testCaptureExploreFlowScreens',
    'test',
], {
    cwd: iosRoot,
    env: {
        ...process.env,
        TELOCARE_UI_EXPLORER: '1',
        SIMCTL_CHILD_TELOCARE_UI_EXPLORER: '1',
    },
    stdio: 'inherit',
});

const activitiesJSON = runCommand('xcrun', [
    'xcresulttool',
    'get',
    'test-results',
    'activities',
    '--path', resultBundlePath,
    '--test-id', 'TelocareUIExplorerUITests/testCaptureExploreFlowScreens()',
    '--format', 'json',
], {
    encoding: 'utf8',
});

const attachments = collectAttachments(JSON.parse(activitiesJSON.stdout));
const uniqueAttachments = dedupeByPayloadID(attachments);

if (uniqueAttachments.length === 0) {
    console.error('No PNG screenshots were found in the result bundle.');
    process.exit(1);
}

uniqueAttachments.sort((left, right) => {
    const timestampCompare = left.timestamp.localeCompare(right.timestamp);
    if (timestampCompare !== 0) {
        return timestampCompare;
    }

    return left.name.localeCompare(right.name);
});

uniqueAttachments.forEach((attachment, index) => {
    const screenshotName = attachment.name.replace(/\.png$/i, '');
    const filename = `${String(index + 1).padStart(2, '0')}-${sanitizeFilename(screenshotName)}.png`;
    const outputPath = path.join(outputDir, filename);

    runCommand('xcrun', [
        'xcresulttool',
        'export',
        '--legacy',
        '--type', 'file',
        '--path', resultBundlePath,
        '--id', attachment.payloadID,
        '--output-path', outputPath,
    ], {
        stdio: 'inherit',
    });
});

console.log(`Explorer screenshots exported to ${outputDir}`);

function runCommand(command, args, options = {}) {
    const result = spawnSync(command, args, {
        cwd: options.cwd,
        env: options.env,
        encoding: options.encoding ?? 'utf8',
        stdio: options.stdio ?? 'pipe',
    });

    if (result.status !== 0) {
        process.exit(result.status ?? 1);
    }

    return result;
}

function collectAttachments(value) {
    const attachments = [];
    traverse(value, attachments);
    return attachments;
}

function traverse(value, attachments) {
    if (Array.isArray(value)) {
        for (const item of value) {
            traverse(item, attachments);
        }
        return;
    }

    if (!value || typeof value !== 'object') {
        return;
    }

    if (Array.isArray(value.attachments)) {
        for (const attachment of value.attachments) {
            if (typeof attachment.payloadId === 'string' && attachment.name.endsWith('.png')) {
                attachments.push({
                    payloadID: attachment.payloadId,
                    name: attachment.name,
                    timestamp: `${attachment.timestamp ?? ''}`,
                });
            }
        }
    }

    for (const nested of Object.values(value)) {
        traverse(nested, attachments);
    }
}

function dedupeByPayloadID(attachments) {
    const byPayload = new Map();

    for (const attachment of attachments) {
        if (!byPayload.has(attachment.payloadID)) {
            byPayload.set(attachment.payloadID, attachment);
        }
    }

    return [...byPayload.values()];
}

function sanitizeFilename(value) {
    const normalized = value
        .toLowerCase()
        .replace(/[^a-z0-9._-]+/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-|-$/g, '');

    return normalized.length > 0 ? normalized : 'screenshot';
}
