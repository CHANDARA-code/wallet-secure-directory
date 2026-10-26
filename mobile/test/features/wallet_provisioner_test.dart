import 'dart:async';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  Future<WalletProvisionResult> addApplePass(Uint8List passBytes) async {
    addApplePassCount++;
    return shouldSucceed
        ? const WalletProvisionSuccess()
        : const WalletProvisionFailure(
            'Failed to provision Apple Wallet pass.',
          );
  }

  @override
  Future<WalletProvisionResult> addGooglePass(String jwt) async {
    addGooglePassCount++;
    return shouldSucceed
        ? const WalletProvisionSuccess()
        : const WalletProvisionFailure(
            'Failed to provision Google Wallet pass.',
          );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    'WalletProvisionCancelled is a direct subclass of WalletProvisionResult and not Failure',
    () {
      const cancelled = WalletProvisionCancelled();
      expect(cancelled, isA<WalletProvisionResult>());
      expect(cancelled, isNot(isA<WalletProvisionFailure>()));
      expect(cancelled.message, 'Pass provisioning was cancelled');
    },
  );

  test(
    'WalletProvisionBusy is a direct subclass of WalletProvisionResult and not Failure',
    () {
      const busy = WalletProvisionBusy();
      expect(busy, isA<WalletProvisionResult>());
      expect(busy, isNot(isA<WalletProvisionFailure>()));
      expect(busy.message, 'Pass provisioning is already in progress');
    },
  );

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

  group('PlatformNativeWalletBridge iOS method channel tests', () {
    const channel = MethodChannel('com.example.wallet_app/wallet');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test('confirmed true yields WalletProvisionSuccess', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      int callCount = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addPass') {
          callCount++;
          return true;
        }
        return null;
      });

      final bridge = PlatformNativeWalletBridge();
      final result = await bridge.addApplePass(signedZipBytes);

      expect(result, isA<WalletProvisionSuccess>());
      expect(callCount, 1);
    });

    test('confirmed string yields WalletProvisionSuccess', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addPass') {
          return 'confirmed';
        }
        return null;
      });

      final bridge = PlatformNativeWalletBridge();
      final result = await bridge.addApplePass(signedZipBytes);

      expect(result, isA<WalletProvisionSuccess>());
    });

    test('user cancelled false yields WalletProvisionCancelled', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addPass') {
          return false;
        }
        return null;
      });

      final bridge = PlatformNativeWalletBridge();
      final result = await bridge.addApplePass(signedZipBytes);

      expect(result, isA<WalletProvisionCancelled>());
      final cancelled = result as WalletProvisionCancelled;
      expect(cancelled.message, 'Pass provisioning was cancelled');
    });

    test('user cancelled string yields WalletProvisionCancelled', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addPass') {
          return 'cancelled';
        }
        return null;
      });

      final bridge = PlatformNativeWalletBridge();
      final result = await bridge.addApplePass(signedZipBytes);

      expect(result, isA<WalletProvisionCancelled>());
    });

    test(
      'invalid_pass error yields WalletProvisionFailure with clear message',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'addPass') {
            throw PlatformException(
              code: 'invalid_pass',
              message: 'PKPass data is corrupt or signature is invalid',
            );
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge();
        final result = await bridge.addApplePass(signedZipBytes);

        expect(result, isA<WalletProvisionFailure>());
        expect(result, isNot(isA<WalletProvisionSuccess>()));
        final failure = result as WalletProvisionFailure;
        expect(
          failure.message,
          contains('Invalid pass bundle: PKPass data is corrupt'),
        );
      },
    );

    test(
      'unknown or null return value yields WalletProvisionFailure and never Success',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        for (final unknownVal in ['unknown', null, 'random_string', 123]) {
          messenger.setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'addPass') {
              return unknownVal;
            }
            return null;
          });

          final bridge = PlatformNativeWalletBridge();
          final result = await bridge.addApplePass(signedZipBytes);

          expect(result, isNot(isA<WalletProvisionSuccess>()));
          expect(result, isA<WalletProvisionFailure>());
          final failure = result as WalletProvisionFailure;
          expect(failure.message, 'Pass addition could not be confirmed.');
        }
      },
    );

    test('generic PlatformException yields WalletProvisionFailure', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addPass') {
          throw PlatformException(
            code: 'unexpected_error',
            message: 'Pass presentation failed',
          );
        }
        return null;
      });

      final bridge = PlatformNativeWalletBridge();
      final result = await bridge.addApplePass(signedZipBytes);

      expect(result, isA<WalletProvisionFailure>());
      expect(result, isNot(isA<WalletProvisionSuccess>()));
      final failure = result as WalletProvisionFailure;
      expect(failure.message, 'Pass presentation failed');
    });

    test(
      'unavailable PlatformException yields WalletProvisionUnavailable',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'addPass') {
            throw PlatformException(
              code: 'unavailable',
              message: 'PassKit cannot add passes on this device',
            );
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge();
        final result = await bridge.addApplePass(signedZipBytes);

        expect(result, isA<WalletProvisionUnavailable>());
        final unavailable = result as WalletProvisionUnavailable;
        expect(unavailable.message, 'PassKit cannot add passes on this device');
      },
    );

    test(
      'AppleWalletProvisioner never calls native channel for stub passes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        int nativeCallCount = 0;
        messenger.setMockMethodCallHandler(channel, (call) async {
          nativeCallCount++;
          return true;
        });

        final mockClient = MockClient((request) async {
          return http.Response.bytes(
            unsignedZipBytes,
            200,
            headers: {'content-type': 'application/vnd.apple.pkpass'},
          );
        });

        final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
        final bridge = PlatformNativeWalletBridge();
        final provisioner = AppleWalletProvisioner(
          apiClient: apiClient,
          bridge: bridge,
        );

        final result = await provisioner.provision(
          documentId: 'doc-stub',
          token: 'token',
        );

        expect(result, isA<WalletProvisionStubError>());
        expect(nativeCallCount, 0);
      },
    );

    test('busy error yields WalletProvisionBusy', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addPass') {
          throw PlatformException(
            code: 'busy',
            message: 'Pass addition already in progress',
          );
        }
        return null;
      });

      final bridge = PlatformNativeWalletBridge();
      final result = await bridge.addApplePass(signedZipBytes);

      expect(result, isA<WalletProvisionBusy>());
      expect(result, isNot(isA<WalletProvisionFailure>()));
      final busy = result as WalletProvisionBusy;
      expect(busy.message, 'Pass addition already in progress');
    });

    test('iOS method channel timeout yields WalletProvisionFailure', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final completer = Completer<dynamic>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addPass') {
          return completer.future;
        }
        return null;
      });

      final bridge = PlatformNativeWalletBridge(
        timeoutDuration: const Duration(milliseconds: 50),
      );
      final result = await bridge.addApplePass(signedZipBytes);

      expect(result, isA<WalletProvisionFailure>());
      final failure = result as WalletProvisionFailure;
      expect(
        failure.message,
        'Pass provisioning timed out waiting for the wallet.',
      );

      completer.complete(true);
    });

    test(
      'iOS method channel late platform error after timeout is ignored',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final completer = Completer<dynamic>();
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'addPass') {
            return completer.future;
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge(
          timeoutDuration: const Duration(milliseconds: 50),
        );
        final result = await bridge.addApplePass(signedZipBytes);

        expect(result, isA<WalletProvisionFailure>());

        completer.completeError(
          PlatformException(code: 'error', message: 'late error'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      },
    );
  });

  group('PlatformNativeWalletBridge Android Google Wallet tests', () {
    const googleChannel = MethodChannel('com.droidsonroids/loyalty_pass');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(googleChannel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    test(
      'Google Wallet unavailable returns WalletProvisionUnavailable',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        messenger.setMockMethodCallHandler(googleChannel, (call) async {
          if (call.method == 'isGoogleWalletApiAvailable') {
            return false;
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge();
        final result = await bridge.addGooglePass('test-jwt');

        expect(result, isA<WalletProvisionUnavailable>());
        final unavailable = result as WalletProvisionUnavailable;
        expect(
          unavailable.message,
          'Google Wallet is not available on this device',
        );
      },
    );

    test(
      'Google Wallet success callback returns WalletProvisionSuccess',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        messenger.setMockMethodCallHandler(googleChannel, (call) async {
          if (call.method == 'isGoogleWalletApiAvailable') {
            return true;
          }
          if (call.method == 'saveLoyaltyPass') {
            final byteData = googleChannel.codec.encodeMethodCall(
              const MethodCall('onSuccess'),
            );
            messenger.handlePlatformMessage(
              googleChannel.name,
              byteData,
              (_) {},
            );
            return null;
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge();
        final result = await bridge.addGooglePass('test-jwt');

        expect(result, isA<WalletProvisionSuccess>());
      },
    );

    test(
      'Google Wallet cancel callback returns WalletProvisionCancelled',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        messenger.setMockMethodCallHandler(googleChannel, (call) async {
          if (call.method == 'isGoogleWalletApiAvailable') {
            return true;
          }
          if (call.method == 'saveLoyaltyPass') {
            final byteData = googleChannel.codec.encodeMethodCall(
              const MethodCall('onCanceled'),
            );
            messenger.handlePlatformMessage(
              googleChannel.name,
              byteData,
              (_) {},
            );
            return null;
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge();
        final result = await bridge.addGooglePass('test-jwt');

        expect(result, isA<WalletProvisionCancelled>());
      },
    );

    test(
      'Google Wallet error callback returns WalletProvisionFailure',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        messenger.setMockMethodCallHandler(googleChannel, (call) async {
          if (call.method == 'isGoogleWalletApiAvailable') {
            return true;
          }
          if (call.method == 'saveLoyaltyPass') {
            final byteData = googleChannel.codec.encodeMethodCall(
              const MethodCall('onError', {
                'message': 'Google Pay connection lost',
              }),
            );
            messenger.handlePlatformMessage(
              googleChannel.name,
              byteData,
              (_) {},
            );
            return null;
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge();
        final result = await bridge.addGooglePass('test-jwt');

        expect(result, isA<WalletProvisionFailure>());
        final failure = result as WalletProvisionFailure;
        expect(failure.message, contains('Google Pay connection lost'));
      },
    );

    test(
      'GoogleWalletProvisioner never calls Google channel for stub passes',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        int nativeCallCount = 0;
        messenger.setMockMethodCallHandler(googleChannel, (call) async {
          nativeCallCount++;
          return true;
        });

        final noneAlgJwt =
            '${base64Url.encode(utf8.encode('{"alg":"none"}'))}.${base64Url.encode(utf8.encode('{}'))}.';
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'jwt': noneAlgJwt,
              'saveUrl': 'https://pay.google.com/save',
              'stub': true,
            }),
            200,
            headers: {
              'content-type': 'application/json',
              'x-pass-stub': 'true',
            },
          );
        });

        final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
        final bridge = PlatformNativeWalletBridge();
        final provisioner = GoogleWalletProvisioner(
          apiClient: apiClient,
          bridge: bridge,
        );

        final result = await provisioner.provision(
          documentId: 'doc-stub',
          token: 'token',
        );

        expect(result, isA<WalletProvisionStubError>());
        expect(nativeCallCount, 0);
      },
    );

    test(
      'Google Wallet busy PlatformException returns WalletProvisionBusy',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        messenger.setMockMethodCallHandler(googleChannel, (call) async {
          if (call.method == 'isGoogleWalletApiAvailable') {
            return true;
          }
          if (call.method == 'saveLoyaltyPass') {
            throw PlatformException(
              code: 'busy',
              message: 'Pass addition already in progress',
            );
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge();
        final result = await bridge.addGooglePass('test-jwt');

        expect(result, isA<WalletProvisionBusy>());
        expect(result, isNot(isA<WalletProvisionFailure>()));
        final busy = result as WalletProvisionBusy;
        expect(busy.message, 'Pass addition already in progress');
      },
    );

    test(
      'Google Wallet timeout yields WalletProvisionFailure and ignores late callbacks',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        messenger.setMockMethodCallHandler(googleChannel, (call) async {
          if (call.method == 'isGoogleWalletApiAvailable') {
            return true;
          }
          return null;
        });

        final bridge = PlatformNativeWalletBridge(
          timeoutDuration: const Duration(milliseconds: 50),
        );
        final result = await bridge.addGooglePass('test-jwt');

        expect(result, isA<WalletProvisionFailure>());
        final failure = result as WalletProvisionFailure;
        expect(
          failure.message,
          'Pass provisioning timed out waiting for the wallet.',
        );

        final byteData = googleChannel.codec.encodeMethodCall(
          const MethodCall('onSuccess'),
        );
        messenger.handlePlatformMessage(googleChannel.name, byteData, (_) {});
      },
    );
  });
}
