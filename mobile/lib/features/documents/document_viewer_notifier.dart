import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'document_model.dart';

class DecryptedDocument {
  final Uint8List rawBytes;
  final DrivingLicenseDocument document;

  DecryptedDocument({required this.rawBytes, required this.document});

  void zeroAndDispose() {
    for (var i = 0; i < rawBytes.length; i++) {
      rawBytes[i] = 0;
    }
  }
}

class DecryptedDocumentNotifier extends Notifier<DecryptedDocument?>
    with WidgetsBindingObserver {
  bool _disposed = false;

  @override
  DecryptedDocument? build() {
    _disposed = false;
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      _disposed = true;
      WidgetsBinding.instance.removeObserver(this);
      final current = state;
      if (current != null) {
        current.zeroAndDispose();
      }
    });
    return null;
  }

  void setDecrypted(DecryptedDocument decrypted) {
    final current = state;
    if (current != null && current != decrypted) {
      current.zeroAndDispose();
    }
    state = decrypted;
  }

  void clear() {
    final current = state;
    if (current != null) {
      current.zeroAndDispose();
    }
    state = null;
  }

  void clearDeferred() {
    final current = state;
    if (current != null) {
      current.zeroAndDispose();
    }
    Future.microtask(() {
      if (!_disposed) {
        try {
          state = null;
        } catch (_) {}
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      clear();
    }
  }
}

final decryptedDocumentNotifierProvider =
    NotifierProvider<DecryptedDocumentNotifier, DecryptedDocument?>(
      DecryptedDocumentNotifier.new,
    );
