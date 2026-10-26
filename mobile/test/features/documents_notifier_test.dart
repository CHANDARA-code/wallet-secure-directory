import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallet_app/core/auth/biometric_auth_service.dart';
import 'package:wallet_app/core/crypto/crypto_service.dart';
import 'package:wallet_app/core/network/api_client.dart';
import 'package:wallet_app/core/storage/encrypted_file_storage.dart';
import 'package:wallet_app/core/storage/secure_storage_service.dart';
import 'package:wallet_app/features/auth/auth_notifier.dart';
import 'package:wallet_app/features/auth/auth_state.dart';
import 'package:wallet_app/features/documents/document_viewer_notifier.dart';
import 'package:wallet_app/features/documents/documents_notifier.dart';

import '../core/biometric_key_provider_test.dart';

class FakeEncryptedFileStorage implements EncryptedFileStorage {
  final Map<String, Uint8List> files = {};
  final Map<String, int> saveCounts = {};

  @override
  Future<void> saveEncryptedDocument({
    required String documentId,
    required Uint8List encryptedEnvelope,
  }) async {
    saveCounts[documentId] = (saveCounts[documentId] ?? 0) + 1;
    files[documentId] = encryptedEnvelope;
  }

  @override
  Future<Uint8List?> readEncryptedDocument(String documentId) async {
    return files[documentId];
  }

  @override
  Future<bool> hasEncryptedDocument(String documentId) async {
    return files.containsKey(documentId);
  }

  @override
  Future<void> deleteEncryptedDocument(String documentId) async {
    files.remove(documentId);
  }

  @override
  Future<void> deleteAllEncryptedDocuments() async {
    files.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSecureStorageService fakeStorage;
  late FakeEncryptedFileStorage fakeFiles;
  late FakeBiometricAuthService fakeAuth;
  late CryptoService crypto;
  late Uint8List masterKey;

  setUp(() {
    crypto = CryptoService();
    masterKey = crypto.generateKey();
    fakeStorage = FakeSecureStorageService(
      keyToReturn: masterKey,
      tokenToReturn: 'valid-token',
    );
    fakeFiles = FakeEncryptedFileStorage();
    fakeAuth = FakeBiometricAuthService(
      const BiometricAuthResult(
        status: BiometricStatus.success,
        message: 'Success',
      ),
    );
  });

  test(
    'DocumentsNotifier auto-encrypts and stores issued documents after loadDocuments',
    () async {
      var rawDocFetchCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents') {
          return http.Response(
            jsonEncode([
              {
                'id': 'dl-1',
                'type': 'driving_license',
                'documentNumber': 'DL-0123456789',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/documents/dl-1') {
          rawDocFetchCount++;
          return http.Response(
            jsonEncode({
              'id': 'dl-1',
              'type': 'driving_license',
              'documentNumber': 'DL-0123456789',
              'data': {
                'fullName': 'Sok Dara',
                'dateOfBirth': '1995-04-12',
                'address': 'Phnom Penh',
                'nationality': 'KH',
                'issuingAuthority': 'MPWT',
                'licenseClasses': ['B', 'C1'],
                'restrictions': ['CORRECTIVE_LENSES'],
                'issueDate': '2026-01-15',
                'expiryDate': '2036-01-14',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(documentsNotifierProvider);
      expect(state, isA<DocumentsLoaded>());
      final loaded = state as DocumentsLoaded;
      expect(loaded.documents.length, 1);
      expect(loaded.documents.first.documentNumber, 'DL-0123456789');
      expect(loaded.documents.first.isStoredOffline, isTrue);
      expect(rawDocFetchCount, 1);

      expect(await fakeFiles.hasEncryptedDocument('dl-1'), isTrue);

      final envelopeBytes = await fakeFiles.readEncryptedDocument('dl-1');
      expect(envelopeBytes, isNotNull);
      final parsed = crypto.parseEnvelope(envelopeBytes!);
      expect(parsed.version, 2);

      final unlockResult = await notifier.unlockDocument('dl-1');
      expect(unlockResult, isA<DocumentUnlockSuccess>());

      final decrypted = container.read(decryptedDocumentNotifierProvider);
      expect(decrypted, isNotNull);
      expect(decrypted!.document.data.fullName, 'Sok Dara');
      expect(decrypted.document.data.licenseClasses, ['B', 'C1']);

      container.dispose();
    },
  );

  test(
    'denied biometrics during loadDocuments leaves list loaded but unstored with zero key reads',
    () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents') {
          return http.Response(
            jsonEncode([
              {
                'id': 'dl-1',
                'type': 'driving_license',
                'documentNumber': 'DL-0123456789',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final deniedAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'Biometric authentication failed.',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(deniedAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      container.read(documentsNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(documentsNotifierProvider);
      expect(state, isA<DocumentsLoaded>());
      final loaded = state as DocumentsLoaded;
      expect(loaded.documents.first.isStoredOffline, isFalse);
      expect(await fakeFiles.hasEncryptedDocument('dl-1'), isFalse);
      expect(fakeStorage.readKeyCallCount, 0);

      container.dispose();
    },
  );

  test(
    'second login with stored file present does not re-download raw document',
    () async {
      var rawDocFetchCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents') {
          return http.Response(
            jsonEncode([
              {
                'id': 'dl-1',
                'type': 'driving_license',
                'documentNumber': 'DL-0123456789',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/documents/dl-1') {
          rawDocFetchCount++;
          return http.Response('{}', 200);
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-1',
        encryptedEnvelope: Uint8List.fromList([2, ...List.filled(40, 1)]),
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      container.read(documentsNotifierProvider.notifier);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(documentsNotifierProvider);
      expect(state, isA<DocumentsLoaded>());
      final loaded = state as DocumentsLoaded;
      expect(loaded.documents.first.isStoredOffline, isTrue);
      expect(rawDocFetchCount, 0);
      expect(fakeAuth.authenticateCallCount, 0);
      expect(fakeStorage.readKeyCallCount, 0);

      container.dispose();
    },
  );

  test('offline viewing succeeds when ApiClient throws on any call', () async {
    final throwingClient = MockClient((request) async {
      throw const SocketException('Connection refused - network down');
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: throwingClient);

    final plainDoc = jsonEncode({
      'id': 'dl-1',
      'type': 'driving_license',
      'documentNumber': 'DL-0123456789',
      'data': {
        'fullName': 'Sok Dara Offline',
        'dateOfBirth': '1995-04-12',
        'address': 'Phnom Penh',
        'nationality': 'KH',
        'issuingAuthority': 'MPWT',
        'licenseClasses': ['B'],
        'restrictions': [],
        'issueDate': '2026-01-15',
        'expiryDate': '2036-01-14',
      },
    });

    final envelope = crypto.encrypt(
      plaintext: Uint8List.fromList(utf8.encode(plainDoc)),
      key: masterKey,
      documentId: 'dl-1',
    );
    await fakeFiles.saveEncryptedDocument(
      documentId: 'dl-1',
      encryptedEnvelope: envelope,
    );

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        secureStorageServiceProvider.overrideWithValue(fakeStorage),
        encryptedFileStorageProvider.overrideWithValue(fakeFiles),
        biometricAuthServiceProvider.overrideWithValue(fakeAuth),
        authNotifierProvider.overrideWith(
          () => _PresetAuthNotifier(
            const Authenticated(token: 'valid-token', user: {}),
          ),
        ),
      ],
    );

    final notifier = container.read(documentsNotifierProvider.notifier);
    final result = await notifier.unlockDocument('dl-1');

    expect(result, isA<DocumentUnlockSuccess>());
    final decrypted = container.read(decryptedDocumentNotifierProvider);
    expect(decrypted, isNotNull);
    expect(decrypted!.document.data.fullName, 'Sok Dara Offline');

    container.dispose();
  });

  test(
    'mismatched key when offline returns clear failure and keeps local document',
    () async {
      final throwingClient = MockClient((request) async {
        throw const SocketException('Network down');
      });
      final apiClient = ApiClient(
        baseUrl: 'http://test',
        client: throwingClient,
      );

      final otherKey = crypto.generateKey();
      final envelope = crypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode('{"id":"dl-1"}')),
        key: otherKey,
        documentId: 'dl-1',
      );
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-1',
        encryptedEnvelope: envelope,
      );

      fakeStorage.mismatchedKeyExists = true;

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final result = await notifier.unlockDocument('dl-1');

      expect(result, isA<DocumentUnlockFailure>());
      final failure = result as DocumentUnlockFailure;
      expect(
        failure.message,
        contains('Connect to the network to refresh your stored copy'),
      );
      expect(await fakeFiles.hasEncryptedDocument('dl-1'), isTrue);

      container.dispose();
    },
  );

  test(
    'mismatched key when online re-downloads, re-encrypts and unlocks successfully',
    () async {
      final plainDoc = jsonEncode({
        'id': 'dl-1',
        'type': 'driving_license',
        'documentNumber': 'DL-0123456789',
        'data': {
          'fullName': 'Sok Dara Recovered',
          'dateOfBirth': '1995-04-12',
          'address': 'Phnom Penh',
          'nationality': 'KH',
          'issuingAuthority': 'MPWT',
          'licenseClasses': ['B'],
          'restrictions': [],
          'issueDate': '2026-01-15',
          'expiryDate': '2036-01-14',
        },
      });

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents/dl-1') {
          return http.Response(
            plainDoc,
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final otherKey = crypto.generateKey();
      final envelope = crypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode(plainDoc)),
        key: otherKey,
        documentId: 'dl-1',
      );
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-1',
        encryptedEnvelope: envelope,
      );

      fakeStorage.mismatchedKeyExists = true;

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final result = await notifier.unlockDocument('dl-1');

      expect(result, isA<DocumentUnlockSuccess>());
      final decrypted = container.read(decryptedDocumentNotifierProvider);
      expect(decrypted, isNotNull);
      expect(decrypted!.document.data.fullName, 'Sok Dara Recovered');

      final newEnvelope = await fakeFiles.readEncryptedDocument('dl-1');
      expect(newEnvelope, isNotNull);
      final decryptedDirect = crypto.decrypt(
        envelopeBytes: newEnvelope!,
        key: masterKey,
        documentId: 'dl-1',
      );
      expect(utf8.decode(decryptedDirect), contains('Sok Dara Recovered'));

      container.dispose();
    },
  );

  test(
    'unlockDocument fails and surfaces error when biometrics fail',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response('{}', 200);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final deniedAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'Biometric authentication failed.',
        ),
      );

      final plainDoc = jsonEncode({
        'id': 'dl-1',
        'type': 'driving_license',
        'documentNumber': 'DL-0123456789',
        'data': {
          'fullName': 'Sok Dara',
          'dateOfBirth': '1995-04-12',
          'address': 'Phnom Penh',
          'nationality': 'KH',
          'issuingAuthority': 'MPWT',
          'licenseClasses': ['B'],
          'restrictions': [],
          'issueDate': '2026-01-15',
          'expiryDate': '2036-01-14',
        },
      });
      final envelope = crypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode(plainDoc)),
        key: masterKey,
        documentId: 'dl-1',
      );
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-1',
        encryptedEnvelope: envelope,
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(deniedAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final unlockResult = await notifier.unlockDocument('dl-1');

      expect(unlockResult, isA<DocumentUnlockFailure>());
      final failure = unlockResult as DocumentUnlockFailure;
      expect(failure.message, 'Biometric authentication failed.');
      expect(container.read(decryptedDocumentNotifierProvider), isNull);

      container.dispose();
    },
  );

  test(
    'when fake denies biometrics and key present neither save-offline nor unlock calls readKey',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'dl-1',
            'type': 'driving_license',
            'documentNumber': 'DL-123',
            'data': {'fullName': 'Test'},
          }),
          200,
        );
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final deniedAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'Biometric rejected',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(deniedAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      expect(fakeStorage.readKeyCallCount, 0);

      final notifier = container.read(documentsNotifierProvider.notifier);
      await notifier.storeDocumentOffline('dl-1');
      expect(fakeStorage.readKeyCallCount, 0);

      final unlockResult = await notifier.unlockDocument('dl-1');
      expect(unlockResult, isA<DocumentUnlockFailure>());
      expect(fakeStorage.readKeyCallCount, 0);

      container.dispose();
    },
  );

  test(
    'unlockDocument handles outdated v1 envelope by deleting and refetching without crashing',
    () async {
      final plainDoc = jsonEncode({
        'id': 'dl-1',
        'type': 'driving_license',
        'documentNumber': 'DL-0123456789',
        'data': {
          'fullName': 'Sok Dara Refetched',
          'dateOfBirth': '1995-04-12',
          'address': 'Phnom Penh',
          'nationality': 'KH',
          'issuingAuthority': 'MPWT',
          'licenseClasses': ['B'],
          'restrictions': [],
          'issueDate': '2026-01-15',
          'expiryDate': '2036-01-14',
        },
      });

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents/dl-1') {
          return http.Response(
            plainDoc,
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final v2Envelope = crypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode('old data')),
        key: masterKey,
        documentId: 'dl-1',
      );
      final v1Envelope = Uint8List.fromList(v2Envelope);
      v1Envelope[0] = 1;
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-1',
        encryptedEnvelope: v1Envelope,
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final result = await notifier.unlockDocument('dl-1');

      expect(result, isA<DocumentUnlockSuccess>());
      final decrypted = container.read(decryptedDocumentNotifierProvider);
      expect(decrypted, isNotNull);
      expect(decrypted!.document.data.fullName, 'Sok Dara Refetched');

      final stored = await fakeFiles.readEncryptedDocument('dl-1');
      expect(stored, isNotNull);
      expect(crypto.parseEnvelope(stored!).version, 2);

      container.dispose();
    },
  );

  test(
    'copying doc_B over doc_A then unlocking A fails with clear error',
    () async {
      final mockClient = MockClient(
        (request) async => http.Response('{}', 200),
      );
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final plainDocB = jsonEncode({
        'id': 'dl-2',
        'type': 'driving_license',
        'documentNumber': 'DL-B',
        'data': {
          'fullName': 'Attacker',
          'dateOfBirth': '1990-01-01',
          'address': 'Nowhere',
          'nationality': 'KH',
          'issuingAuthority': 'MPWT',
          'licenseClasses': ['A'],
          'restrictions': [],
          'issueDate': '2026-01-15',
          'expiryDate': '2036-01-14',
        },
      });

      final envelopeB = crypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode(plainDocB)),
        key: masterKey,
        documentId: 'dl-2',
      );
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-1',
        encryptedEnvelope: envelopeB,
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final result = await notifier.unlockDocument('dl-1');

      expect(result, isA<DocumentUnlockFailure>());
      final failure = result as DocumentUnlockFailure;
      expect(failure.message, contains('corrupted or modified'));
      expect(container.read(decryptedDocumentNotifierProvider), isNull);

      container.dispose();
    },
  );

  test('signOut purges token, key and encrypted files', () async {
    final mockClient = MockClient((request) async {
      return http.Response('{}', 200);
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

    await fakeFiles.saveEncryptedDocument(
      documentId: 'dl-1',
      encryptedEnvelope: Uint8List(30),
    );

    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        secureStorageServiceProvider.overrideWithValue(fakeStorage),
        encryptedFileStorageProvider.overrideWithValue(fakeFiles),
      ],
    );

    final authNotifier = container.read(authNotifierProvider.notifier);
    await authNotifier.signIn(email: 'test@example.com', password: 'pw');

    expect(fakeStorage.tokenToReturn, isNotNull);
    expect(fakeStorage.keyToReturn, isNotNull);
    expect(await fakeFiles.hasEncryptedDocument('dl-1'), isTrue);

    await authNotifier.signOut();

    expect(fakeStorage.tokenToReturn, isNull);
    expect(fakeStorage.keyToReturn, isNull);
    expect(await fakeFiles.hasEncryptedDocument('dl-1'), isFalse);
    expect(container.read(decryptedDocumentNotifierProvider), isNull);

    container.dispose();
  });

  test(
    'signIn is all-or-nothing and cleans up token when key provisioning fails',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'token': 'atomic-token',
            'user': {'id': '1'},
          }),
          200,
        );
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final failingStorage = FakeSecureStorageService(keyToReturn: null);
      failingStorage.throwOnWriteKey = true;

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(failingStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
        ],
      );

      final authNotifier = container.read(authNotifierProvider.notifier);
      await authNotifier.signIn(email: 'test@example.com', password: 'pw');

      final state = container.read(authNotifierProvider);
      expect(state, isA<AuthError>());
      expect(failingStorage.tokenToReturn, isNull);
      expect(failingStorage.keyToReturn, isNull);

      container.dispose();
    },
  );

  test(
    'loadDocuments overlapping calls share one run with single prompt and single write per file',
    () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents') {
          return http.Response(
            jsonEncode([
              {
                'id': 'dl-concurrency',
                'type': 'driving_license',
                'documentNumber': 'DL-CONC',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/documents/dl-concurrency') {
          return http.Response(
            jsonEncode({
              'id': 'dl-concurrency',
              'type': 'driving_license',
              'documentNumber': 'DL-CONC',
              'data': {
                'fullName': 'Concurrent User',
                'dateOfBirth': '1990-01-01',
                'address': 'Test',
                'nationality': 'KH',
                'issuingAuthority': 'MPWT',
                'licenseClasses': ['B'],
                'restrictions': [],
                'issueDate': '2026-01-15',
                'expiryDate': '2036-01-14',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final countingFiles = FakeEncryptedFileStorage();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(countingFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final f1 = notifier.loadDocuments('valid-token');
      final f2 = notifier.loadDocuments('valid-token');
      await Future.wait([f1, f2]);

      expect(fakeAuth.authenticateCallCount, 1);
      expect(countingFiles.saveCounts['dl-concurrency'], 1);

      container.dispose();
    },
  );

  test(
    'loadDocuments overlapping calls when key does not exist creates exactly one key',
    () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents') {
          return http.Response(
            jsonEncode([
              {
                'id': 'dl-concurrency-new',
                'type': 'driving_license',
                'documentNumber': 'DL-NEW',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/documents/dl-concurrency-new') {
          return http.Response(
            jsonEncode({
              'id': 'dl-concurrency-new',
              'type': 'driving_license',
              'documentNumber': 'DL-NEW',
              'data': {
                'fullName': 'New Key User',
                'dateOfBirth': '1990-01-01',
                'address': 'Test',
                'nationality': 'KH',
                'issuingAuthority': 'MPWT',
                'licenseClasses': ['B'],
                'restrictions': [],
                'issueDate': '2026-01-15',
                'expiryDate': '2036-01-14',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final emptyStorage = FakeSecureStorageService(keyToReturn: null);
      final countingFiles = FakeEncryptedFileStorage();
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(emptyStorage),
          encryptedFileStorageProvider.overrideWithValue(countingFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final f1 = notifier.loadDocuments('valid-token');
      final f2 = notifier.loadDocuments('valid-token');
      await Future.wait([f1, f2]);

      expect(emptyStorage.writeKeyCallCount, 1);
      expect(countingFiles.saveCounts['dl-concurrency-new'], 1);

      container.dispose();
    },
  );

  test(
    'unlockDocument zeroes decrypted plaintext buffer when json deserialization throws',
    () async {
      final mockClient = MockClient(
        (request) async => http.Response('{}', 200),
      );
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final trackingCrypto = TrackingCryptoService();
      final invalidJsonEnvelope = trackingCrypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode('this is not json {[{')),
        key: masterKey,
        documentId: 'dl-invalid-json',
      );
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-invalid-json',
        encryptedEnvelope: invalidJsonEnvelope,
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          cryptoServiceProvider.overrideWithValue(trackingCrypto),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final result = await notifier.unlockDocument('dl-invalid-json');

      expect(result, isA<DocumentUnlockFailure>());
      expect(trackingCrypto.lastDecryptedBytes, isNotNull);
      expect(trackingCrypto.lastDecryptedBytes!.every((b) => b == 0), isTrue);

      container.dispose();
    },
  );

  test(
    'online migration in loadDocuments replaces all files atomically and clears mismatched key',
    () async {
      final plainDoc1 = jsonEncode({
        'id': 'dl-1',
        'type': 'driving_license',
        'documentNumber': 'DL-1',
        'data': {
          'fullName': 'Migrated 1',
          'dateOfBirth': '1990-01-01',
          'address': 'Test',
          'nationality': 'KH',
          'issuingAuthority': 'MPWT',
          'licenseClasses': ['B'],
          'restrictions': [],
          'issueDate': '2026-01-15',
          'expiryDate': '2036-01-14',
        },
      });
      final plainDoc2 = jsonEncode({
        'id': 'dl-2',
        'type': 'driving_license',
        'documentNumber': 'DL-2',
        'data': {
          'fullName': 'Migrated 2',
          'dateOfBirth': '1990-01-01',
          'address': 'Test',
          'nationality': 'KH',
          'issuingAuthority': 'MPWT',
          'licenseClasses': ['B'],
          'restrictions': [],
          'issueDate': '2026-01-15',
          'expiryDate': '2036-01-14',
        },
      });

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents') {
          return http.Response(
            jsonEncode([
              {
                'id': 'dl-1',
                'type': 'driving_license',
                'documentNumber': 'DL-1',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
              {
                'id': 'dl-2',
                'type': 'driving_license',
                'documentNumber': 'DL-2',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/documents/dl-1') {
          return http.Response(plainDoc1, 200);
        }
        if (request.url.path == '/api/documents/dl-2') {
          return http.Response(plainDoc2, 200);
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final legacyKey = crypto.generateKey();
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-1',
        encryptedEnvelope: crypto.encrypt(
          plaintext: Uint8List.fromList(utf8.encode('old 1')),
          key: legacyKey,
          documentId: 'dl-1',
        ),
      );
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-2',
        encryptedEnvelope: crypto.encrypt(
          plaintext: Uint8List.fromList(utf8.encode('old 2')),
          key: legacyKey,
          documentId: 'dl-2',
        ),
      );

      fakeStorage.mismatchedKeyExists = true;

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      await notifier.loadDocuments('valid-token');

      expect(fakeStorage.mismatchedKeyExists, isFalse);

      final env1 = await fakeFiles.readEncryptedDocument('dl-1');
      expect(env1, isNotNull);
      final dec1 = crypto.decrypt(
        envelopeBytes: env1!,
        key: masterKey,
        documentId: 'dl-1',
      );
      expect(utf8.decode(dec1), contains('Migrated 1'));

      final env2 = await fakeFiles.readEncryptedDocument('dl-2');
      expect(env2, isNotNull);
      final dec2 = crypto.decrypt(
        envelopeBytes: env2!,
        key: masterKey,
        documentId: 'dl-2',
      );
      expect(utf8.decode(dec2), contains('Migrated 2'));

      container.dispose();
    },
  );

  test(
    'online migration failure halfway preserves old files and legacy key',
    () async {
      final plainDoc1 = jsonEncode({
        'id': 'dl-1',
        'type': 'driving_license',
        'documentNumber': 'DL-1',
        'data': {
          'fullName': 'Migrated 1',
          'dateOfBirth': '1990-01-01',
          'address': 'Test',
          'nationality': 'KH',
          'issuingAuthority': 'MPWT',
          'licenseClasses': ['B'],
          'restrictions': [],
          'issueDate': '2026-01-15',
          'expiryDate': '2036-01-14',
        },
      });

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents') {
          return http.Response(
            jsonEncode([
              {
                'id': 'dl-1',
                'type': 'driving_license',
                'documentNumber': 'DL-1',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
              {
                'id': 'dl-2',
                'type': 'driving_license',
                'documentNumber': 'DL-2',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/documents/dl-1') {
          return http.Response(plainDoc1, 200);
        }
        if (request.url.path == '/api/documents/dl-2') {
          throw const SocketException('Network error during migration');
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final legacyKey = crypto.generateKey();
      final legacyEnvelope2 = crypto.encrypt(
        plaintext: Uint8List.fromList(utf8.encode('old 2 payload')),
        key: legacyKey,
        documentId: 'dl-2',
      );
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-1',
        encryptedEnvelope: crypto.encrypt(
          plaintext: Uint8List.fromList(utf8.encode('old 1')),
          key: legacyKey,
          documentId: 'dl-1',
        ),
      );
      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-2',
        encryptedEnvelope: legacyEnvelope2,
      );

      fakeStorage.mismatchedKeyExists = true;

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      await notifier.loadDocuments('valid-token');

      expect(fakeStorage.mismatchedKeyExists, isTrue);

      final env2 = await fakeFiles.readEncryptedDocument('dl-2');
      expect(env2, isNotNull);
      final dec2 = crypto.decrypt(
        envelopeBytes: env2!,
        key: legacyKey,
        documentId: 'dl-2',
      );
      expect(utf8.decode(dec2), 'old 2 payload');

      container.dispose();
    },
  );

  test(
    'loadDocuments recovers from invalidated key by purging local files, creating fresh key and re-storing',
    () async {
      final plainDoc = jsonEncode({
        'id': 'dl-invalidated',
        'type': 'driving_license',
        'documentNumber': 'DL-INV',
        'data': {
          'fullName': 'Recovered After Invalidation',
          'dateOfBirth': '1990-01-01',
          'address': 'Test',
          'nationality': 'KH',
          'issuingAuthority': 'MPWT',
          'licenseClasses': ['B'],
          'restrictions': [],
          'issueDate': '2026-01-15',
          'expiryDate': '2036-01-14',
        },
      });

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/documents') {
          return http.Response(
            jsonEncode([
              {
                'id': 'dl-invalidated',
                'type': 'driving_license',
                'documentNumber': 'DL-INV',
                'status': 'issued',
                'issuedAt': '2026-01-15T00:00:00.000Z',
                'expiresAt': '2036-01-14T23:59:59.999Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/documents/dl-invalidated') {
          return http.Response(plainDoc, 200);
        }
        return http.Response('Not found', 404);
      });
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      await fakeFiles.saveEncryptedDocument(
        documentId: 'dl-invalidated',
        encryptedEnvelope: Uint8List.fromList([1, 2, 3]),
      );

      final boundStorage = FakeSecureStorageService(
        keyToReturn: masterKey,
        isOsBound: true,
      );
      boundStorage.throwOnReadKey = true;
      boundStorage.errorToThrowOnReadKey = Exception(
        'PlatformException(errSecItemNotFound, Item not found, -25293, null)',
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(boundStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      await notifier.loadDocuments('valid-token');

      final state = notifier.state;
      expect(state, isA<DocumentsLoaded>());
      final loaded = state as DocumentsLoaded;
      expect(
        loaded.notice,
        'Biometric settings changed: stored documents were refreshed.',
      );
      expect(await fakeFiles.hasEncryptedDocument('dl-invalidated'), isTrue);

      final savedEnvelope = await fakeFiles.readEncryptedDocument(
        'dl-invalidated',
      );
      expect(savedEnvelope, isNotNull);
      final newKey = boundStorage.keyToReturn;
      expect(newKey, isNotNull);
      final decrypted = crypto.decrypt(
        envelopeBytes: savedEnvelope!,
        key: newKey!,
        documentId: 'dl-invalidated',
      );
      expect(utf8.decode(decrypted), contains('Recovered After Invalidation'));

      container.dispose();
    },
  );

  test(
    'unlockDocument returns clear failure when key is invalidated and does not loop',
    () async {
      final mockClient = MockClient(
        (request) async => http.Response('{}', 200),
      );
      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

      final boundStorage = FakeSecureStorageService(
        keyToReturn: masterKey,
        isOsBound: true,
      );
      boundStorage.throwOnReadKey = true;
      boundStorage.errorToThrowOnReadKey = Exception(
        'PlatformException(errSecItemNotFound, Item not found, -25293, null)',
      );

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          secureStorageServiceProvider.overrideWithValue(boundStorage),
          encryptedFileStorageProvider.overrideWithValue(fakeFiles),
          biometricAuthServiceProvider.overrideWithValue(fakeAuth),
          authNotifierProvider.overrideWith(
            () => _PresetAuthNotifier(
              const Authenticated(token: 'valid-token', user: {}),
            ),
          ),
        ],
      );

      final notifier = container.read(documentsNotifierProvider.notifier);
      final result = await notifier.unlockDocument('dl-1');

      expect(result, isA<DocumentUnlockFailure>());
      final failure = result as DocumentUnlockFailure;
      expect(
        failure.message,
        contains('Biometric enrollment changed and the key was invalidated'),
      );

      container.dispose();
    },
  );
}

class TrackingCryptoService extends CryptoService {
  Uint8List? lastDecryptedBytes;

  @override
  Uint8List decrypt({
    required Uint8List envelopeBytes,
    required Uint8List key,
    required String documentId,
  }) {
    final result = super.decrypt(
      envelopeBytes: envelopeBytes,
      key: key,
      documentId: documentId,
    );
    lastDecryptedBytes = result;
    return result;
  }
}

class _PresetAuthNotifier extends AuthNotifier {
  final AuthState _preset;
  _PresetAuthNotifier(this._preset);

  @override
  AuthState build() => _preset;
}
