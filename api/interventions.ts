import type { VercelRequest, VercelResponse } from '@vercel/node';
import interventions from '../data/interventions.json';

export default function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.json(interventions);
}
