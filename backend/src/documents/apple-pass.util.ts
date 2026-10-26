import { createHash, sign, type KeyObject } from 'node:crypto';
import { crc32, deflateRawSync, deflateSync } from 'node:zlib';
import * as asn1js from 'asn1js';
import * as pkijs from 'pkijs';
import type { ApplePassConfig } from '../config/env.js';

export interface ZipEntry {
  name: string;
  content: string | Buffer;
}

export interface AppleSigningKeys {
  signerCert: pkijs.Certificate;
  signerKey: KeyObject;
  wwdrCert: pkijs.Certificate;
}

function createPngChunk(type: string, data: Buffer): Buffer {
  const typeBuf = Buffer.from(type, 'ascii');
  const lenBuf = Buffer.alloc(4);
  lenBuf.writeUInt32BE(data.length, 0);
  const toCrc = Buffer.concat([typeBuf, data]);
  const crcVal = crc32(toCrc);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crcVal >>> 0, 0);
  return Buffer.concat([lenBuf, typeBuf, data, crcBuf]);
}

export function generateTinyPng(width = 1, height = 1): Buffer {
  const signature = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  ]);
  const ihdrData = Buffer.alloc(13);
  ihdrData.writeUInt32BE(width, 0);
  ihdrData.writeUInt32BE(height, 4);
  ihdrData.writeUInt8(8, 8);
  ihdrData.writeUInt8(6, 9);
  ihdrData.writeUInt8(0, 10);
  ihdrData.writeUInt8(0, 11);
  ihdrData.writeUInt8(0, 12);

  const ihdrChunk = createPngChunk('IHDR', ihdrData);
  const scanlineLength = 1 + width * 4;
  const rawData = Buffer.alloc(scanlineLength * height, 0);
  const compressed = deflateSync(rawData);
  const idatChunk = createPngChunk('IDAT', compressed);
  const iendChunk = createPngChunk('IEND', Buffer.alloc(0));

  return Buffer.concat([signature, ihdrChunk, idatChunk, iendChunk]);
}

export function createZipBuffer(entries: ZipEntry[]): Buffer {
  const localHeaders: Buffer[] = [];
  const centralHeaders: Buffer[] = [];
  let offset = 0;

  for (const entry of entries) {
    const nameBuf = Buffer.from(entry.name, 'utf8');
    const dataBuf = Buffer.isBuffer(entry.content)
      ? entry.content
      : Buffer.from(entry.content, 'utf8');
    const crc = crc32(dataBuf);
    const uncompressedSize = dataBuf.length;
    const compressed = deflateRawSync(dataBuf);
    const compressedSize = compressed.length;

    const localHeader = Buffer.alloc(30 + nameBuf.length);
    localHeader.writeUInt32LE(0x04034b50, 0);
    localHeader.writeUInt16LE(20, 4);
    localHeader.writeUInt16LE(0, 6);
    localHeader.writeUInt16LE(8, 8);
    localHeader.writeUInt16LE(0, 10);
    localHeader.writeUInt16LE(0, 12);
    localHeader.writeUInt32LE(crc, 14);
    localHeader.writeUInt32LE(compressedSize, 18);
    localHeader.writeUInt32LE(uncompressedSize, 22);
    localHeader.writeUInt16LE(nameBuf.length, 26);
    localHeader.writeUInt16LE(0, 28);
    nameBuf.copy(localHeader, 30);

    const centralHeader = Buffer.alloc(46 + nameBuf.length);
    centralHeader.writeUInt32LE(0x02014b50, 0);
    centralHeader.writeUInt16LE(20, 4);
    centralHeader.writeUInt16LE(20, 6);
    centralHeader.writeUInt16LE(0, 8);
    centralHeader.writeUInt16LE(8, 10);
    centralHeader.writeUInt16LE(0, 12);
    centralHeader.writeUInt16LE(0, 14);
    centralHeader.writeUInt32LE(crc, 16);
    centralHeader.writeUInt32LE(compressedSize, 20);
    centralHeader.writeUInt32LE(uncompressedSize, 24);
    centralHeader.writeUInt16LE(nameBuf.length, 28);
    centralHeader.writeUInt16LE(0, 30);
    centralHeader.writeUInt16LE(0, 32);
    centralHeader.writeUInt16LE(0, 34);
    centralHeader.writeUInt16LE(0, 36);
    centralHeader.writeUInt32LE(0, 38);
    centralHeader.writeUInt32LE(offset, 42);
    nameBuf.copy(centralHeader, 46);

    localHeaders.push(localHeader, compressed);
    centralHeaders.push(centralHeader);
    offset += localHeader.length + compressed.length;
  }

  const centralDirectory = Buffer.concat(centralHeaders);
  const endOfCentralDirectory = Buffer.alloc(22);
  endOfCentralDirectory.writeUInt32LE(0x06054b50, 0);
  endOfCentralDirectory.writeUInt16LE(0, 4);
  endOfCentralDirectory.writeUInt16LE(0, 6);
  endOfCentralDirectory.writeUInt16LE(entries.length, 8);
  endOfCentralDirectory.writeUInt16LE(entries.length, 10);
  endOfCentralDirectory.writeUInt32LE(centralDirectory.length, 12);
  endOfCentralDirectory.writeUInt32LE(offset, 16);
  endOfCentralDirectory.writeUInt16LE(0, 20);

  return Buffer.concat([
    ...localHeaders,
    centralDirectory,
    endOfCentralDirectory,
  ]);
}

export function createApplePassZip(
  documentNumber: string,
  payload: Record<string, unknown>,
): Buffer {
  const passJson = {
    formatVersion: 1,
    passTypeIdentifier: 'pass.com.wallet.driving-license',
    serialNumber: documentNumber,
    teamIdentifier: 'STUB_TEAM_ID',
    organizationName: 'Ministry of Public Works and Transport',
    description: 'Driving License',
    generic: {
      primaryFields: [
        {
          key: 'name',
          label: 'NAME',
          value:
            typeof payload['fullName'] === 'string' ? payload['fullName'] : '',
        },
      ],
      secondaryFields: [
        {
          key: 'licenseNumber',
          label: 'LICENSE NO',
          value: documentNumber,
        },
      ],
      auxiliaryFields: [
        {
          key: 'expiryDate',
          label: 'EXPIRY DATE',
          value:
            typeof payload['expiryDate'] === 'string'
              ? payload['expiryDate']
              : '',
        },
      ],
    },
  };

  const passJsonContent = JSON.stringify(passJson, null, 2);
  const passJsonSha1 = createHash('sha1')
    .update(Buffer.from(passJsonContent, 'utf8'))
    .digest('hex');

  const manifestJson = {
    'pass.json': passJsonSha1,
  };
  const manifestJsonContent = JSON.stringify(manifestJson, null, 2);

  return createZipBuffer([
    { name: 'pass.json', content: passJsonContent },
    { name: 'manifest.json', content: manifestJsonContent },
  ]);
}

export function createSignedApplePassZip(
  documentNumber: string,
  payload: Record<string, unknown>,
  config: ApplePassConfig,
  keys: AppleSigningKeys,
): Buffer {
  const passJson = {
    formatVersion: 1,
    passTypeIdentifier: config.passTypeId,
    serialNumber: documentNumber,
    teamIdentifier: config.teamId,
    organizationName: config.organizationName,
    description: 'Driving License',
    logoText: config.organizationName,
    generic: {
      primaryFields: [
        {
          key: 'name',
          label: 'NAME',
          value:
            typeof payload['fullName'] === 'string' ? payload['fullName'] : '',
        },
      ],
      secondaryFields: [
        {
          key: 'licenseNumber',
          label: 'LICENSE NO',
          value: documentNumber,
        },
        {
          key: 'classes',
          label: 'CLASSES',
          value: Array.isArray(payload['licenseClasses'])
            ? payload['licenseClasses'].join(', ')
            : '',
        },
      ],
      auxiliaryFields: [
        {
          key: 'expiryDate',
          label: 'EXPIRY DATE',
          value:
            typeof payload['expiryDate'] === 'string'
              ? payload['expiryDate']
              : '',
        },
      ],
    },
  };

  const passJsonBuffer = Buffer.from(JSON.stringify(passJson, null, 2), 'utf8');
  const iconPngBuffer = generateTinyPng(1, 1);
  const icon2xPngBuffer = generateTinyPng(2, 2);

  const manifest: Record<string, string> = {
    'icon.png': createHash('sha1').update(iconPngBuffer).digest('hex'),
    'icon@2x.png': createHash('sha1').update(icon2xPngBuffer).digest('hex'),
    'pass.json': createHash('sha1').update(passJsonBuffer).digest('hex'),
  };

  const manifestBuffer = Buffer.from(JSON.stringify(manifest, null, 2), 'utf8');
  const manifestSha256 = createHash('sha256').update(manifestBuffer).digest();

  const signedAttrs = new pkijs.SignedAndUnsignedAttributes({
    type: 0,
    attributes: [
      new pkijs.Attribute({
        type: '1.2.840.113549.1.9.3',
        values: [
          new asn1js.ObjectIdentifier({ value: '1.2.840.113549.1.7.1' }),
        ],
      }),
      new pkijs.Attribute({
        type: '1.2.840.113549.1.9.5',
        values: [new asn1js.UTCTime({ valueDate: new Date() })],
      }),
      new pkijs.Attribute({
        type: '1.2.840.113549.1.9.4',
        values: [new asn1js.OctetString({ valueHex: manifestSha256 })],
      }),
    ],
  });

  const attrsBer = signedAttrs.toSchema().toBER();
  const attrsUint8 = new Uint8Array(attrsBer);
  attrsUint8[0] = 0x31;

  const signature = sign('sha256', Buffer.from(attrsUint8), keys.signerKey);

  const signerInfo = new pkijs.SignerInfo({
    version: 1,
    sid: new pkijs.IssuerAndSerialNumber({
      issuer: keys.signerCert.issuer,
      serialNumber: keys.signerCert.serialNumber,
    }),
    digestAlgorithm: new pkijs.AlgorithmIdentifier({
      algorithmId: '2.16.840.1.101.3.4.2.1',
      algorithmParams: new asn1js.Null(),
    }),
    signedAttrs,
    signatureAlgorithm: new pkijs.AlgorithmIdentifier({
      algorithmId: '1.2.840.113549.1.1.1',
      algorithmParams: new asn1js.Null(),
    }),
    signature: new asn1js.OctetString({ valueHex: signature }),
  });

  const signedData = new pkijs.SignedData({
    version: 1,
    digestAlgorithms: [
      new pkijs.AlgorithmIdentifier({
        algorithmId: '2.16.840.1.101.3.4.2.1',
        algorithmParams: new asn1js.Null(),
      }),
    ],
    encapContentInfo: new pkijs.EncapsulatedContentInfo({
      eContentType: '1.2.840.113549.1.7.1',
    }),
    certificates: [keys.signerCert, keys.wwdrCert],
    signerInfos: [signerInfo],
  });

  const cms = new pkijs.ContentInfo({
    contentType: '1.2.840.113549.1.7.2',
    content: signedData.toSchema(true),
  });

  const signatureBuffer = Buffer.from(cms.toSchema().toBER());

  return createZipBuffer([
    { name: 'icon.png', content: iconPngBuffer },
    { name: 'icon@2x.png', content: icon2xPngBuffer },
    { name: 'manifest.json', content: manifestBuffer },
    { name: 'pass.json', content: passJsonBuffer },
    { name: 'signature', content: signatureBuffer },
  ]);
}
