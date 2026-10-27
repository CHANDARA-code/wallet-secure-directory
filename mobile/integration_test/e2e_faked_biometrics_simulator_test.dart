import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wallet_app/core/auth/biometric_auth_service.dart';
import 'package:wallet_app/core/network/api_client.dart';
import 'package:wallet_app/core/storage/secure_storage_service.dart';
import 'package:wallet_app/features/auth/auth_notifier.dart';
import 'package:wallet_app/features/documents/document_viewer_notifier.dart';
import 'package:wallet_app/features/documents/document_viewer_screen.dart';
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

class ToggleableHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  bool offline = false;
  int callCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    callCount++;
    if (offline) {
      throw const SocketException('Connection refused (offline test mode)');
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
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
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 100));
      return;
    }
  }
  expect(
    finder,
    findsOneWidget,
    reason: 'Timed out waiting for $finder after ${timeout.inSeconds} seconds',
  );
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

    const apiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:3170',
    );

    final fakeBiometrics = ControllableBiometricAuthService();
    final toggleableClient = ToggleableHttpClient();
    final apiClient = ApiClient(baseUrl: apiBaseUrl, client: toggleableClient);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biometricAuthServiceProvider.overrideWithValue(fakeBiometrics),
          apiClientProvider.overrideWithValue(apiClient),
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
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      qaPassword,
    );
    await tester.pump(const Duration(milliseconds: 100));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.byKey(const Key('login_submit_button')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.text('Driving License'));
    expect(find.text('Driving License'), findsOneWidget);

    final appSupportDir = await getApplicationSupportDirectory();
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    var encFiles = <File>[];
    while (DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
      encFiles = appSupportDir
          .listSync()
          .where((entity) => entity is File && entity.path.endsWith('.enc'))
          .cast<File>()
          .toList();
      if (encFiles.isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(encFiles, isNotEmpty, reason: 'Expected auto-stored .enc file on disk');

    await _waitFor(tester, find.text('Stored offline'));
    expect(find.text('Stored offline'), findsOneWidget);

    final encBytes = await encFiles.first.readAsBytes();
    expect(encBytes.isNotEmpty, isTrue);
    expect(encBytes[0], equals(0x02));

    final encString = String.fromCharCodes(encBytes);
    expect(encString.contains('QA User'), isFalse);
    expect(_containsSublist(encBytes, utf8.encode('QA User')), isFalse);

    toggleableClient.offline = true;
    final offlineCallsBefore = toggleableClient.callCount;

    fakeBiometrics.shouldSucceed = false;
    await tester.tap(find.text('View Document'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(find.byType(DocumentViewerScreen), findsNothing);
    expect(find.text('Full Name'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DocumentViewerScreen),
        matching: find.text('QA User'),
      ),
      findsNothing,
    );

    fakeBiometrics.shouldSucceed = true;
    final viewCallsBefore = toggleableClient.callCount;
    await tester.tap(find.text('View Document'));
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.byType(DocumentViewerScreen));
    await _waitFor(tester, find.text('Full Name'));
    expect(
      find.descendant(
        of: find.byType(DocumentViewerScreen),
        matching: find.text('QA User'),
      ),
      findsOneWidget,
    );
    expect(container.read(decryptedDocumentNotifierProvider), isNotNull);
    expect(toggleableClient.callCount - viewCallsBefore, equals(0));

    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.text('Driving License'));

    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(find.byType(DocumentViewerScreen), findsNothing);
    expect(
      find.descendant(
        of: find.byType(DocumentViewerScreen),
        matching: find.text('QA User'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('View Document'));
    await tester.pump(const Duration(milliseconds: 100));
    await _waitFor(tester, find.text('Full Name'));
    expect(container.read(decryptedDocumentNotifierProvider), isNotNull);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(find.text('Document Locked'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DocumentViewerScreen),
        matching: find.text('QA User'),
      ),
      findsNothing,
    );

    fakeBiometrics.shouldSucceed = false;
    await tester.tap(find.text('Unlock with Biometrics'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(decryptedDocumentNotifierProvider), isNull);
    expect(find.text('Document Locked'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DocumentViewerScreen),
        matching: find.text('QA User'),
      ),
      findsNothing,
    );

    fakeBiometrics.shouldSucceed = true;
    final reunlockCallsBefore = toggleableClient.callCount;
    await tester.tap(find.text('Unlock with Biometrics'));
    await tester.pump(const Duration(milliseconds: 100));

    await _waitFor(tester, find.text('Full Name'));
    expect(
      find.descendant(
        of: find.byType(DocumentViewerScreen),
        matching: find.text('QA User'),
      ),
      findsOneWidget,
    );
    expect(container.read(decryptedDocumentNotifierProvider), isNotNull);
    expect(toggleableClient.callCount - reunlockCallsBefore, equals(0));
    expect(toggleableClient.callCount - offlineCallsBefore, equals(0));

    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 400));
    await _waitFor(tester, find.byKey(const Key('sign_out_button')));

    toggleableClient.offline = false;

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

    final emailDomain =
        qaEmail.contains('@') ? qaEmail.split('@')[1] : 'wallet.local';
    final uniqueEmail =
        'qa+${DateTime.now().millisecondsSinceEpoch}@$emailDomain';

    await tester.enterText(
      find.byKey(const Key('create_account_name_field')),
      'New QA Tester',
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(
      find.byKey(const Key('create_account_email_field')),
      uniqueEmail,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(
      find.byKey(const Key('create_account_password_field')),
      qaPassword,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(
      find.byKey(const Key('create_account_confirm_password_field')),
      qaPassword,
    );
    await tester.pump(const Duration(milliseconds: 50));

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(
      find.byKey(const Key('create_account_submit_button')),
    );
    await tester.pump(const Duration(milliseconds: 100));
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
