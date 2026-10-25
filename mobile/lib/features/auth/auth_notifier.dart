import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/encrypted_file_storage.dart';
import '../../core/storage/secure_storage_service.dart';
import '../documents/document_viewer_notifier.dart';
import 'auth_state.dart';

class AuthNotifier extends Notifier<AuthState> {
  late ApiClient _apiClient;
  late SecureStorageService _secureStorage;
  late EncryptedFileStorage _encryptedStorage;
  late CryptoService _cryptoService;

  @override
  AuthState build() {
    _apiClient = ref.watch(apiClientProvider);
    _secureStorage = ref.watch(secureStorageServiceProvider);
    _encryptedStorage = ref.watch(encryptedFileStorageProvider);
    _cryptoService = CryptoService();

    Future.microtask(() => checkSession());
    return const AuthInitial();
  }

  Future<void> checkSession() async {
    final token = await _secureStorage.readToken();
    if (token != null && token.isNotEmpty) {
      state = Authenticated(token: token, user: const {});
    } else {
      state = const Unauthenticated();
    }
  }

  void clearError() {
    if (state is AuthError) {
      state = const Unauthenticated();
    }
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    state = const AuthLoading();
    try {
      final response = await _apiClient.signUp(
        name: name,
        email: email,
        password: password,
      );

      try {
        await _secureStorage.writeToken(response.token);

        final hasKey = await _secureStorage.hasKey();
        if (!hasKey) {
          final newKey = _cryptoService.generateKey();
          try {
            await _secureStorage.writeKey(newKey);
          } finally {
            newKey.fillRange(0, newKey.length, 0);
          }
        }
      } catch (e) {
        await _secureStorage.deleteAll();
        rethrow;
      }

      state = Authenticated(token: response.token, user: response.user);
    } on ApiException catch (e) {
      state = AuthError(e.message);
    } catch (_) {
      state = const AuthError('Sign up failed. Please try again.');
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = const AuthLoading();
    try {
      final response = await _apiClient.signIn(
        email: email,
        password: password,
      );

      try {
        await _secureStorage.writeToken(response.token);

        final hasKey = await _secureStorage.hasKey();
        if (!hasKey) {
          final newKey = _cryptoService.generateKey();
          try {
            await _secureStorage.writeKey(newKey);
          } finally {
            newKey.fillRange(0, newKey.length, 0);
          }
        }
      } catch (e) {
        await _secureStorage.deleteAll();
        rethrow;
      }

      state = Authenticated(token: response.token, user: response.user);
    } on ApiException catch (e) {
      state = AuthError(e.message);
    } catch (_) {
      state = const AuthError('Sign in failed. Please check your credentials.');
    }
  }

  Future<void> signOut() async {
    final currentState = state;
    if (currentState is Authenticated) {
      try {
        await _apiClient.signOut(currentState.token);
      } catch (_) {}
    }

    await _encryptedStorage.deleteAllEncryptedDocuments();
    await _secureStorage.deleteAll();
    ref.read(decryptedDocumentNotifierProvider.notifier).clear();

    state = const Unauthenticated();
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
