import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_app/core/storage/encrypted_file_storage.dart';

void main() {
  late Directory tempDir;
  late Directory legacyDir;
  late IoEncryptedFileStorage storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wallet_test_storage_');
    legacyDir = await Directory.systemTemp.createTemp('wallet_test_legacy_');
    storage = IoEncryptedFileStorage(
      directoryProvider: () async => tempDir,
      legacyDirectoryProvider: () async => legacyDir,
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    if (await legacyDir.exists()) {
      await legacyDir.delete(recursive: true);
    }
  });

  test('saves, reads, checks existence and deletes encrypted files', () async {
    final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6]);

    expect(await storage.hasEncryptedDocument('doc-1'), isFalse);
    expect(await storage.readEncryptedDocument('doc-1'), isNull);

    await storage.saveEncryptedDocument(
      documentId: 'doc-1',
      encryptedEnvelope: payload,
    );

    expect(await storage.hasEncryptedDocument('doc-1'), isTrue);
    final readBytes = await storage.readEncryptedDocument('doc-1');
    expect(readBytes, equals(payload));

    await storage.saveEncryptedDocument(
      documentId: 'doc-2',
      encryptedEnvelope: payload,
    );
    expect(await storage.hasEncryptedDocument('doc-2'), isTrue);

    await storage.deleteEncryptedDocument('doc-1');
    expect(await storage.hasEncryptedDocument('doc-1'), isFalse);
    expect(await storage.hasEncryptedDocument('doc-2'), isTrue);

    await storage.deleteAllEncryptedDocuments();
    expect(await storage.hasEncryptedDocument('doc-2'), isFalse);
  });

  test('rejects invalid document IDs with ArgumentError', () async {
    final dummyBytes = Uint8List.fromList([1, 2, 3]);

    expect(
      () => storage.hasEncryptedDocument('../x'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.hasEncryptedDocument('a/b'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.hasEncryptedDocument(''),
      throwsA(isA<ArgumentError>()),
    );
    final longId = 'a' * 129;
    expect(
      () => storage.hasEncryptedDocument(longId),
      throwsA(isA<ArgumentError>()),
    );

    expect(
      () => storage.readEncryptedDocument('../x'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.readEncryptedDocument('a/b'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.readEncryptedDocument(''),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.readEncryptedDocument(longId),
      throwsA(isA<ArgumentError>()),
    );

    expect(
      () => storage.saveEncryptedDocument(
        documentId: '../x',
        encryptedEnvelope: dummyBytes,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.saveEncryptedDocument(
        documentId: 'a/b',
        encryptedEnvelope: dummyBytes,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.saveEncryptedDocument(
        documentId: '',
        encryptedEnvelope: dummyBytes,
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.saveEncryptedDocument(
        documentId: longId,
        encryptedEnvelope: dummyBytes,
      ),
      throwsA(isA<ArgumentError>()),
    );

    expect(
      () => storage.deleteEncryptedDocument('../x'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.deleteEncryptedDocument('a/b'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.deleteEncryptedDocument(''),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => storage.deleteEncryptedDocument(longId),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'migrates and deletes old file in legacy documents directory on first read',
    () async {
      final oldFile = File('${legacyDir.path}/doc_migrated.enc');
      await oldFile.writeAsBytes([1, 2, 3, 4]);
      expect(await oldFile.exists(), isTrue);

      final readResult = await storage.readEncryptedDocument('migrated');
      expect(readResult, isNull);
      expect(await oldFile.exists(), isFalse);
    },
  );
}
