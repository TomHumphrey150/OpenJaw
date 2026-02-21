import type { VercelRequest, VercelResponse } from '@vercel/node';
import defaultGraph from '../data/default-graph.json';
import {
  FirstPartyContentKey,
  FirstPartyContentType,
  isObjectPayload,
  loadFirstPartyContent,
} from './firstPartyContent';

function isGraphPayload(value: unknown): value is { nodes: unknown[]; edges: unknown[] } {
  if (!isObjectPayload(value)) {
    return false;
  }

  return Array.isArray(value.nodes) && Array.isArray(value.edges);
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  try {
    const fromDatabase = await loadFirstPartyContent(
      FirstPartyContentType.graph,
      FirstPartyContentKey.canonicalGraph
    );

    if (isGraphPayload(fromDatabase)) {
      res.json(fromDatabase);
      return;
    }
  } catch {
    // Local fallback below.
  }

  res.json(defaultGraph);
}
