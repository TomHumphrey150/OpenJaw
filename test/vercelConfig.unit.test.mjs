import assert from 'node:assert/strict';
import { lstat, readFile } from 'node:fs/promises';
import { test } from 'node:test';

test('vercel.json keeps static output config and does not reintroduce rewrites', async () => {
    const raw = await readFile(new URL('../vercel.json', import.meta.url), 'utf-8');
    const config = JSON.parse(raw);

    assert.equal(config.outputDirectory, 'public');
    assert.equal(Object.hasOwn(config, 'rewrites'), false);
});

test('api data files are real JSON files and parse correctly', async () => {
    const bruxismPath = new URL('../data/bruxism-info.json', import.meta.url);
    const interventionsPath = new URL('../data/interventions.json', import.meta.url);

    const bruxismStat = await lstat(bruxismPath);
    const interventionsStat = await lstat(interventionsPath);
    assert.equal(bruxismStat.isSymbolicLink(), false, 'bruxism-info.json must not be a symlink');
    assert.equal(interventionsStat.isSymbolicLink(), false, 'interventions.json must not be a symlink');

    const bruxismRaw = await readFile(bruxismPath, 'utf-8');
    const interventionsRaw = await readFile(interventionsPath, 'utf-8');
    const bruxism = JSON.parse(bruxismRaw);
    const interventions = JSON.parse(interventionsRaw);

    assert.ok(Array.isArray(bruxism.sections), 'bruxism-info.json should include sections array');
    assert.ok(Array.isArray(interventions.interventions), 'interventions.json should include interventions array');
});
