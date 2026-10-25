import { rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { openSqlite } from '../src/database/database.module.js';

describe('openSqlite file permissions', () => {
  it('creates directory with mode 0700 and db file with mode 0600 on POSIX', () => {
    const testDir = join(
      tmpdir(),
      `wallet-perm-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
    );
    const dbPath = join(testDir, 'sub', 'test.db');

    const sqlite = openSqlite(dbPath);
    try {
      if (process.platform !== 'win32') {
        const dirStat = statSync(dirname(dbPath));
        const fileStat = statSync(dbPath);

        expect(dirStat.mode & 0o777).toBe(0o700);
        expect(fileStat.mode & 0o777).toBe(0o600);
      }
    } finally {
      sqlite.close();
      rmSync(testDir, { recursive: true, force: true });
    }
  });
});
