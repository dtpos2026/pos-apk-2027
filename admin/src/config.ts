export interface FirebaseWebConfig { apiKey: string; authDomain: string; projectId: string; appId: string; storageBucket?: string; messagingSenderId?: string }

export function validateConfig(raw: unknown): { config?: FirebaseWebConfig; problem?: string } {
  if (!raw || typeof raw !== 'object') return { problem: 'The Firebase config is empty.' };
  const r = raw as Record<string, unknown>;
  for (const k of ['apiKey', 'authDomain', 'projectId', 'appId']) {
    const v = r[k];
    if (typeof v !== 'string' || !v.trim() || /YOUR-|REPLACE/i.test(v)) return { problem: `"${k}" is missing or still an example value.` };
  }
  return { config: r as unknown as FirebaseWebConfig };
}

/** On Firebase Hosting the config is served at /__/firebase/init.json; elsewhere (local dev, GitHub Pages) use ./config.json. */
export async function loadConfig(fetcher: typeof fetch = fetch): Promise<{ config?: FirebaseWebConfig; problem?: string }> {
  for (const url of ['/__/firebase/init.json', '/config.json']) {
    try {
      const res = await fetcher(url, { cache: 'no-store' });
      if (!res.ok || !(res.headers.get('content-type') ?? '').includes('json')) continue;
      const v = validateConfig(await res.json());
      if (v.config) return v;
    } catch { /* try the next source */ }
  }
  return { problem: 'No Firebase config found. Deploy with Firebase Hosting, or copy config.example.json to config.json.' };
}
