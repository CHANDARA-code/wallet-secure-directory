import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_app/core/auth/biometric_auth_service.dart';
import 'package:wallet_app/core/auth/biometric_key_provider.dart';
import 'package:wallet_app/core/storage/secure_storage_service.dart';

class FakeBiometricAuthService implements BiometricAuthService {
  BiometricAuthResult resultToReturn;
  int authenticateCallCount = 0;

  FakeBiometricAuthService(this.resultToReturn);

  @override
  Future<BiometricAuthResult> authenticate() async {
    authenticateCallCount++;
    return resultToReturn;
  }
}

class FakeSecureStorageService implements SecureStorageService {
  Uint8List? keyToReturn;
  String? tokenToReturn;
  int readKeyCallCount = 0;
  int writeKeyCallCount = 0;
  bool throwOnWriteKey = false;
  bool throwOnReadKey = false;
  Object? errorToThrowOnReadKey;
  @override
  bool isOsBound = false;
  bool mismatchedKeyExists = false;

  FakeSecureStorageService({
    Uint8List? keyToReturn,
    this.tokenToReturn,
    this.isOsBound = false,
  }) : keyToReturn = keyToReturn != null
           ? Uint8List.fromList(keyToReturn)
           : null;

  @override
  Future<void> writeKey(Uint8List key) async {
    writeKeyCallCount++;
    if (throwOnWriteKey) {
      throw Exception('Key write failed');
    }
    keyToReturn = Uint8List.fromList(key);
  }

  @override
  Future<Uint8List?> readKey() async {
    readKeyCallCount++;
    if (throwOnReadKey) {
      if (errorToThrowOnReadKey != null) {
        throw errorToThrowOnReadKey!;
      }
      throw Exception('Key read failed');
    }
    return keyToReturn != null ? Uint8List.fromList(keyToReturn!) : null;
  }

  @override
  Future<bool> hasKey() async {
    return keyToReturn != null;
  }

  @override
  Future<void> deleteKey() async {
    keyToReturn = null;
  }

  @override
  Future<bool> hasMismatchedKey() async {
    return mismatchedKeyExists;
  }

  @override
  Future<void> clearMismatchedKey() async {
    mismatchedKeyExists = false;
  }

  @override
  Future<void> writeToken(String token) async {
    tokenToReturn = token;
  }

  @override
  Future<String?> readToken() async {
    return tokenToReturn;
  }

  @override
  Future<void> deleteToken() async {
    tokenToReturn = null;
  }

  @override
  Future<void> deleteAll() async {
    keyToReturn = null;
    tokenToReturn = null;
    mismatchedKeyExists = false;
  }
}

class RecordingFlutterSecureStorage extends FlutterSecureStorage {
  final Map<String, String> data = {};
  AppleOptions? lastIOptions;
  AndroidOptions? lastAOptions;
  String? lastKey;

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    lastKey = key;
    lastIOptions = iOptions;
    lastAOptions = aOptions;
    if (value != null) {
      data[key] = value;
    } else {
      data.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    lastKey = key;
    lastIOptions = iOptions;
    lastAOptions = aOptions;
    return data[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    lastKey = key;
    lastIOptions = iOptions;
    lastAOptions = aOptions;
    return data.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    lastKey = key;
    lastIOptions = iOptions;
    lastAOptions = aOptions;
    data.remove(key);
  }
}

void main() {
  final expectedKey = Uint8List.fromList(List.generate(32, (i) => i));

  test('biometric success releases the key from secure storage', () async {
    final fakeAuth = FakeBiometricAuthService(
      const BiometricAuthResult(
        status: BiometricStatus.success,
        message: 'Success',
      ),
    );
    final fakeStorage = FakeSecureStorageService(keyToReturn: expectedKey);
    final provider = BiometricKeyProvider(
      biometricAuth: fakeAuth,
      secureStorage: fakeStorage,
    );

    final result = await provider.getDecryptionKey();

    expect(result, isA<KeyRetrievalSuccess>());
    final success = result as KeyRetrievalSuccess;
    expect(success.key, expectedKey);
    expect(fakeAuth.authenticateCallCount, 1);
    expect(fakeStorage.readKeyCallCount, 1);
  });

  test(
    'biometric denial releases no key and does not query secure storage',
    () async {
      final fakeAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'Biometric authentication failed.',
        ),
      );
      final fakeStorage = FakeSecureStorageService(keyToReturn: expectedKey);
      final provider = BiometricKeyProvider(
        biometricAuth: fakeAuth,
        secureStorage: fakeStorage,
      );

      final result = await provider.getDecryptionKey();

      expect(result, isA<KeyRetrievalFailure>());
      final failure = result as KeyRetrievalFailure;
      expect(failure.status, BiometricStatus.failure);
      expect(failure.message, 'Biometric authentication failed.');
      expect(fakeAuth.authenticateCallCount, 1);
      expect(fakeStorage.readKeyCallCount, 0);
    },
  );

  test('biometric not-enrolled releases no key with explicit message', () async {
    final fakeAuth = FakeBiometricAuthService(
      const BiometricAuthResult(
        status: BiometricStatus.notEnrolled,
        message:
            'No biometrics enrolled. Please set up fingerprint or Face ID in device settings.',
      ),
    );
    final fakeStorage = FakeSecureStorageService(keyToReturn: expectedKey);
    final provider = BiometricKeyProvider(
      biometricAuth: fakeAuth,
      secureStorage: fakeStorage,
    );

    final result = await provider.getDecryptionKey();

    expect(result, isA<KeyRetrievalFailure>());
    final failure = result as KeyRetrievalFailure;
    expect(failure.status, BiometricStatus.notEnrolled);
    expect(failure.message, contains('No biometrics enrolled'));
    expect(fakeStorage.readKeyCallCount, 0);
  });

  test('biometric lockout releases no key with explicit message', () async {
    final fakeAuth = FakeBiometricAuthService(
      const BiometricAuthResult(
        status: BiometricStatus.lockedOut,
        message:
            'Biometrics locked out due to too many failed attempts. Please try again later.',
      ),
    );
    final fakeStorage = FakeSecureStorageService(keyToReturn: expectedKey);
    final provider = BiometricKeyProvider(
      biometricAuth: fakeAuth,
      secureStorage: fakeStorage,
    );

    final result = await provider.getDecryptionKey();

    expect(result, isA<KeyRetrievalFailure>());
    final failure = result as KeyRetrievalFailure;
    expect(failure.status, BiometricStatus.lockedOut);
    expect(failure.message, contains('locked out'));
    expect(fakeStorage.readKeyCallCount, 0);
  });

  test('biometric unsupported releases no key with explicit message', () async {
    final fakeAuth = FakeBiometricAuthService(
      const BiometricAuthResult(
        status: BiometricStatus.unsupported,
        message: 'Biometrics are not supported or available on this device.',
      ),
    );
    final fakeStorage = FakeSecureStorageService(keyToReturn: expectedKey);
    final provider = BiometricKeyProvider(
      biometricAuth: fakeAuth,
      secureStorage: fakeStorage,
    );

    final result = await provider.getDecryptionKey();

    expect(result, isA<KeyRetrievalFailure>());
    final failure = result as KeyRetrievalFailure;
    expect(failure.status, BiometricStatus.unsupported);
    expect(failure.message, contains('not supported'));
    expect(fakeStorage.readKeyCallCount, 0);
  });

  test('biometric canceled releases no key with explicit message', () async {
    final fakeAuth = FakeBiometricAuthService(
      const BiometricAuthResult(
        status: BiometricStatus.canceled,
        message: 'Biometric authentication was canceled.',
      ),
    );
    final fakeStorage = FakeSecureStorageService(keyToReturn: expectedKey);
    final provider = BiometricKeyProvider(
      biometricAuth: fakeAuth,
      secureStorage: fakeStorage,
    );

    final result = await provider.getDecryptionKey();

    expect(result, isA<KeyRetrievalFailure>());
    final failure = result as KeyRetrievalFailure;
    expect(failure.status, BiometricStatus.canceled);
    expect(failure.message, contains('canceled'));
    expect(fakeStorage.readKeyCallCount, 0);
  });

  test(
    'getOrCreateEncryptionKey generates and stores key without prompt when none exists',
    () async {
      final fakeAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'Biometric should not be called',
        ),
      );
      final fakeStorage = FakeSecureStorageService(keyToReturn: null);
      final provider = BiometricKeyProvider(
        biometricAuth: fakeAuth,
        secureStorage: fakeStorage,
      );

      final result = await provider.getOrCreateEncryptionKey();

      expect(result, isA<KeyRetrievalSuccess>());
      final success = result as KeyRetrievalSuccess;
      expect(success.key.length, 32);
      expect(fakeStorage.keyToReturn, isNotNull);
      expect(fakeStorage.writeKeyCallCount, 1);
      expect(fakeStorage.readKeyCallCount, 0);
      expect(fakeAuth.authenticateCallCount, 0);
    },
  );

  test(
    'getOrCreateEncryptionKey requires biometric authentication when key exists',
    () async {
      final fakeAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'Biometric authentication failed.',
        ),
      );
      final fakeStorage = FakeSecureStorageService(keyToReturn: expectedKey);
      final provider = BiometricKeyProvider(
        biometricAuth: fakeAuth,
        secureStorage: fakeStorage,
      );

      final result = await provider.getOrCreateEncryptionKey();

      expect(result, isA<KeyRetrievalFailure>());
      expect(fakeAuth.authenticateCallCount, 1);
      expect(fakeStorage.readKeyCallCount, 0);
    },
  );

  test(
    'when isOsBound is true, readKey success does not double-prompt',
    () async {
      final fakeAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'App prompt should not be called',
        ),
      );
      final fakeStorage = FakeSecureStorageService(
        keyToReturn: expectedKey,
        isOsBound: true,
      );
      final provider = BiometricKeyProvider(
        biometricAuth: fakeAuth,
        secureStorage: fakeStorage,
      );

      final result = await provider.getDecryptionKey();

      expect(result, isA<KeyRetrievalSuccess>());
      expect(fakeAuth.authenticateCallCount, 0);
      expect(fakeStorage.readKeyCallCount, 1);
    },
  );

  test(
    'when isOsBound is true, canceled OS prompt maps to BiometricStatus.canceled',
    () async {
      final fakeAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'App prompt should not be called',
        ),
      );
      final fakeStorage = FakeSecureStorageService(
        keyToReturn: expectedKey,
        isOsBound: true,
      );
      fakeStorage.throwOnReadKey = true;
      fakeStorage.errorToThrowOnReadKey = Exception(
        'User canceled biometric authentication',
      );
      final provider = BiometricKeyProvider(
        biometricAuth: fakeAuth,
        secureStorage: fakeStorage,
      );

      final result = await provider.getDecryptionKey();

      expect(result, isA<KeyRetrievalFailure>());
      final failure = result as KeyRetrievalFailure;
      expect(failure.status, BiometricStatus.canceled);
      expect(fakeAuth.authenticateCallCount, 0);
    },
  );

  test(
    'when isOsBound is true, lockout OS prompt maps to BiometricStatus.lockedOut',
    () async {
      final fakeAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'App prompt should not be called',
        ),
      );
      final fakeStorage = FakeSecureStorageService(
        keyToReturn: expectedKey,
        isOsBound: true,
      );
      fakeStorage.throwOnReadKey = true;
      fakeStorage.errorToThrowOnReadKey = Exception(
        'Biometrics locked out due to attempts',
      );
      final provider = BiometricKeyProvider(
        biometricAuth: fakeAuth,
        secureStorage: fakeStorage,
      );

      final result = await provider.getDecryptionKey();

      expect(result, isA<KeyRetrievalFailure>());
      final failure = result as KeyRetrievalFailure;
      expect(failure.status, BiometricStatus.lockedOut);
    },
  );

  test(
    'option plumbing passes distinct keys and accessControlFlags only when OS_BOUND_KEY is on',
    () async {
      final storageDefault = RecordingFlutterSecureStorage();
      final serviceDefault = FlutterSecureStorageService(
        storage: storageDefault,
        isOsBound: false,
      );

      await serviceDefault.writeKey(expectedKey);
      expect(storageDefault.lastKey, 'doc_aes_gcm_key');
      expect(storageDefault.lastIOptions, isNotNull);
      final defaultMap = storageDefault.lastIOptions!.toMap();
      expect(defaultMap.containsKey('accessControlFlags'), isFalse);
      expect(
        storageDefault.lastAOptions!.toMap()['enforceBiometrics'],
        'false',
      );

      final storageBound = RecordingFlutterSecureStorage();
      final serviceBound = FlutterSecureStorageService(
        storage: storageBound,
        isOsBound: true,
      );

      await serviceBound.writeKey(expectedKey);
      expect(storageBound.lastKey, 'doc_aes_gcm_key_os_bound');
      expect(storageBound.lastIOptions, isNotNull);
      final boundMap = storageBound.lastIOptions!.toMap();
      expect(boundMap.containsKey('accessControlFlags'), isTrue);
      expect(boundMap['accessControlFlags'], contains('biometryCurrentSet'));
      expect(storageBound.lastAOptions!.toMap()['enforceBiometrics'], 'true');
      expect(
        storageBound.lastAOptions!.toMap()['requireBiometricsPerOperation'],
        'true',
      );

      expect(await serviceBound.hasMismatchedKey(), isFalse);
      storageBound.data['doc_aes_gcm_key'] = 'legacy';
      expect(await serviceBound.hasMismatchedKey(), isTrue);
      await serviceBound.clearMismatchedKey();
      expect(await serviceBound.hasMismatchedKey(), isFalse);
      expect(storageBound.data.containsKey('doc_aes_gcm_key'), isFalse);

      final storageLegacy = RecordingFlutterSecureStorage();
      final serviceLegacy = FlutterSecureStorageService(
        storage: storageLegacy,
        isOsBound: false,
      );
      await serviceLegacy.writeKey(expectedKey);
      storageLegacy.data['doc_aes_gcm_key_os_bound'] = 'legacy_os';
      expect(await serviceLegacy.hasMismatchedKey(), isTrue);
      await serviceLegacy.clearMismatchedKey();
      expect(await serviceLegacy.hasMismatchedKey(), isFalse);
      expect(
        storageLegacy.data.containsKey('doc_aes_gcm_key_os_bound'),
        isFalse,
      );
    },
  );

  test(
    'when isOsBound is true, invalidated OS keychain maps to BiometricStatus.keyInvalidated',
    () async {
      final fakeAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'App prompt should not be called',
        ),
      );
      final fakeStorage = FakeSecureStorageService(
        keyToReturn: expectedKey,
        isOsBound: true,
      );
      fakeStorage.throwOnReadKey = true;
      fakeStorage.errorToThrowOnReadKey = Exception(
        'PlatformException(errSecItemNotFound, Item not found, -25293, null)',
      );
      final provider = BiometricKeyProvider(
        biometricAuth: fakeAuth,
        secureStorage: fakeStorage,
      );

      final result = await provider.getDecryptionKey();

      expect(result, isA<KeyRetrievalFailure>());
      final failure = result as KeyRetrievalFailure;
      expect(failure.status, BiometricStatus.keyInvalidated);
      expect(fakeAuth.authenticateCallCount, 0);
    },
  );

  test(
    'when isOsBound is true, Android KeyPermanentlyInvalidatedException maps to BiometricStatus.keyInvalidated',
    () async {
      final fakeAuth = FakeBiometricAuthService(
        const BiometricAuthResult(
          status: BiometricStatus.failure,
          message: 'App prompt should not be called',
        ),
      );
      final fakeStorage = FakeSecureStorageService(
        keyToReturn: expectedKey,
        isOsBound: true,
      );
      fakeStorage.throwOnReadKey = true;
      fakeStorage.errorToThrowOnReadKey = Exception(
        'android.security.keystore.KeyPermanentlyInvalidatedException: Key permanently invalidated',
      );
      final provider = BiometricKeyProvider(
        biometricAuth: fakeAuth,
        secureStorage: fakeStorage,
      );

      final result = await provider.getDecryptionKey();

      expect(result, isA<KeyRetrievalFailure>());
      final failure = result as KeyRetrievalFailure;
      expect(failure.status, BiometricStatus.keyInvalidated);
      expect(fakeAuth.authenticateCallCount, 0);
    },
  );
}
