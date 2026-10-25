import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/biometric_key_provider.dart';
import '../../core/crypto/crypto_exceptions.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/encrypted_file_storage.dart';
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
  const DocumentsLoaded(this.documents);
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

  @override
  DocumentsState build() {
    _apiClient = ref.watch(apiClientProvider);
    _encryptedStorage = ref.watch(encryptedFileStorageProvider);
    _cryptoService = CryptoService();
    _biometricKeyProvider = ref.watch(biometricKeyProvider);

    final authState = ref.watch(authNotifierProvider);
    if (authState is Authenticated) {
      Future.microtask(() => loadDocuments(authState.token));
    }

    return const DocumentsLoading();
  }

  Future<void> loadDocuments([String? token]) async {
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
        return;
      }

      final updatedSummaries = <DocumentSummary>[];
      for (final json in summaries) {
        final doc = DocumentSummary.fromJson(json);
        final isOffline = await _encryptedStorage.hasEncryptedDocument(doc.id);
        updatedSummaries.add(doc.copyWith(isStoredOffline: isOffline));
      }

      state = DocumentsLoaded(updatedSummaries);
    } on ApiException catch (e) {
      state = DocumentsError(e.message);
    } catch (_) {
      state = const DocumentsError('Failed to load documents.');
    }
  }

  Future<void> storeDocumentOffline(String documentId, {Uint8List? key}) async {
    final authState = ref.read(authNotifierProvider);
    if (authState is! Authenticated) return;

    final token = authState.token;
    final rawBytes = await _apiClient.getDocumentRaw(token, documentId);

    Uint8List? effectiveKey = key;
    var shouldZeroKey = false;
    if (effectiveKey == null) {
      final keyResult = await _biometricKeyProvider.getOrCreateEncryptionKey();
      if (keyResult is! KeyRetrievalSuccess) {
        for (var i = 0; i < rawBytes.length; i++) {
          rawBytes[i] = 0;
        }
        return;
      }
      effectiveKey = keyResult.key;
      shouldZeroKey = true;
    }

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
      state = DocumentsLoaded(updated);
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

          Uint8List decryptedBytes;
          try {
            decryptedBytes = _cryptoService.decrypt(
              envelopeBytes: envelope,
              key: key,
              documentId: documentId,
            );
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
            } catch (_) {
              return const DocumentUnlockFailure(
                'Failed to update outdated document.',
              );
            }
          }

          final jsonStr = utf8.decode(decryptedBytes);
          final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
          final doc = DrivingLicenseDocument.fromJson(decoded);

          ref
              .read(decryptedDocumentNotifierProvider.notifier)
              .setDecrypted(
                DecryptedDocument(rawBytes: decryptedBytes, document: doc),
              );

          return const DocumentUnlockSuccess();
        } on CryptoAuthenticationException catch (_) {
          return const DocumentUnlockFailure(
            'Failed to decrypt document. The data may be corrupted or modified.',
          );
        } catch (_) {
          return const DocumentUnlockFailure(
            'Failed to decrypt document. The data may be corrupted or modified.',
          );
        } finally {
          key.fillRange(0, key.length, 0);
        }
    }
  }
}

final documentsNotifierProvider =
    NotifierProvider<DocumentsNotifier, DocumentsState>(DocumentsNotifier.new);
