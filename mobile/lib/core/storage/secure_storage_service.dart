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

  bool get isOsBound;
  Future<bool> hasMismatchedKey();
  Future<void> clearMismatchedKey();

  Future<void> deleteAll();
}

class FlutterSecureStorageService implements SecureStorageService {
  static const String _tokenKey = 'auth_bearer_token';
  static const String _encryptionKeyKey = 'doc_aes_gcm_key';
  static const String _osBoundEncryptionKeyKey = 'doc_aes_gcm_key_os_bound';

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

  static const _iBoundOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
    accessControlFlags: [
      AccessControlFlag.biometryCurrentSet,
      AccessControlFlag.userPresence,
    ],
  );

  static const _aBoundOptions = AndroidOptions.biometric(
    resetOnError: true,
    enforceBiometrics: true,
    requireBiometricsPerOperation: true,
    biometricPromptTitle: 'Authenticate to access document key',
    biometricPromptSubtitle: 'Biometric authentication required',
    biometricPromptNegativeButton: 'Cancel',
  );

  final FlutterSecureStorage _storage;
  final bool _isOsBound;

  FlutterSecureStorageService({FlutterSecureStorage? storage, bool? isOsBound})
    : _isOsBound =
          isOsBound ??
          const bool.fromEnvironment('OS_BOUND_KEY', defaultValue: false),
      _storage =
          storage ??
          const FlutterSecureStorage(iOptions: _iOptions, aOptions: _aOptions);

  @override
  bool get isOsBound => _isOsBound;

  String get _activeKeyName =>
      _isOsBound ? _osBoundEncryptionKeyKey : _encryptionKeyKey;

  String get _mismatchedKeyName =>
      _isOsBound ? _encryptionKeyKey : _osBoundEncryptionKeyKey;

  IOSOptions get _activeIOptions => _isOsBound ? _iBoundOptions : _iOptions;
  AndroidOptions get _activeAOptions => _isOsBound ? _aBoundOptions : _aOptions;

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
      key: _activeKeyName,
      value: base64Key,
      iOptions: _activeIOptions,
      aOptions: _activeAOptions,
    );
  }

  @override
  Future<Uint8List?> readKey() async {
    final base64Key = await _storage.read(
      key: _activeKeyName,
      iOptions: _activeIOptions,
      aOptions: _activeAOptions,
    );
    if (base64Key == null || base64Key.isEmpty) {
      return null;
    }
    return Uint8List.fromList(base64Decode(base64Key));
  }

  @override
  Future<bool> hasKey() async {
    return _storage.containsKey(
      key: _activeKeyName,
      iOptions: _activeIOptions,
      aOptions: _activeAOptions,
    );
  }

  @override
  Future<void> deleteKey() async {
    await _storage.delete(
      key: _activeKeyName,
      iOptions: _activeIOptions,
      aOptions: _activeAOptions,
    );
  }

  @override
  Future<bool> hasMismatchedKey() async {
    return _storage.containsKey(
      key: _mismatchedKeyName,
      iOptions: _isOsBound ? _iOptions : _iBoundOptions,
      aOptions: _isOsBound ? _aOptions : _aBoundOptions,
    );
  }

  @override
  Future<void> clearMismatchedKey() async {
    await _storage.delete(
      key: _mismatchedKeyName,
      iOptions: _isOsBound ? _iOptions : _iBoundOptions,
      aOptions: _isOsBound ? _aOptions : _aBoundOptions,
    );
  }

  @override
  Future<void> deleteAll() async {
    await deleteToken();
    await _storage.delete(
      key: _encryptionKeyKey,
      iOptions: _iOptions,
      aOptions: _aOptions,
    );
    await _storage.delete(
      key: _osBoundEncryptionKeyKey,
      iOptions: _iBoundOptions,
      aOptions: _aBoundOptions,
    );
  }
}

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return FlutterSecureStorageService();
});
