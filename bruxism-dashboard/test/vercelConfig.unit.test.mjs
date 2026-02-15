import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

test('vercel.json keeps static output config and does not reintroduce rewrites', async () => {
    const raw = await readFile(new URL('../vercel.json', import.meta.url), 'utf-8');
    const config = JSON.parse(raw);

    assert.equal(config.outputDirectory, 'public');
    assert.equal(Object.hasOwn(config, 'rewrites'), false);
});
