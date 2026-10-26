import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallet_app/core/network/api_client.dart';
import 'package:wallet_app/core/storage/secure_storage_service.dart';
import 'package:wallet_app/core/theme/app_theme.dart';
import 'package:wallet_app/features/auth/create_account_screen.dart';
import 'package:wallet_app/features/auth/login_screen.dart';

import '../core/biometric_key_provider_test.dart';

void main() {
  testWidgets('Create account screen validates fields', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeStorage = FakeSecureStorageService();
    final mockClient = MockClient((request) async {
      return http.Response('{}', 200);
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureStorageServiceProvider.overrideWithValue(fakeStorage),
          apiClientProvider.overrideWithValue(apiClient),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CreateAccountScreen(),
        ),
      ),
    );

    expect(find.byKey(const Key('create_account_name_field')), findsOneWidget);
    expect(find.byKey(const Key('create_account_email_field')), findsOneWidget);
    expect(
      find.byKey(const Key('create_account_password_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('create_account_confirm_password_field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('create_account_submit_button')),
      findsOneWidget,
    );

    final passwordField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('create_account_password_field')),
        matching: find.byType(TextField),
      ),
    );
    expect(passwordField.obscureText, isTrue);

    final confirmPasswordField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('create_account_confirm_password_field')),
        matching: find.byType(TextField),
      ),
    );
    expect(confirmPasswordField.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your name'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('create_account_name_field')),
      'Alice',
    );
    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your email'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('create_account_email_field')),
      'not-an-email',
    );
    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a valid email address'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('create_account_email_field')),
      'alice@example.com',
    );
    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('create_account_password_field')),
      'short',
    );
    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('create_account_password_field')),
      'validpassword123',
    );
    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Please confirm your password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('create_account_confirm_password_field')),
      'differentpassword',
    );
    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('Create account shows server error for 422 user already exists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeStorage = FakeSecureStorageService();
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'message': 'User already exists. Use another email.',
          'code': 'USER_ALREADY_EXISTS_USE_ANOTHER_EMAIL',
        }),
        422,
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
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CreateAccountScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('create_account_name_field')),
      'Existing User',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_email_field')),
      'existing@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_password_field')),
      'password123',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_confirm_password_field')),
      'password123',
    );

    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();

    expect(
      find.text('User already exists. Use another email.'),
      findsOneWidget,
    );
  });

  testWidgets('Create account shows server error for 400 validation error', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeStorage = FakeSecureStorageService();
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'Invalid input data', 'error': 'Bad Request'}),
        400,
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
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CreateAccountScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('create_account_name_field')),
      'Bad User',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_email_field')),
      'bad@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_password_field')),
      'password123',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_confirm_password_field')),
      'password123',
    );

    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid input data'), findsOneWidget);
  });

  testWidgets('Create account success path stores token and authenticates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeStorage = FakeSecureStorageService();
    final mockClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path == '/api/auth/sign-up/email' &&
          body['name'] == 'Alice Doe' &&
          body['email'] == 'alice@example.com' &&
          body['password'] == 'securePassword123') {
        return http.Response(
          jsonEncode({
            'token': 'signup-token-123',
            'user': {
              'id': 'user-new',
              'name': 'Alice Doe',
              'email': 'alice@example.com',
            },
          }),
          200,
          headers: {
            'content-type': 'application/json',
            'set-auth-token': 'signup-token-123',
          },
        );
      }
      return http.Response(
        jsonEncode({'statusCode': 400, 'message': 'Bad Request'}),
        400,
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
        child: MaterialApp(
          theme: AppTheme.light,
          home: const CreateAccountScreen(),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('create_account_name_field')),
      'Alice Doe',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_email_field')),
      'alice@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_password_field')),
      'securePassword123',
    );
    await tester.enterText(
      find.byKey(const Key('create_account_confirm_password_field')),
      'securePassword123',
    );

    await tester.tap(find.byKey(const Key('create_account_submit_button')));
    await tester.pumpAndSettle();

    expect(fakeStorage.tokenToReturn, 'signup-token-123');
    expect(fakeStorage.keyToReturn, isNotNull);
  });

  testWidgets(
    'Navigation reaches create account from login and returns to login',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeStorage = FakeSecureStorageService();
      final mockClient = MockClient((request) async {
        return http.Response('{}', 200);
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

      expect(
        find.byKey(const Key('login_create_account_button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('login_create_account_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('create_account_name_field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('create_account_login_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('create_account_login_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    },
  );
}
