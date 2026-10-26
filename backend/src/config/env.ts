import { accessSync, constants } from 'node:fs';
import { basename } from 'node:path';

export interface ApplePassConfig {
  passTypeId: string;
  teamId: string;
  certPath: string;
  keyPath: string;
  wwdrCertPath: string;
  keyPassphrase?: string;
  organizationName: string;
}

export interface GooglePassConfig {
  issuerId: string;
  serviceAccountEmail: string;
  privateKeyPath: string;
  classSuffix: string;
  origins: string[];
}

export interface Env {
  NODE_ENV: 'development' | 'production' | 'test';
  PORT: number;
  DATABASE_PATH: string;
  BETTER_AUTH_SECRET: string;
  BETTER_AUTH_URL: string;
  TRUSTED_ORIGINS: string[];
  TRUST_PROXY_HOPS: number;
  applePass?: ApplePassConfig;
  googlePass?: GooglePassConfig;
}

const MIN_SECRET_LENGTH = 32;

const APPLE_REQUIRED_KEYS = [
  'APPLE_PASS_TYPE_ID',
  'APPLE_TEAM_ID',
  'APPLE_PASS_CERT_PATH',
  'APPLE_PASS_KEY_PATH',
  'APPLE_WWDR_CERT_PATH',
] as const;

const APPLE_ALL_KEYS = [
  ...APPLE_REQUIRED_KEYS,
  'APPLE_PASS_KEY_PASSPHRASE',
  'APPLE_PASS_ORGANIZATION',
] as const;

const GOOGLE_REQUIRED_KEYS = [
  'GOOGLE_WALLET_ISSUER_ID',
  'GOOGLE_WALLET_SERVICE_ACCOUNT_EMAIL',
  'GOOGLE_WALLET_PRIVATE_KEY_PATH',
] as const;

const GOOGLE_ALL_KEYS = [
  ...GOOGLE_REQUIRED_KEYS,
  'GOOGLE_WALLET_CLASS_SUFFIX',
  'GOOGLE_WALLET_ORIGINS',
] as const;

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

  let applePass: ApplePassConfig | undefined;
  const hasAnyApple = APPLE_ALL_KEYS.some(
    (key) => raw[key] !== undefined && String(raw[key]).trim() !== '',
  );

  if (hasAnyApple) {
    const missing = APPLE_REQUIRED_KEYS.filter(
      (key) => raw[key] === undefined || String(raw[key]).trim() === '',
    );
    if (missing.length > 0) {
      throw new Error(
        `Apple pass configuration is incomplete. Missing: ${missing.join(', ')}`,
      );
    }

    const certPath = String(raw.APPLE_PASS_CERT_PATH);
    const keyPath = String(raw.APPLE_PASS_KEY_PATH);
    const wwdrCertPath = String(raw.APPLE_WWDR_CERT_PATH);

    for (const [key, filePath] of [
      ['APPLE_PASS_CERT_PATH', certPath],
      ['APPLE_PASS_KEY_PATH', keyPath],
      ['APPLE_WWDR_CERT_PATH', wwdrCertPath],
    ] as const) {
      try {
        accessSync(filePath, constants.R_OK);
      } catch {
        throw new Error(
          `${key} file "${basename(filePath)}" does not exist or is not readable`,
        );
      }
    }

    applePass = {
      passTypeId: String(raw.APPLE_PASS_TYPE_ID),
      teamId: String(raw.APPLE_TEAM_ID),
      certPath,
      keyPath,
      wwdrCertPath,
      keyPassphrase:
        raw.APPLE_PASS_KEY_PASSPHRASE &&
        String(raw.APPLE_PASS_KEY_PASSPHRASE).trim() !== ''
          ? String(raw.APPLE_PASS_KEY_PASSPHRASE)
          : undefined,
      organizationName:
        raw.APPLE_PASS_ORGANIZATION &&
        String(raw.APPLE_PASS_ORGANIZATION).trim() !== ''
          ? String(raw.APPLE_PASS_ORGANIZATION)
          : 'Secure Identity Wallet',
    };
  }

  let googlePass: GooglePassConfig | undefined;
  const hasAnyGoogle = GOOGLE_ALL_KEYS.some(
    (key) => raw[key] !== undefined && String(raw[key]).trim() !== '',
  );

  if (hasAnyGoogle) {
    const missing = GOOGLE_REQUIRED_KEYS.filter(
      (key) => raw[key] === undefined || String(raw[key]).trim() === '',
    );
    if (missing.length > 0) {
      throw new Error(
        `Google pass configuration is incomplete. Missing: ${missing.join(', ')}`,
      );
    }

    const privateKeyPath = String(raw.GOOGLE_WALLET_PRIVATE_KEY_PATH);
    try {
      accessSync(privateKeyPath, constants.R_OK);
    } catch {
      throw new Error(
        `GOOGLE_WALLET_PRIVATE_KEY_PATH file "${basename(privateKeyPath)}" does not exist or is not readable`,
      );
    }

    const rawOrigins = String(raw.GOOGLE_WALLET_ORIGINS ?? '');
    const origins = rawOrigins
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean);

    googlePass = {
      issuerId: String(raw.GOOGLE_WALLET_ISSUER_ID),
      serviceAccountEmail: String(raw.GOOGLE_WALLET_SERVICE_ACCOUNT_EMAIL),
      privateKeyPath,
      classSuffix:
        raw.GOOGLE_WALLET_CLASS_SUFFIX &&
        String(raw.GOOGLE_WALLET_CLASS_SUFFIX).trim() !== ''
          ? String(raw.GOOGLE_WALLET_CLASS_SUFFIX)
          : 'identity_wallet',
      origins,
    };
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
    applePass,
    googlePass,
  };
}
