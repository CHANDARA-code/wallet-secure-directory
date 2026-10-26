import 'dart:async';
import 'dart:convert';
import 'package:add_to_google_wallet/add_to_google_wallet.dart';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';

sealed class WalletProvisionResult {
  const WalletProvisionResult();
}

class WalletProvisionSuccess extends WalletProvisionResult {
  const WalletProvisionSuccess();
}

class WalletProvisionStubError extends WalletProvisionResult {
  final String message;
  const WalletProvisionStubError([
    this.message = 'Pass provisioning requires a signed pass from the issuer',
  ]);
}

class WalletProvisionFailure extends WalletProvisionResult {
  final String message;
  const WalletProvisionFailure(this.message);
}

class WalletProvisionCancelled extends WalletProvisionResult {
  final String message;
  const WalletProvisionCancelled([
    this.message = 'Pass provisioning was cancelled',
  ]);
}

class WalletProvisionBusy extends WalletProvisionResult {
  final String message;
  const WalletProvisionBusy([
    this.message = 'Pass provisioning is already in progress',
  ]);
}

class WalletProvisionUnavailable extends WalletProvisionResult {
  final String message;
  const WalletProvisionUnavailable([
    this.message = 'Native wallet provisioning is not available in this build',
  ]);
}

abstract interface class NativeWalletBridge {
  bool get isAvailable;
  Future<WalletProvisionResult> addApplePass(Uint8List passBytes);
  Future<WalletProvisionResult> addGooglePass(String jwt);
}

class UnavailableNativeWalletBridge implements NativeWalletBridge {
  final String message;
  const UnavailableNativeWalletBridge([
    this.message = 'Native wallet provisioning is not available in this build',
  ]);

  @override
  bool get isAvailable => false;

  @override
  Future<WalletProvisionResult> addApplePass(Uint8List passBytes) async {
    return WalletProvisionUnavailable(message);
  }

  @override
  Future<WalletProvisionResult> addGooglePass(String jwt) async {
    return WalletProvisionUnavailable(message);
  }
}

class PlatformNativeWalletBridge implements NativeWalletBridge {
  static const String appleChannelName = 'com.example.wallet_app/wallet';
  static const Duration defaultTimeout = Duration(minutes: 5);
  static const Object _timeoutSentinel = Object();

  final MethodChannel _appleChannel;
  final AddToGoogleWallet _googleWallet;
  final Duration timeoutDuration;

  PlatformNativeWalletBridge({
    MethodChannel? appleChannel,
    AddToGoogleWallet? googleWallet,
    Duration? timeoutDuration,
  }) : _appleChannel = appleChannel ?? const MethodChannel(appleChannelName),
       _googleWallet = googleWallet ?? AddToGoogleWallet(),
       timeoutDuration = timeoutDuration ?? defaultTimeout;

  @override
  bool get isAvailable {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  @override
  Future<WalletProvisionResult> addApplePass(Uint8List passBytes) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const WalletProvisionUnavailable();
    }
    try {
      final methodFuture = _appleChannel.invokeMethod<dynamic>(
        'addPass',
        passBytes,
      );
      final dynamic result = await methodFuture
          .timeout(timeoutDuration, onTimeout: () => _timeoutSentinel)
          .whenComplete(() {
            methodFuture.ignore();
          });
      if (identical(result, _timeoutSentinel)) {
        return const WalletProvisionFailure(
          'Pass provisioning timed out waiting for the wallet.',
        );
      }
      if (result == true || result == 'confirmed') {
        return const WalletProvisionSuccess();
      } else if (result == false || result == 'cancelled') {
        return const WalletProvisionCancelled();
      } else {
        return const WalletProvisionFailure(
          'Pass addition could not be confirmed.',
        );
      }
    } on PlatformException catch (e) {
      if (e.code == 'busy') {
        return WalletProvisionBusy(
          e.message ?? 'Pass provisioning is already in progress',
        );
      } else if (e.code == 'invalid_pass') {
        return WalletProvisionFailure(
          'Invalid pass bundle: ${e.message ?? e.code}',
        );
      } else if (e.code == 'unavailable') {
        return WalletProvisionUnavailable(
          e.message ?? 'PassKit cannot add passes on this device',
        );
      }
      return WalletProvisionFailure(
        e.message ?? 'Failed to add pass to Apple Wallet.',
      );
    } catch (e) {
      return WalletProvisionFailure('Failed to add pass to Apple Wallet: $e');
    }
  }

  @override
  Future<WalletProvisionResult> addGooglePass(String jwt) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const WalletProvisionUnavailable();
    }
    try {
      final isAvailable = await _googleWallet.isGoogleWalletApiAvailable;
      if (!isAvailable) {
        return const WalletProvisionUnavailable(
          'Google Wallet is not available on this device',
        );
      }
      final completer = Completer<WalletProvisionResult>();
      await _googleWallet.saveLoyaltyPass(
        pass: jwt,
        onSuccess: () {
          if (!completer.isCompleted) {
            completer.complete(const WalletProvisionSuccess());
          }
        },
        onCanceled: () {
          if (!completer.isCompleted) {
            completer.complete(const WalletProvisionCancelled());
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.complete(
              WalletProvisionFailure('Google Wallet error: $error'),
            );
          }
        },
      );
      final result = await completer.future
          .timeout(
            timeoutDuration,
            onTimeout: () {
              if (!completer.isCompleted) {
                completer.complete(
                  const WalletProvisionFailure(
                    'Pass provisioning timed out waiting for the wallet.',
                  ),
                );
              }
              return const WalletProvisionFailure(
                'Pass provisioning timed out waiting for the wallet.',
              );
            },
          )
          .whenComplete(() {
            completer.future.ignore();
          });
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'busy') {
        return WalletProvisionBusy(
          e.message ?? 'Pass provisioning is already in progress',
        );
      }
      return WalletProvisionFailure(
        e.message ?? 'Failed to add pass to Google Wallet.',
      );
    } catch (e) {
      return WalletProvisionFailure('Failed to add pass to Google Wallet: $e');
    }
  }
}

abstract interface class WalletProvisioner {
  Future<WalletProvisionResult> provision({
    required String documentId,
    required String token,
  });
}

bool _isJwtAlgNone(String jwt) {
  try {
    final parts = jwt.split('.');
    if (parts.isEmpty || parts[0].isEmpty) return true;
    final normalized = base64Url.normalize(parts[0]);
    final headerJson = utf8.decode(base64Url.decode(normalized));
    final header = jsonDecode(headerJson);
    if (header is Map<String, dynamic>) {
      final alg = header['alg'];
      return alg == null || alg.toString().toLowerCase() == 'none';
    }
    return true;
  } catch (_) {
    return true;
  }
}

bool _isApplePassStub(ApplePassResponse response) {
  if (response.isStub) return true;
  try {
    final archive = ZipDecoder().decodeBytes(response.bytes);
    final hasSignature = archive.files.any((file) => file.name == 'signature');
    return !hasSignature;
  } catch (_) {
    return true;
  }
}

class GoogleWalletProvisioner implements WalletProvisioner {
  final ApiClient _apiClient;
  final NativeWalletBridge _bridge;

  GoogleWalletProvisioner({
    required ApiClient apiClient,
    NativeWalletBridge? bridge,
  }) : _apiClient = apiClient,
       _bridge = bridge ?? const UnavailableNativeWalletBridge();

  @override
  Future<WalletProvisionResult> provision({
    required String documentId,
    required String token,
  }) async {
    try {
      final response = await _apiClient.getGooglePass(token, documentId);
      if (response.isStub || _isJwtAlgNone(response.jwt)) {
        return const WalletProvisionStubError();
      }
      if (!_bridge.isAvailable) {
        return const WalletProvisionUnavailable();
      }
      return await _bridge.addGooglePass(response.jwt);
    } on ApiException catch (e) {
      return WalletProvisionFailure(e.message);
    } catch (_) {
      return const WalletProvisionFailure(
        'Failed to provision Google Wallet pass.',
      );
    }
  }
}

class AppleWalletProvisioner implements WalletProvisioner {
  final ApiClient _apiClient;
  final NativeWalletBridge _bridge;

  AppleWalletProvisioner({
    required ApiClient apiClient,
    NativeWalletBridge? bridge,
  }) : _apiClient = apiClient,
       _bridge = bridge ?? const UnavailableNativeWalletBridge();

  @override
  Future<WalletProvisionResult> provision({
    required String documentId,
    required String token,
  }) async {
    try {
      final response = await _apiClient.getApplePass(token, documentId);
      if (_isApplePassStub(response)) {
        return const WalletProvisionStubError();
      }
      if (!_bridge.isAvailable) {
        return const WalletProvisionUnavailable();
      }
      return await _bridge.addApplePass(response.bytes);
    } on ApiException catch (e) {
      return WalletProvisionFailure(e.message);
    } catch (_) {
      return const WalletProvisionFailure(
        'Failed to provision Apple Wallet pass.',
      );
    }
  }
}

final nativeWalletBridgeProvider = Provider<NativeWalletBridge>((ref) {
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android)) {
    return PlatformNativeWalletBridge();
  }
  return const UnavailableNativeWalletBridge();
});

final walletProvisionerProvider = Provider<WalletProvisioner>((ref) {
  final client = ref.watch(apiClientProvider);
  final bridge = ref.watch(nativeWalletBridgeProvider);
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return GoogleWalletProvisioner(apiClient: client, bridge: bridge);
  }
  return AppleWalletProvisioner(apiClient: client, bridge: bridge);
});
