import 'dart:convert';
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

  @override
  Future<void> saveEncryptedDocument({
    required String documentId,
    required Uint8List encryptedEnvelope,
  }) async {
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
    'DocumentsNotifier loads documents and saves offline encrypted',
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
        if (request.url.path == '/api/documents/dl-1') {
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
      await notifier.loadDocuments('valid-token');

      final state = container.read(documentsNotifierProvider);
      expect(state, isA<DocumentsLoaded>());
      final loaded = state as DocumentsLoaded;
      expect(loaded.documents.length, 1);
      expect(loaded.documents.first.documentNumber, 'DL-0123456789');
      expect(loaded.documents.first.isStoredOffline, isFalse);

      await notifier.storeDocumentOffline('dl-1');
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
}

class _PresetAuthNotifier extends AuthNotifier {
  final AuthState _preset;
  _PresetAuthNotifier(this._preset);

  @override
  AuthState build() => _preset;
}
