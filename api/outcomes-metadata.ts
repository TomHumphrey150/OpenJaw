import type { VercelRequest, VercelResponse } from '@vercel/node';
import defaultGraph from '../data/default-graph.json';
import {
  FirstPartyContentKey,
  FirstPartyContentType,
  isObjectPayload,
  loadFirstPartyContent,
} from './firstPartyContent';

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function firstLine(value: unknown): string {
  if (typeof value !== 'string') {
    return '';
  }

  const index = value.indexOf('\n');
  if (index < 0) {
    return value;
  }

  return value.slice(0, index);
}

function isOutcomesMetadataPayload(value: unknown): value is { metrics: unknown[]; nodes: unknown[] } {
  if (!isObjectPayload(value)) {
    return false;
  }

  return Array.isArray(value.metrics) && Array.isArray(value.nodes);
}

function fallbackOutcomesMetadata() {
  const graphData: unknown = defaultGraph;

  if (!isRecord(graphData) || !Array.isArray(graphData.nodes)) {
    return {
      metrics: [],
      nodes: [],
      updatedAt: new Date().toISOString(),
    };
  }

  const metrics = [
    {
      id: 'microArousalRatePerHour',
      label: 'Microarousal rate per hour',
      unit: 'events/hour',
      direction: 'lower_better',
      description: 'Frequency of microarousal events during sleep. Lower values indicate calmer sleep continuity.',
    },
    {
      id: 'microArousalCount',
      label: 'Microarousal count',
      unit: 'events/night',
      direction: 'lower_better',
      description: 'Total microarousal events observed during the recorded night.',
    },
    {
      id: 'confidence',
      label: 'Outcome confidence',
      unit: '0_to_1',
      direction: 'higher_better',
      description: 'Model confidence for the recorded outcome estimate.',
    },
  ];

  const nodes = graphData.nodes
    .filter((node) => {
      if (!isRecord(node) || !isRecord(node.data)) {
        return false;
      }

      const id = node.data.id;
      const styleClass = node.data.styleClass;

      if (typeof id !== 'string' || typeof styleClass !== 'string') {
        return false;
      }

      if (styleClass === 'symptom') {
        return true;
      }

      return id === 'MICRO' || id === 'RMMA';
    })
    .map((node) => {
      const data = isRecord(node) && isRecord(node.data) ? node.data : {};
      const tooltip = isRecord(data.tooltip) ? data.tooltip : {};

      return {
        id: typeof data.id === 'string' ? data.id : '',
        label: firstLine(data.label),
        styleClass: typeof data.styleClass === 'string' ? data.styleClass : 'unknown',
        evidence: typeof tooltip.evidence === 'string' ? tooltip.evidence : null,
        stat: typeof tooltip.stat === 'string' ? tooltip.stat : null,
        citation: typeof tooltip.citation === 'string' ? tooltip.citation : null,
        mechanism: typeof tooltip.mechanism === 'string' ? tooltip.mechanism : null,
      };
    })
    .filter((node) => node.id.length > 0);

  return {
    metrics,
    nodes,
    updatedAt: new Date().toISOString(),
  };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  try {
    const fromDatabase = await loadFirstPartyContent(
      FirstPartyContentType.outcomes,
      FirstPartyContentKey.outcomesMetadata
    );

    if (isOutcomesMetadataPayload(fromDatabase)) {
      res.json(fromDatabase);
      return;
    }
  } catch {
    // Local fallback below.
  }

  const fallback = fallbackOutcomesMetadata();
  res.json(fallback);
}
