import 'dart:typed_data';
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

  FakeSecureStorageService({Uint8List? keyToReturn, this.tokenToReturn})
    : keyToReturn = keyToReturn != null
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
}
