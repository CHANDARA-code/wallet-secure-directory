import { betterAuth } from 'better-auth';
import { drizzleAdapter } from 'better-auth/adapters/drizzle';
import { bearer } from 'better-auth/plugins';
import type { Env } from '../config/env.js';
import type { AppDatabase } from '../database/database.module.js';
import * as schema from '../database/schema.js';

export const AUTH_BASE_PATH = '/api/auth';

export type AuthEnv = Pick<
  Env,
  | 'BETTER_AUTH_SECRET'
  | 'BETTER_AUTH_URL'
  | 'TRUSTED_ORIGINS'
  | 'NODE_ENV'
  | 'TRUST_PROXY_HOPS'
>;

export function createAuth(db: AppDatabase, env: AuthEnv) {
  return betterAuth({
    appName: 'Secure Identity Wallet',
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.BETTER_AUTH_URL,
    basePath: AUTH_BASE_PATH,
    trustedOrigins: env.TRUSTED_ORIGINS,
    database: drizzleAdapter(db, {
      provider: 'sqlite',
      schema: {
        user: schema.user,
        session: schema.session,
        account: schema.account,
        verification: schema.verification,
      },
    }),
    emailAndPassword: {
      enabled: true,
      minPasswordLength: 8,
      maxPasswordLength: 128,
    },
    rateLimit: {
      enabled: env.NODE_ENV === 'production',
    },
    advanced: {
      useSecureCookies: env.NODE_ENV === 'production',
      ipAddress: {
        ipAddressHeaders: env.TRUST_PROXY_HOPS > 0 ? ['x-forwarded-for'] : [],
      },
    },
    user: {
      additionalFields: {
        role: {
          type: 'string',
          required: false,
          defaultValue: 'user',
          input: false,
        },
      },
    },
    plugins: [bearer()],
  });
}

export type Auth = ReturnType<typeof createAuth>;
export type AuthSession = NonNullable<
  Awaited<ReturnType<Auth['api']['getSession']>>
>;
