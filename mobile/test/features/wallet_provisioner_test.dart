import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wallet_app/core/network/api_client.dart';
import 'package:wallet_app/features/wallet/wallet_provisioner.dart';

class FakeNativeWalletBridge implements NativeWalletBridge {
  bool available;
  bool shouldSucceed;
  int addApplePassCount = 0;
  int addGooglePassCount = 0;

  FakeNativeWalletBridge({this.available = true, this.shouldSucceed = true});

  @override
  bool get isAvailable => available;

  @override
  Future<bool> addApplePass(Uint8List passBytes) async {
    addApplePassCount++;
    return shouldSucceed;
  }

  @override
  Future<bool> addGooglePass(String jwt) async {
    addGooglePassCount++;
    return shouldSucceed;
  }
}

void main() {
  late Uint8List unsignedZipBytes;
  late Uint8List signedZipBytes;

  setUp(() {
    final unsignedArchive = Archive();
    unsignedArchive.addFile(
      ArchiveFile('pass.json', 16, utf8.encode('{"formatVersion":1}')),
    );
    unsignedZipBytes = Uint8List.fromList(
      ZipEncoder().encode(unsignedArchive)!,
    );

    final signedArchive = Archive();
    signedArchive.addFile(
      ArchiveFile('pass.json', 16, utf8.encode('{"formatVersion":1}')),
    );
    signedArchive.addFile(
      ArchiveFile('signature', 14, utf8.encode('fake-signature')),
    );
    signedZipBytes = Uint8List.fromList(ZipEncoder().encode(signedArchive)!);
  });

  test(
    'GoogleWalletProvisioner returns WalletProvisionStubError for stub passes with header',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'jwt': 'stub-jwt',
            'saveUrl': 'https://pay.google.com/stub',
            'stub': true,
          }),
          200,
          headers: {'content-type': 'application/json', 'x-pass-stub': 'true'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final fakeBridge = FakeNativeWalletBridge(shouldSucceed: true);
      final provisioner = GoogleWalletProvisioner(
        apiClient: apiClient,
        bridge: fakeBridge,
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionStubError>());
      final stubError = result as WalletProvisionStubError;
      expect(
        stubError.message,
        'Pass provisioning requires a signed pass from the issuer',
      );
      expect(fakeBridge.addGooglePassCount, 0);
    },
  );

  test(
    'GoogleWalletProvisioner detects stub when header stripped but JWT alg is none',
    () async {
      final noneAlgJwt =
          '${base64Url.encode(utf8.encode('{"alg":"none"}'))}.${base64Url.encode(utf8.encode('{}'))}.';
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'jwt': noneAlgJwt,
            'saveUrl': 'https://pay.google.com/save',
            'stub': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final fakeBridge = FakeNativeWalletBridge(shouldSucceed: true);
      final provisioner = GoogleWalletProvisioner(
        apiClient: apiClient,
        bridge: fakeBridge,
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionStubError>());
      expect(fakeBridge.addGooglePassCount, 0);
    },
  );

  test(
    'GoogleWalletProvisioner returns WalletProvisionSuccess when fake bridge confirms',
    () async {
      final signedJwt =
          '${base64Url.encode(utf8.encode('{"alg":"ES256"}'))}.${base64Url.encode(utf8.encode('{}'))}.signature';
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'jwt': signedJwt,
            'saveUrl': 'https://pay.google.com/save',
            'stub': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final fakeBridge = FakeNativeWalletBridge(shouldSucceed: true);
      final provisioner = GoogleWalletProvisioner(
        apiClient: apiClient,
        bridge: fakeBridge,
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionSuccess>());
      expect(fakeBridge.addGooglePassCount, 1);
    },
  );

  test(
    'GoogleWalletProvisioner returns WalletProvisionFailure when fake bridge fails',
    () async {
      final signedJwt =
          '${base64Url.encode(utf8.encode('{"alg":"ES256"}'))}.${base64Url.encode(utf8.encode('{}'))}.signature';
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'jwt': signedJwt,
            'saveUrl': 'https://pay.google.com/save',
            'stub': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final fakeBridge = FakeNativeWalletBridge(shouldSucceed: false);
      final provisioner = GoogleWalletProvisioner(
        apiClient: apiClient,
        bridge: fakeBridge,
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionFailure>());
      expect(fakeBridge.addGooglePassCount, 1);
    },
  );

  test(
    'AppleWalletProvisioner returns WalletProvisionStubError for stub passes with header',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          Uint8List.fromList([1, 2, 3, 4]),
          200,
          headers: {
            'content-type': 'application/vnd.apple.pkpass',
            'x-pass-stub': 'true',
          },
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final fakeBridge = FakeNativeWalletBridge(shouldSucceed: true);
      final provisioner = AppleWalletProvisioner(
        apiClient: apiClient,
        bridge: fakeBridge,
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionStubError>());
      final stubError = result as WalletProvisionStubError;
      expect(
        stubError.message,
        'Pass provisioning requires a signed pass from the issuer',
      );
      expect(fakeBridge.addApplePassCount, 0);
    },
  );

  test(
    'AppleWalletProvisioner detects stub when header stripped but zip has no signature',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          unsignedZipBytes,
          200,
          headers: {'content-type': 'application/vnd.apple.pkpass'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final fakeBridge = FakeNativeWalletBridge(shouldSucceed: true);
      final provisioner = AppleWalletProvisioner(
        apiClient: apiClient,
        bridge: fakeBridge,
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionStubError>());
      expect(fakeBridge.addApplePassCount, 0);
    },
  );

  test(
    'AppleWalletProvisioner returns WalletProvisionSuccess when bridge confirms signed pass',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          signedZipBytes,
          200,
          headers: {'content-type': 'application/vnd.apple.pkpass'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final fakeBridge = FakeNativeWalletBridge(shouldSucceed: true);
      final provisioner = AppleWalletProvisioner(
        apiClient: apiClient,
        bridge: fakeBridge,
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionSuccess>());
      expect(fakeBridge.addApplePassCount, 1);
    },
  );

  test(
    'AppleWalletProvisioner returns WalletProvisionFailure when bridge fails',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          signedZipBytes,
          200,
          headers: {'content-type': 'application/vnd.apple.pkpass'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final fakeBridge = FakeNativeWalletBridge(shouldSucceed: false);
      final provisioner = AppleWalletProvisioner(
        apiClient: apiClient,
        bridge: fakeBridge,
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionFailure>());
      expect(fakeBridge.addApplePassCount, 1);
    },
  );

  test(
    'UnavailableNativeWalletBridge yields WalletProvisionUnavailable',
    () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          signedZipBytes,
          200,
          headers: {'content-type': 'application/vnd.apple.pkpass'},
        );
      });

      final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
      final provisioner = AppleWalletProvisioner(
        apiClient: apiClient,
        bridge: const UnavailableNativeWalletBridge(),
      );

      final result = await provisioner.provision(
        documentId: 'doc-1',
        token: 'fake-token',
      );

      expect(result, isA<WalletProvisionUnavailable>());
      final unavailable = result as WalletProvisionUnavailable;
      expect(
        unavailable.message,
        'Native wallet provisioning is not available in this build',
      );
    },
  );
}
