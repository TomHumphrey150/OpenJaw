import type { VercelRequest, VercelResponse } from '@vercel/node';
import bruxismInfo from '../data/bruxism-info.json';
import {
  FirstPartyContentKey,
  FirstPartyContentType,
  isObjectPayload,
  loadFirstPartyContent,
} from './firstPartyContent';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  try {
    const fromDatabase = await loadFirstPartyContent(
      FirstPartyContentType.info,
      FirstPartyContentKey.bruxismInfo
    );

    if (isObjectPayload(fromDatabase)) {
      res.json(fromDatabase);
      return;
    }
  } catch {
    // Local fallback below.
  }

  res.json(bruxismInfo);
}
