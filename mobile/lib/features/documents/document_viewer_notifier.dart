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
  @override
  DecryptedDocument? build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      clear();
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
