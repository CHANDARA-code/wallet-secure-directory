import { describe, expect, it } from 'vitest';
import { validateEnv } from '../src/config/env.js';

describe('validateEnv', () => {
  const validSecret = '0123456789012345678901234567890123456789';
  const placeholderSecret =
    'replace-with-output-of-openssl-rand-base64-32-or-longer';

  it('validates a minimal development configuration with defaults', () => {
    const env = validateEnv({
      BETTER_AUTH_SECRET: validSecret,
    });
    expect(env.NODE_ENV).toBe('development');
    expect(env.PORT).toBe(3000);
    expect(env.DATABASE_PATH).toBe('./data/wallet.db');
    expect(env.BETTER_AUTH_SECRET).toBe(validSecret);
    expect(env.BETTER_AUTH_URL).toBe('http://localhost:3000');
    expect(env.TRUSTED_ORIGINS).toEqual([]);
    expect(env.TRUST_PROXY_HOPS).toBe(0);
  });

  it('validates a complete production configuration with valid values', () => {
    const env = validateEnv({
      NODE_ENV: 'production',
      PORT: '8080',
      DATABASE_PATH: '/var/data/wallet.db',
      BETTER_AUTH_SECRET: validSecret,
      BETTER_AUTH_URL: 'https://wallet.example.com',
      TRUSTED_ORIGINS: 'https://app.example.com, https://admin.example.com',
      TRUST_PROXY_HOPS: '2',
    });
    expect(env.NODE_ENV).toBe('production');
    expect(env.PORT).toBe(8080);
    expect(env.DATABASE_PATH).toBe('/var/data/wallet.db');
    expect(env.BETTER_AUTH_SECRET).toBe(validSecret);
    expect(env.BETTER_AUTH_URL).toBe('https://wallet.example.com');
    expect(env.TRUSTED_ORIGINS).toEqual([
      'https://app.example.com',
      'https://admin.example.com',
    ]);
    expect(env.TRUST_PROXY_HOPS).toBe(2);
  });

  it('validates a test configuration', () => {
    const env = validateEnv({
      NODE_ENV: 'test',
      BETTER_AUTH_SECRET: validSecret,
    });
    expect(env.NODE_ENV).toBe('test');
  });

  it('rejects invalid NODE_ENV values', () => {
    expect(() =>
      validateEnv({
        NODE_ENV: 'staging',
        BETTER_AUTH_SECRET: validSecret,
      }),
    ).toThrow(
      'NODE_ENV must be development, production or test, got "staging"',
    );
  });

  it('rejects invalid PORT values', () => {
    expect(() =>
      validateEnv({
        PORT: '0',
        BETTER_AUTH_SECRET: validSecret,
      }),
    ).toThrow('PORT must be an integer between 1 and 65535, got "0"');

    expect(() =>
      validateEnv({
        PORT: '70000',
        BETTER_AUTH_SECRET: validSecret,
      }),
    ).toThrow('PORT must be an integer between 1 and 65535, got "70000"');

    expect(() =>
      validateEnv({
        PORT: '3000.5',
        BETTER_AUTH_SECRET: validSecret,
      }),
    ).toThrow('PORT must be an integer between 1 and 65535, got "3000.5"');

    expect(() =>
      validateEnv({
        PORT: 'invalid-port',
        BETTER_AUTH_SECRET: validSecret,
      }),
    ).toThrow(
      'PORT must be an integer between 1 and 65535, got "invalid-port"',
    );
  });

  it('rejects BETTER_AUTH_SECRET under 32 characters in all environments', () => {
    const shortSecret = 'too-short';
    expect(() =>
      validateEnv({
        NODE_ENV: 'development',
        BETTER_AUTH_SECRET: shortSecret,
      }),
    ).toThrow('BETTER_AUTH_SECRET must be at least 32 characters');

    expect(() =>
      validateEnv({
        NODE_ENV: 'test',
        BETTER_AUTH_SECRET: shortSecret,
      }),
    ).toThrow('BETTER_AUTH_SECRET must be at least 32 characters');

    expect(() =>
      validateEnv({
        NODE_ENV: 'production',
        BETTER_AUTH_SECRET: shortSecret,
      }),
    ).toThrow('BETTER_AUTH_SECRET must be at least 32 characters');
  });

  it('rejects placeholder secret from .env.example in production', () => {
    expect(() =>
      validateEnv({
        NODE_ENV: 'production',
        BETTER_AUTH_SECRET: placeholderSecret,
      }),
    ).toThrow('BETTER_AUTH_SECRET cannot use placeholder secret in production');
  });

  it('allows placeholder secret from .env.example in development and test', () => {
    const devEnv = validateEnv({
      NODE_ENV: 'development',
      BETTER_AUTH_SECRET: placeholderSecret,
    });
    expect(devEnv.BETTER_AUTH_SECRET).toBe(placeholderSecret);

    const testEnv = validateEnv({
      NODE_ENV: 'test',
      BETTER_AUTH_SECRET: placeholderSecret,
    });
    expect(testEnv.BETTER_AUTH_SECRET).toBe(placeholderSecret);
  });

  it('rejects invalid TRUST_PROXY_HOPS values', () => {
    expect(() =>
      validateEnv({
        BETTER_AUTH_SECRET: validSecret,
        TRUST_PROXY_HOPS: '-1',
      }),
    ).toThrow('TRUST_PROXY_HOPS must be a non-negative integer, got "-1"');

    expect(() =>
      validateEnv({
        BETTER_AUTH_SECRET: validSecret,
        TRUST_PROXY_HOPS: '1.5',
      }),
    ).toThrow('TRUST_PROXY_HOPS must be a non-negative integer, got "1.5"');

    expect(() =>
      validateEnv({
        BETTER_AUTH_SECRET: validSecret,
        TRUST_PROXY_HOPS: 'abc',
      }),
    ).toThrow('TRUST_PROXY_HOPS must be a non-negative integer, got "abc"');
  });

  it('requires explicit TRUST_PROXY_HOPS in production mode', () => {
    expect(() =>
      validateEnv({
        NODE_ENV: 'production',
        BETTER_AUTH_SECRET: validSecret,
      }),
    ).toThrow(
      'TRUST_PROXY_HOPS must be set explicitly in production (0 for direct connections, 1+ behind reverse proxies)',
    );

    expect(() =>
      validateEnv({
        NODE_ENV: 'production',
        BETTER_AUTH_SECRET: validSecret,
        TRUST_PROXY_HOPS: '',
      }),
    ).toThrow(
      'TRUST_PROXY_HOPS must be set explicitly in production (0 for direct connections, 1+ behind reverse proxies)',
    );

    const prodEnvDirect = validateEnv({
      NODE_ENV: 'production',
      BETTER_AUTH_SECRET: validSecret,
      TRUST_PROXY_HOPS: '0',
    });
    expect(prodEnvDirect.TRUST_PROXY_HOPS).toBe(0);

    const prodEnvProxied = validateEnv({
      NODE_ENV: 'production',
      BETTER_AUTH_SECRET: validSecret,
      TRUST_PROXY_HOPS: '1',
    });
    expect(prodEnvProxied.TRUST_PROXY_HOPS).toBe(1);
  });
});
