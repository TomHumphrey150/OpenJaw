#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

function getArg(name, fallback = null) {
  const flag = `--${name}`;
  const index = process.argv.indexOf(flag);
  if (index < 0) {
    return fallback;
  }
  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) {
    return fallback;
  }
  return value;
}

function parsePillarsFromReport(markdown) {
  const lines = markdown.split(/\r?\n/);
  const pillars = [];
  let current = null;

  for (const line of lines) {
    const sectionMatch = line.match(/^##\s+(\d+)\.\s+(.+)$/);
    if (sectionMatch) {
      if (current) {
        pillars.push(current);
      }
      const rank = Number(sectionMatch[1]);
      current = {
        rank,
        title: sectionMatch[2].trim(),
        subdomains: [],
        baselineMaintenances: [],
        blockerPatterns: [],
      };
      continue;
    }

    if (!current) {
      continue;
    }

    const subdomainMatch = line.match(/^###\s+\d+\.\d+\s+(.+)$/);
    if (subdomainMatch) {
      current.subdomains.push(subdomainMatch[1].trim());
      continue;
    }

    const bulletMatch = line.match(/^\s*-\s+(.+)$/);
    if (!bulletMatch) {
      continue;
    }

    const text = bulletMatch[1].trim();
    if (text.length === 0) {
      continue;
    }

    current.baselineMaintenances.push(text);
    const lower = text.toLowerCase();
    if (
      lower.includes('avoid') ||
      lower.includes('limit') ||
      lower.includes('screen') ||
      lower.includes('disorder') ||
      lower.includes('treatment') ||
      lower.includes('stress') ||
      lower.includes('apnoea') ||
      lower.includes('insomnia')
    ) {
      current.blockerPatterns.push(text);
    }
  }

  if (current) {
    pillars.push(current);
  }

  return pillars;
}

function pillarIDForRank(rank) {
  const map = {
    1: 'sleep',
    2: 'nutrition',
    3: 'exercise',
    4: 'socialLife',
    5: 'stressManagement',
    6: 'avoidingDrugs',
    7: 'medical',
    8: 'romanticPersonalCare',
    9: 'environment',
    10: 'financialSecurity',
  };
  return map[rank] ?? null;
}

function parseCatalogInterventionIDs(jsonText) {
  const payload = JSON.parse(jsonText);
  if (Array.isArray(payload?.interventions)) {
    return new Set(payload.interventions.map((value) => value.id).filter(Boolean));
  }
  if (payload?.data?.interventions && Array.isArray(payload.data.interventions)) {
    return new Set(payload.data.interventions.map((value) => value.id).filter(Boolean));
  }
  return new Set();
}

function parseGraphNodeIDs(graphText) {
  const graph = JSON.parse(graphText);
  const nodes = graph?.nodes ?? graph?.graphData?.nodes ?? [];
  return new Set(nodes.map((node) => node?.data?.id).filter(Boolean));
}

function parseMappingsFromCatalog(catalogText) {
  const payload = JSON.parse(catalogText);
  const interventions = Array.isArray(payload?.interventions) ? payload.interventions : [];
  const mappings = interventions
    .filter((intervention) => {
      if (!intervention || typeof intervention !== 'object') {
        return false;
      }
      if (typeof intervention.id !== 'string' || intervention.id.trim().length === 0) {
        return false;
      }
      if (!Array.isArray(intervention.pillars) || intervention.pillars.length === 0) {
        return false;
      }
      if (!Array.isArray(intervention.planningTags) || intervention.planningTags.length === 0) {
        return false;
      }
      return true;
    })
    .map((intervention) => {
      const preferredWindows = Array.isArray(intervention.preferredWindows)
        ? intervention.preferredWindows
            .filter(
              (window) =>
                window &&
                Number.isFinite(window.startMinutes) &&
                Number.isFinite(window.endMinutes)
            )
            .map((window) => ({
              startMinutes: Math.max(0, Math.min(24 * 60, Number(window.startMinutes))),
              endMinutes: Math.max(0, Math.min(24 * 60, Number(window.endMinutes))),
            }))
            .filter((window) => window.endMinutes > window.startMinutes)
        : [];

      const mapping = {
        interventionID: intervention.id,
        pillars: intervention.pillars.filter((value) => typeof value === 'string'),
        tags: intervention.planningTags.filter((value) => typeof value === 'string'),
        foundationRole:
          intervention.foundationRole === 'blocker' ? 'blocker' : 'maintenance',
        acuteTargetNodeIDs: Array.isArray(intervention.acuteTargets)
          ? intervention.acuteTargets.filter((value) => typeof value === 'string')
          : [],
        defaultMinutes:
          Number.isFinite(intervention.defaultMinutes) && intervention.defaultMinutes > 0
            ? Number(intervention.defaultMinutes)
            : 15,
        ladderTemplateID:
          typeof intervention.ladderTemplateID === 'string' && intervention.ladderTemplateID.trim().length > 0
            ? intervention.ladderTemplateID
            : 'general',
      };

      if (preferredWindows.length > 0) {
        mapping.preferredWindows = preferredWindows;
      }

      return mapping;
    })
    .sort((lhs, rhs) => lhs.interventionID.localeCompare(rhs.interventionID));

  return mappings;
}

function ensure(condition, message) {
  if (!condition) {
    console.error(message);
    process.exit(1);
  }
}

const repoRoot = process.cwd();
const reportPath = getArg('report-path', path.join(repoRoot, 'ios', 'Telocare', 'v1-foundation-health.md'));
const graphPath = getArg(
  'graph-path',
  path.join(repoRoot, 'ios', 'Telocare', 'Telocare', 'Resources', 'Graph', 'default-graph.json')
);
const catalogPath = getArg('catalog-path', path.join(repoRoot, 'data', 'interventions.json'));
const outputPath = getArg(
  'out',
  path.join(repoRoot, 'ios', 'Telocare', 'Telocare', 'Resources', 'Foundation', 'foundation-v1-catalog.json')
);

ensure(fs.existsSync(reportPath), `Missing report file: ${reportPath}`);
ensure(fs.existsSync(graphPath), `Missing graph file: ${graphPath}`);
ensure(fs.existsSync(catalogPath), `Missing catalog file: ${catalogPath}`);

const reportText = fs.readFileSync(reportPath, 'utf8');
const graphText = fs.readFileSync(graphPath, 'utf8');
const catalogText = fs.readFileSync(catalogPath, 'utf8');

const parsedPillars = parsePillarsFromReport(reportText);
const pillars = parsedPillars
  .map((pillar) => {
    const id = pillarIDForRank(pillar.rank);
    if (!id) {
      return null;
    }
    return {
      id,
      rank: pillar.rank,
      title: pillar.title,
      subdomains: pillar.subdomains,
      baselineMaintenances: pillar.baselineMaintenances.slice(0, 20),
      blockerPatterns: pillar.blockerPatterns.slice(0, 20),
    };
  })
  .filter(Boolean)
  .sort((lhs, rhs) => lhs.rank - rhs.rank);

ensure(pillars.length === 10, `Expected 10 pillars, found ${pillars.length}`);

const mappings = parseMappingsFromCatalog(catalogText);
ensure(mappings.length >= 40, `Expected at least 40 intervention mappings, found ${mappings.length}`);

const nodeIDs = parseGraphNodeIDs(graphText);
const interventionIDs = parseCatalogInterventionIDs(catalogText);
ensure(interventionIDs.size > 0, `No interventions loaded from catalog: ${catalogPath}`);
const pillarIDs = new Set(pillars.map((pillar) => pillar.id));

for (const mapping of mappings) {
  ensure(interventionIDs.has(mapping.interventionID), `Unknown intervention ID: ${mapping.interventionID}`);
  for (const pillarID of mapping.pillars) {
    ensure(
      pillarIDs.has(pillarID),
      `Unknown pillar ID in mapping: ${mapping.interventionID} -> ${pillarID}`
    );
  }
  for (const nodeID of mapping.acuteTargetNodeIDs) {
    ensure(nodeIDs.has(nodeID), `Unknown graph node ID in mapping: ${mapping.interventionID} -> ${nodeID}`);
  }
}

const output = {
  schemaVersion: 'foundation.v1',
  sourceReportPath: reportPath,
  generatedAt: new Date().toISOString(),
  pillars,
  interventionMappings: mappings,
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(output, null, 2)}\n`);
console.log(`Wrote foundation catalog: ${outputPath}`);
