// lib\services\crypto_isolate.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

// ---------------- Data classes ----------------
class HashArgs {
  final String value;
  final int iters;
  HashArgs(this.value, this.iters);
}

class VerifyArgs {
  final String candidate;
  final String hashB64;
  final String saltB64;
  final int iters;
  VerifyArgs(this.candidate, this.hashB64, this.saltB64, this.iters);
}

// ---------------- Crypto helpers ----------------
List<int> _randBytes(int n) =>
    List<int>.generate(n, (_) => Random.secure().nextInt(256));

List<int> _pbkdf2(String input, List<int> salt,
    {required int iters, int length = 32}) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iters, length));
  return derivator.process(Uint8List.fromList(utf8.encode(input)));
}

// ---------------- Workers ----------------
Map<String, dynamic> hashWorker(HashArgs args) {
  final salt = _randBytes(16);
  final hash = _pbkdf2(args.value.trim().toLowerCase(), salt, iters: args.iters);
  return {
    'hashB64': base64Encode(hash),
    'saltB64': base64Encode(salt),
    'iters': args.iters,
  };
}

bool verifyWorker(VerifyArgs a) {
  final salt = base64Decode(a.saltB64);
  final expected = base64Decode(a.hashB64);
  final hash = _pbkdf2(a.candidate.trim().toLowerCase(), salt, iters: a.iters);
  return const ListEquality<int>().equals(hash, expected);
}
