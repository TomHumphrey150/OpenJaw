import process from 'node:process';
import { createClient } from '@supabase/supabase-js';
import { isUnknownRecord } from './pillar-integrity-lib';

const BATCH_SIZE = 200;

interface ParsedArgs {
  userID: string | null;
  limit: number | null;
  write: boolean;
  dryRun: boolean;
  allUsers: boolean;
}

interface UserDataRow {
  userID: string;
  store: Record<string, unknown>;
  updatedAt: string | null;
}

interface ResetPlan {
  userID: string;
  updatedAt: string | null;
  nextStore: Record<string, unknown>;
  dailyCheckInsCount: number;
  morningStatesCount: number;
  foundationCheckInsCount: number;
  pillarCheckInsCount: number;
  hadMorningQuestionnaire: boolean;
  hadProgressQuestionSetState: boolean;
}

function requiredEnv(...names: string[]): string {
  for (const name of names) {
    const value = process.env[name];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }

  throw new Error(`Missing environment variable. Provide one of: ${names.join(', ')}`);
}

function getArg(name: string): string | null {
  const needle = `--${name}`;
  const index = process.argv.indexOf(needle);
  if (index < 0) {
    return null;
  }

  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) {
    return null;
  }

  return value;
}

function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
}

function parseLimit(rawLimit: string | null): number | null {
  if (rawLimit === null) {
    return null;
  }

  const value = Number(rawLimit);
  if (!Number.isInteger(value) || value <= 0 || value > 10_000) {
    throw new Error(`Invalid --limit value "${rawLimit}". Use an integer between 1 and 10000.`);
  }

  return value;
}

function parseArgs(): ParsedArgs {
  const write = hasFlag('write');
  const dryRunFlag = hasFlag('dry-run');

  if (write && dryRunFlag) {
    throw new Error('Choose either --dry-run or --write, not both.');
  }

  return {
    userID: getArg('user-id'),
    limit: parseLimit(getArg('limit')),
    write,
    dryRun: dryRunFlag || !write,
    allUsers: hasFlag('all-users'),
  };
}

function printUsageAndExit(): never {
  console.error('Usage:');
  console.error('  npm run reset:progress-checkins -- --dry-run [--limit <n>]');
  console.error('  npm run reset:progress-checkins -- --write --all-users [--limit <n>]');
  console.error('  npm run reset:progress-checkins -- --dry-run --user-id <uuid>');
  console.error('  npm run reset:progress-checkins -- --write --user-id <uuid>');
  process.exit(1);
  throw new Error('Unreachable');
}

function parseUserDataRows(rawRows: unknown): UserDataRow[] {
  if (!Array.isArray(rawRows)) {
    return [];
  }

  const rows: UserDataRow[] = [];
  for (const entry of rawRows) {
    if (!isUnknownRecord(entry)) {
      continue;
    }

    const userID = typeof entry.user_id === 'string' ? entry.user_id.trim() : '';
    if (userID.length === 0) {
      continue;
    }

    const store = isUnknownRecord(entry.data) ? entry.data : {};
    const updatedAt = typeof entry.updated_at === 'string' ? entry.updated_at : null;

    rows.push({
      userID,
      store,
      updatedAt,
    });
  }

  return rows;
}

function readArrayLength(store: Record<string, unknown>, key: string): number {
  const value = store[key];
  if (!Array.isArray(value)) {
    return 0;
  }

  return value.length;
}

function readObjectKeyCount(store: Record<string, unknown>, key: string): number {
  const value = store[key];
  if (!isUnknownRecord(value)) {
    return 0;
  }

  return Object.keys(value).length;
}

function hasNonNullValue(store: Record<string, unknown>, key: string): boolean {
  if (!Object.prototype.hasOwnProperty.call(store, key)) {
    return false;
  }

  return store[key] !== null;
}

function planReset(row: UserDataRow): ResetPlan | null {
  const dailyCheckInsCount = readObjectKeyCount(row.store, 'dailyCheckIns');
  const morningStatesCount = readArrayLength(row.store, 'morningStates');
  const foundationCheckInsCount = readArrayLength(row.store, 'foundationCheckIns');
  const pillarCheckInsCount = readArrayLength(row.store, 'pillarCheckIns');
  const hadMorningQuestionnaire = hasNonNullValue(row.store, 'morningQuestionnaire');
  const hadProgressQuestionSetState = hasNonNullValue(row.store, 'progressQuestionSetState');

  const shouldReset =
    dailyCheckInsCount > 0
    || morningStatesCount > 0
    || foundationCheckInsCount > 0
    || hadMorningQuestionnaire
    || hadProgressQuestionSetState;
  if (!shouldReset) {
    return null;
  }

  const nextStore = structuredClone(row.store);
  delete nextStore.dailyCheckIns;
  delete nextStore.morningStates;
  delete nextStore.foundationCheckIns;
  delete nextStore.progressQuestionSetState;
  delete nextStore.morningQuestionnaire;

  return {
    userID: row.userID,
    updatedAt: row.updatedAt,
    nextStore,
    dailyCheckInsCount,
    morningStatesCount,
    foundationCheckInsCount,
    pillarCheckInsCount,
    hadMorningQuestionnaire,
    hadProgressQuestionSetState,
  };
}

async function loadRowsForSingleUser(
  supabaseURL: string,
  supabaseSecretKey: string,
  userID: string,
): Promise<UserDataRow[]> {
  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const query = await supabase
    .from('user_data')
    .select('user_id,data,updated_at')
    .eq('user_id', userID);

  if (query.error) {
    throw new Error(`user_data query failed for user_id=${userID}: ${query.error.message}`);
  }

  return parseUserDataRows(query.data);
}

async function loadRowsForAllUsers(
  supabaseURL: string,
  supabaseSecretKey: string,
  limit: number | null,
): Promise<UserDataRow[]> {
  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const allRows: UserDataRow[] = [];
  let startIndex = 0;

  while (true) {
    const remaining = limit === null ? BATCH_SIZE : limit - allRows.length;
    if (remaining <= 0) {
      break;
    }
    const batchSize = Math.min(BATCH_SIZE, remaining);
    const endIndex = startIndex + batchSize - 1;

    const query = await supabase
      .from('user_data')
      .select('user_id,data,updated_at')
      .order('updated_at', { ascending: false })
      .range(startIndex, endIndex);

    if (query.error) {
      throw new Error(`user_data query failed: ${query.error.message}`);
    }

    const rows = parseUserDataRows(query.data);
    allRows.push(...rows);

    if (rows.length < batchSize) {
      break;
    }

    startIndex += rows.length;
  }

  return allRows;
}

function printPlan(mode: 'dry-run' | 'write', scannedRows: number, plans: ResetPlan[]): void {
  const totalDailyCheckIns = plans.reduce((sum, row) => sum + row.dailyCheckInsCount, 0);
  const totalMorningStates = plans.reduce((sum, row) => sum + row.morningStatesCount, 0);
  const totalFoundationCheckIns = plans.reduce((sum, row) => sum + row.foundationCheckInsCount, 0);
  const totalPillarCheckIns = plans.reduce((sum, row) => sum + row.pillarCheckInsCount, 0);
  const totalMorningQuestionnaires = plans.reduce(
    (sum, row) => sum + (row.hadMorningQuestionnaire ? 1 : 0),
    0,
  );
  const totalProgressQuestionState = plans.reduce(
    (sum, row) => sum + (row.hadProgressQuestionSetState ? 1 : 0),
    0,
  );

  console.log(`Mode: ${mode}`);
  console.log(`Rows scanned: ${scannedRows}`);
  console.log(`Rows requiring reset: ${plans.length}`);
  console.log(`Daily check-in day maps to remove: ${totalDailyCheckIns}`);
  console.log(`Morning states to clear: ${totalMorningStates}`);
  console.log(`Foundation check-ins to clear: ${totalFoundationCheckIns}`);
  console.log(`Pillar check-ins retained: ${totalPillarCheckIns}`);
  console.log(`Morning questionnaires to remove: ${totalMorningQuestionnaires}`);
  console.log(`Progress question states to clear: ${totalProgressQuestionState}`);

  if (plans.length === 0) {
    return;
  }

  console.log('Rows requiring reset (user_id | updated_at | daily/morning/foundation/pillar/questionnaire/state):');
  for (const row of plans) {
    const questionnaireFlag = row.hadMorningQuestionnaire ? 'yes' : 'no';
    const stateFlag = row.hadProgressQuestionSetState ? 'yes' : 'no';
    console.log(
      `  ${row.userID} | ${row.updatedAt ?? '(missing)'} | ${row.dailyCheckInsCount}/${row.morningStatesCount}/${row.foundationCheckInsCount}/${row.pillarCheckInsCount}/${questionnaireFlag}/${stateFlag}`,
    );
  }
}

async function applyResetPlans(
  supabaseURL: string,
  supabaseSecretKey: string,
  plans: ResetPlan[],
): Promise<void> {
  if (plans.length === 0) {
    return;
  }

  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  for (const plan of plans) {
    const update = await supabase
      .from('user_data')
      .update({ data: plan.nextStore })
      .eq('user_id', plan.userID);

    if (update.error) {
      throw new Error(`Failed to update user_id=${plan.userID}: ${update.error.message}`);
    }
  }
}

async function run(): Promise<void> {
  const args = parseArgs();
  if (args.userID === null && args.write && !args.allUsers) {
    throw new Error('Refusing global write without --all-users.');
  }

  if (args.userID !== null && args.allUsers) {
    throw new Error('Use either --user-id or --all-users, not both.');
  }

  if (args.userID === null && args.limit !== null && args.limit <= 0) {
    printUsageAndExit();
  }

  const supabaseURL = requiredEnv('SUPABASE_URL');
  const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');

  const rows = args.userID === null
    ? await loadRowsForAllUsers(supabaseURL, supabaseSecretKey, args.limit)
    : await loadRowsForSingleUser(supabaseURL, supabaseSecretKey, args.userID);

  if (args.userID !== null && rows.length === 0) {
    console.log(`No row found for user_id=${args.userID}`);
    return;
  }

  const plans: ResetPlan[] = [];
  for (const row of rows) {
    const plan = planReset(row);
    if (plan !== null) {
      plans.push(plan);
    }
  }

  printPlan(args.write ? 'write' : 'dry-run', rows.length, plans);
  if (args.dryRun) {
    return;
  }

  await applyResetPlans(supabaseURL, supabaseSecretKey, plans);
  console.log(`Applied reset to ${plans.length} row(s).`);
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
});
