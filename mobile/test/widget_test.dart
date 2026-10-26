import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallet_app/core/network/api_client.dart';
import 'package:wallet_app/core/storage/secure_storage_service.dart';
import 'package:wallet_app/core/theme/app_theme.dart';
import 'package:wallet_app/features/auth/login_screen.dart';

import 'core/biometric_key_provider_test.dart';

void main() {
  testWidgets('Login screen validates fields and authenticates user', (
    tester,
  ) async {
    final fakeStorage = FakeSecureStorageService();
    final mockClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['email'] == 'valid@example.com' &&
          body['password'] == 'secret-password') {
        return http.Response(
          jsonEncode({
            'token': 'test-token',
            'user': {'id': 'u1', 'email': 'valid@example.com'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'statusCode': 401, 'message': 'Invalid credentials'}),
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
      ),
    );

    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    expect(find.byKey(const Key('login_submit_button')), findsOneWidget);

    final passwordField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('login_password_field')),
        matching: find.byType(TextField),
      ),
    );
    expect(passwordField.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your email'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login_email_field')),
      'not-an-email',
    );
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email address'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login_email_field')),
      'valid@example.com',
    );
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      'wrong-password',
    );
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Invalid credentials'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login_password_field')),
      'secret-password',
    );
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();

    expect(fakeStorage.tokenToReturn, 'test-token');
  });
}
