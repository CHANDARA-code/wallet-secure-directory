import { ConfigService } from '@nestjs/config';
import { execFileSync } from 'node:child_process';
import {
  createHash,
  createPrivateKey,
  createVerify,
  generateKeyPairSync,
  X509Certificate,
} from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as pkijs from 'pkijs';
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import type {
  ApplePassConfig,
  Env,
  GooglePassConfig,
} from '../src/config/env.js';
import {
  createApplePassZip,
  createSignedApplePassZip,
  type AppleSigningKeys,
} from '../src/documents/apple-pass.util.js';
import {
  createGooglePassStub,
  createSignedGooglePass,
} from '../src/documents/google-pass.util.js';
import { PassSigningService } from '../src/documents/pass-signing.service.js';

describe('Wallet passes signing and stub behavior', () => {
  let tempDir: string;
  let appleConfig: ApplePassConfig;
  let googleConfig: GooglePassConfig;
  let googlePrivateKeyPem: string;
  let googlePublicKeyPem: string;
  let wrongGooglePublicKeyPem: string;
  let appleKeys: AppleSigningKeys;

  const testPayload = {
    fullName: 'Alice Walker',
    dateOfBirth: '1990-01-01',
    address: '123 Test Street, Phnom Penh',
    licenseClasses: ['A', 'B'],
    expiryDate: '2030-12-31',
  };
  const testDocNumber = 'DL-1234567890';

  beforeAll(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'wallet-pass-test-'));

    const certPath = join(tempDir, 'signer.cert');
    const keyPath = join(tempDir, 'signer.key');
    const wwdrCertPath = join(tempDir, 'wwdr.cert');
    const wwdrKeyPath = join(tempDir, 'wwdr.key');
    const signerCsrPath = join(tempDir, 'signer.csr');

    execFileSync('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      wwdrKeyPath,
      '-out',
      wwdrCertPath,
      '-days',
      '365',
      '-subj',
      '/CN=Apple Worldwide Developer Relations Certification Authority/OU=Apple/O=Apple Inc./C=US',
    ]);

    execFileSync('openssl', [
      'req',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      keyPath,
      '-out',
      signerCsrPath,
      '-subj',
      '/CN=Pass Type ID: pass.com.wallet.test/OU=TEAM123456/O=Secure Identity Wallet/C=US',
    ]);

    execFileSync('openssl', [
      'x509',
      '-req',
      '-in',
      signerCsrPath,
      '-CA',
      wwdrCertPath,
      '-CAkey',
      wwdrKeyPath,
      '-CAcreateserial',
      '-out',
      certPath,
      '-days',
      '365',
    ]);

    const signerCertNode = new X509Certificate(readFileSync(certPath));
    const wwdrCertNode = new X509Certificate(readFileSync(wwdrCertPath));
    const signerKey = createPrivateKey(readFileSync(keyPath, 'utf8'));

    appleConfig = {
      passTypeId: 'pass.com.wallet.test',
      teamId: 'TEAM123456',
      certPath,
      keyPath,
      wwdrCertPath,
      organizationName: 'Secure Identity Wallet',
    };

    appleKeys = {
      signerCert: pkijs.Certificate.fromBER(signerCertNode.raw),
      signerKey,
      wwdrCert: pkijs.Certificate.fromBER(wwdrCertNode.raw),
    };

    const googleKp = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
    googlePrivateKeyPem = googleKp.privateKey;
    googlePublicKeyPem = googleKp.publicKey;

    const wrongKp = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      publicKeyEncoding: { type: 'spki', format: 'pem' },
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
    });
    wrongGooglePublicKeyPem = wrongKp.publicKey;

    const googleKeyPath = join(tempDir, 'google.key');
    writeFileSync(googleKeyPath, googlePrivateKeyPem);

    googleConfig = {
      issuerId: '33880000000221199',
      serviceAccountEmail: 'wallet-service@project.iam.gserviceaccount.com',
      privateKeyPath: googleKeyPath,
      classSuffix: 'identity_wallet',
      origins: ['https://wallet.example.com'],
    };
  });

  afterAll(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('generates a valid signed Apple pass with detached PKCS#7 signature and minimal visible fields', () => {
    const pkpassBuffer = createSignedApplePassZip(
      testDocNumber,
      testPayload,
      appleConfig,
      appleKeys,
    );

    const extractDir = join(tempDir, 'apple-extracted');
    const pkpassPath = join(tempDir, 'test.pkpass');
    writeFileSync(pkpassPath, pkpassBuffer);

    execFileSync('unzip', ['-q', pkpassPath, '-d', extractDir]);

    const passJsonRaw = readFileSync(join(extractDir, 'pass.json'), 'utf8');
    const passJson = JSON.parse(passJsonRaw);

    expect(passJson.formatVersion).toBe(1);
    expect(passJson.passTypeIdentifier).toBe('pass.com.wallet.test');
    expect(passJson.teamIdentifier).toBe('TEAM123456');
    expect(passJson.serialNumber).toBe(testDocNumber);
    expect(passJson.organizationName).toBe('Secure Identity Wallet');
    expect(passJson.description).toBe('Driving License');
    expect(passJson.logoText).toBe('Secure Identity Wallet');

    expect(passJson.generic.primaryFields[0].value).toBe(testPayload.fullName);
    expect(passJson.generic.secondaryFields[0].value).toBe(testDocNumber);
    expect(passJson.generic.secondaryFields[1].value).toBe('A, B');
    expect(passJson.generic.auxiliaryFields[0].value).toBe(
      testPayload.expiryDate,
    );

    expect(passJsonRaw).not.toContain('dateOfBirth');
    expect(passJsonRaw).not.toContain('1990-01-01');
    expect(passJsonRaw).not.toContain('address');
    expect(passJsonRaw).not.toContain('Phnom Penh');

    const manifestRaw = readFileSync(join(extractDir, 'manifest.json'), 'utf8');
    const manifest = JSON.parse(manifestRaw);

    const passJsonSha1 = createHash('sha1')
      .update(readFileSync(join(extractDir, 'pass.json')))
      .digest('hex');
    const iconSha1 = createHash('sha1')
      .update(readFileSync(join(extractDir, 'icon.png')))
      .digest('hex');
    const icon2xSha1 = createHash('sha1')
      .update(readFileSync(join(extractDir, 'icon@2x.png')))
      .digest('hex');

    expect(manifest['pass.json']).toBe(passJsonSha1);
    expect(manifest['icon.png']).toBe(iconSha1);
    expect(manifest['icon@2x.png']).toBe(icon2xSha1);

    const sigPath = join(extractDir, 'signature');
    const manifestPath = join(extractDir, 'manifest.json');

    const opensslOutput = execFileSync(
      'openssl',
      [
        'smime',
        '-verify',
        '-inform',
        'DER',
        '-binary',
        '-noverify',
        '-in',
        sigPath,
        '-content',
        manifestPath,
      ],
      { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] },
    );

    expect(JSON.parse(opensslOutput)).toEqual(manifest);
  });

  it('fails Apple pass signature verification when manifest is tampered', () => {
    const pkpassBuffer = createSignedApplePassZip(
      testDocNumber,
      testPayload,
      appleConfig,
      appleKeys,
    );

    const extractDir = join(tempDir, 'apple-extracted-tampered');
    const pkpassPath = join(tempDir, 'test-tampered.pkpass');
    writeFileSync(pkpassPath, pkpassBuffer);

    execFileSync('unzip', ['-q', pkpassPath, '-d', extractDir]);

    const sigPath = join(extractDir, 'signature');
    const tamperedManifestPath = join(extractDir, 'manifest-tampered.json');

    const manifestContent = readFileSync(
      join(extractDir, 'manifest.json'),
      'utf8',
    );
    writeFileSync(
      tamperedManifestPath,
      manifestContent.slice(0, -2) + ' "tampered": "invalid" }',
    );

    expect(() =>
      execFileSync(
        'openssl',
        [
          'smime',
          '-verify',
          '-inform',
          'DER',
          '-binary',
          '-noverify',
          '-in',
          sigPath,
          '-content',
          tamperedManifestPath,
        ],
        { stdio: 'pipe' },
      ),
    ).toThrow();
  });

  it('generates a valid RS256 signed Google pass JWT with minimal fields', () => {
    const signedPass = createSignedGooglePass(
      testDocNumber,
      testPayload,
      googleConfig,
      googlePrivateKeyPem,
    );

    expect(signedPass.stub).toBe(false);
    expect(signedPass.saveUrl).toBe(
      `https://pay.google.com/gp/v/save/${signedPass.jwt}`,
    );

    const parts = signedPass.jwt.split('.');
    expect(parts.length).toBe(3);

    const header = JSON.parse(
      Buffer.from(parts[0], 'base64url').toString('utf8'),
    );
    expect(header.alg).toBe('RS256');
    expect(header.typ).toBe('JWT');

    const claims = JSON.parse(
      Buffer.from(parts[1], 'base64url').toString('utf8'),
    );
    expect(claims.iss).toBe(googleConfig.serviceAccountEmail);
    expect(claims.aud).toBe('google');
    expect(claims.typ).toBe('savetowallet');
    expect(typeof claims.iat).toBe('number');
    expect(claims.origins).toEqual(['https://wallet.example.com']);

    const obj = claims.payload.genericObjects[0];
    expect(obj.id).toBe(`33880000000221199.${testDocNumber}`);
    expect(obj.classId).toBe('33880000000221199.identity_wallet');
    expect(obj.cardTitle.defaultValue.value).toBe('Driving License');
    expect(obj.header.defaultValue.value).toBe(testPayload.fullName);
    expect(obj.subheader.defaultValue.value).toBe('A, B');

    const rawClaims = JSON.stringify(claims);
    expect(rawClaims).not.toContain('dateOfBirth');
    expect(rawClaims).not.toContain('1990-01-01');
    expect(rawClaims).not.toContain('address');
    expect(rawClaims).not.toContain('Phnom Penh');

    const verifier = createVerify('RSA-SHA256');
    verifier.update(`${parts[0]}.${parts[1]}`);
    const isSignatureValid = verifier.verify(
      googlePublicKeyPem,
      parts[2],
      'base64url',
    );
    expect(isSignatureValid).toBe(true);
  });

  it('fails Google JWT verification when verified with the wrong key', () => {
    const signedPass = createSignedGooglePass(
      testDocNumber,
      testPayload,
      googleConfig,
      googlePrivateKeyPem,
    );

    const parts = signedPass.jwt.split('.');
    const verifier = createVerify('RSA-SHA256');
    verifier.update(`${parts[0]}.${parts[1]}`);
    const isSignatureValid = verifier.verify(
      wrongGooglePublicKeyPem,
      parts[2],
      'base64url',
    );
    expect(isSignatureValid).toBe(false);
  });

  it('falls back to unsigned stubs when pass credentials are not configured', () => {
    const appleStubZip = createApplePassZip(testDocNumber, testPayload);
    const appleExtractDir = join(tempDir, 'stub-apple-extracted');
    const appleStubPath = join(tempDir, 'stub.pkpass');
    writeFileSync(appleStubPath, appleStubZip);
    execFileSync('unzip', ['-q', appleStubPath, '-d', appleExtractDir]);

    const stubFiles = execFileSync('unzip', ['-l', appleStubPath], {
      encoding: 'utf8',
    });
    expect(stubFiles).toContain('pass.json');
    expect(stubFiles).toContain('manifest.json');
    expect(stubFiles).not.toContain('signature');
    expect(stubFiles).not.toContain('icon.png');

    const googleStub = createGooglePassStub(testDocNumber, testPayload);
    expect(googleStub.stub).toBe(true);
    expect(googleStub.saveUrl).toContain(googleStub.jwt);
    const parts = googleStub.jwt.split('.');
    const header = JSON.parse(
      Buffer.from(parts[0], 'base64url').toString('utf8'),
    );
    const claims = JSON.parse(
      Buffer.from(parts[1], 'base64url').toString('utf8'),
    );
    expect(header.alg).toBe('none');
    expect(claims.iss).toBe('wallet-backend-dev');
  });

  it('properly caches loaded credentials in PassSigningService', async () => {
    const configService = {
      get: (key: string) => {
        if (key === 'applePass') return appleConfig;
        if (key === 'googlePass') return googleConfig;
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    const readSpy = vi.spyOn(service as any, 'readCredentialFile');
    const appleLoaderSpy = vi.spyOn(service as any, 'loadAppleKeys');
    const googleLoaderSpy = vi.spyOn(service as any, 'loadGooglePrivateKey');

    const [apple1, apple2, apple3, google1, google2, google3] =
      await Promise.all([
        Promise.resolve().then(() =>
          service.getApplePass(testDocNumber, testPayload),
        ),
        Promise.resolve().then(() =>
          service.getApplePass(testDocNumber, testPayload),
        ),
        Promise.resolve().then(() =>
          service.getApplePass(testDocNumber, testPayload),
        ),
        Promise.resolve().then(() =>
          service.getGooglePass(testDocNumber, testPayload),
        ),
        Promise.resolve().then(() =>
          service.getGooglePass(testDocNumber, testPayload),
        ),
        Promise.resolve().then(() =>
          service.getGooglePass(testDocNumber, testPayload),
        ),
      ]);

    expect(apple1.isStub).toBe(false);
    expect(apple2.isStub).toBe(false);
    expect(apple3.isStub).toBe(false);
    expect(google1.stub).toBe(false);
    expect(google2.stub).toBe(false);
    expect(google3.stub).toBe(false);

    expect(appleLoaderSpy).toHaveBeenCalledTimes(1);
    expect(googleLoaderSpy).toHaveBeenCalledTimes(1);

    const readFiles = readSpy.mock.calls.map((call) => call[0]);
    expect(readFiles.filter((f) => f === appleConfig.certPath)).toHaveLength(1);
    expect(readFiles.filter((f) => f === appleConfig.keyPath)).toHaveLength(1);
    expect(
      readFiles.filter((f) => f === appleConfig.wwdrCertPath),
    ).toHaveLength(1);
    expect(
      readFiles.filter((f) => f === googleConfig.privateKeyPath),
    ).toHaveLength(1);
    expect(readSpy).toHaveBeenCalledTimes(4);
  });

  it('refuses to boot when Apple signer certificate is expired', () => {
    const expiredCertPath = join(tempDir, 'expired.cert');
    const expiredKeyPath = join(tempDir, 'expired.key');

    execFileSync('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      expiredKeyPath,
      '-out',
      expiredCertPath,
      '-days',
      '1',
      '-subj',
      '/CN=Expired Pass/OU=TEAM123/O=Test/C=US',
    ]);

    const fakeNow = Date.now() + 2 * 24 * 60 * 60 * 1000;
    const dateSpy = vi.spyOn(Date, 'now').mockReturnValue(fakeNow);

    const configService = {
      get: (key: string) => {
        if (key === 'applePass') {
          return {
            ...appleConfig,
            certPath: expiredCertPath,
            keyPath: expiredKeyPath,
          };
        }
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    try {
      expect(() => service.onModuleInit()).toThrow(
        /APPLE_PASS_CERT_PATH "expired\.cert" is expired/,
      );
    } finally {
      dateSpy.mockRestore();
    }
  });

  it('refuses to boot when Apple signer certificate is not yet valid', () => {
    const futureCertPath = join(tempDir, 'future.cert');
    const futureKeyPath = join(tempDir, 'future.key');

    execFileSync('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      futureKeyPath,
      '-out',
      futureCertPath,
      '-days',
      '30',
      '-subj',
      '/CN=Future Pass/OU=TEAM123/O=Test/C=US',
    ]);

    const fakeNow = Date.now() - 60 * 24 * 60 * 60 * 1000;
    const dateSpy = vi.spyOn(Date, 'now').mockReturnValue(fakeNow);

    const configService = {
      get: (key: string) => {
        if (key === 'applePass') {
          return {
            ...appleConfig,
            certPath: futureCertPath,
            keyPath: futureKeyPath,
          };
        }
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    try {
      expect(() => service.onModuleInit()).toThrow(
        /APPLE_PASS_CERT_PATH "future\.cert" is not yet valid/,
      );
    } finally {
      dateSpy.mockRestore();
    }
  });

  it('warns when Apple signer certificate expires within 30 days without leaking secrets', () => {
    const expiringCertPath = join(tempDir, 'expiring-soon.cert');
    const expiringKeyPath = join(tempDir, 'expiring-soon.key');

    execFileSync('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-keyout',
      expiringKeyPath,
      '-out',
      expiringCertPath,
      '-days',
      '15',
      '-subj',
      '/CN=Expiring Soon/OU=TEAM123/O=Test/C=US',
    ]);

    const warnSpy = vi.spyOn(console, 'warn').mockImplementation(() => {});

    const configService = {
      get: (key: string) => {
        if (key === 'applePass') {
          return {
            ...appleConfig,
            certPath: expiringCertPath,
            keyPath: expiringKeyPath,
          };
        }
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    try {
      service.onModuleInit();
      expect(warnSpy).toHaveBeenCalled();
      const warningText = warnSpy.mock.calls[0]?.[0] as string;
      expect(warningText).toContain(
        'Apple pass certificate "expiring-soon.cert" expires within 30 days',
      );
      expect(warningText).not.toContain(expiringCertPath);
      expect(warningText).not.toContain('PRIVATE KEY');
    } finally {
      warnSpy.mockRestore();
    }
  });

  it('refuses to boot when private key does not match certificate', () => {
    const mismatchedKeyPath = join(tempDir, 'mismatched.key');
    const mismatchedKp = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
      publicKeyEncoding: { type: 'spki', format: 'pem' },
    });
    writeFileSync(mismatchedKeyPath, mismatchedKp.privateKey);

    const configService = {
      get: (key: string) => {
        if (key === 'applePass') {
          return {
            ...appleConfig,
            keyPath: mismatchedKeyPath,
          };
        }
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    expect(() => service.onModuleInit()).toThrow(
      'APPLE_PASS_KEY_PATH "mismatched.key" does not match certificate "signer.cert"',
    );
  });

  it('refuses to boot when encrypted key passphrase is wrong', () => {
    const encKeyPath = join(tempDir, 'encrypted-wrong-pass.key');
    const encKp = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      privateKeyEncoding: {
        type: 'pkcs8',
        format: 'pem',
        cipher: 'aes-256-cbc',
        passphrase: 'correct-secret-passphrase',
      },
      publicKeyEncoding: { type: 'spki', format: 'pem' },
    });
    writeFileSync(encKeyPath, encKp.privateKey);

    const configService = {
      get: (key: string) => {
        if (key === 'applePass') {
          return {
            ...appleConfig,
            keyPath: encKeyPath,
            keyPassphrase: 'wrong-passphrase',
          };
        }
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    expect(() => service.onModuleInit()).toThrow(
      'APPLE_PASS_KEY_PASSPHRASE did not decrypt the key in "encrypted-wrong-pass.key"',
    );
  });

  it('refuses to boot when key is encrypted but no passphrase is configured', () => {
    const encKeyPath = join(tempDir, 'encrypted-no-pass.key');
    const encKp = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      privateKeyEncoding: {
        type: 'pkcs8',
        format: 'pem',
        cipher: 'aes-256-cbc',
        passphrase: 'some-passphrase',
      },
      publicKeyEncoding: { type: 'spki', format: 'pem' },
    });
    writeFileSync(encKeyPath, encKp.privateKey);

    const configService = {
      get: (key: string) => {
        if (key === 'applePass') {
          return {
            ...appleConfig,
            keyPath: encKeyPath,
            keyPassphrase: undefined,
          };
        }
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    expect(() => service.onModuleInit()).toThrow(
      'APPLE_PASS_KEY_PATH "encrypted-no-pass.key" is encrypted but APPLE_PASS_KEY_PASSPHRASE is not set',
    );
  });

  it('refuses to boot when Google private key is not an RSA key', () => {
    const ecKeyPath = join(tempDir, 'google-ec.key');
    const ecKp = generateKeyPairSync('ec', {
      namedCurve: 'prime256v1',
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
      publicKeyEncoding: { type: 'spki', format: 'pem' },
    });
    writeFileSync(ecKeyPath, ecKp.privateKey);

    const configService = {
      get: (key: string) => {
        if (key === 'googlePass') {
          return {
            ...googleConfig,
            privateKeyPath: ecKeyPath,
          };
        }
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    expect(() => service.onModuleInit()).toThrow(
      'GOOGLE_WALLET_PRIVATE_KEY_PATH "google-ec.key" must be an RSA private key for RS256',
    );
  });

  it('boots cleanly and initializes credentials when valid configuration is provided', () => {
    const configService = {
      get: (key: string) => {
        if (key === 'applePass') return appleConfig;
        if (key === 'googlePass') return googleConfig;
        return undefined;
      },
    } as unknown as ConfigService<Env, true>;

    const service = new PassSigningService(configService);
    expect(() => service.onModuleInit()).not.toThrow();
  });
});
