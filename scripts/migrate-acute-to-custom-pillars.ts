import process from 'node:process';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { createClient } from '@supabase/supabase-js';
import { AUTHORIZED_USER_ID } from './user-graph-patch-lib';
import { isUnknownRecord, UnknownRecord } from './pillar-integrity-lib';

interface ParsedArgs {
  dryRun: boolean;
  write: boolean;
  strict: boolean;
  allowGlobalWrites: boolean;
  confirmHardDelete: boolean;
  dryRunArtifactPath: string | null;
  reportOutPath: string | null;
}

interface InterventionRecord {
  id: string;
  value: UnknownRecord;
}

interface UserContentRow {
  user_id: string;
  data: unknown;
}

interface UserDataRow {
  user_id: string;
  data: unknown;
}

interface PlannedUserMutation {
  userID: string;
  pillarID: string;
  pillarTitle: string;
  transformedAcuteInterventionCount: number;
  createdUserContentRow: boolean;
  userDefinedPillarsAdded: number;
  pillarAssignmentsUpdated: boolean;
  activeQuestionsUpdated: boolean;
}

interface PillarAssignmentRecord {
  pillarId: string;
  graphNodeIds: string[];
  graphEdgeIds: string[];
  interventionIds: string[];
  questionId: string;
}

interface MigrationReport {
  generatedAt: string;
  mode: 'dry-run' | 'write';
  strict: boolean;
  acuteInterventionIDs: string[];
  firstPartyInterventionsBefore: number;
  firstPartyInterventionsAfter: number;
  plannedUserMutations: PlannedUserMutation[];
  plannedUserMutationsCount: number;
  hardDeleteSummary: {
    firstPartyAcuteRemoved: number;
  };
  checksum: string;
}

interface MigrationChecksumInput {
  acuteInterventionIDs: string[];
  firstPartyInterventionsBefore: number;
  firstPartyInterventionsAfter: number;
  plannedUserMutations: PlannedUserMutation[];
  plannedUserMutationsCount: number;
  hardDeleteSummary: {
    firstPartyAcuteRemoved: number;
  };
}

function hasFlag(name: string): boolean {
  return process.argv.includes(`--${name}`);
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

function requiredEnv(...names: string[]): string {
  for (const name of names) {
    const value = process.env[name];
    if (typeof value === 'string' && value.trim().length > 0) {
      return value.trim();
    }
  }
  throw new Error(`Missing environment variable. Provide one of: ${names.join(', ')}`);
}

function parseArgs(): ParsedArgs {
  const write = hasFlag('write');
  const dryRun = hasFlag('dry-run') || !write;
  if (write && hasFlag('dry-run')) {
    throw new Error('Choose either --dry-run or --write, not both.');
  }

  return {
    dryRun,
    write,
    strict: hasFlag('strict'),
    allowGlobalWrites: hasFlag('allow-global-writes'),
    confirmHardDelete: hasFlag('confirm-hard-delete'),
    dryRunArtifactPath: getArg('dry-run-artifact'),
    reportOutPath: getArg('report-out'),
  };
}

function printUsageAndExit(): never {
  console.error(
    'Usage: npm run migrate:acute-to-custom-pillars -- --dry-run|--write [--strict] [--allow-global-writes] [--confirm-hard-delete] [--dry-run-artifact <path>] [--report-out <path>]',
  );
  process.exit(1);
}

function readOptionalString(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }
  const trimmed = value.trim();
  return trimmed.length === 0 ? null : trimmed;
}

function readStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const values = new Set<string>();
  for (const entry of value) {
    const parsed = readOptionalString(entry);
    if (parsed !== null) {
      values.add(parsed);
    }
  }
  return [...values].sort((left, right) => left.localeCompare(right));
}

function asInterventionsCatalog(data: unknown): InterventionRecord[] {
  if (!isUnknownRecord(data)) {
    return [];
  }
  const interventionsRaw = data.interventions;
  if (!Array.isArray(interventionsRaw)) {
    return [];
  }

  const parsed: InterventionRecord[] = [];
  for (const row of interventionsRaw) {
    if (!isUnknownRecord(row)) {
      continue;
    }
    const id = readOptionalString(row.id);
    if (id === null) {
      continue;
    }
    parsed.push({ id, value: row });
  }
  return parsed;
}

function isAcuteIntervention(record: InterventionRecord): boolean {
  const planningTags = new Set(readStringArray(record.value.planningTags));
  if (planningTags.has('acute')) {
    return true;
  }
  const pillars = new Set(readStringArray(record.value.pillars));
  return pillars.has('acute');
}

function normalizedTagsWithoutAcute(record: InterventionRecord): string[] {
  return readStringArray(record.value.planningTags).filter((tag) => tag !== 'acute');
}

function transformedInterventionForPillar(record: InterventionRecord, pillarID: string): UnknownRecord {
  const transformed = structuredClone(record.value);
  transformed.pillars = [pillarID];
  transformed.planningTags = normalizedTagsWithoutAcute(record);
  return transformed;
}

function sanitizePillarTitle(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length === 0) {
    return 'My Acute';
  }
  return trimmed;
}

function checksumForReportInput(value: unknown): string {
  const payload = JSON.stringify(value);
  return createHash('sha256').update(payload, 'utf8').digest('hex');
}

function readPillarAssignmentRecord(value: unknown): PillarAssignmentRecord | null {
  if (!isUnknownRecord(value)) {
    return null;
  }
  const pillarId = readOptionalString(value.pillarId);
  if (pillarId === null) {
    return null;
  }
  const questionId = readOptionalString(value.questionId) ?? `pillar.${pillarId}`;
  return {
    pillarId,
    graphNodeIds: readStringArray(value.graphNodeIds),
    graphEdgeIds: readStringArray(value.graphEdgeIds),
    interventionIds: readStringArray(value.interventionIds),
    questionId,
  };
}

function areStringArraysEqual(left: string[], right: string[]): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      return false;
    }
  }
  return true;
}

function arePillarAssignmentsEqual(left: PillarAssignmentRecord, right: PillarAssignmentRecord): boolean {
  return (
    left.pillarId === right.pillarId
    && left.questionId === right.questionId
    && areStringArraysEqual(left.graphNodeIds, right.graphNodeIds)
    && areStringArraysEqual(left.graphEdgeIds, right.graphEdgeIds)
    && areStringArraysEqual(left.interventionIds, right.interventionIds)
  );
}

interface QuestionGraphSources {
  sourceNodeIDs: string[];
  sourceEdgeIDs: string[];
}

function readQuestionGraphSources(
  progressQuestionSetState: unknown,
  questionID: string,
): QuestionGraphSources | null {
  if (!isUnknownRecord(progressQuestionSetState)) {
    return null;
  }

  const activeQuestionsRaw = progressQuestionSetState.activeQuestions;
  if (!Array.isArray(activeQuestionsRaw)) {
    return null;
  }

  for (const row of activeQuestionsRaw) {
    if (!isUnknownRecord(row)) {
      continue;
    }
    const id = readOptionalString(row.id);
    if (id !== questionID) {
      continue;
    }

    return {
      sourceNodeIDs: readStringArray(row.sourceNodeIDs),
      sourceEdgeIDs: readStringArray(row.sourceEdgeIDs),
    };
  }
  return null;
}

interface GraphEdgeEndpoint {
  source: string;
  target: string;
}

function buildGraphEdgeEndpointMap(userData: UnknownRecord): Map<string, GraphEdgeEndpoint> {
  const endpointsByEdgeID = new Map<string, GraphEdgeEndpoint>();
  const customCausalDiagram = isUnknownRecord(userData.customCausalDiagram)
    ? userData.customCausalDiagram
    : null;
  if (customCausalDiagram === null) {
    return endpointsByEdgeID;
  }
  const graphData = isUnknownRecord(customCausalDiagram.graphData)
    ? customCausalDiagram.graphData
    : null;
  if (graphData === null || !Array.isArray(graphData.edges)) {
    return endpointsByEdgeID;
  }

  const duplicateCounterByBase = new Map<string, number>();
  for (const edgeRaw of graphData.edges) {
    if (!isUnknownRecord(edgeRaw)) {
      continue;
    }
    const data = isUnknownRecord(edgeRaw.data)
      ? edgeRaw.data
      : edgeRaw;
    const source = readOptionalString(data.source);
    const target = readOptionalString(data.target);
    if (source === null || target === null) {
      continue;
    }
    const edgeType = readOptionalString(data.edgeType) ?? '';
    const label = readOptionalString(data.label) ?? '';
    const explicitID = readOptionalString(data.id);
    const base = `edge:${source}|${target}|${edgeType}|${label}`;
    const duplicateIndex = duplicateCounterByBase.get(base) ?? 0;
    duplicateCounterByBase.set(base, duplicateIndex + 1);
    const edgeID = explicitID ?? `${base}#${duplicateIndex}`;
    endpointsByEdgeID.set(edgeID, { source, target });
  }
  return endpointsByEdgeID;
}

function loadArtifactChecksum(artifactPath: string): string {
  const raw = readFileSync(artifactPath, 'utf8');
  const parsed = JSON.parse(raw) as UnknownRecord;
  const checksum = readOptionalString(parsed.checksum);
  if (checksum === null) {
    throw new Error(`Dry-run artifact ${artifactPath} is missing checksum.`);
  }
  return checksum;
}

function runStrictPreflightChecks(): void {
  execSync('npm run test', { stdio: 'inherit' });
  execSync(
    `npm run debug:user-graph-audit -- --user-id ${AUTHORIZED_USER_ID} --raw`,
    { stdio: 'inherit' },
  );
  execSync(
    `npm run debug:pillar-integrity -- --user-id ${AUTHORIZED_USER_ID} --strict --raw`,
    { stdio: 'inherit' },
  );
}

function ensureWriteGuardrails(args: ParsedArgs, reportChecksum: string): void {
  if (!args.write) {
    return;
  }
  if (!args.strict) {
    throw new Error('Write mode requires --strict.');
  }
  if (!args.allowGlobalWrites) {
    throw new Error('Write mode requires --allow-global-writes.');
  }
  if (!args.confirmHardDelete) {
    throw new Error('Write mode requires --confirm-hard-delete.');
  }
  if (args.dryRunArtifactPath === null) {
    throw new Error('Write mode requires --dry-run-artifact <path>.');
  }

  const expectedChecksum = loadArtifactChecksum(args.dryRunArtifactPath);
  if (expectedChecksum !== reportChecksum) {
    throw new Error(
      `Dry-run artifact checksum mismatch. expected=${expectedChecksum} current=${reportChecksum}`,
    );
  }
}

async function run(): Promise<void> {
  const args = parseArgs();

  const supabaseURL = requiredEnv('SUPABASE_URL');
  const supabaseSecretKey = requiredEnv('SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY');
  const supabase = createClient(supabaseURL, supabaseSecretKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const firstPartyCatalogQuery = await supabase
    .from('first_party_content')
    .select('content_type,content_key,data')
    .eq('content_type', 'inputs')
    .eq('content_key', 'interventions_catalog')
    .limit(1)
    .maybeSingle();

  if (firstPartyCatalogQuery.error) {
    throw new Error(`first_party_content interventions query failed: ${firstPartyCatalogQuery.error.message}`);
  }
  if (!firstPartyCatalogQuery.data || !isUnknownRecord(firstPartyCatalogQuery.data.data)) {
    throw new Error('Missing first_party_content inputs/interventions_catalog.');
  }

  const firstPartyContentType = readOptionalString(firstPartyCatalogQuery.data.content_type);
  const firstPartyContentKey = readOptionalString(firstPartyCatalogQuery.data.content_key);
  if (firstPartyContentType === null || firstPartyContentKey === null) {
    throw new Error('first_party_content inputs/interventions_catalog row missing content_type/content_key.');
  }
  const firstPartyCatalogData = structuredClone(firstPartyCatalogQuery.data.data);
  const firstPartyInterventions = asInterventionsCatalog(firstPartyCatalogData);
  const firstPartyAcuteInterventions = firstPartyInterventions.filter(isAcuteIntervention);
  const acuteInterventionIDs = firstPartyAcuteInterventions.map((entry) => entry.id).sort();

  const userDataQuery = await supabase
    .from('user_data')
    .select('user_id,data');
  if (userDataQuery.error) {
    throw new Error(`user_data query failed: ${userDataQuery.error.message}`);
  }
  const userRows = (userDataQuery.data ?? []) as UserDataRow[];

  const userContentQuery = await supabase
    .from('user_content')
    .select('user_id,data')
    .eq('content_type', 'inputs')
    .eq('content_key', 'interventions_catalog');
  if (userContentQuery.error) {
    throw new Error(`user_content interventions query failed: ${userContentQuery.error.message}`);
  }
  const userContentRows = (userContentQuery.data ?? []) as UserContentRow[];
  const userContentByUserID = new Map<string, UnknownRecord>();
  for (const row of userContentRows) {
    if (isUnknownRecord(row.data)) {
      userContentByUserID.set(row.user_id, structuredClone(row.data));
    }
  }

  const plannedUserMutations: PlannedUserMutation[] = [];
  const updatedUserDataByUserID = new Map<string, UnknownRecord>();
  const updatedUserContentByUserID = new Map<string, UnknownRecord>();

  for (const row of userRows) {
    const userID = readOptionalString(row.user_id);
    if (userID === null) {
      continue;
    }
    if (!isUnknownRecord(row.data)) {
      continue;
    }

    const pillarID = 'neck';
    const pillarTitle = userID === AUTHORIZED_USER_ID ? 'My Neck' : 'My Acute';
    const questionID = `pillar.${pillarID}`;

    const nextUserData = structuredClone(row.data);
    const userDefinedPillarsRaw = Array.isArray(nextUserData.userDefinedPillars)
      ? structuredClone(nextUserData.userDefinedPillars)
      : [];
    const pillarAssignmentsRaw = Array.isArray(nextUserData.pillarAssignments)
      ? structuredClone(nextUserData.pillarAssignments)
      : [];

    const baseCatalog = userContentByUserID.get(userID) ?? firstPartyCatalogData;
    const baseInterventions = asInterventionsCatalog(baseCatalog);
    const acuteForUser = baseInterventions.filter(isAcuteIntervention);
    const graphEdgeEndpointByID = buildGraphEdgeEndpointMap(nextUserData);
    const transformedAcute = acuteForUser.map((entry) => ({
      id: entry.id,
      value: transformedInterventionForPillar(entry, pillarID),
    }));

    const existingAssignments = pillarAssignmentsRaw.filter(isUnknownRecord);
    const existingIndex = existingAssignments.findIndex((entry) => readOptionalString(entry.pillarId) === pillarID);
    const nodeIDs = new Set<string>();
    const edgeIDs = new Set<string>();
    const interventionIDs = new Set<string>();

    const existingQuestionSources = readQuestionGraphSources(
      nextUserData.progressQuestionSetState,
      questionID,
    );

    for (const acuteEntry of transformedAcute) {
      interventionIDs.add(acuteEntry.id);
      const nodeID = readOptionalString(acuteEntry.value.graphNodeId);
      if (nodeID !== null) {
        nodeIDs.add(nodeID);
      }
      for (const edgeID of readStringArray(acuteEntry.value.graphEdgeIds)) {
        edgeIDs.add(edgeID);
        const endpoints = graphEdgeEndpointByID.get(edgeID);
        if (endpoints !== undefined) {
          nodeIDs.add(endpoints.source);
          nodeIDs.add(endpoints.target);
        }
      }
    }

    if (transformedAcute.length === 0 && existingQuestionSources !== null) {
      for (const nodeID of existingQuestionSources.sourceNodeIDs) {
        nodeIDs.add(nodeID);
      }
      for (const edgeID of existingQuestionSources.sourceEdgeIDs) {
        edgeIDs.add(edgeID);
        const endpoints = graphEdgeEndpointByID.get(edgeID);
        if (endpoints !== undefined) {
          nodeIDs.add(endpoints.source);
          nodeIDs.add(endpoints.target);
        }
      }

      if (pillarID == 'neck') {
        const progressQuestionSetState = isUnknownRecord(nextUserData.progressQuestionSetState)
          ? nextUserData.progressQuestionSetState
          : null;
        if (progressQuestionSetState !== null) {
          const activeQuestionsRaw = progressQuestionSetState.activeQuestions;
          if (Array.isArray(activeQuestionsRaw)) {
            for (const questionRow of activeQuestionsRaw) {
              if (!isUnknownRecord(questionRow)) {
                continue;
              }
              const id = readOptionalString(questionRow.id);
              if (id === null || !id.startsWith('morning.')) {
                continue;
              }
              for (const nodeID of readStringArray(questionRow.sourceNodeIDs)) {
                nodeIDs.add(nodeID);
              }
              for (const edgeID of readStringArray(questionRow.sourceEdgeIDs)) {
                edgeIDs.add(edgeID);
                const endpoints = graphEdgeEndpointByID.get(edgeID);
                if (endpoints !== undefined) {
                  nodeIDs.add(endpoints.source);
                  nodeIDs.add(endpoints.target);
                }
              }
            }
          }
        }
      }

      for (const intervention of baseInterventions) {
        const graphNodeID = readOptionalString(intervention.value.graphNodeId);
        const graphEdgeIDs = readStringArray(intervention.value.graphEdgeIds);
        const nodeMatch = graphNodeID !== null && nodeIDs.has(graphNodeID);
        const edgeMatch = graphEdgeIDs.some((edgeID) => edgeIDs.has(edgeID));
        if (nodeMatch || edgeMatch) {
          interventionIDs.add(intervention.id);
        }
      }
    }

    let userDefinedPillarsAdded = 0;
    const hasPillar = userDefinedPillarsRaw.some((entry) => isUnknownRecord(entry) && readOptionalString(entry.id) === pillarID);
    const hasAssignmentSource =
      interventionIDs.size > 0
      || nodeIDs.size > 0
      || edgeIDs.size > 0;
    if (!hasPillar && hasAssignmentSource) {
      const timestamp = new Date().toISOString();
      userDefinedPillarsRaw.push({
        id: pillarID,
        title: sanitizePillarTitle(pillarTitle),
        templateId: 'acute-neck-template',
        createdAt: timestamp,
        updatedAt: timestamp,
        isArchived: false,
      });
      userDefinedPillarsAdded = 1;
    }

    let pillarAssignmentsUpdated = false;
    if (hasAssignmentSource) {
      const nextAssignmentRecord: PillarAssignmentRecord = {
        pillarId: pillarID,
        graphNodeIds: [...nodeIDs].sort((left, right) => left.localeCompare(right)),
        graphEdgeIds: [...edgeIDs].sort((left, right) => left.localeCompare(right)),
        interventionIds: [...interventionIDs].sort((left, right) => left.localeCompare(right)),
        questionId: questionID,
      };
      const nextAssignment: UnknownRecord = {
        pillarId: nextAssignmentRecord.pillarId,
        graphNodeIds: nextAssignmentRecord.graphNodeIds,
        graphEdgeIds: nextAssignmentRecord.graphEdgeIds,
        interventionIds: nextAssignmentRecord.interventionIds,
        questionId: nextAssignmentRecord.questionId,
      };
      if (existingIndex >= 0) {
        const existingAssignment = readPillarAssignmentRecord(existingAssignments[existingIndex]);
        if (existingAssignment === null || !arePillarAssignmentsEqual(existingAssignment, nextAssignmentRecord)) {
          existingAssignments[existingIndex] = nextAssignment;
          pillarAssignmentsUpdated = true;
        }
      } else {
        existingAssignments.push(nextAssignment);
        pillarAssignmentsUpdated = true;
      }
    }

    nextUserData.userDefinedPillars = userDefinedPillarsRaw;
    nextUserData.pillarAssignments = existingAssignments;

    let activeQuestionsUpdated = false;
    const progressState = isUnknownRecord(nextUserData.progressQuestionSetState)
      ? structuredClone(nextUserData.progressQuestionSetState)
      : null;
    if (progressState !== null) {
      const activeQuestions = Array.isArray(progressState.activeQuestions)
        ? progressState.activeQuestions.filter(isUnknownRecord)
        : [];
      const hasPillarQuestion = activeQuestions.some((entry) => readOptionalString(entry.id) === questionID);
      if (!hasPillarQuestion && hasAssignmentSource) {
        activeQuestions.push({
          id: questionID,
          title: `How was your ${sanitizePillarTitle(pillarTitle).toLowerCase()} today?`,
          sourceNodeIDs: [...nodeIDs].sort((left, right) => left.localeCompare(right)),
          sourceEdgeIDs: [...edgeIDs].sort((left, right) => left.localeCompare(right)),
        });
        progressState.activeQuestions = activeQuestions;
        progressState.updatedAt = new Date().toISOString();
        activeQuestionsUpdated = true;
      }
      nextUserData.progressQuestionSetState = progressState;
    }

    const baseInterventionByID = new Map<string, UnknownRecord>();
    for (const intervention of baseInterventions) {
      if (!baseInterventionByID.has(intervention.id)) {
        baseInterventionByID.set(intervention.id, structuredClone(intervention.value));
      }
    }
    for (const acuteEntry of transformedAcute) {
      baseInterventionByID.set(acuteEntry.id, structuredClone(acuteEntry.value));
    }

    const nextCatalogInterventions = [...baseInterventionByID.entries()]
      .map(([id, value]) => {
        value.id = id;
        return value;
      })
      .sort((left, right) => {
        const leftID = readOptionalString(left.id) ?? '';
        const rightID = readOptionalString(right.id) ?? '';
        return leftID.localeCompare(rightID);
      });
    const nextUserContent = {
      interventions: nextCatalogInterventions,
    };

    const shouldUpdateUserContent = transformedAcute.length > 0;
    const shouldUpdateUserData =
      userDefinedPillarsAdded > 0
      || pillarAssignmentsUpdated
      || activeQuestionsUpdated;
    if (!shouldUpdateUserData && !shouldUpdateUserContent) {
      continue;
    }

    if (shouldUpdateUserData) {
      updatedUserDataByUserID.set(userID, nextUserData);
    }
    if (shouldUpdateUserContent) {
      updatedUserContentByUserID.set(userID, nextUserContent);
    }
    plannedUserMutations.push({
      userID,
      pillarID,
      pillarTitle,
      transformedAcuteInterventionCount: transformedAcute.length,
      createdUserContentRow: !userContentByUserID.has(userID),
      userDefinedPillarsAdded,
      pillarAssignmentsUpdated,
      activeQuestionsUpdated,
    });
  }

  const nextFirstPartyInterventions = firstPartyInterventions
    .filter((entry) => !isAcuteIntervention(entry))
    .map((entry) => structuredClone(entry.value));
  const nextFirstPartyCatalog = {
    interventions: nextFirstPartyInterventions,
  };

  const checksumInput: MigrationChecksumInput = {
    acuteInterventionIDs,
    firstPartyInterventionsBefore: firstPartyInterventions.length,
    firstPartyInterventionsAfter: nextFirstPartyInterventions.length,
    plannedUserMutations,
    plannedUserMutationsCount: plannedUserMutations.length,
    hardDeleteSummary: {
      firstPartyAcuteRemoved: firstPartyInterventions.length - nextFirstPartyInterventions.length,
    },
  };
  const mode: MigrationReport['mode'] = args.write ? 'write' : 'dry-run';
  const reportBase: Omit<MigrationReport, 'checksum'> = {
    generatedAt: new Date().toISOString(),
    mode,
    strict: args.strict,
    ...checksumInput,
  };
  const checksum = checksumForReportInput(checksumInput);
  const report: MigrationReport = {
    ...reportBase,
    checksum,
  };

  ensureWriteGuardrails(args, checksum);
  if (args.write) {
    runStrictPreflightChecks();

    for (const [userID, data] of updatedUserContentByUserID.entries()) {
      const upsertContent = await supabase
        .from('user_content')
        .upsert(
          {
            user_id: userID,
            content_type: 'inputs',
            content_key: 'interventions_catalog',
            data,
          },
          { onConflict: 'user_id,content_type,content_key' },
        );
      if (upsertContent.error) {
        throw new Error(`Failed to upsert user_content inputs/interventions_catalog for ${userID}: ${upsertContent.error.message}`);
      }
    }

    for (const [userID, data] of updatedUserDataByUserID.entries()) {
      const updateUserData = await supabase
        .from('user_data')
        .update({ data })
        .eq('user_id', userID);
      if (updateUserData.error) {
        throw new Error(`Failed to update user_data for ${userID}: ${updateUserData.error.message}`);
      }
    }

    const updateFirstParty = await supabase
      .from('first_party_content')
      .update({ data: nextFirstPartyCatalog })
      .eq('content_type', firstPartyContentType)
      .eq('content_key', firstPartyContentKey);
    if (updateFirstParty.error) {
      throw new Error(`Failed to hard-delete acute records from first_party_content: ${updateFirstParty.error.message}`);
    }
  }

  const reportOutPath = args.reportOutPath
    ? path.resolve(process.cwd(), args.reportOutPath)
    : path.resolve(
      process.cwd(),
      args.write ? 'artifacts/acute-migration-write.json' : 'artifacts/acute-migration-dry-run.json',
    );
  mkdirSync(path.dirname(reportOutPath), { recursive: true });
  writeFileSync(reportOutPath, JSON.stringify(report, null, 2) + '\n', 'utf8');

  if (args.dryRun) {
    console.log(`Dry-run complete. Planned user migrations: ${plannedUserMutations.length}.`);
    console.log(`First-party acute interventions to hard-delete: ${report.hardDeleteSummary.firstPartyAcuteRemoved}.`);
    console.log(`Report: ${reportOutPath}`);
    return;
  }

  console.log(`Write complete. Migrated users: ${plannedUserMutations.length}.`);
  console.log(`Hard-deleted first-party acute interventions: ${report.hardDeleteSummary.firstPartyAcuteRemoved}.`);
  console.log(`Report: ${reportOutPath}`);
}

run().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`migrate-acute-to-custom-pillars failed: ${message}`);
  process.exit(1);
});
