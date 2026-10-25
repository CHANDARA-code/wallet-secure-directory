import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? error;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.error,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class SignInResponse {
  final String token;
  final Map<String, dynamic> user;

  const SignInResponse({required this.token, required this.user});
}

class ApplePassResponse {
  final Uint8List bytes;
  final bool isStub;

  const ApplePassResponse({required this.bytes, required this.isStub});
}

class GooglePassResponse {
  final String jwt;
  final String saveUrl;
  final bool isStub;

  const GooglePassResponse({
    required this.jwt,
    required this.saveUrl,
    required this.isStub,
  });
}

String resolveBaseUrl({bool releaseMode = kReleaseMode}) {
  const envUrl = String.fromEnvironment('API_BASE_URL');
  if (releaseMode) {
    if (!envUrl.startsWith('https://')) {
      throw StateError('Production API_BASE_URL must use HTTPS');
    }
    return envUrl;
  }
  if (envUrl.isNotEmpty) {
    return envUrl;
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:3000';
  }
  return 'http://localhost:3000';
}

class ApiClient {
  static final RegExp _documentIdRegex = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  final String baseUrl;
  final http.Client _client;

  ApiClient({
    String? baseUrl,
    http.Client? client,
    bool releaseMode = kReleaseMode,
  }) : _client = client ?? http.Client(),
       baseUrl = _resolveAndValidateBaseUrl(baseUrl, releaseMode);

  static String _resolveAndValidateBaseUrl(String? baseUrl, bool releaseMode) {
    final resolved = baseUrl ?? resolveBaseUrl(releaseMode: releaseMode);
    if (releaseMode && !resolved.startsWith('https://')) {
      throw StateError('Production API_BASE_URL must use HTTPS');
    }
    return resolved;
  }

  void _validateDocumentId(String documentId) {
    if (!_documentIdRegex.hasMatch(documentId)) {
      throw ArgumentError.value(
        documentId,
        'documentId',
        'Invalid documentId format',
      );
    }
  }

  Uri _uri(String path) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$cleanBase$cleanPath');
  }

  Map<String, String> _headers([String? token]) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _sendAuthenticatedRequest(
    String method,
    Uri uri,
    String token, {
    Map<String, String>? extraHeaders,
    Uint8List? bodyBytes,
    String? body,
  }) async {
    final request = http.Request(method, uri);
    final headers = _headers(token);
    if (extraHeaders != null) {
      headers.addAll(extraHeaders);
    }
    request.headers.addAll(headers);
    request.followRedirects = false;
    if (bodyBytes != null) {
      request.bodyBytes = bodyBytes;
    } else if (body != null) {
      request.body = body;
    }
    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Redirects are not permitted on authenticated requests',
      );
    }
    return response;
  }

  Never _handleErrorResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'];
        final error = decoded['error'] as String?;
        final parsedMessage = message is List
            ? message.join(', ')
            : message?.toString() ?? 'Request failed';
        throw ApiException(
          statusCode: response.statusCode,
          message: parsedMessage,
          error: error,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
    }
    throw ApiException(
      statusCode: response.statusCode,
      message: 'Request failed with status ${response.statusCode}',
    );
  }

  Future<SignInResponse> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      _uri('/api/auth/sign-up/email'),
      headers: _headers(),
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      _handleErrorResponse(response);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final headerToken = response.headers['set-auth-token'];
    final bodyToken = decoded['token'] as String?;
    final token = headerToken ?? bodyToken ?? '';
    final user = (decoded['user'] as Map<String, dynamic>?) ?? {};

    return SignInResponse(token: token, user: user);
  }

  Future<SignInResponse> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      _uri('/api/auth/sign-in/email'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode != 200) {
      _handleErrorResponse(response);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final headerToken = response.headers['set-auth-token'];
    final bodyToken = decoded['token'] as String?;
    final token = headerToken ?? bodyToken ?? '';
    final user = (decoded['user'] as Map<String, dynamic>?) ?? {};

    return SignInResponse(token: token, user: user);
  }

  Future<void> signOut(String token) async {
    final response = await _sendAuthenticatedRequest(
      'POST',
      _uri('/api/auth/sign-out'),
      token,
      body: jsonEncode({}),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      _handleErrorResponse(response);
    }
  }

  Future<List<Map<String, dynamic>>> getDocuments(String token) async {
    final response = await _sendAuthenticatedRequest(
      'GET',
      _uri('/api/documents'),
      token,
    );

    if (response.statusCode != 200) {
      _handleErrorResponse(response);
    }

    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Uint8List> getDocumentRaw(String token, String documentId) async {
    _validateDocumentId(documentId);
    final encodedId = Uri.encodeComponent(documentId);
    final response = await _sendAuthenticatedRequest(
      'GET',
      _uri('/api/documents/$encodedId'),
      token,
    );

    if (response.statusCode != 200) {
      _handleErrorResponse(response);
    }

    return response.bodyBytes;
  }

  Future<ApplePassResponse> getApplePass(
    String token,
    String documentId,
  ) async {
    _validateDocumentId(documentId);
    final encodedId = Uri.encodeComponent(documentId);
    final response = await _sendAuthenticatedRequest(
      'GET',
      _uri('/api/documents/$encodedId/pass/apple'),
      token,
      extraHeaders: {'Accept': 'application/vnd.apple.pkpass'},
    );

    if (response.statusCode != 200) {
      _handleErrorResponse(response);
    }

    final isStubHeader =
        response.headers['x-pass-stub']?.toLowerCase() == 'true';
    return ApplePassResponse(bytes: response.bodyBytes, isStub: isStubHeader);
  }

  Future<GooglePassResponse> getGooglePass(
    String token,
    String documentId,
  ) async {
    _validateDocumentId(documentId);
    final encodedId = Uri.encodeComponent(documentId);
    final response = await _sendAuthenticatedRequest(
      'GET',
      _uri('/api/documents/$encodedId/pass/google'),
      token,
    );

    if (response.statusCode != 200) {
      _handleErrorResponse(response);
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final isStubHeader =
        response.headers['x-pass-stub']?.toLowerCase() == 'true';
    final isStubBody = decoded['stub'] == true;

    return GooglePassResponse(
      jwt: decoded['jwt'] as String? ?? '',
      saveUrl: decoded['saveUrl'] as String? ?? '',
      isStub: isStubHeader || isStubBody,
    );
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});
