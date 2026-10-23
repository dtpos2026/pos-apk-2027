export interface AppConfig { supabaseUrl: string; supabaseAnonKey: string; brandName: string }

/** Reads ./config.json at runtime so the same build works for any project. Returns the reason when it is unusable. */
export function validateConfig(raw: unknown): { config?: AppConfig; problem?: string } {
  if (!raw || typeof raw !== 'object') return { problem: 'config.json is empty or not an object' };
  const r = raw as Record<string, unknown>;
  const url = typeof r.supabaseUrl === 'string' ? r.supabaseUrl.trim() : '';
  const key = typeof r.supabaseAnonKey === 'string' ? r.supabaseAnonKey.trim() : '';
  if (!/^https:\/\/[^/]+\.[^/]+/.test(url) || url.includes('YOUR-PROJECT')) return { problem: 'supabaseUrl is missing or still the example value' };
  if (key.length < 20 || key.includes('YOUR-ANON')) return { problem: 'supabaseAnonKey is missing or still the example value' };
  return { config: { supabaseUrl: url, supabaseAnonKey: key, brandName: typeof r.brandName === 'string' && r.brandName.trim() ? r.brandName.trim() : 'Digital Target' } };
}

export async function loadConfig(fetcher: typeof fetch = fetch): Promise<{ config?: AppConfig; problem?: string }> {
  try {
    const res = await fetcher('./config.json', { cache: 'no-store' });
    if (!res.ok) return { problem: 'config.json was not found next to the panel (copy config.example.json to config.json)' };
    return validateConfig(await res.json());
  } catch (e) {
    return { problem: 'config.json could not be read: ' + (e instanceof Error ? e.message : String(e)) };
  }
}
