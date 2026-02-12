#!/usr/bin/env node
/**
 * Causal Graph Snapshot Tool
 *
 * Boots the Express server, opens the dashboard in headless Chromium via
 * Playwright, and captures PNG screenshots of the causal graph in various
 * states (tabs, interventions on/off, feedback loops on/off).
 *
 * Usage:
 *   node snapshot-graph.mjs                 # all states → ./snapshots/
 *   node snapshot-graph.mjs --state base    # just the base graph
 *   node snapshot-graph.mjs --out /tmp/snaps
 *
 * States captured:
 *   base           – Interventions tab, default view (no interventions, feedback on)
 *   interventions  – Interventions tab, Tx toggle ON
 *   no-feedback    – Interventions tab, feedback loops OFF
 *   research       – Research tab graph
 *   experiments    – Experiments tab graph
 */

import { chromium } from '/opt/node22/lib/node_modules/playwright/index.mjs';
import { spawn } from 'child_process';
import { mkdirSync } from 'fs';
import { resolve, join } from 'path';

// ── CLI args ──
const args = process.argv.slice(2);
function getArg(name) {
    const i = args.indexOf(`--${name}`);
    return i !== -1 && args[i + 1] ? args[i + 1] : null;
}

const REQUESTED_STATE = getArg('state');  // null = all
const OUT_DIR = resolve(getArg('out') || join(import.meta.dirname, 'snapshots'));
const PORT = 3987;
const BASE_URL = `http://localhost:${PORT}`;
const TIMEOUT = 30_000;

// ── Helpers ──

function log(msg) { console.log(`[snapshot] ${msg}`); }

function startServer() {
    return new Promise((resolve, reject) => {
        const server = spawn('node', ['dist/server.js'], {
            cwd: import.meta.dirname,
            env: { ...process.env, PORT: String(PORT) },
            stdio: ['ignore', 'pipe', 'pipe'],
        });

        let started = false;
        const onData = (chunk) => {
            const text = chunk.toString();
            if (!started && (text.includes('listening') || text.includes(String(PORT)) || text.includes('Server'))) {
                started = true;
                resolve(server);
            }
        };
        server.stdout.on('data', onData);
        server.stderr.on('data', onData);
        server.on('error', reject);

        setTimeout(() => { if (!started) { started = true; resolve(server); } }, 2000);
    });
}

async function switchToTab(page, tabName) {
    await page.click(`button[data-tab="${tabName}"]`);
    // refreshPanZoom fires after 100ms; Cytoscape init takes more time
    await page.waitForTimeout(500);
}

async function waitForGraph(page, cyContainerId) {
    // Wait for Cytoscape canvas to appear (created lazily on tab visibility)
    await page.waitForFunction(
        (id) => {
            const el = document.getElementById(id);
            return el && el.querySelector('canvas') !== null;
        },
        cyContainerId,
        { timeout: TIMEOUT }
    );
    // Let the layout settle
    await page.waitForTimeout(2000);
}

async function screenshotGraph(page, containerId, filename) {
    const el = page.locator(`#${containerId}`);
    const path = join(OUT_DIR, filename);
    await el.screenshot({ path, type: 'png' });
    log(`  saved ${filename}`);
    return path;
}

// ── Snapshot states ──

const STATES = {
    async base(page) {
        log('State: base (default view)');
        await waitForGraph(page, 'causal-graph-cy');
        return screenshotGraph(page, 'causal-graph', 'graph-base.png');
    },

    async interventions(page) {
        log('State: interventions (Tx ON)');
        await waitForGraph(page, 'causal-graph-cy');
        await page.click('#causal-graph .panzoom-controls button[data-action="toggleTx"]');
        await waitForGraph(page, 'causal-graph-cy');
        return screenshotGraph(page, 'causal-graph', 'graph-interventions.png');
    },

    async 'no-feedback'(page) {
        log('State: no-feedback (Fb OFF)');
        await waitForGraph(page, 'causal-graph-cy');
        await page.click('#causal-graph .panzoom-controls button[data-action="toggleFb"]');
        await waitForGraph(page, 'causal-graph-cy');
        return screenshotGraph(page, 'causal-graph', 'graph-no-feedback.png');
    },

    async defense(page) {
        log('State: defense mode (Df ON, with some check-ins)');
        await waitForGraph(page, 'causal-graph-cy');
        // Simulate daily check-ins via localStorage
        await page.evaluate(() => {
            const data = JSON.parse(localStorage.getItem('bruxism_personal_data') || '{}');
            if (!data.dailyCheckIns) data.dailyCheckIns = {};
            const active = ['PPI_TX', 'REFLUX_DIET_TX', 'MEAL_TIMING_TX', 'BED_ELEV_TX', 'HYDRATION',
                'SCREENS_TX', 'CIRCADIAN_TX', 'SLEEP_HYG_TX', 'MINDFULNESS_TX', 'EXERCISE_TX',
                'BREATHING_TX', 'MG_SUPP', 'YOGA_TX', 'PHYSIO_TX', 'SPLINT'];
            const partial = ['PPI_TX', 'MEAL_TIMING_TX', 'BED_ELEV_TX', 'SCREENS_TX', 'MG_SUPP',
                'BREATHING_TX', 'SPLINT', 'PHYSIO_TX', 'HYDRATION', 'EXERCISE_TX'];
            for (let i = 0; i < 7; i++) {
                const d = new Date(); d.setDate(d.getDate() - i);
                const k = d.toISOString().split('T')[0];
                data.dailyCheckIns[k] = i === 0 ? active : (i < 3 ? active : partial);
            }
            if (!data.interventionRatings) data.interventionRatings = [];
            const ratings = [
                { interventionId: 'PPI_TX', effectiveness: 'highly_effective' },
                { interventionId: 'BED_ELEV_TX', effectiveness: 'effective' },
                { interventionId: 'MG_SUPP', effectiveness: 'effective' },
                { interventionId: 'SPLINT', effectiveness: 'highly_effective' },
                { interventionId: 'BREATHING_TX', effectiveness: 'modest' },
                { interventionId: 'SCREENS_TX', effectiveness: 'modest' },
            ];
            ratings.forEach(r => {
                const idx = data.interventionRatings.findIndex(x => x.interventionId === r.interventionId);
                if (idx >= 0) data.interventionRatings[idx] = { ...r, lastUpdated: new Date().toISOString() };
                else data.interventionRatings.push({ ...r, lastUpdated: new Date().toISOString() });
            });
            localStorage.setItem('bruxism_personal_data', JSON.stringify(data));
        });
        await page.click('#causal-graph .panzoom-controls button[data-action="toggleDf"]');
        await waitForGraph(page, 'causal-graph-cy');
        await screenshotGraph(page, 'causal-graph', 'graph-defense.png');
        return screenshotGraph(page, 'app', 'graph-defense-full.png');
    },
};

// ── Main ──

async function main() {
    mkdirSync(OUT_DIR, { recursive: true });

    log('Starting Express server...');
    const server = await startServer();
    log(`Server PID ${server.pid} on port ${PORT}`);

    const BROWSER_ARGS = [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--single-process',
    ];

    const statesToRun = REQUESTED_STATE ? [REQUESTED_STATE] : Object.keys(STATES);
    const captured = [];

    for (const state of statesToRun) {
        if (!STATES[state]) {
            log(`Unknown state: ${state}. Available: ${Object.keys(STATES).join(', ')}`);
            continue;
        }

        // Fresh browser per state to avoid --single-process crashes
        let browser;
        try {
            browser = await chromium.launch({ headless: true, args: BROWSER_ARGS });
            const context = await browser.newContext({
                viewport: { width: 1600, height: 1000 },
                deviceScaleFactor: 2,
            });
            const page = await context.newPage();
            page.on('pageerror', err => log(`  [page error] ${err.message}`));

            await page.goto(BASE_URL, { waitUntil: 'networkidle', timeout: TIMEOUT });
            await page.waitForSelector('#app:not(.hidden)', { timeout: TIMEOUT });

            const path = await STATES[state](page);
            captured.push(path);
        } catch (err) {
            log(`  Error on state "${state}": ${err.message}`);
        } finally {
            if (browser) await browser.close();
        }
    }

    server.kill('SIGTERM');
    log('Server stopped');

    log(`\nDone! ${captured.length} screenshots saved to ${OUT_DIR}/`);
    captured.forEach(p => console.log(`  ${p}`));
}

main().catch(err => {
    console.error('[snapshot] Fatal:', err);
    process.exit(1);
});
