import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricStatus {
  success,
  notEnrolled,
  lockedOut,
  unsupported,
  canceled,
  failure,
  keyInvalidated,
}

class BiometricAuthResult {
  final BiometricStatus status;
  final String message;

  const BiometricAuthResult({required this.status, required this.message});

  bool get isSuccess => status == BiometricStatus.success;
}

abstract interface class BiometricAuthService {
  Future<BiometricAuthResult> authenticate();
}

class LocalAuthBiometricService implements BiometricAuthService {
  final LocalAuthentication _localAuth;

  LocalAuthBiometricService({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  @override
  Future<BiometricAuthResult> authenticate() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!isSupported || !canCheck) {
        return const BiometricAuthResult(
          status: BiometricStatus.unsupported,
          message: 'Biometrics are not supported or available on this device.',
        );
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate with biometrics to unlock your document',
        biometricOnly: true,
      );

      if (authenticated) {
        return const BiometricAuthResult(
          status: BiometricStatus.success,
          message: 'Biometric authentication succeeded.',
        );
      } else {
        return const BiometricAuthResult(
          status: BiometricStatus.canceled,
          message: 'Biometric authentication was canceled.',
        );
      }
    } on PlatformException catch (e) {
      if (e.code == 'NotEnrolled') {
        return const BiometricAuthResult(
          status: BiometricStatus.notEnrolled,
          message:
              'No biometrics enrolled. Please set up fingerprint or Face ID in device settings.',
        );
      }
      if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        return const BiometricAuthResult(
          status: BiometricStatus.lockedOut,
          message:
              'Biometrics locked out due to too many failed attempts. Please try again later.',
        );
      }
      if (e.code == 'NotAvailable') {
        return const BiometricAuthResult(
          status: BiometricStatus.unsupported,
          message: 'Biometrics are not supported or available on this device.',
        );
      }
      return BiometricAuthResult(
        status: BiometricStatus.failure,
        message: 'Biometric authentication failed: ${e.message ?? e.code}',
      );
    } catch (_) {
      return const BiometricAuthResult(
        status: BiometricStatus.failure,
        message: 'Biometric authentication failed.',
      );
    }
  }
}

final biometricAuthServiceProvider = Provider<BiometricAuthService>((ref) {
  return LocalAuthBiometricService();
});
