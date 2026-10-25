import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_app/features/documents/document_model.dart';
import 'package:wallet_app/features/documents/document_viewer_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late Uint8List originalBytes;
  late DrivingLicenseDocument mockDoc;

  setUp(() {
    container = ProviderContainer();
    final jsonStr = jsonEncode({
      'id': 'test-1',
      'type': 'driving_license',
      'documentNumber': 'DL-0123456789',
      'data': {
        'fullName': 'Sok Dara',
        'dateOfBirth': '1995-04-12',
        'address': 'Phnom Penh',
        'nationality': 'KH',
        'issuingAuthority': 'MPWT',
        'licenseClasses': ['B'],
        'restrictions': [],
        'issueDate': '2026-01-15',
        'expiryDate': '2036-01-14',
      },
    });
    originalBytes = Uint8List.fromList(utf8.encode(jsonStr));
    mockDoc = DrivingLicenseDocument.fromJson(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('setting decrypted document holds state in notifier', () {
    final notifier = container.read(decryptedDocumentNotifierProvider.notifier);
    final decrypted = DecryptedDocument(
      rawBytes: originalBytes,
      document: mockDoc,
    );

    notifier.setDecrypted(decrypted);

    final state = container.read(decryptedDocumentNotifierProvider);
    expect(state, isNotNull);
    expect(state!.document.documentNumber, 'DL-0123456789');
    expect(state.rawBytes, equals(originalBytes));
  });

  test('clears and zeroes rawBytes on lifecycle paused', () {
    final notifier = container.read(decryptedDocumentNotifierProvider.notifier);
    final buffer = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    final decrypted = DecryptedDocument(rawBytes: buffer, document: mockDoc);

    notifier.setDecrypted(decrypted);
    expect(container.read(decryptedDocumentNotifierProvider), isNotNull);

    notifier.didChangeAppLifecycleState(AppLifecycleState.paused);

    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    for (var i = 0; i < buffer.length; i++) {
      expect(buffer[i], 0);
    }
  });

  test('clears and zeroes rawBytes on lifecycle inactive and hidden', () {
    final notifier = container.read(decryptedDocumentNotifierProvider.notifier);
    final bufferInactive = Uint8List.fromList([10, 20, 30]);
    notifier.setDecrypted(
      DecryptedDocument(rawBytes: bufferInactive, document: mockDoc),
    );
    notifier.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(bufferInactive.every((b) => b == 0), isTrue);

    final bufferHidden = Uint8List.fromList([40, 50, 60]);
    notifier.setDecrypted(
      DecryptedDocument(rawBytes: bufferHidden, document: mockDoc),
    );
    notifier.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(bufferHidden.every((b) => b == 0), isTrue);
  });

  test('clears and zeroes rawBytes on container dispose', () {
    final scopedContainer = ProviderContainer();
    final notifier = scopedContainer.read(
      decryptedDocumentNotifierProvider.notifier,
    );
    final buffer = Uint8List.fromList([99, 98, 97]);
    notifier.setDecrypted(
      DecryptedDocument(rawBytes: buffer, document: mockDoc),
    );

    scopedContainer.dispose();

    expect(buffer.every((b) => b == 0), isTrue);
  });
}
