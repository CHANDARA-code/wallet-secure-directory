import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/biometric_auth_service.dart';
import '../../core/auth/biometric_key_provider.dart';
import '../../core/crypto/crypto_exceptions.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/encrypted_file_storage.dart';
import '../../core/storage/secure_storage_service.dart';
import '../auth/auth_notifier.dart';
import '../auth/auth_state.dart';
import 'document_model.dart';
import 'document_viewer_notifier.dart';

sealed class DocumentsState {
  const DocumentsState();
}

class DocumentsLoading extends DocumentsState {
  const DocumentsLoading();
}

class DocumentsEmpty extends DocumentsState {
  const DocumentsEmpty();
}

class DocumentsLoaded extends DocumentsState {
  final List<DocumentSummary> documents;
  final String? notice;
  const DocumentsLoaded(this.documents, {this.notice});
}

class DocumentsError extends DocumentsState {
  final String message;
  const DocumentsError(this.message);
}

sealed class DocumentUnlockResult {
  const DocumentUnlockResult();
}

class DocumentUnlockSuccess extends DocumentUnlockResult {
  const DocumentUnlockSuccess();
}

class DocumentUnlockFailure extends DocumentUnlockResult {
  final String message;
  const DocumentUnlockFailure(this.message);
}

class DocumentsNotifier extends Notifier<DocumentsState> {
  late ApiClient _apiClient;
  late EncryptedFileStorage _encryptedStorage;
  late CryptoService _cryptoService;
  late BiometricKeyProvider _biometricKeyProvider;
  late SecureStorageService _secureStorage;
  Future<void>? _activeLoadFuture;

  @override
  DocumentsState build() {
    _apiClient = ref.watch(apiClientProvider);
    _encryptedStorage = ref.watch(encryptedFileStorageProvider);
    _cryptoService = ref.watch(cryptoServiceProvider);
    _biometricKeyProvider = ref.watch(biometricKeyProvider);
    _secureStorage = ref.watch(secureStorageServiceProvider);

    final authState = ref.watch(authNotifierProvider);
    if (authState is Authenticated) {
      Future.microtask(() => loadDocuments(authState.token));
    }

    return const DocumentsLoading();
  }

  Future<void> loadDocuments([String? token]) async {
    if (_activeLoadFuture != null) {
      return _activeLoadFuture;
    }
    final future = _loadDocumentsInternal(token);
    _activeLoadFuture = future;
    try {
      await future;
    } finally {
      _activeLoadFuture = null;
    }
  }

  Future<void> _loadDocumentsInternal(String? token) async {
    final effectiveToken =
        token ??
        (ref.read(authNotifierProvider) is Authenticated
            ? (ref.read(authNotifierProvider) as Authenticated).token
            : null);

    if (effectiveToken == null) {
      state = const DocumentsError('Not authenticated');
      return;
    }

    state = const DocumentsLoading();
    try {
      final summaries = await _apiClient.getDocuments(effectiveToken);
      if (summaries.isEmpty) {
        state = const DocumentsEmpty();
        final hasMismatch = await _secureStorage.hasMismatchedKey();
        if (hasMismatch) {
          await _secureStorage.clearMismatchedKey();
        }
        return;
      }

      final updatedSummaries = <DocumentSummary>[];
      for (final json in summaries) {
        final doc = DocumentSummary.fromJson(json);
        final isOffline = await _encryptedStorage.hasEncryptedDocument(doc.id);
        updatedSummaries.add(doc.copyWith(isStoredOffline: isOffline));
      }

      state = DocumentsLoaded(List.unmodifiable(updatedSummaries));

      final hasMismatch = await _secureStorage.hasMismatchedKey();
      final unstored = updatedSummaries
          .where((d) => d.status == 'issued' && !d.isStoredOffline)
          .toList();
      final isOsBoundAndHasKey =
          _secureStorage.isOsBound && await _secureStorage.hasKey();

      if (hasMismatch || unstored.isNotEmpty || isOsBoundAndHasKey) {
        final keyResult = await _biometricKeyProvider
            .getOrCreateEncryptionKey();
        if (keyResult is KeyRetrievalFailure &&
            keyResult.status == BiometricStatus.keyInvalidated) {
          await _recoverFromInvalidatedKey(effectiveToken, updatedSummaries);
          return;
        }
        if (keyResult is KeyRetrievalSuccess) {
          final key = keyResult.key;
          try {
            if (hasMismatch) {
              final storedDocs = updatedSummaries
                  .where((d) => d.isStoredOffline)
                  .toList();
              for (final doc in storedDocs) {
                final rawBytes = await _apiClient.getDocumentRaw(
                  effectiveToken,
                  doc.id,
                );
                try {
                  final envelope = _cryptoService.encrypt(
                    plaintext: rawBytes,
                    key: key,
                    documentId: doc.id,
                  );
                  await _encryptedStorage.saveEncryptedDocument(
                    documentId: doc.id,
                    encryptedEnvelope: envelope,
                  );
                } finally {
                  for (var i = 0; i < rawBytes.length; i++) {
                    rawBytes[i] = 0;
                  }
                }
              }
              await _secureStorage.clearMismatchedKey();
            }

            for (final doc in unstored) {
              try {
                final rawBytes = await _apiClient.getDocumentRaw(
                  effectiveToken,
                  doc.id,
                );
                try {
                  final envelope = _cryptoService.encrypt(
                    plaintext: rawBytes,
                    key: key,
                    documentId: doc.id,
                  );
                  await _encryptedStorage.saveEncryptedDocument(
                    documentId: doc.id,
                    encryptedEnvelope: envelope,
                  );
                  final idx = updatedSummaries.indexWhere(
                    (d) => d.id == doc.id,
                  );
                  if (idx != -1) {
                    updatedSummaries[idx] = updatedSummaries[idx].copyWith(
                      isStoredOffline: true,
                    );
                    state = DocumentsLoaded(
                      List.unmodifiable(updatedSummaries),
                    );
                  }
                } finally {
                  for (var i = 0; i < rawBytes.length; i++) {
                    rawBytes[i] = 0;
                  }
                }
              } catch (_) {}
            }
          } finally {
            key.fillRange(0, key.length, 0);
          }
        }
      }
    } on ApiException catch (e) {
      state = DocumentsError(e.message);
    } catch (_) {
      state = const DocumentsError('Failed to load documents.');
    }
  }

  Future<void> _recoverFromInvalidatedKey(
    String effectiveToken,
    List<DocumentSummary> summaries,
  ) async {
    await _secureStorage.deleteKey();
    await _encryptedStorage.deleteAllEncryptedDocuments();
    final freshKey = _cryptoService.generateKey();
    try {
      await _secureStorage.writeKey(freshKey);
      final issuedDocs = summaries.where((d) => d.status == 'issued').toList();
      final updatedSummaries = summaries.map((d) {
        if (d.status == 'issued') {
          return d.copyWith(isStoredOffline: true);
        }
        return d.copyWith(isStoredOffline: false);
      }).toList();

      for (final doc in issuedDocs) {
        try {
          final rawBytes = await _apiClient.getDocumentRaw(
            effectiveToken,
            doc.id,
          );
          try {
            final envelope = _cryptoService.encrypt(
              plaintext: rawBytes,
              key: freshKey,
              documentId: doc.id,
            );
            await _encryptedStorage.saveEncryptedDocument(
              documentId: doc.id,
              encryptedEnvelope: envelope,
            );
          } finally {
            for (var i = 0; i < rawBytes.length; i++) {
              rawBytes[i] = 0;
            }
          }
        } catch (_) {}
      }

      state = DocumentsLoaded(
        List.unmodifiable(updatedSummaries),
        notice: 'Biometric settings changed: stored documents were refreshed.',
      );
    } finally {
      freshKey.fillRange(0, freshKey.length, 0);
    }
  }

  Future<void> storeDocumentOffline(String documentId, {Uint8List? key}) async {
    final authState = ref.read(authNotifierProvider);
    if (authState is! Authenticated) return;

    final token = authState.token;

    Uint8List? effectiveKey = key;
    var shouldZeroKey = false;
    if (effectiveKey == null) {
      final keyResult = await _biometricKeyProvider.getOrCreateEncryptionKey();
      if (keyResult is! KeyRetrievalSuccess) {
        return;
      }
      effectiveKey = keyResult.key;
      shouldZeroKey = true;
    }

    try {
      final rawBytes = await _apiClient.getDocumentRaw(token, documentId);
      try {
        final envelope = _cryptoService.encrypt(
          plaintext: rawBytes,
          key: effectiveKey,
          documentId: documentId,
        );
        await _encryptedStorage.saveEncryptedDocument(
          documentId: documentId,
          encryptedEnvelope: envelope,
        );
      } finally {
        for (var i = 0; i < rawBytes.length; i++) {
          rawBytes[i] = 0;
        }
      }
    } finally {
      if (shouldZeroKey) {
        effectiveKey.fillRange(0, effectiveKey.length, 0);
      }
    }

    final currentState = state;
    if (currentState is DocumentsLoaded) {
      final updated = currentState.documents.map((d) {
        if (d.id == documentId) {
          return d.copyWith(isStoredOffline: true);
        }
        return d;
      }).toList();
      state = DocumentsLoaded(List.unmodifiable(updated));
    }
  }

  Future<DocumentUnlockResult> unlockDocument(String documentId) async {
    final keyResult = await _biometricKeyProvider.getOrCreateEncryptionKey();
    switch (keyResult) {
      case KeyRetrievalFailure(:final message):
        return DocumentUnlockFailure(message);
      case KeyRetrievalNotFound(:final message):
        return DocumentUnlockFailure(message);
      case KeyRetrievalSuccess(:final key):
        try {
          Uint8List? envelope = await _encryptedStorage.readEncryptedDocument(
            documentId,
          );

          if (envelope == null) {
            final authState = ref.read(authNotifierProvider);
            if (authState is Authenticated) {
              try {
                await storeDocumentOffline(documentId, key: key);
                envelope = await _encryptedStorage.readEncryptedDocument(
                  documentId,
                );
              } catch (_) {
                return const DocumentUnlockFailure(
                  'Could not fetch document to decrypt.',
                );
              }
            }
          }

          if (envelope == null) {
            return const DocumentUnlockFailure(
              'Document not found in local storage.',
            );
          }

          final hasMismatch = await _secureStorage.hasMismatchedKey();
          if (hasMismatch) {
            final authState = ref.read(authNotifierProvider);
            if (authState is! Authenticated) {
              return const DocumentUnlockFailure(
                'Connect to the network to refresh your stored copy',
              );
            }
            try {
              await storeDocumentOffline(documentId, key: key);
              final refreshedEnvelope = await _encryptedStorage
                  .readEncryptedDocument(documentId);
              if (refreshedEnvelope == null) {
                return const DocumentUnlockFailure(
                  'Connect to the network to refresh your stored copy',
                );
              }
              envelope = refreshedEnvelope;
            } catch (_) {
              return const DocumentUnlockFailure(
                'Connect to the network to refresh your stored copy',
              );
            }
          }

          Uint8List? decryptedBytes;
          var transferredOwnership = false;
          try {
            decryptedBytes = _cryptoService.decrypt(
              envelopeBytes: envelope,
              key: key,
              documentId: documentId,
            );

            final jsonStr = utf8.decode(decryptedBytes);
            final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
            final doc = DrivingLicenseDocument.fromJson(decoded);

            ref
                .read(decryptedDocumentNotifierProvider.notifier)
                .setDecrypted(
                  DecryptedDocument(rawBytes: decryptedBytes, document: doc),
                );
            transferredOwnership = true;

            return const DocumentUnlockSuccess();
          } on InvalidEnvelopeVersionException catch (_) {
            await _encryptedStorage.deleteEncryptedDocument(documentId);
            final authState = ref.read(authNotifierProvider);
            if (authState is! Authenticated) {
              return const DocumentUnlockFailure(
                'Stored copy is outdated and user is not authenticated.',
              );
            }
            try {
              await storeDocumentOffline(documentId, key: key);
              final refreshedEnvelope = await _encryptedStorage
                  .readEncryptedDocument(documentId);
              if (refreshedEnvelope == null) {
                return const DocumentUnlockFailure(
                  'Could not fetch document to decrypt.',
                );
              }
              decryptedBytes = _cryptoService.decrypt(
                envelopeBytes: refreshedEnvelope,
                key: key,
                documentId: documentId,
              );
              final jsonStr = utf8.decode(decryptedBytes);
              final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
              final doc = DrivingLicenseDocument.fromJson(decoded);

              ref
                  .read(decryptedDocumentNotifierProvider.notifier)
                  .setDecrypted(
                    DecryptedDocument(rawBytes: decryptedBytes, document: doc),
                  );
              transferredOwnership = true;

              return const DocumentUnlockSuccess();
            } catch (_) {
              return const DocumentUnlockFailure(
                'Failed to update outdated document.',
              );
            }
          } on CryptoAuthenticationException catch (_) {
            if (hasMismatch) {
              return const DocumentUnlockFailure(
                'Connect to the network to refresh your stored copy',
              );
            }
            return const DocumentUnlockFailure(
              'Failed to decrypt document. The data may be corrupted or modified.',
            );
          } catch (_) {
            return const DocumentUnlockFailure(
              'Failed to decrypt document. The data may be corrupted or modified.',
            );
          } finally {
            if (!transferredOwnership && decryptedBytes != null) {
              decryptedBytes.fillRange(0, decryptedBytes.length, 0);
            }
          }
        } finally {
          key.fillRange(0, key.length, 0);
        }
    }
  }
}

final documentsNotifierProvider =
    NotifierProvider<DocumentsNotifier, DocumentsState>(DocumentsNotifier.new);
