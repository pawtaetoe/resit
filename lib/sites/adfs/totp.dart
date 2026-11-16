import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Time-based one-time password settings (RFC 6238), as found in the
/// `otpauth://totp/...` link behind an authenticator setup QR code.
class TotpConfig {
  /// Secret key in base32, upper case, no padding or spaces.
  final String secret;
  final int digits;
  final int period; // seconds
  final String algorithm; // SHA1, SHA256 or SHA512
  final String? issuer;
  final String? account;

  final Uint8List _key;

  TotpConfig._(this.secret, this._key,
      {this.digits = 6, this.period = 30, this.algorithm = 'SHA1', this.issuer, this.account});

  /// Reads either a full `otpauth://totp/...` link or just the secret key
  /// (spaces and lower case allowed). Throws [FormatException] with a
  /// message that can be shown to the user.
  factory TotpConfig.parse(String input) {
    final text = input.trim();
    if (text.isEmpty) throw const FormatException('Paste the setup link or the secret key.');

    if (!text.toLowerCase().startsWith('otpauth://')) {
      return TotpConfig._fromParts(text);
    }

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } catch (_) {
      throw const FormatException("That link isn't a valid otpauth:// link.");
    }
    if (uri.host.toLowerCase() != 'totp') {
      throw const FormatException('Only time-based (TOTP) codes are supported, not counter-based (HOTP).');
    }
    final q = uri.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));
    final secret = q['secret'];
    if (secret == null || secret.isEmpty) {
      throw const FormatException('The link has no secret in it.');
    }

    // The label is "Issuer:account" or just "account".
    final label = Uri.decodeComponent(uri.path.replaceFirst('/', ''));
    final colon = label.indexOf(':');
    final labelIssuer = colon > 0 ? label.substring(0, colon).trim() : null;
    final account = (colon > 0 ? label.substring(colon + 1) : label).trim();

    return TotpConfig._fromParts(
      secret,
      digits: int.tryParse(q['digits'] ?? '') ?? 6,
      period: int.tryParse(q['period'] ?? '') ?? 30,
      algorithm: (q['algorithm'] ?? 'SHA1').toUpperCase(),
      issuer: q['issuer'] ?? labelIssuer,
      account: account.isEmpty ? null : account,
    );
  }

  factory TotpConfig._fromParts(String rawSecret,
      {int digits = 6, int period = 30, String algorithm = 'SHA1', String? issuer, String? account}) {
    final secret = rawSecret.replaceAll(RegExp(r'[\s-]'), '').replaceAll('=', '').toUpperCase();
    if (!RegExp(r'^[A-Z2-7]+$').hasMatch(secret)) {
      throw const FormatException('The secret key should only contain letters A–Z and digits 2–7.');
    }
    final key = base32Decode(secret);
    if (key.length < 10) throw const FormatException('That secret key is too short.');
    if (digits < 6 || digits > 8) throw const FormatException('Codes must be 6 to 8 digits long.');
    if (period < 15 || period > 120) throw const FormatException('Unsupported code period.');
    if (!const {'SHA1', 'SHA256', 'SHA512'}.contains(algorithm)) {
      throw FormatException('Unsupported algorithm $algorithm.');
    }
    return TotpConfig._(secret, key,
        digits: digits, period: period, algorithm: algorithm, issuer: issuer, account: account);
  }

  /// The code valid at [time].
  String codeAt(DateTime time) {
    final counter = time.millisecondsSinceEpoch ~/ 1000 ~/ period;
    // Big-endian 64-bit counter, written as two 32-bit halves because the
    // web build doesn't support 64-bit accessors.
    final msg = ByteData(8)
      ..setUint32(0, counter ~/ 0x100000000)
      ..setUint32(4, counter % 0x100000000);
    final hash = Hmac(_hash, _key).convert(msg.buffer.asUint8List()).bytes;
    final offset = hash.last & 0x0f;
    final binary =
        ((hash[offset] & 0x7f) << 24) | (hash[offset + 1] << 16) | (hash[offset + 2] << 8) | hash[offset + 3];
    var mod = 1;
    for (var i = 0; i < digits; i++) {
      mod *= 10;
    }
    return (binary % mod).toString().padLeft(digits, '0');
  }

  /// Seconds until the code at [time] changes.
  int secondsLeft(DateTime time) => period - (time.millisecondsSinceEpoch ~/ 1000) % period;

  Hash get _hash => switch (algorithm) {
        'SHA256' => sha256,
        'SHA512' => sha512,
        _ => sha1,
      };

  /// Canonical link, used for storage.
  String toUri() => Uri(
        scheme: 'otpauth',
        host: 'totp',
        path: '/${Uri.encodeComponent([if (issuer != null) issuer!, account ?? 'reSIT'].join(':'))}',
        queryParameters: {
          'secret': secret,
          if (issuer != null) 'issuer': issuer!,
          'algorithm': algorithm,
          'digits': '$digits',
          'period': '$period',
        },
      ).toString();
}

Uint8List base32Decode(String input) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in input.split('')) {
    final v = alphabet.indexOf(ch);
    if (v < 0) throw FormatException('Invalid base32 character "$ch".');
    buffer = (buffer << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xff);
    }
  }
  return Uint8List.fromList(out);
}
