import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_app/core/theme/app_theme.dart';
import 'package:wallet_app/features/documents/document_model.dart';
import 'package:wallet_app/features/documents/document_viewer_notifier.dart';
import 'package:wallet_app/features/documents/document_viewer_screen.dart';

void main() {
  testWidgets(
    'DocumentViewerScreen dispose wipes buffers immediately and clears state deferred',
    (tester) async {
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
      final buffer = Uint8List.fromList(utf8.encode(jsonStr));
      final doc = DrivingLicenseDocument.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

      final container = ProviderContainer();
      final notifier = container.read(
        decryptedDocumentNotifierProvider.notifier,
      );
      notifier.setDecrypted(DecryptedDocument(rawBytes: buffer, document: doc));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const DocumentViewerScreen(documentId: 'test-1'),
                        transitionDuration: Duration.zero,
                        reverseTransitionDuration: Duration.zero,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(DocumentViewerScreen), findsOneWidget);
      expect(find.text('Sok Dara'), findsOneWidget);

      Navigator.of(tester.element(find.byType(DocumentViewerScreen))).pop();
      await tester.pump();

      expect(buffer.every((b) => b == 0), isTrue);
      await tester.pump(Duration.zero);
      expect(container.read(decryptedDocumentNotifierProvider), isNull);
    },
  );
}
