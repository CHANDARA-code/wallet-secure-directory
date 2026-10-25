import { execFileSync } from 'node:child_process';
import { readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { ConfigService } from '@nestjs/config';
import { Test } from '@nestjs/testing';
import { drizzle } from 'drizzle-orm/better-sqlite3';
import { migrate } from 'drizzle-orm/better-sqlite3/migrator';
import type Database from 'better-sqlite3';
import helmet from 'helmet';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { AUTH } from '../src/auth/auth.constants.js';
import type { Auth } from '../src/auth/auth.factory.js';
import type { Env } from '../src/config/env.js';
import { SQLITE } from '../src/database/database.module.js';

const ORIGIN = 'http://localhost:5173';
const credentials = {
  name: 'Test User',
  email: 'e2e@example.com',
  password: 'password123',
};

const validDrivingLicenseData = {
  fullName: 'Sok Dara',
  dateOfBirth: '1995-04-12',
  address: '12 Street 51, Phnom Penh',
  nationality: 'KH',
  issuingAuthority: 'Ministry of Public Works and Transport',
  licenseClasses: ['B', 'C1'],
  restrictions: ['CORRECTIVE_LENSES'],
  issueDate: '2026-01-15',
  expiryDate: '2036-01-14',
};

async function createAndAuthenticateUser(
  app: NestExpressApplication,
  userData: { name: string; email: string; password: string },
) {
  const http = request(app.getHttpServer());
  const signUpRes = await http
    .post('/api/auth/sign-up/email')
    .set('origin', ORIGIN)
    .send(userData)
    .expect(200);

  const signInRes = await http
    .post('/api/auth/sign-in/email')
    .set('origin', ORIGIN)
    .send({ email: userData.email, password: userData.password })
    .expect(200);

  const token = signInRes.headers['set-auth-token'];
  return { user: signUpRes.body.user, token };
}

describe('backend (e2e)', () => {
  let app: NestExpressApplication;
  let sqlite: Database.Database;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication<NestExpressApplication>({
      bodyParser: false,
    });
    const config = app.get(ConfigService<Env, true>);
    app.set('trust proxy', config.get('TRUST_PROXY_HOPS'));
    app.use(
      helmet({
        contentSecurityPolicy: false,
        hsts: config.get('NODE_ENV') === 'production',
        crossOriginResourcePolicy: { policy: 'cross-origin' },
      }),
    );
    app.enableCors({
      origin: config.get('TRUSTED_ORIGINS'),
      credentials: true,
      exposedHeaders: ['set-auth-token'],
    });
    sqlite = app.get(SQLITE);
    migrate(drizzle(sqlite), { migrationsFolder: './drizzle' });
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('runs SQLite in WAL mode', async () => {
    expect(sqlite.pragma('journal_mode', { simple: true })).toBe('wal');
    const res = await request(app.getHttpServer())
      .get('/api/health')
      .expect(200);
    expect(res.body).toEqual({ status: 'ok', journalMode: 'wal' });
  });

  it('rejects /api/me without a session', async () => {
    await request(app.getHttpServer()).get('/api/me').expect(401);
  });

  it('signs up without allowing role escalation, then authenticates by bearer token', async () => {
    const http = request(app.getHttpServer());
    const signUp = await http
      .post('/api/auth/sign-up/email')
      .set('origin', ORIGIN)
      .send({ ...credentials, role: 'admin' })
      .expect(200);
    expect(signUp.body.user.role).toBe('user');

    const signIn = await http
      .post('/api/auth/sign-in/email')
      .set('origin', ORIGIN)
      .send({ email: credentials.email, password: credentials.password })
      .expect(200);
    const token = signIn.headers['set-auth-token'];
    expect(token).toBeTruthy();

    const me = await http
      .get('/api/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body.user.email).toBe(credentials.email);

    await http
      .post('/api/auth/sign-out')
      .set('origin', ORIGIN)
      .set('Authorization', `Bearer ${token}`)
      .send({})
      .expect(200);
    await http
      .get('/api/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(401);
  });

  it('rejects wrong passwords and untrusted origins', async () => {
    const http = request(app.getHttpServer());
    await http
      .post('/api/auth/sign-in/email')
      .set('origin', ORIGIN)
      .send({ email: credentials.email, password: 'wrongpass1' })
      .expect(401);
    await http
      .post('/api/auth/sign-in/email')
      .set('origin', 'http://evil.example')
      .send({ email: credentials.email, password: credentials.password })
      .expect(403);
  });

  it('enforces authentication on documents and admin endpoints', async () => {
    const http = request(app.getHttpServer());
    await http.get('/api/documents').expect(401);
    await http.get('/api/documents/some-id').expect(401);
    await http.get('/api/documents/some-id/pass/apple').expect(401);
    await http.get('/api/documents/some-id/pass/google').expect(401);
    await http.get('/api/admin/users').expect(401);
    await http.get('/api/admin/documents').expect(401);
    await http.post('/api/admin/documents').send({}).expect(401);
    await http.post('/api/admin/documents/some-id/revoke').send({}).expect(401);
  });

  it('blocks non-admin users from admin routes with 403', async () => {
    const http = request(app.getHttpServer());
    const normalUser = await createAndAuthenticateUser(app, {
      name: 'Normal User',
      email: 'normal@example.com',
      password: 'password123',
    });

    await http
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${normalUser.token}`)
      .expect(403);

    await http
      .get('/api/admin/documents')
      .set('Authorization', `Bearer ${normalUser.token}`)
      .expect(403);

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${normalUser.token}`)
      .send({})
      .expect(403);

    await http
      .post('/api/admin/documents/some-id/revoke')
      .set('Authorization', `Bearer ${normalUser.token}`)
      .send({})
      .expect(403);
  });

  it('validates driving license payload strictly and rejects invalid data with 400', async () => {
    const http = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Admin User',
      email: 'admin-tester@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    const normalUser = await createAndAuthenticateUser(app, {
      name: 'License Holder',
      email: 'holder@example.com',
      password: 'password123',
    });

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: normalUser.user.id,
        type: 'driving_license',
        extraField: 'unexpected',
        data: validDrivingLicenseData,
      })
      .expect(400);

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: normalUser.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          extraFieldInData: 'unexpected',
        },
      })
      .expect(400);

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: normalUser.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          expiryDate: '2026-02-31',
        },
      })
      .expect(400);

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: normalUser.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          issueDate: '2026-05-01',
          expiryDate: '2026-05-01',
        },
      })
      .expect(400);

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: normalUser.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          licenseClasses: [],
        },
      })
      .expect(400);

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: 'non-existent-user-id',
        type: 'driving_license',
        data: validDrivingLicenseData,
      })
      .expect(404);
  });

  it('allows admin to issue document, verifies user ownership and pass generation', async () => {
    const http = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Super Admin',
      email: 'superadmin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    const holder = await createAndAuthenticateUser(app, {
      name: 'Sok Dara',
      email: 'sok.dara@example.com',
      password: 'password123',
    });

    const otherUser = await createAndAuthenticateUser(app, {
      name: 'Other User',
      email: 'other@example.com',
      password: 'password123',
    });

    const issueRes = await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: holder.user.id,
        type: 'driving_license',
        data: validDrivingLicenseData,
      })
      .expect(201);

    const docId = issueRes.body.id;
    const docNumber = issueRes.body.documentNumber;

    expect(docNumber).toMatch(/^DL-\d{10}$/);
    expect(issueRes.body.userId).toBe(holder.user.id);
    expect(issueRes.body.userEmail).toBe(holder.user.email);
    expect(issueRes.body.status).toBe('issued');
    expect(issueRes.body.revokedAt).toBeNull();
    expect(issueRes.body.expiresAt).toBe('2036-01-14T23:59:59.999Z');

    const holderDocsRes = await http
      .get('/api/documents')
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(200);

    expect(holderDocsRes.headers['cache-control']).toBe('no-store');
    expect(holderDocsRes.body).toHaveLength(1);
    expect(holderDocsRes.body[0].id).toBe(docId);
    expect(holderDocsRes.body[0].documentNumber).toBe(docNumber);
    expect(holderDocsRes.body[0].status).toBe('issued');

    const holderDocRes = await http
      .get(`/api/documents/${docId}`)
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(200);

    expect(holderDocRes.headers['cache-control']).toBe('no-store');
    expect(holderDocRes.body.id).toBe(docId);
    expect(holderDocRes.body.documentNumber).toBe(docNumber);
    expect(holderDocRes.body.data).toEqual(validDrivingLicenseData);

    const otherDocsRes = await http
      .get('/api/documents')
      .set('Authorization', `Bearer ${otherUser.token}`)
      .expect(200);

    expect(otherDocsRes.body).toHaveLength(0);

    await http
      .get(`/api/documents/${docId}`)
      .set('Authorization', `Bearer ${otherUser.token}`)
      .expect(404);

    await http
      .get(`/api/documents/${docId}/pass/apple`)
      .set('Authorization', `Bearer ${otherUser.token}`)
      .expect(404);

    await http
      .get(`/api/documents/${docId}/pass/google`)
      .set('Authorization', `Bearer ${otherUser.token}`)
      .expect(404);

    const applePassRes = await http
      .get(`/api/documents/${docId}/pass/apple`)
      .set('Authorization', `Bearer ${holder.token}`)
      .responseType('blob')
      .expect(200);

    expect(applePassRes.headers['content-type']).toBe(
      'application/vnd.apple.pkpass',
    );
    expect(applePassRes.headers['content-disposition']).toBe(
      `attachment; filename="${docNumber}.pkpass"`,
    );
    expect(applePassRes.headers['x-pass-stub']).toBe('true');
    expect(applePassRes.headers['cache-control']).toBe('no-store');

    const pkpassBuffer = Buffer.from(applePassRes.body);
    const tempPkpassPath = join(tmpdir(), `test-${docNumber}.pkpass`);
    writeFileSync(tempPkpassPath, pkpassBuffer);
    const unzipOutput = execFileSync('unzip', ['-l', tempPkpassPath], {
      encoding: 'utf8',
    });
    execFileSync('unzip', ['-t', tempPkpassPath]);
    unlinkSync(tempPkpassPath);

    expect(unzipOutput).toContain('pass.json');
    expect(unzipOutput).toContain('manifest.json');

    const googlePassRes = await http
      .get(`/api/documents/${docId}/pass/google`)
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(200);

    expect(googlePassRes.headers['cache-control']).toBe('no-store');
    expect(googlePassRes.body.stub).toBe(true);
    expect(googlePassRes.body.jwt).toBeTruthy();
    expect(googlePassRes.body.saveUrl).toBe(
      `https://pay.google.com/gp/v/save/${googlePassRes.body.jwt}`,
    );

    const jwtParts = googlePassRes.body.jwt.split('.');
    expect(jwtParts.length).toBeGreaterThanOrEqual(2);
    const decodedPayload = JSON.parse(
      Buffer.from(jwtParts[1], 'base64url').toString('utf8'),
    );
    expect(decodedPayload.iss).toBe('wallet-backend-dev');
    expect(decodedPayload.payload.genericObjects[0].id).toBe(docNumber);

    const firstRevokeRes = await http
      .post(`/api/admin/documents/${docId}/revoke`)
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(firstRevokeRes.body.id).toBe(docId);
    expect(firstRevokeRes.body.status).toBe('revoked');
    expect(firstRevokeRes.body.revokedAt).toBeTruthy();

    const secondRevokeRes = await http
      .post(`/api/admin/documents/${docId}/revoke`)
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(secondRevokeRes.body.id).toBe(docId);
    expect(secondRevokeRes.body.status).toBe('revoked');
    expect(secondRevokeRes.body.revokedAt).toBe(firstRevokeRes.body.revokedAt);

    await http
      .post('/api/admin/documents/non-existent-id/revoke')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(404);

    const revokedUserDocs = await http
      .get('/api/documents')
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(200);
    expect(revokedUserDocs.body).toHaveLength(0);

    await http
      .get(`/api/documents/${docId}`)
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(404);

    await http
      .get(`/api/documents/${docId}/pass/apple`)
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(404);

    await http
      .get(`/api/documents/${docId}/pass/google`)
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(404);
  });

  it('supports admin user search, document count and pagination', async () => {
    const http = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Query Admin',
      email: 'query-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    const activeUser = await createAndAuthenticateUser(app, {
      name: 'Chanthou Seng',
      email: 'chanthou@example.com',
      password: 'password123',
    });

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: activeUser.user.id,
        type: 'driving_license',
        data: validDrivingLicenseData,
      })
      .expect(201);

    const usersListRes = await http
      .get('/api/admin/users?q=chanthou')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(usersListRes.body.total).toBe(1);
    expect(usersListRes.body.items).toHaveLength(1);
    expect(usersListRes.body.items[0].email).toBe('chanthou@example.com');
    expect(usersListRes.body.items[0].documentCount).toBe(1);

    const pagedUsersRes = await http
      .get('/api/admin/users?limit=2&offset=0')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(pagedUsersRes.body.items).toHaveLength(2);
    expect(pagedUsersRes.body.total).toBeGreaterThanOrEqual(2);

    await http
      .get('/api/admin/users?limit=0')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(400);

    await http
      .get('/api/admin/users?limit=101')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(400);

    await http
      .get('/api/admin/users?offset=-1')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(400);

    const adminDocsRes = await http
      .get(`/api/admin/documents?userId=${activeUser.user.id}`)
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(adminDocsRes.body.total).toBe(1);
    expect(adminDocsRes.body.items).toHaveLength(1);
    expect(adminDocsRes.body.items[0].userId).toBe(activeUser.user.id);
    expect(adminDocsRes.body.items[0].userEmail).toBe('chanthou@example.com');
  });

  it('applies helmet security headers with sane API defaults and maintains CORS credentials', async () => {
    const http = request(app.getHttpServer());
    const res = await http.get('/api/health').set('origin', ORIGIN).expect(200);

    expect(res.headers['x-content-type-options']).toBe('nosniff');
    expect(res.headers['content-security-policy']).toBeUndefined();
    expect(res.headers['strict-transport-security']).toBeUndefined();
    expect(res.headers['access-control-allow-origin']).toBe(ORIGIN);
    expect(res.headers['access-control-allow-credentials']).toBe('true');
  });

  it('rejects oversize auth body with 413 Payload Too Large', async () => {
    const http = request(app.getHttpServer());
    const largePayload = {
      email: 'oversize@example.com',
      password: 'password123',
      padding: 'a'.repeat(101 * 1024),
    };

    const res = await http
      .post('/api/auth/sign-in/email')
      .set('origin', ORIGIN)
      .send(largePayload)
      .expect(413);

    expect(res.body.statusCode).toBe(413);
    expect(res.body.error).toBe('Payload Too Large');
  });

  it('refuses to boot in production mode with the .env.example placeholder secret', () => {
    const envExample = readFileSync('.env.example', 'utf8');
    const secretLine = envExample
      .split('\n')
      .find((line) => line.startsWith('BETTER_AUTH_SECRET='));
    const secret = secretLine?.split('=')[1]?.trim() ?? '';

    let processError: unknown;
    try {
      execFileSync(
        process.execPath,
        [
          '--input-type=module',
          '-e',
          `process.env.NODE_ENV = 'production'; process.env.BETTER_AUTH_SECRET = '${secret}'; import('./dist/main.js');`,
        ],
        {
          cwd: process.cwd(),
          encoding: 'utf8',
          stdio: ['pipe', 'pipe', 'pipe'],
        },
      );
    } catch (error) {
      processError = error;
    }

    expect(processError).toBeDefined();
    const err = processError as {
      status: number;
      stderr: string;
      stdout: string;
    };
    expect(err.status).toBe(1);
    const combinedOutput = `${err.stderr || ''}${err.stdout || ''}`;
    expect(combinedOutput).toContain(
      'BETTER_AUTH_SECRET cannot use placeholder secret in production',
    );
  });

  it('prevents direct role escalation via POST /api/auth/update-user', async () => {
    const http = request(app.getHttpServer());
    const user = await createAndAuthenticateUser(app, {
      name: 'Escalation Target',
      email: 'escalation-target@example.com',
      password: 'password123',
    });

    const updateRes = await http
      .post('/api/auth/update-user')
      .set('origin', ORIGIN)
      .set('Authorization', `Bearer ${user.token}`)
      .send({ role: 'admin' })
      .expect(400);

    expect(updateRes.body.code).toBe('FIELD_NOT_ALLOWED');

    const meRes = await http
      .get('/api/me')
      .set('Authorization', `Bearer ${user.token}`)
      .expect(200);

    expect(meRes.body.user.role).toBe('user');
  });

  it('orders user documents newest first and excludes revoked documents', async () => {
    const http = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Ordering Admin',
      email: 'ordering-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    const holder = await createAndAuthenticateUser(app, {
      name: 'Multi Doc Holder',
      email: 'multidoc@example.com',
      password: 'password123',
    });

    const doc1Res = await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: holder.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          issueDate: '2026-01-01',
          expiryDate: '2031-01-01',
        },
      })
      .expect(201);

    const doc2Res = await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: holder.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          issueDate: '2026-02-01',
          expiryDate: '2031-02-01',
        },
      })
      .expect(201);

    const doc3Res = await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: holder.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          issueDate: '2026-03-01',
          expiryDate: '2031-03-01',
        },
      })
      .expect(201);

    const docsBeforeRevoke = await http
      .get('/api/documents')
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(200);

    expect(docsBeforeRevoke.body).toHaveLength(3);
    expect(docsBeforeRevoke.body[0].id).toBe(doc3Res.body.id);
    expect(docsBeforeRevoke.body[1].id).toBe(doc2Res.body.id);
    expect(docsBeforeRevoke.body[2].id).toBe(doc1Res.body.id);

    await http
      .post(`/api/admin/documents/${doc2Res.body.id}/revoke`)
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    const docsAfterRevoke = await http
      .get('/api/documents')
      .set('Authorization', `Bearer ${holder.token}`)
      .expect(200);

    expect(docsAfterRevoke.body).toHaveLength(2);
    expect(docsAfterRevoke.body[0].id).toBe(doc3Res.body.id);
    expect(docsAfterRevoke.body[1].id).toBe(doc1Res.body.id);
  });

  it('strictly rejects unknown keys on admin user and document query parameters', async () => {
    const http = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Strict Admin',
      email: 'strict-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    await http
      .get('/api/admin/users?unexpectedParam=true')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(400);

    await http
      .get('/api/admin/documents?unexpectedParam=true')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(400);
  });

  it('strictly enforces pagination bounds on admin documents endpoint', async () => {
    const http = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Bounds Admin',
      email: 'bounds-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    await http
      .get('/api/admin/documents?limit=0')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(400);

    await http
      .get('/api/admin/documents?limit=101')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(400);

    await http
      .get('/api/admin/documents?offset=-1')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(400);
  });

  it('strictly validates expiryDate must be after issueDate on document issue', async () => {
    const http = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Date Admin',
      email: 'date-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    const normalUser = await createAndAuthenticateUser(app, {
      name: 'Date User',
      email: 'date-user@example.com',
      password: 'password123',
    });

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: normalUser.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          issueDate: '2026-05-10',
          expiryDate: '2026-05-10',
        },
      })
      .expect(400);

    await http
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: normalUser.user.id,
        type: 'driving_license',
        data: {
          ...validDrivingLicenseData,
          issueDate: '2026-05-10',
          expiryDate: '2026-05-09',
        },
      })
      .expect(400);
  });

  it('handles chunked streaming auth body > 100KB with 413 and allows subsequent sign-in on fresh connection', async () => {
    const server = app.getHttpServer();
    if (!server.listening) {
      await new Promise<void>((resolve) => server.listen(0, resolve));
    }
    const address = server.address() as AddressInfo;
    const port = address.port;

    const response = await new Promise<{ statusCode: number; body: string }>(
      (resolve, reject) => {
        const req = http.request(
          {
            hostname: '127.0.0.1',
            port,
            path: '/api/auth/sign-in/email',
            method: 'POST',
            headers: {
              origin: ORIGIN,
              'Content-Type': 'application/json',
            },
          },
          (res) => {
            let data = '';
            res.on('data', (chunk) => {
              data += chunk;
            });
            res.on('end', () => {
              resolve({ statusCode: res.statusCode ?? 0, body: data });
            });
          },
        );

        req.on('error', (err) => {
          reject(err);
        });

        const chunk = Buffer.alloc(16 * 1024, 'a');
        for (let i = 0; i < 8; i++) {
          req.write(chunk);
        }
        req.end();
      },
    );

    expect(response.statusCode).toBe(413);
    const parsed = JSON.parse(response.body);
    expect(parsed.statusCode).toBe(413);
    expect(parsed.error).toBe('Payload Too Large');

    const freshUser = await createAndAuthenticateUser(app, {
      name: 'Fresh Connection User',
      email: 'fresh-connection@example.com',
      password: 'password123',
    });
    expect(freshUser.token).toBeDefined();

    const httpTest = request(app.getHttpServer());
    const signInRes = await httpTest
      .post('/api/auth/sign-in/email')
      .set('origin', ORIGIN)
      .send({
        email: 'fresh-connection@example.com',
        password: 'password123',
      })
      .expect(200);

    expect(signInRes.headers['set-auth-token']).toBeDefined();
  });

  it('escapes LIKE wildcards in admin user search and paginates with offset', async () => {
    const httpTest = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Search Wildcard Admin',
      email: 'search-wildcard-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    await createAndAuthenticateUser(app, {
      name: 'User_With_Underscore',
      email: 'userunder@example.com',
      password: 'password123',
    });

    await createAndAuthenticateUser(app, {
      name: 'User Without Underscore',
      email: 'plainuser@example.com',
      password: 'password123',
    });

    const percentSearchRes = await httpTest
      .get('/api/admin/users?q=%25')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(percentSearchRes.body.items).toHaveLength(0);
    expect(percentSearchRes.body.total).toBe(0);

    await createAndAuthenticateUser(app, {
      name: 'User 100% Legit',
      email: 'percentuser@example.com',
      password: 'password123',
    });

    const percentFoundRes = await httpTest
      .get('/api/admin/users?q=%25')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(percentFoundRes.body.total).toBe(1);
    expect(percentFoundRes.body.items).toHaveLength(1);
    expect(percentFoundRes.body.items[0].email).toBe('percentuser@example.com');

    const underscoreSearchRes = await httpTest
      .get('/api/admin/users?q=_')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(underscoreSearchRes.body.total).toBe(1);
    expect(underscoreSearchRes.body.items).toHaveLength(1);
    expect(underscoreSearchRes.body.items[0].email).toBe(
      'userunder@example.com',
    );

    const page0Res = await httpTest
      .get('/api/admin/users?limit=1&offset=0')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    const page1Res = await httpTest
      .get('/api/admin/users?limit=1&offset=1')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    const pageAllRes = await httpTest
      .get('/api/admin/users?limit=2&offset=0')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(page0Res.body.total).toBe(page1Res.body.total);
    expect(pageAllRes.body.total).toBe(page0Res.body.total);
    expect(page0Res.body.items[0].id).not.toBe(page1Res.body.items[0].id);
    expect(pageAllRes.body.items[0].id).toBe(page0Res.body.items[0].id);
    expect(pageAllRes.body.items[1].id).toBe(page1Res.body.items[0].id);

    const emptyPageRes = await httpTest
      .get('/api/admin/users?limit=10&offset=9999')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(emptyPageRes.body.items).toHaveLength(0);
    expect(emptyPageRes.body.total).toBe(page0Res.body.total);
  });

  it('treats empty userId query parameter as absent on admin documents endpoint', async () => {
    const httpTest = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Empty UserId Admin',
      email: 'empty-userid-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    const res = await httpTest
      .get('/api/admin/documents?userId=')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(res.body.items).toBeDefined();
    expect(typeof res.body.total).toBe('number');
  });

  it('immediately revokes admin access when role is demoted in database and handles deleted user without 500', async () => {
    const httpTest = request(app.getHttpServer());
    const demotedAdmin = await createAndAuthenticateUser(app, {
      name: 'Demote Admin User',
      email: 'demote-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', demotedAdmin.user.id);

    await httpTest
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${demotedAdmin.token}`)
      .expect(200);

    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('user', demotedAdmin.user.id);

    await httpTest
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${demotedAdmin.token}`)
      .expect(403);

    const deletedAdmin = await createAndAuthenticateUser(app, {
      name: 'Deleted Admin User',
      email: 'deleted-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', deletedAdmin.user.id);

    await httpTest
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${deletedAdmin.token}`)
      .expect(200);

    sqlite.prepare('DELETE FROM user WHERE id = ?').run(deletedAdmin.user.id);

    const deletedRes = await httpTest
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${deletedAdmin.token}`);

    expect([401, 403]).toContain(deletedRes.status);
    expect(deletedRes.status).not.toBe(500);
  });

  it('reads current role directly from database even when session user role is spoofed to admin', async () => {
    const regularUser = await createAndAuthenticateUser(app, {
      name: 'Regular Role User',
      email: 'regular-role@example.com',
      password: 'password123',
    });

    const auth = app.get<Auth>(AUTH);
    const originalGetSession = auth.api.getSession;
    auth.api.getSession = (async () => ({
      user: {
        id: regularUser.user.id,
        role: 'admin',
        email: regularUser.user.email,
        name: regularUser.user.name,
        createdAt: new Date(),
        updatedAt: new Date(),
        emailVerified: true,
      },
      session: {
        id: 'cached-session-id',
        userId: regularUser.user.id,
        expiresAt: new Date(Date.now() + 3600000),
        token: 'cached-token',
        createdAt: new Date(),
        updatedAt: new Date(),
      },
    })) as any;

    try {
      const httpTest = request(app.getHttpServer());
      await httpTest
        .get('/api/admin/users')
        .set('Authorization', `Bearer ${regularUser.token}`)
        .expect(403);
    } finally {
      auth.api.getSession = originalGetSession;
    }
  });

  it('applies Cache-Control no-store header to admin endpoints', async () => {
    const httpTest = request(app.getHttpServer());
    const admin = await createAndAuthenticateUser(app, {
      name: 'Cache Control Admin',
      email: 'cache-control-admin@example.com',
      password: 'password123',
    });
    sqlite
      .prepare('UPDATE user SET role = ? WHERE id = ?')
      .run('admin', admin.user.id);

    const usersRes = await httpTest
      .get('/api/admin/users')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(usersRes.headers['cache-control']).toBe('no-store');

    const docsRes = await httpTest
      .get('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .expect(200);

    expect(docsRes.headers['cache-control']).toBe('no-store');

    const issueRes = await httpTest
      .post('/api/admin/documents')
      .set('Authorization', `Bearer ${admin.token}`)
      .send({
        userId: admin.user.id,
        type: 'driving_license',
        data: validDrivingLicenseData,
      })
      .expect(201);

    expect(issueRes.headers['cache-control']).toBe('no-store');
  });

  it('refuses to boot in production mode when TRUST_PROXY_HOPS is missing, and boots when set explicitly', () => {
    const validSecret = '0123456789012345678901234567890123456789';

    let missingHopsError: unknown;
    try {
      execFileSync(
        process.execPath,
        [
          '--input-type=module',
          '-e',
          `process.env.NODE_ENV = 'production'; process.env.BETTER_AUTH_SECRET = '${validSecret}'; process.env.TRUST_PROXY_HOPS = ''; import('./dist/main.js');`,
        ],
        {
          cwd: process.cwd(),
          encoding: 'utf8',
          stdio: ['pipe', 'pipe', 'pipe'],
        },
      );
    } catch (error) {
      missingHopsError = error;
    }

    expect(missingHopsError).toBeDefined();
    const missingErr = missingHopsError as {
      status: number;
      stderr: string;
      stdout: string;
    };
    expect(missingErr.status).toBe(1);
    const combinedOutput = `${missingErr.stderr || ''}${missingErr.stdout || ''}`;
    expect(combinedOutput).toContain(
      'TRUST_PROXY_HOPS must be set explicitly in production (0 for direct connections, 1+ behind reverse proxies)',
    );

    const bootOutput = execFileSync(
      process.execPath,
      [
        '--input-type=module',
        '-e',
        `process.env.NODE_ENV = 'production'; process.env.BETTER_AUTH_SECRET = '${validSecret}'; process.env.TRUST_PROXY_HOPS = '0'; process.env.DATABASE_PATH = ':memory:'; process.env.PORT = '3000'; const { validateEnv } = await import('./dist/config/env.js'); validateEnv(process.env); console.log('EXPLICIT_HOPS_BOOT_SUCCESS');`,
      ],
      {
        cwd: process.cwd(),
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      },
    );
    expect(bootOutput).toContain('EXPLICIT_HOPS_BOOT_SUCCESS');
  });

  it('fails cleanly when seed-admin script runs without BETTER_AUTH_SECRET', () => {
    let seedError: unknown;
    try {
      execFileSync('npx', ['tsx', 'scripts/seed-admin.ts'], {
        cwd: process.cwd(),
        env: {
          ...process.env,
          ADMIN_EMAIL: 'seed-test-admin@example.com',
          ADMIN_PASSWORD: 'password123',
          BETTER_AUTH_SECRET: '',
        },
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
    } catch (error) {
      seedError = error;
    }

    expect(seedError).toBeDefined();
    const err = seedError as {
      status: number;
      stderr: string;
      stdout: string;
    };
    expect(err.status).toBe(1);
    const output = `${err.stderr || ''}${err.stdout || ''}`;
    expect(output).toContain(
      'BETTER_AUTH_SECRET must be at least 32 characters',
    );
  });
});
