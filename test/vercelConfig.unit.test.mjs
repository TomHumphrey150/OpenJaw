import assert from 'node:assert/strict';
import { lstat, readFile } from 'node:fs/promises';
import { test } from 'node:test';

test('vercel.json explicitly routes static public files and api functions', async () => {
    const raw = await readFile(new URL('../vercel.json', import.meta.url), 'utf-8');
    const config = JSON.parse(raw);

    assert.equal(config.version, 2);
    assert.ok(Array.isArray(config.builds));
    assert.ok(Array.isArray(config.routes));

    const nodeBuild = config.builds.find((b) => b.src === 'api/**/*.ts');
    const staticBuild = config.builds.find((b) => b.src === 'public/**/*');
    assert.equal(nodeBuild?.use, '@vercel/node');
    assert.equal(staticBuild?.use, '@vercel/static');

    const apiRoute = config.routes.find((r) => r.src === '/api/(.*)');
    const rootRoute = config.routes.find((r) => r.src === '/');
    assert.equal(apiRoute?.dest, '/api/$1');
    assert.equal(rootRoute?.dest, '/public/index.html');
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
