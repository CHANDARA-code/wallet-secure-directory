import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'crypto_exceptions.dart';

class ParsedEnvelope {
  final int version;
  final Uint8List iv;
  final Uint8List tag;
  final Uint8List ciphertext;

  const ParsedEnvelope({
    required this.version,
    required this.iv,
    required this.tag,
    required this.ciphertext,
  });
}

class CryptoService {
  static const int currentVersion = 2;
  static const int keyLength = 32;
  static const int ivLength = 12;
  static const int tagLength = 16;
  static const int minEnvelopeLength = 1 + ivLength + tagLength;

  final Random _random;

  CryptoService({Random? random}) : _random = random ?? Random.secure();

  Uint8List generateKey() {
    final bytes = Uint8List(keyLength);
    for (var i = 0; i < keyLength; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  Uint8List generateIv() {
    final bytes = Uint8List(ivLength);
    for (var i = 0; i < ivLength; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  ParsedEnvelope parseEnvelope(Uint8List envelopeBytes) {
    if (envelopeBytes.length < minEnvelopeLength) {
      throw const TruncatedEnvelopeException();
    }

    final version = envelopeBytes[0];
    if (version != currentVersion) {
      throw InvalidEnvelopeVersionException(version);
    }

    final iv = envelopeBytes.sublist(1, 1 + ivLength);
    final tag = envelopeBytes.sublist(1 + ivLength, 1 + ivLength + tagLength);
    final ciphertext = envelopeBytes.sublist(1 + ivLength + tagLength);

    return ParsedEnvelope(
      version: version,
      iv: iv,
      tag: tag,
      ciphertext: ciphertext,
    );
  }

  Uint8List encrypt({
    required Uint8List plaintext,
    required Uint8List key,
    required String documentId,
    Uint8List? explicitIv,
  }) {
    if (key.length != keyLength) {
      throw ArgumentError('Key must be $keyLength bytes.');
    }

    final ivBytes = explicitIv ?? generateIv();
    if (ivBytes.length != ivLength) {
      throw ArgumentError('IV must be $ivLength bytes.');
    }

    final encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));
    final associatedData = Uint8List.fromList(
      utf8.encode('wallet-doc:v2:$documentId'),
    );
    final encrypted = encrypter.encryptBytes(
      plaintext,
      iv: IV(ivBytes),
      associatedData: associatedData,
    );

    final combined = encrypted.bytes;
    final ciphertextLength = combined.length - tagLength;
    final ciphertext = combined.sublist(0, ciphertextLength);
    final tag = combined.sublist(ciphertextLength);

    final envelope = Uint8List(minEnvelopeLength + ciphertext.length);
    envelope[0] = currentVersion;
    envelope.setRange(1, 1 + ivLength, ivBytes);
    envelope.setRange(1 + ivLength, 1 + ivLength + tagLength, tag);
    envelope.setRange(minEnvelopeLength, envelope.length, ciphertext);

    return envelope;
  }

  Uint8List decrypt({
    required Uint8List envelopeBytes,
    required Uint8List key,
    required String documentId,
  }) {
    if (key.length != keyLength) {
      throw ArgumentError('Key must be $keyLength bytes.');
    }

    final parsed = parseEnvelope(envelopeBytes);

    final combined = Uint8List(parsed.ciphertext.length + parsed.tag.length);
    combined.setRange(0, parsed.ciphertext.length, parsed.ciphertext);
    combined.setRange(parsed.ciphertext.length, combined.length, parsed.tag);

    try {
      final encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));
      final associatedData = Uint8List.fromList(
        utf8.encode('wallet-doc:v2:$documentId'),
      );
      final decrypted = encrypter.decryptBytes(
        Encrypted(combined),
        iv: IV(parsed.iv),
        associatedData: associatedData,
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      if (e is InvalidEnvelopeVersionException ||
          e is TruncatedEnvelopeException) {
        rethrow;
      }
      throw const CryptoAuthenticationException();
    }
  }
}
