import { createSign } from 'node:crypto';
import type { GooglePassConfig } from '../config/env.js';

export interface GooglePassStub {
  jwt: string;
  saveUrl: string;
  stub: true;
}

export interface GooglePassSigned {
  jwt: string;
  saveUrl: string;
  stub: false;
}

export type GooglePassResponse = GooglePassStub | GooglePassSigned;

export function createGooglePassStub(
  documentNumber: string,
  payload: Record<string, unknown>,
): GooglePassStub {
  const header = {
    alg: 'none',
    typ: 'JWT',
  };

  const claims = {
    iss: 'wallet-backend-dev',
    aud: 'google',
    typ: 'savetogooglepay',
    origins: [],
    payload: {
      genericObjects: [
        {
          id: documentNumber,
          classId: 'driving_license',
          cardTitle: {
            defaultValue: {
              language: 'en',
              value: 'Driving License',
            },
          },
          header: {
            defaultValue: {
              language: 'en',
              value:
                typeof payload['fullName'] === 'string'
                  ? payload['fullName']
                  : '',
            },
          },
        },
      ],
    },
  };

  const headerB64 = Buffer.from(JSON.stringify(header)).toString('base64url');
  const claimsB64 = Buffer.from(JSON.stringify(claims)).toString('base64url');
  const jwt = `${headerB64}.${claimsB64}.`;

  return {
    jwt,
    saveUrl: `https://pay.google.com/gp/v/save/${jwt}`,
    stub: true,
  };
}

export function createSignedGooglePass(
  documentNumber: string,
  payload: Record<string, unknown>,
  config: GooglePassConfig,
  privateKeyPem: string,
): GooglePassSigned {
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  };

  const claims = {
    iss: config.serviceAccountEmail,
    aud: 'google',
    typ: 'savetowallet',
    iat: Math.floor(Date.now() / 1000),
    origins: config.origins,
    payload: {
      genericObjects: [
        {
          id: `${config.issuerId}.${documentNumber}`,
          classId: `${config.issuerId}.${config.classSuffix}`,
          cardTitle: {
            defaultValue: {
              language: 'en',
              value: 'Driving License',
            },
          },
          header: {
            defaultValue: {
              language: 'en',
              value:
                typeof payload['fullName'] === 'string'
                  ? payload['fullName']
                  : '',
            },
          },
          subheader: {
            defaultValue: {
              language: 'en',
              value: Array.isArray(payload['licenseClasses'])
                ? payload['licenseClasses'].join(', ')
                : '',
            },
          },
        },
      ],
    },
  };

  const headerB64 = Buffer.from(JSON.stringify(header)).toString('base64url');
  const claimsB64 = Buffer.from(JSON.stringify(claims)).toString('base64url');
  const signingInput = `${headerB64}.${claimsB64}`;

  const signer = createSign('RSA-SHA256');
  signer.update(signingInput);
  const signatureB64 = signer.sign(privateKeyPem, 'base64url');
  const jwt = `${signingInput}.${signatureB64}`;

  return {
    jwt,
    saveUrl: `https://pay.google.com/gp/v/save/${jwt}`,
    stub: false,
  };
}
