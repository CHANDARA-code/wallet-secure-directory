import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
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

class WalletProvisionUnavailable extends WalletProvisionResult {
  final String message;
  const WalletProvisionUnavailable([
    this.message = 'Native wallet provisioning is not available in this build',
  ]);
}

abstract interface class NativeWalletBridge {
  bool get isAvailable;
  Future<bool> addApplePass(Uint8List passBytes);
  Future<bool> addGooglePass(String jwt);
}

class UnavailableNativeWalletBridge implements NativeWalletBridge {
  final String message;
  const UnavailableNativeWalletBridge([
    this.message = 'Native wallet provisioning is not available in this build',
  ]);

  @override
  bool get isAvailable => false;

  @override
  Future<bool> addApplePass(Uint8List passBytes) async {
    return false;
  }

  @override
  Future<bool> addGooglePass(String jwt) async {
    return false;
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
      final confirmed = await _bridge.addGooglePass(response.jwt);
      if (confirmed) {
        return const WalletProvisionSuccess();
      }
      return const WalletProvisionFailure(
        'Failed to provision Google Wallet pass.',
      );
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
      final confirmed = await _bridge.addApplePass(response.bytes);
      if (confirmed) {
        return const WalletProvisionSuccess();
      }
      return const WalletProvisionFailure(
        'Failed to provision Apple Wallet pass.',
      );
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
