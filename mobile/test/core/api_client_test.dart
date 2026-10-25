import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallet_app/core/network/api_client.dart';

void main() {
  test('resolveBaseUrl requires https in release mode', () {
    expect(() => resolveBaseUrl(releaseMode: true), throwsA(isA<StateError>()));
  });

  test(
    'ApiClient constructor throws StateError for http base URL in release mode',
    () {
      expect(
        () => ApiClient(
          baseUrl: 'http://insecure.example.com',
          releaseMode: true,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('ApiClient constructor succeeds for https base URL in release mode', () {
    final client = ApiClient(
      baseUrl: 'https://secure.example.com',
      releaseMode: true,
    );
    expect(client.baseUrl, 'https://secure.example.com');
  });

  test('ApiClient validates documentId against path traversal', () {
    final client = ApiClient(baseUrl: 'http://localhost:3000');
    final longId = 'a' * 129;

    expect(
      () => client.getDocumentRaw('token', '../x'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => client.getDocumentRaw('token', 'a/b'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => client.getDocumentRaw('token', ''),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => client.getDocumentRaw('token', longId),
      throwsA(isA<ArgumentError>()),
    );

    expect(
      () => client.getApplePass('token', '../x'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => client.getGooglePass('token', '../x'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test(
    'authenticated request sets followRedirects to false and disallows 3xx',
    () async {
      bool? capturedFollowRedirects;
      final mockClient = MockClient((request) async {
        capturedFollowRedirects = request.followRedirects;
        return http.Response(
          'Redirected',
          302,
          headers: {'location': 'http://evil.com'},
        );
      });

      final client = ApiClient(baseUrl: 'http://test', client: mockClient);

      await expectLater(
        () => client.getDocuments('secret-token'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 302),
        ),
      );
      expect(capturedFollowRedirects, isFalse);
    },
  );

  test('signOut sets followRedirects to false', () async {
    bool? capturedFollowRedirects;
    final mockClient = MockClient((request) async {
      capturedFollowRedirects = request.followRedirects;
      return http.Response('', 204);
    });

    final client = ApiClient(baseUrl: 'http://test', client: mockClient);
    await client.signOut('token');

    expect(capturedFollowRedirects, isFalse);
  });

  test(
    'signUp sends credentials to /api/auth/sign-up/email and extracts token',
    () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/auth/sign-up/email');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'John Doe');
        expect(body['email'], 'john@example.com');
        expect(body['password'], 'secretpass');
        return http.Response(
          jsonEncode({
            'token': 'fallback-token',
            'user': {'id': 'u1', 'name': 'John Doe'},
          }),
          200,
          headers: {
            'content-type': 'application/json',
            'set-auth-token': 'header-token',
          },
        );
      });

      final client = ApiClient(baseUrl: 'http://test', client: mockClient);
      final response = await client.signUp(
        name: 'John Doe',
        email: 'john@example.com',
        password: 'secretpass',
      );

      expect(response.token, 'header-token');
      expect(response.user['id'], 'u1');
    },
  );

  test('signUp throws ApiException on 422 server error', () async {
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

    final client = ApiClient(baseUrl: 'http://test', client: mockClient);
    await expectLater(
      () => client.signUp(
        name: 'John Doe',
        email: 'john@example.com',
        password: 'secretpass',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having(
              (e) => e.message,
              'message',
              'User already exists. Use another email.',
            ),
      ),
    );
  });
}
