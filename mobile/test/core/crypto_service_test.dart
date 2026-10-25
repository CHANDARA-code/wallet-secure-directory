import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_app/core/crypto/crypto_exceptions.dart';
import 'package:wallet_app/core/crypto/crypto_service.dart';

void main() {
  late CryptoService crypto;
  late Uint8List key;

  setUp(() {
    crypto = CryptoService();
    key = crypto.generateKey();
  });

  test('key is 32 bytes and iv is 12 bytes', () {
    expect(key.length, 32);
    final iv = crypto.generateIv();
    expect(iv.length, 12);
  });

  test('encrypt and decrypt round trip succeeds', () {
    final plaintext = Uint8List.fromList(utf8.encode('Top Secret Document'));
    final envelope = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-1',
    );
    final decrypted = crypto.decrypt(
      envelopeBytes: envelope,
      key: key,
      documentId: 'doc-1',
    );

    expect(utf8.decode(decrypted), 'Top Secret Document');
  });

  test('decrypting with different documentId fails authentication', () {
    final plaintext = Uint8List.fromList(utf8.encode('Sensitive Data'));
    final envelope = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-A',
    );

    expect(
      () => crypto.decrypt(
        envelopeBytes: envelope,
        key: key,
        documentId: 'doc-B',
      ),
      throwsA(isA<CryptoAuthenticationException>()),
    );
  });

  test(
    'copying doc_B over doc_A then unlocking A fails with authentication error',
    () {
      final plainA = Uint8List.fromList(utf8.encode('Doc A Data'));
      final plainB = Uint8List.fromList(utf8.encode('Doc B Data'));

      crypto.encrypt(plaintext: plainA, key: key, documentId: 'doc-A');
      final envelopeB = crypto.encrypt(
        plaintext: plainB,
        key: key,
        documentId: 'doc-B',
      );

      expect(
        () => crypto.decrypt(
          envelopeBytes: envelopeB,
          key: key,
          documentId: 'doc-A',
        ),
        throwsA(isA<CryptoAuthenticationException>()),
      );
    },
  );

  test('same plaintext twice produces different IV and ciphertext', () {
    final plaintext = Uint8List.fromList(utf8.encode('Identical Content'));
    final envelope1 = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-1',
    );
    final envelope2 = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-1',
    );

    expect(envelope1, isNot(equals(envelope2)));

    final parsed1 = crypto.parseEnvelope(envelope1);
    final parsed2 = crypto.parseEnvelope(envelope2);

    expect(parsed1.iv, isNot(equals(parsed2.iv)));
    expect(parsed1.ciphertext, isNot(equals(parsed2.ciphertext)));
  });

  test('flipping one ciphertext byte fails authentication', () {
    final plaintext = Uint8List.fromList(utf8.encode('Uncompromised Data'));
    final envelope = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-1',
    );

    final tampered = Uint8List.fromList(envelope);
    final lastByteIndex = tampered.length - 1;
    tampered[lastByteIndex] ^= 0x01;

    expect(
      () => crypto.decrypt(
        envelopeBytes: tampered,
        key: key,
        documentId: 'doc-1',
      ),
      throwsA(isA<CryptoAuthenticationException>()),
    );
  });

  test('flipping one tag byte fails authentication', () {
    final plaintext = Uint8List.fromList(utf8.encode('Protected Header'));
    final envelope = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-1',
    );

    final tampered = Uint8List.fromList(envelope);
    tampered[13] ^= 0x01;

    expect(
      () => crypto.decrypt(
        envelopeBytes: tampered,
        key: key,
        documentId: 'doc-1',
      ),
      throwsA(isA<CryptoAuthenticationException>()),
    );
  });

  test('wrong key fails decryption with CryptoAuthenticationException', () {
    final plaintext = Uint8List.fromList(utf8.encode('Sensitive payload'));
    final envelope = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-1',
    );
    final wrongKey = crypto.generateKey();

    expect(
      () => crypto.decrypt(
        envelopeBytes: envelope,
        key: wrongKey,
        documentId: 'doc-1',
      ),
      throwsA(isA<CryptoAuthenticationException>()),
    );
  });

  test('envelope parser validates envelope structure', () {
    final plaintext = Uint8List.fromList(utf8.encode('Test Envelope'));
    final envelope = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-1',
    );

    final parsed = crypto.parseEnvelope(envelope);
    expect(parsed.version, 2);
    expect(parsed.iv.length, 12);
    expect(parsed.tag.length, 16);
    expect(parsed.ciphertext.length, plaintext.length);
  });

  test('v1 envelope is rejected with InvalidEnvelopeVersionException', () {
    final plaintext = Uint8List.fromList(utf8.encode('V1 Payload'));
    final envelope = crypto.encrypt(
      plaintext: plaintext,
      key: key,
      documentId: 'doc-1',
    );
    final v1Envelope = Uint8List.fromList(envelope);
    v1Envelope[0] = 1;

    expect(
      () => crypto.parseEnvelope(v1Envelope),
      throwsA(
        isA<InvalidEnvelopeVersionException>().having(
          (e) => e.version,
          'version',
          1,
        ),
      ),
    );
    expect(
      () => crypto.decrypt(
        envelopeBytes: v1Envelope,
        key: key,
        documentId: 'doc-1',
      ),
      throwsA(isA<InvalidEnvelopeVersionException>()),
    );
  });

  test(
    'envelope parser throws TruncatedEnvelopeException on truncated bytes',
    () {
      final truncated = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(
        () => crypto.parseEnvelope(truncated),
        throwsA(isA<TruncatedEnvelopeException>()),
      );
    },
  );

  test(
    'envelope parser throws InvalidEnvelopeVersionException on unknown version',
    () {
      final plaintext = Uint8List.fromList(utf8.encode('Future Version'));
      final envelope = crypto.encrypt(
        plaintext: plaintext,
        key: key,
        documentId: 'doc-1',
      );
      final invalidVersionBytes = Uint8List.fromList(envelope);
      invalidVersionBytes[0] = 99;

      expect(
        () => crypto.parseEnvelope(invalidVersionBytes),
        throwsA(isA<InvalidEnvelopeVersionException>()),
      );
    },
  );
}
