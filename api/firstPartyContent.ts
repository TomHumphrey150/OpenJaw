const DEFAULT_SUPABASE_URL = 'https://aocndwnnkffumisprifx.supabase.co';

export const FirstPartyContentType = Object.freeze({
  graph: 'graph',
  inputs: 'inputs',
  outcomes: 'outcomes',
  citations: 'citations',
  info: 'info',
});

export const FirstPartyContentKey = Object.freeze({
  canonicalGraph: 'canonical_causal_graph',
  interventionsCatalog: 'interventions_catalog',
  outcomesMetadata: 'outcomes_metadata',
  citationsCatalog: 'citations_catalog',
  bruxismInfo: 'bruxism_info',
});

function normalizeEnvValue(value: string | undefined): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }

  return trimmed;
}

function supabaseConfig(): { url: string; key: string } | null {
  const url = normalizeEnvValue(process.env.SUPABASE_URL) ?? DEFAULT_SUPABASE_URL;
  const key =
    normalizeEnvValue(process.env.SUPABASE_SERVICE_ROLE_KEY)
    ?? normalizeEnvValue(process.env.SUPABASE_SECRET_KEY)
    ?? normalizeEnvValue(process.env.SUPABASE_PUBLISHABLE_KEY)
    ?? normalizeEnvValue(process.env.SUPABASE_ANON_KEY)
    ?? normalizeEnvValue(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)
    ?? null;

  if (!key) {
    return null;
  }

  return { url, key };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

export function isObjectPayload(value: unknown): value is Record<string, unknown> {
  return isRecord(value);
}

export async function loadFirstPartyContent(contentType: string, contentKey: string): Promise<unknown | null> {
  const config = supabaseConfig();
  if (!config) {
    return null;
  }

  const trimmedType = contentType.trim();
  const trimmedKey = contentKey.trim();
  if (!trimmedType || !trimmedKey) {
    return null;
  }

  const query = new URLSearchParams({
    select: 'data',
    content_type: `eq.${trimmedType}`,
    content_key: `eq.${trimmedKey}`,
    limit: '1',
  }).toString();

  const response = await fetch(`${config.url}/rest/v1/first_party_content?${query}`, {
    method: 'GET',
    headers: {
      apikey: config.key,
      authorization: `Bearer ${config.key}`,
      accept: 'application/json',
    },
  });

  if (!response.ok) {
    return null;
  }

  const payload: unknown = await response.json();
  if (!Array.isArray(payload) || payload.length === 0) {
    return null;
  }

  const firstRow = payload[0];
  if (!isRecord(firstRow)) {
    return null;
  }

  if (!Object.prototype.hasOwnProperty.call(firstRow, 'data')) {
    return null;
  }

  return firstRow.data;
}
