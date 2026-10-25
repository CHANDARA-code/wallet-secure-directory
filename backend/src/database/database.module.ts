import {
  Global,
  Inject,
  Injectable,
  Module,
  OnApplicationShutdown,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import Database from 'better-sqlite3';
import {
  drizzle,
  type BetterSQLite3Database,
} from 'drizzle-orm/better-sqlite3';
import { chmodSync, existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import type { Env } from '../config/env.js';
import * as schema from './schema.js';

export const SQLITE = Symbol('SQLITE');
export const DRIZZLE = Symbol('DRIZZLE');

export type AppDatabase = BetterSQLite3Database<typeof schema>;

export function openSqlite(path: string): Database.Database {
  if (path !== ':memory:') {
    const dir = dirname(path);
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    try {
      chmodSync(dir, 0o700);
    } catch {}
  }
  const sqlite = new Database(path);
  sqlite.pragma('journal_mode = WAL');
  sqlite.pragma('synchronous = NORMAL');
  sqlite.pragma('foreign_keys = ON');
  sqlite.pragma('busy_timeout = 5000');
  if (path !== ':memory:') {
    for (const suffix of ['', '-wal', '-shm']) {
      const filePath = `${path}${suffix}`;
      try {
        if (existsSync(filePath)) {
          chmodSync(filePath, 0o600);
        }
      } catch {}
    }
  }
  return sqlite;
}

@Injectable()
class SqliteLifecycle implements OnApplicationShutdown {
  constructor(@Inject(SQLITE) private readonly sqlite: Database.Database) {}

  onApplicationShutdown() {
    if (this.sqlite.open) {
      this.sqlite.close();
    }
  }
}

@Global()
@Module({
  providers: [
    {
      provide: SQLITE,
      inject: [ConfigService],
      useFactory: (config: ConfigService<Env, true>) =>
        openSqlite(config.get('DATABASE_PATH')),
    },
    {
      provide: DRIZZLE,
      inject: [SQLITE],
      useFactory: (sqlite: Database.Database): AppDatabase =>
        drizzle(sqlite, { schema }),
    },
    SqliteLifecycle,
  ],
  exports: [SQLITE, DRIZZLE],
})
export class DatabaseModule {}
