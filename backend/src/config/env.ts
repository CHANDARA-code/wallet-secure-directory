export interface Env {
  NODE_ENV: 'development' | 'production' | 'test';
  PORT: number;
  DATABASE_PATH: string;
  BETTER_AUTH_SECRET: string;
  BETTER_AUTH_URL: string;
  TRUSTED_ORIGINS: string[];
  TRUST_PROXY_HOPS: number;
}

const MIN_SECRET_LENGTH = 32;

export function validateEnv(raw: Record<string, unknown>): Env {
  const nodeEnv = String(raw.NODE_ENV ?? 'development');
  if (!['development', 'production', 'test'].includes(nodeEnv)) {
    throw new Error(
      `NODE_ENV must be development, production or test, got "${nodeEnv}"`,
    );
  }

  const port = Number(raw.PORT ?? 3000);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error(
      `PORT must be an integer between 1 and 65535, got "${raw.PORT}"`,
    );
  }

  const secret = String(raw.BETTER_AUTH_SECRET ?? '');
  if (secret.length < MIN_SECRET_LENGTH) {
    throw new Error(
      `BETTER_AUTH_SECRET must be at least ${MIN_SECRET_LENGTH} characters`,
    );
  }

  if (nodeEnv === 'production' && secret.startsWith('replace-with-')) {
    throw new Error(
      'BETTER_AUTH_SECRET cannot use placeholder secret in production',
    );
  }

  const rawHops = raw.TRUST_PROXY_HOPS;
  if (nodeEnv === 'production' && (rawHops === undefined || rawHops === '')) {
    throw new Error(
      'TRUST_PROXY_HOPS must be set explicitly in production (0 for direct connections, 1+ behind reverse proxies)',
    );
  }

  let trustProxyHops = 0;
  if (rawHops !== undefined && rawHops !== '') {
    const parsed = Number(rawHops);
    if (!Number.isInteger(parsed) || parsed < 0) {
      throw new Error(
        `TRUST_PROXY_HOPS must be a non-negative integer, got "${rawHops}"`,
      );
    }
    trustProxyHops = parsed;
  }

  return {
    NODE_ENV: nodeEnv as Env['NODE_ENV'],
    PORT: port,
    DATABASE_PATH: String(raw.DATABASE_PATH ?? './data/wallet.db'),
    BETTER_AUTH_SECRET: secret,
    BETTER_AUTH_URL: String(raw.BETTER_AUTH_URL ?? `http://localhost:${port}`),
    TRUSTED_ORIGINS: String(raw.TRUSTED_ORIGINS ?? '')
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
    TRUST_PROXY_HOPS: trustProxyHops,
  };
}
