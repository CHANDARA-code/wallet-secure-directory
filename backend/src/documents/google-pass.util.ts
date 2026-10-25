export interface GooglePassStub {
  jwt: string;
  saveUrl: string;
  stub: true;
}

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
