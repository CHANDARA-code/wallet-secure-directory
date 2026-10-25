class CryptoException implements Exception {
  final String message;
  const CryptoException(this.message);

  @override
  String toString() => 'CryptoException: $message';
}

class CryptoAuthenticationException extends CryptoException {
  const CryptoAuthenticationException([
    super.message =
        'GCM authentication failed: tampered ciphertext or wrong key',
  ]);
}

class TruncatedEnvelopeException extends CryptoException {
  const TruncatedEnvelopeException([
    super.message = 'Envelope is truncated: insufficient byte length',
  ]);
}

class InvalidEnvelopeVersionException extends CryptoException {
  final int version;
  const InvalidEnvelopeVersionException(this.version, [String? message])
    : super(message ?? 'Unsupported envelope version: $version');
}
