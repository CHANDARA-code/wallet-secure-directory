import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../crypto/crypto_service.dart';
import '../storage/secure_storage_service.dart';
import 'biometric_auth_service.dart';

sealed class KeyRetrievalResult {
  const KeyRetrievalResult();
}

class KeyRetrievalSuccess extends KeyRetrievalResult {
  final Uint8List key;
  const KeyRetrievalSuccess(this.key);
}

class KeyRetrievalFailure extends KeyRetrievalResult {
  final BiometricAuthResult authResult;
  const KeyRetrievalFailure(this.authResult);

  String get message => authResult.message;
  BiometricStatus get status => authResult.status;
}

class KeyRetrievalNotFound extends KeyRetrievalResult {
  final String message;
  const KeyRetrievalNotFound([
    this.message = 'Encryption key not found in secure storage.',
  ]);
}

class BiometricKeyProvider {
  final BiometricAuthService _biometricAuth;
  final SecureStorageService _secureStorage;
  final CryptoService _cryptoService;

  BiometricKeyProvider({
    required BiometricAuthService biometricAuth,
    required SecureStorageService secureStorage,
    CryptoService? cryptoService,
  }) : _biometricAuth = biometricAuth,
       _secureStorage = secureStorage,
       _cryptoService = cryptoService ?? CryptoService();

  BiometricAuthResult _mapPlatformException(Object error) {
    final str = error.toString().toLowerCase();
    if (str.contains('keypermanentlyinvalidatedexception') ||
        str.contains('-25293') ||
        str.contains('item not found') ||
        str.contains('errsecitemnotfound') ||
        str.contains('permanently invalidated') ||
        str.contains('biometry set changed') ||
        str.contains('authentication-failed') ||
        str.contains('authentication failed')) {
      return const BiometricAuthResult(
        status: BiometricStatus.keyInvalidated,
        message: 'Biometric enrollment changed and the key was invalidated.',
      );
    }
    if (str.contains('cancel')) {
      return const BiometricAuthResult(
        status: BiometricStatus.canceled,
        message: 'Biometric authentication was canceled.',
      );
    }
    if (str.contains('not enrolled') ||
        str.contains('notenrolled') ||
        str.contains('nobio')) {
      return const BiometricAuthResult(
        status: BiometricStatus.notEnrolled,
        message:
            'No biometrics enrolled. Please set up fingerprint or Face ID in device settings.',
      );
    }
    if (str.contains('lockout') ||
        str.contains('lockedout') ||
        str.contains('locked out')) {
      return const BiometricAuthResult(
        status: BiometricStatus.lockedOut,
        message:
            'Biometrics locked out due to too many failed attempts. Please try again later.',
      );
    }
    if (str.contains('unsupported') ||
        str.contains('not supported') ||
        str.contains('not available') ||
        str.contains('hardware')) {
      return const BiometricAuthResult(
        status: BiometricStatus.unsupported,
        message: 'Biometrics are not supported or available on this device.',
      );
    }
    return const BiometricAuthResult(
      status: BiometricStatus.failure,
      message: 'Biometric authentication failed.',
    );
  }

  Future<KeyRetrievalResult> getDecryptionKey() async {
    if (_secureStorage.isOsBound) {
      try {
        final key = await _secureStorage.readKey();
        if (key == null) {
          return const KeyRetrievalNotFound();
        }
        return KeyRetrievalSuccess(key);
      } catch (e) {
        return KeyRetrievalFailure(_mapPlatformException(e));
      }
    }

    final authResult = await _biometricAuth.authenticate();
    if (!authResult.isSuccess) {
      return KeyRetrievalFailure(authResult);
    }

    try {
      final key = await _secureStorage.readKey();
      if (key == null) {
        return const KeyRetrievalNotFound();
      }
      return KeyRetrievalSuccess(key);
    } catch (e) {
      return KeyRetrievalFailure(_mapPlatformException(e));
    }
  }

  Future<KeyRetrievalResult> getOrCreateEncryptionKey() async {
    final exists = await _secureStorage.hasKey();
    if (!exists) {
      final key = _cryptoService.generateKey();
      await _secureStorage.writeKey(key);
      return KeyRetrievalSuccess(key);
    }
    return getDecryptionKey();
  }
}

final biometricKeyProvider = Provider<BiometricKeyProvider>((ref) {
  return BiometricKeyProvider(
    biometricAuth: ref.watch(biometricAuthServiceProvider),
    secureStorage: ref.watch(secureStorageServiceProvider),
    cryptoService: ref.watch(cryptoServiceProvider),
  );
});
