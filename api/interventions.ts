import type { VercelRequest, VercelResponse } from '@vercel/node';
import interventions from '../data/interventions.json';
import {
  FirstPartyContentKey,
  FirstPartyContentType,
  isObjectPayload,
  loadFirstPartyContent,
} from './firstPartyContent';

function isInterventionsPayload(value: unknown): value is { interventions: unknown[] } {
  if (!isObjectPayload(value)) {
    return false;
  }

  return Array.isArray(value.interventions);
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  try {
    const fromDatabase = await loadFirstPartyContent(
      FirstPartyContentType.inputs,
      FirstPartyContentKey.interventionsCatalog
    );

    if (isInterventionsPayload(fromDatabase)) {
      res.json(fromDatabase);
      return;
    }
  } catch {
    // Local fallback below.
  }

  res.json(interventions);
}
