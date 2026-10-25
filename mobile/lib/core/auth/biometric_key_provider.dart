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

  Future<KeyRetrievalResult> getDecryptionKey() async {
    final authResult = await _biometricAuth.authenticate();
    if (!authResult.isSuccess) {
      return KeyRetrievalFailure(authResult);
    }

    final key = await _secureStorage.readKey();
    if (key == null) {
      return const KeyRetrievalNotFound();
    }

    return KeyRetrievalSuccess(key);
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
  );
});
