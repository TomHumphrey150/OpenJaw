import type { VercelRequest, VercelResponse } from '@vercel/node';
import bruxismInfo from '../data/bruxism-info.json';

export default function handler(req: VercelRequest, res: VercelResponse) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.json(bruxismInfo);
}
