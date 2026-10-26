import { Inject, Injectable, type OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createPrivateKey, X509Certificate, type KeyObject } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import * as pkijs from 'pkijs';
import type { ApplePassConfig, Env, GooglePassConfig } from '../config/env.js';
import {
  createApplePassZip,
  createSignedApplePassZip,
  type AppleSigningKeys,
} from './apple-pass.util.js';
import {
  createGooglePassStub,
  createSignedGooglePass,
  type GooglePassResponse,
} from './google-pass.util.js';

@Injectable()
export class PassSigningService implements OnModuleInit {
  private appleKeys: AppleSigningKeys | null = null;
  private googlePrivateKey: string | null = null;

  constructor(
    @Inject(ConfigService)
    private readonly configService: ConfigService<Env, true>,
  ) {}

  onModuleInit() {
    const appleConfig = this.configService.get('applePass', { infer: true });
    if (appleConfig) {
      this.getAppleKeys();
    }

    const googleConfig = this.configService.get('googlePass', { infer: true });
    if (googleConfig) {
      this.getGooglePrivateKey();
    }
  }

  private readCredentialFile(filePath: string): string {
    return readFileSync(filePath, 'utf8');
  }

  private loadAppleKeys(config: ApplePassConfig): AppleSigningKeys {
    const certPem = this.readCredentialFile(config.certPath);
    const keyPem = this.readCredentialFile(config.keyPath);
    const wwdrPem = this.readCredentialFile(config.wwdrCertPath);

    let signerCertNode: X509Certificate;
    try {
      signerCertNode = new X509Certificate(certPem);
    } catch {
      throw new Error(
        `APPLE_PASS_CERT_PATH "${basename(config.certPath)}" is not a valid X.509 certificate`,
      );
    }

    let wwdrCertNode: X509Certificate;
    try {
      wwdrCertNode = new X509Certificate(wwdrPem);
    } catch {
      throw new Error(
        `APPLE_WWDR_CERT_PATH "${basename(config.wwdrCertPath)}" is not a valid X.509 certificate`,
      );
    }

    const now = Date.now();
    const notBefore = new Date(signerCertNode.validFrom).getTime();
    const notAfter = new Date(signerCertNode.validTo).getTime();

    if (now < notBefore) {
      throw new Error(
        `APPLE_PASS_CERT_PATH "${basename(config.certPath)}" is not yet valid (valid from ${signerCertNode.validFrom})`,
      );
    }

    if (now > notAfter) {
      throw new Error(
        `APPLE_PASS_CERT_PATH "${basename(config.certPath)}" is expired (expired on ${signerCertNode.validTo})`,
      );
    }

    const thirtyDaysMs = 30 * 24 * 60 * 60 * 1000;
    if (notAfter - now <= thirtyDaysMs) {
      console.warn(
        `Apple pass certificate "${basename(config.certPath)}" expires within 30 days on ${signerCertNode.validTo}`,
      );
    }

    const wwdrNotBefore = new Date(wwdrCertNode.validFrom).getTime();
    const wwdrNotAfter = new Date(wwdrCertNode.validTo).getTime();

    if (now < wwdrNotBefore) {
      throw new Error(
        `APPLE_WWDR_CERT_PATH "${basename(config.wwdrCertPath)}" is not yet valid (valid from ${wwdrCertNode.validFrom})`,
      );
    }

    if (now > wwdrNotAfter) {
      throw new Error(
        `APPLE_WWDR_CERT_PATH "${basename(config.wwdrCertPath)}" is expired (expired on ${wwdrCertNode.validTo})`,
      );
    }

    let signerKey: KeyObject;
    if (config.keyPassphrase) {
      try {
        signerKey = createPrivateKey({
          key: keyPem,
          passphrase: config.keyPassphrase,
        });
      } catch {
        throw new Error(
          `APPLE_PASS_KEY_PASSPHRASE did not decrypt the key in "${basename(config.keyPath)}"`,
        );
      }
    } else {
      if (
        keyPem.includes('-----BEGIN ENCRYPTED PRIVATE KEY-----') ||
        keyPem.includes('Proc-Type: 4,ENCRYPTED')
      ) {
        throw new Error(
          `APPLE_PASS_KEY_PATH "${basename(config.keyPath)}" is encrypted but APPLE_PASS_KEY_PASSPHRASE is not set`,
        );
      }
      try {
        signerKey = createPrivateKey(keyPem);
      } catch {
        throw new Error(
          `APPLE_PASS_KEY_PATH "${basename(config.keyPath)}" is not a valid private key`,
        );
      }
    }

    if (!signerCertNode.checkPrivateKey(signerKey)) {
      throw new Error(
        `APPLE_PASS_KEY_PATH "${basename(config.keyPath)}" does not match certificate "${basename(config.certPath)}"`,
      );
    }

    const signerCert = pkijs.Certificate.fromBER(signerCertNode.raw);
    const wwdrCert = pkijs.Certificate.fromBER(wwdrCertNode.raw);

    return {
      signerCert,
      signerKey,
      wwdrCert,
    };
  }

  private loadGooglePrivateKey(config: GooglePassConfig): string {
    const keyPem = this.readCredentialFile(config.privateKeyPath);
    let keyObject: KeyObject;
    try {
      keyObject = createPrivateKey(keyPem);
    } catch {
      throw new Error(
        `GOOGLE_WALLET_PRIVATE_KEY_PATH "${basename(config.privateKeyPath)}" is not a valid private key`,
      );
    }

    if (keyObject.asymmetricKeyType !== 'rsa') {
      throw new Error(
        `GOOGLE_WALLET_PRIVATE_KEY_PATH "${basename(config.privateKeyPath)}" must be an RSA private key for RS256`,
      );
    }

    return keyPem;
  }

  private getAppleKeys(): AppleSigningKeys {
    if (this.appleKeys) {
      return this.appleKeys;
    }

    const config = this.configService.get('applePass', { infer: true });
    if (!config) {
      throw new Error('Apple pass configuration is missing');
    }

    this.appleKeys = this.loadAppleKeys(config);
    return this.appleKeys;
  }

  private getGooglePrivateKey(): string {
    if (this.googlePrivateKey) {
      return this.googlePrivateKey;
    }

    const config = this.configService.get('googlePass', { infer: true });
    if (!config) {
      throw new Error('Google pass configuration is missing');
    }

    this.googlePrivateKey = this.loadGooglePrivateKey(config);
    return this.googlePrivateKey;
  }

  getApplePass(
    documentNumber: string,
    payload: Record<string, unknown>,
  ): { documentNumber: string; zipBuffer: Buffer; isStub: boolean } {
    const config = this.configService.get('applePass', { infer: true });
    if (!config) {
      return {
        documentNumber,
        zipBuffer: createApplePassZip(documentNumber, payload),
        isStub: true,
      };
    }

    const keys = this.getAppleKeys();
    return {
      documentNumber,
      zipBuffer: createSignedApplePassZip(
        documentNumber,
        payload,
        config,
        keys,
      ),
      isStub: false,
    };
  }

  getGooglePass(
    documentNumber: string,
    payload: Record<string, unknown>,
  ): GooglePassResponse {
    const config = this.configService.get('googlePass', { infer: true });
    if (!config) {
      return createGooglePassStub(documentNumber, payload);
    }

    const privateKey = this.getGooglePrivateKey();
    return createSignedGooglePass(documentNumber, payload, config, privateKey);
  }
}
