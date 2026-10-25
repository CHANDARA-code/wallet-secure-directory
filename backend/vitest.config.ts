import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { defineConfig } from 'vitest/config';

const testDatabaseDir = mkdtempSync(join(tmpdir(), 'wallet-e2e-'));

export default defineConfig({
  resolve: { tsconfigPaths: true },
  test: {
    globals: true,
    root: './',
    include: ['test/**/*.e2e-spec.ts', 'test/**/*.spec.ts'],
    fileParallelism: false,
    env: {
      NODE_ENV: 'development',
      TEST: 'false',
      PORT: '3999',
      DATABASE_PATH: join(testDatabaseDir, 'test.db'),
      BETTER_AUTH_SECRET: 'e2e-secret-e2e-secret-e2e-secret-e2e-secret',
      BETTER_AUTH_URL: 'http://localhost:3999',
      TRUSTED_ORIGINS: 'http://localhost:5173',
      TRUST_PROXY_HOPS: '0',
    },
  },
});
