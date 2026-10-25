import { describe, expect, it } from 'vitest';
import express from 'express';
import request from 'supertest';
import { toNodeHandler } from 'better-auth/node';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { createAuth } from '../src/auth/auth.factory.js';
import { openSqlite } from '../src/database/database.module.js';
import * as schema from '../src/database/schema.js';

describe('better-auth rate limiter and proxy headers', () => {
  it('enforces rate limits on sign-in and sign-up in production mode and respects proxy hops', async () => {
    const sqlite = openSqlite(':memory:');
    sqlite.exec(`
      CREATE TABLE user (id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE, email_verified INTEGER NOT NULL DEFAULT 0, image TEXT, role TEXT NOT NULL DEFAULT 'user', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE session (id TEXT PRIMARY KEY, token TEXT NOT NULL UNIQUE, expires_at INTEGER NOT NULL, ip_address TEXT, user_agent TEXT, user_id TEXT NOT NULL REFERENCES user(id), created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE account (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, provider_id TEXT NOT NULL, user_id TEXT NOT NULL REFERENCES user(id), access_token TEXT, refresh_token TEXT, id_token TEXT, access_token_expires_at INTEGER, refresh_token_expires_at INTEGER, scope TEXT, password TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE verification (id TEXT PRIMARY KEY, identifier TEXT NOT NULL, value TEXT NOT NULL, expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
    `);
    const db = drizzle(sqlite, { schema });

    const auth = createAuth(db, {
      BETTER_AUTH_SECRET: 'rate-limit-test-secret-at-least-32-chars',
      BETTER_AUTH_URL: 'http://localhost:3000',
      TRUSTED_ORIGINS: ['http://localhost:5173'],
      NODE_ENV: 'production',
      TRUST_PROXY_HOPS: 1,
    });

    const app = express();
    app.all('/api/auth/{*path}', toNodeHandler(auth));
    const http = request(app);

    const clientIp = '198.51.100.42';

    const res1 = await http
      .post('/api/auth/sign-in/email')
      .set('origin', 'http://localhost:5173')
      .set('x-forwarded-for', clientIp)
      .send({ email: 'ratelimit@example.com', password: 'wrong' });
    expect(res1.status).toBe(401);

    const res2 = await http
      .post('/api/auth/sign-in/email')
      .set('origin', 'http://localhost:5173')
      .set('x-forwarded-for', clientIp)
      .send({ email: 'ratelimit@example.com', password: 'wrong' });
    expect(res2.status).toBe(401);

    const res3 = await http
      .post('/api/auth/sign-in/email')
      .set('origin', 'http://localhost:5173')
      .set('x-forwarded-for', clientIp)
      .send({ email: 'ratelimit@example.com', password: 'wrong' });
    expect(res3.status).toBe(401);

    const res4 = await http
      .post('/api/auth/sign-in/email')
      .set('origin', 'http://localhost:5173')
      .set('x-forwarded-for', clientIp)
      .send({ email: 'ratelimit@example.com', password: 'wrong' });
    expect(res4.status).toBe(429);

    const differentIp = '198.51.100.43';
    const resDifferentIp = await http
      .post('/api/auth/sign-in/email')
      .set('origin', 'http://localhost:5173')
      .set('x-forwarded-for', differentIp)
      .send({ email: 'ratelimit@example.com', password: 'wrong' });
    expect(resDifferentIp.status).toBe(401);

    sqlite.close();
  });
});
