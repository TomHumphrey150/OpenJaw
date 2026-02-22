import test from 'node:test';
import assert from 'node:assert/strict';
import {
  loadCatalogInterventions,
  normalizeStore,
} from '../scripts/normalize-user-data-interventions.mjs';

test('loadCatalogInterventions throws on alias collisions', () => {
  assert.throws(() => {
    loadCatalogInterventions([
      { id: 'one', legacyIds: ['alias'] },
      { id: 'two', legacyIds: ['alias'] },
    ]);
  }, /Alias collision/);
});

test('normalizeStore canonicalizes intervention ids and initializes dose fields', () => {
  const interventions = [
    {
      id: 'water_intake',
      legacyIds: ['hydration_target', 'HYDRATION'],
      trackingType: 'dose',
      doseConfig: { unit: 'milliliters', defaultDailyGoal: 3000, defaultIncrement: 100 },
    },
    {
      id: 'exercise_minutes',
      legacyIds: ['exercise_timing', 'EXERCISE_TX'],
      trackingType: 'dose',
      doseConfig: { unit: 'minutes', defaultDailyGoal: 30, defaultIncrement: 10 },
    },
    {
      id: 'vitamin_d',
      legacyIds: ['VIT_D_TX'],
      trackingType: 'binary',
    },
  ];

  const { canonicalByAlias, doseDefaults } = loadCatalogInterventions(interventions);

  const counters = {
    aliasReplacements: 0,
    duplicateRemovals: 0,
    doseResets: 0,
  };

  const normalized = normalizeStore(
    {
      dailyCheckIns: {
        '2026-02-22': ['hydration_target', 'HYDRATION', 'exercise_timing', 'EXERCISE_TX'],
      },
      hiddenInterventions: ['HYDRATION', 'hydration_target', 'VIT_D_TX'],
      interventionRatings: [
        { interventionId: 'VIT_D_TX', effectiveness: 'effective', lastUpdated: '2026-02-22T00:00:00Z' },
        { interventionId: 'vitamin_d', effectiveness: 'modest', lastUpdated: '2026-02-23T00:00:00Z' },
      ],
      habitClassifications: [
        { interventionId: 'exercise_timing', status: 'helpful', nightsOn: 1, nightsOff: 1, updatedAt: '2026-02-22T00:00:00Z' },
        { interventionId: 'EXERCISE_TX', status: 'neutral', nightsOn: 1, nightsOff: 1, updatedAt: '2026-02-23T00:00:00Z' },
      ],
      habitTrials: [
        { id: 'trial-1', interventionId: 'exercise_timing' },
      ],
      nightExposures: [
        { nightId: '2026-02-22', interventionId: 'hydration_target', enabled: true },
      ],
      experiments: [
        { id: 'exp-1', interventionId: 'exercise_timing', interventionName: 'Exercise' },
      ],
      dailyDoseProgress: {
        '2026-02-22': { hydration_target: 100, HYDRATION: 200 },
      },
      interventionDoseSettings: {
        hydration_target: { dailyGoal: 2500, increment: 50 },
      },
    },
    canonicalByAlias,
    doseDefaults,
    counters
  );

  assert.deepEqual(normalized.dailyCheckIns['2026-02-22'], ['water_intake', 'exercise_minutes']);
  assert.deepEqual(normalized.hiddenInterventions, ['water_intake', 'vitamin_d']);

  assert.equal(normalized.interventionRatings.length, 1);
  assert.equal(normalized.interventionRatings[0].interventionId, 'vitamin_d');

  assert.equal(normalized.habitClassifications.length, 1);
  assert.equal(normalized.habitClassifications[0].interventionId, 'exercise_minutes');
  assert.equal(normalized.habitTrials[0].interventionId, 'exercise_minutes');
  assert.equal(normalized.nightExposures[0].interventionId, 'water_intake');
  assert.equal(normalized.experiments[0].interventionId, 'exercise_minutes');

  assert.deepEqual(normalized.dailyDoseProgress, {});
  assert.deepEqual(normalized.interventionDoseSettings.water_intake, { dailyGoal: 2500, increment: 50 });
  assert.deepEqual(normalized.interventionDoseSettings.exercise_minutes, { dailyGoal: 30, increment: 10 });

  assert.ok(counters.aliasReplacements > 0);
  assert.ok(counters.duplicateRemovals > 0);
  assert.equal(counters.doseResets, 1);
});

test('normalizeStore does not count dose reset when daily progress is already empty', () => {
  const interventions = [
    {
      id: 'water_intake',
      legacyIds: ['HYDRATION'],
      trackingType: 'dose',
      doseConfig: { unit: 'milliliters', defaultDailyGoal: 3000, defaultIncrement: 100 },
    },
  ];

  const { canonicalByAlias, doseDefaults } = loadCatalogInterventions(interventions);

  const counters = {
    aliasReplacements: 0,
    duplicateRemovals: 0,
    doseResets: 0,
  };

  const normalized = normalizeStore(
    {
      dailyDoseProgress: {},
      interventionDoseSettings: {
        water_intake: { dailyGoal: 3000, increment: 100 },
      },
    },
    canonicalByAlias,
    doseDefaults,
    counters
  );

  assert.deepEqual(normalized.dailyDoseProgress, {});
  assert.equal(counters.doseResets, 0);
});
