import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wallet_app/core/auth/biometric_auth_service.dart';
import 'package:wallet_app/core/storage/secure_storage_service.dart';
import 'package:wallet_app/features/auth/auth_notifier.dart';
import 'package:wallet_app/features/documents/document_viewer_notifier.dart';
import 'package:wallet_app/main.dart';

class ControllableBiometricAuthService implements BiometricAuthService {
  bool shouldSucceed = true;

  @override
  Future<BiometricAuthResult> authenticate() async {
    if (shouldSucceed) {
      return const BiometricAuthResult(
        status: BiometricStatus.success,
        message: 'Biometric authentication succeeded.',
      );
    }
    return const BiometricAuthResult(
      status: BiometricStatus.failure,
      message: 'Biometric authentication failed.',
    );
  }
}

bool _containsSublist(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
      return;
    }
  }
  expect(finder, findsOneWidget);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('End-to-end security and document verification flow', (
    tester,
  ) async {
    const qaEmail = String.fromEnvironment('QA_EMAIL');
    const qaPassword = String.fromEnvironment('QA_PASSWORD');

    if (qaEmail.isEmpty || qaPassword.isEmpty) {
      throw StateError(
        'QA_EMAIL and QA_PASSWORD must be provided via --dart-define',
      );
    }

    final fakeBiometrics = ControllableBiometricAuthService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biometricAuthServiceProvider.overrideWithValue(fakeBiometrics),
        ],
        child: const WalletApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WalletApp)),
    );

    final authNotifier = container.read(authNotifierProvider.notifier);
    await authNotifier.signOut();
    await tester.pump(const Duration(milliseconds: 200));

    await _waitFor(tester, find.byKey(const Key('login_email_field')));

    await tester.enterText(find.byKey(const Key('login_email_field')), qaEmail);
    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      qaPassword,
    );
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.text('Driving License'));
    expect(find.text('Driving License'), findsOneWidget);

    final saveOfflineFinder = find.text('Save Offline');
    await _waitFor(tester, saveOfflineFinder);
    await tester.tap(saveOfflineFinder);
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.text('Stored offline'));
    expect(find.text('Stored offline'), findsOneWidget);

    final appSupportDir = await getApplicationSupportDirectory();
    final encFiles = appSupportDir
        .listSync()
        .where((entity) => entity is File && entity.path.endsWith('.enc'))
        .cast<File>()
        .toList();
    expect(encFiles, isNotEmpty);

    final encBytes = await encFiles.first.readAsBytes();
    expect(encBytes.isNotEmpty, isTrue);
    expect(encBytes[0], 0x02);

    final encString = String.fromCharCodes(encBytes);
    expect(encString.contains('QA User'), isFalse);
    expect(_containsSublist(encBytes, utf8.encode('QA User')), isFalse);

    fakeBiometrics.shouldSucceed = true;
    final viewDocFinder = find.text('View Document');
    await tester.tap(viewDocFinder);
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.text('Full Name'));
    expect(find.text('QA User'), findsOneWidget);
    expect(container.read(decryptedDocumentNotifierProvider), isNotNull);

    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 100));
    await _waitFor(tester, find.text('Driving License'));

    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(find.text('Driving License'), findsOneWidget);

    await tester.tap(find.text('View Document'));
    await tester.pump(const Duration(milliseconds: 100));
    await _waitFor(tester, find.text('Full Name'));
    expect(container.read(decryptedDocumentNotifierProvider), isNotNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(find.text('Document Locked'), findsOneWidget);

    fakeBiometrics.shouldSucceed = false;
    await tester.tap(find.text('Unlock with Biometrics'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(find.text('Document Locked'), findsOneWidget);
    expect(find.text('QA User'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 100));
    await _waitFor(tester, find.byKey(const Key('sign_out_button')));

    final signOutFinder = find.byKey(const Key('sign_out_button'));
    await tester.tap(signOutFinder);
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.byKey(const Key('login_email_field')));

    final secureStorage = container.read(secureStorageServiceProvider);
    expect(await secureStorage.readToken(), isNull);
    expect(await secureStorage.hasKey(), isFalse);

    final remainingEncFiles = appSupportDir
        .listSync()
        .where((entity) => entity is File && entity.path.endsWith('.enc'))
        .toList();
    expect(remainingEncFiles, isEmpty);

    await tester.tap(find.byKey(const Key('login_create_account_button')));
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.byKey(const Key('create_account_name_field')));

    final uniqueEmail =
        'qa+${DateTime.now().millisecondsSinceEpoch}@wallet.local';
    await tester.enterText(
      find.byKey(const Key('create_account_name_field')),
      'New QA Tester',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_email_field')),
      uniqueEmail,
    );
    await tester.enterText(
      find.byKey(const Key('create_account_password_field')),
      qaPassword,
    );
    await tester.enterText(
      find.byKey(const Key('create_account_confirm_password_field')),
      qaPassword,
    );

    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.byKey(const Key('sign_out_button')));

    expect(await secureStorage.readToken(), isNotNull);
    expect(await secureStorage.hasKey(), isTrue);

    await tester.tap(find.byKey(const Key('sign_out_button')));
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.byKey(const Key('login_email_field')));
  });
}
