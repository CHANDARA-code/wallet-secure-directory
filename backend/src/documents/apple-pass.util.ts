import { createHash } from 'node:crypto';
import { crc32, deflateRawSync } from 'node:zlib';

export interface ZipEntry {
  name: string;
  content: string | Buffer;
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
