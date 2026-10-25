import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureStorageService {
  Future<void> writeToken(String token);
  Future<String?> readToken();
  Future<void> deleteToken();

  Future<void> writeKey(Uint8List key);
  Future<Uint8List?> readKey();
  Future<bool> hasKey();
  Future<void> deleteKey();

  Future<void> deleteAll();
}

class FlutterSecureStorageService implements SecureStorageService {
  static const String _tokenKey = 'auth_bearer_token';
  static const String _encryptionKeyKey = 'doc_aes_gcm_key';

  static const _iOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );

  static const _aOptions = AndroidOptions(
    resetOnError: true,
    keyCipherAlgorithm:
        KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
  );

  final FlutterSecureStorage _storage;

  FlutterSecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(iOptions: _iOptions, aOptions: _aOptions);

  @override
  Future<void> writeToken(String token) async {
    await _storage.write(
      key: _tokenKey,
      value: token,
      iOptions: _iOptions,
      aOptions: _aOptions,
    );
  }

  @override
  Future<String?> readToken() async {
    return _storage.read(
      key: _tokenKey,
      iOptions: _iOptions,
      aOptions: _aOptions,
    );
  }

  @override
  Future<void> deleteToken() async {
    await _storage.delete(
      key: _tokenKey,
      iOptions: _iOptions,
      aOptions: _aOptions,
    );
  }

  @override
  Future<void> writeKey(Uint8List key) async {
    final base64Key = base64Encode(key);
    await _storage.write(
      key: _encryptionKeyKey,
      value: base64Key,
      iOptions: _iOptions,
      aOptions: _aOptions,
    );
  }

  @override
  Future<Uint8List?> readKey() async {
    final base64Key = await _storage.read(
      key: _encryptionKeyKey,
      iOptions: _iOptions,
      aOptions: _aOptions,
    );
    if (base64Key == null || base64Key.isEmpty) {
      return null;
    }
    return Uint8List.fromList(base64Decode(base64Key));
  }

  @override
  Future<bool> hasKey() async {
    return _storage.containsKey(
      key: _encryptionKeyKey,
      iOptions: _iOptions,
      aOptions: _aOptions,
    );
  }

  @override
  Future<void> deleteKey() async {
    await _storage.delete(
      key: _encryptionKeyKey,
      iOptions: _iOptions,
      aOptions: _aOptions,
    );
  }

  @override
  Future<void> deleteAll() async {
    await deleteToken();
    await deleteKey();
  }
}

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return FlutterSecureStorageService();
});
