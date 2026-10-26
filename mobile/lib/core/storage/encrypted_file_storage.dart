import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class EncryptedFileStorage {
  Future<void> saveEncryptedDocument({
    required String documentId,
    required Uint8List encryptedEnvelope,
  });

  Future<Uint8List?> readEncryptedDocument(String documentId);

  Future<bool> hasEncryptedDocument(String documentId);

  Future<void> deleteEncryptedDocument(String documentId);

  Future<void> deleteAllEncryptedDocuments();
}

class IoEncryptedFileStorage implements EncryptedFileStorage {
  static const MethodChannel _backupChannel = MethodChannel(
    'com.example.wallet_app/backup_exclusion',
  );

  static final RegExp _documentIdRegex = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  final Future<Directory> Function() _directoryProvider;
  final Future<Directory> Function() _legacyDirectoryProvider;
  bool _exclusionApplied = false;

  IoEncryptedFileStorage({
    Future<Directory> Function()? directoryProvider,
    Future<Directory> Function()? legacyDirectoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _legacyDirectoryProvider =
           legacyDirectoryProvider ?? getApplicationDocumentsDirectory;

  void _validateDocumentId(String documentId) {
    if (!_documentIdRegex.hasMatch(documentId)) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'Invalid documentId format',
      );
    }
  }

  Future<Directory> _getDirectory() async {
    final dir = await _directoryProvider();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (!_exclusionApplied) {
      _exclusionApplied = true;
      try {
        await _backupChannel.invokeMethod('excludeFromBackup', {
          'path': dir.path,
        });
      } catch (_) {}
    }
    return dir;
  }

  Future<File> _getFile(String documentId) async {
    _validateDocumentId(documentId);
    final dir = await _getDirectory();
    return File('${dir.path}/doc_$documentId.enc');
  }

  @override
  Future<void> saveEncryptedDocument({
    required String documentId,
    required Uint8List encryptedEnvelope,
  }) async {
    _validateDocumentId(documentId);
    final file = await _getFile(documentId);
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsBytes(encryptedEnvelope, flush: true);
    await tempFile.rename(file.path);
  }

  @override
  Future<Uint8List?> readEncryptedDocument(String documentId) async {
    _validateDocumentId(documentId);
    try {
      final legacyDir = await _legacyDirectoryProvider();
      final legacyFile = File('${legacyDir.path}/doc_$documentId.enc');
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    } catch (_) {}

    final file = await _getFile(documentId);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<bool> hasEncryptedDocument(String documentId) async {
    _validateDocumentId(documentId);
    final file = await _getFile(documentId);
    return file.exists();
  }

  @override
  Future<void> deleteEncryptedDocument(String documentId) async {
    _validateDocumentId(documentId);
    final file = await _getFile(documentId);
    if (await file.exists()) {
      await file.delete();
    }
    try {
      final legacyDir = await _legacyDirectoryProvider();
      final legacyFile = File('${legacyDir.path}/doc_$documentId.enc');
      if (await legacyFile.exists()) {
        await legacyFile.delete();
      }
    } catch (_) {}
  }

  @override
  Future<void> deleteAllEncryptedDocuments() async {
    final dir = await _getDirectory();
    if (await dir.exists()) {
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.enc')) {
          await entity.delete();
        }
      }
    }
    try {
      final legacyDir = await _legacyDirectoryProvider();
      if (await legacyDir.exists()) {
        final entities = legacyDir.listSync();
        for (final entity in entities) {
          if (entity is File && entity.path.endsWith('.enc')) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }
}

final encryptedFileStorageProvider = Provider<EncryptedFileStorage>((ref) {
  return IoEncryptedFileStorage();
});
