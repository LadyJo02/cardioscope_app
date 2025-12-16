// 📁 lib/services/auth_backup_service.dart
//
// ✅ Production-safe PBKDF2 via isolates (see crypto_isolate.dart)
// ✅ No duplicate function names
// ✅ Atomic JSON write for auth backup
//

import 'dart:convert';
import 'dart:io';
import 'dart:math';

// Use the pure-Dart isolate workers
import 'package:cardioscope_app/services/crypto_isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Hashed secret structure used by the app (PIN / security answer)
class HashedSecret {
  final String hashB64;
  final String saltB64;
  final int iters;
  HashedSecret(this.hashB64, this.saltB64, this.iters);

  Map<String, dynamic> toJson() => {
        'hash': hashB64,
        'salt': saltB64,
        'iters': iters,
      };
}

/// Hash a secret using an isolate (non-blocking on UI)
Future<HashedSecret> hashSecret(String value, {int iters = 50000}) async {
  final map = await compute(hashWorker, HashArgs(value, iters));
  return HashedSecret(
    map['hashB64'] as String,
    map['saltB64'] as String,
    map['iters'] as int,
  );
}

/// Verify secret using isolate worker
Future<bool> verifySecret(
  String candidate,
  String hashB64,
  String saltB64,
  int iters,
) {
  return compute(
    verifyWorker,
    VerifyArgs(candidate, hashB64, saltB64, iters > 0 ? iters : 50000),
  );
}

// --------------------------------------------------
// 🔐 Auth Backup JSON (for reinstall recovery)
// --------------------------------------------------

class AuthBackupService {
  /// Save hashed Q&A to practitioner folder (no plaintext)
  static Future<void> saveAuthBackup({
    required String practitionerFolderPath,
    required String emailCanonical,
    required String question,
    required HashedSecret answer,
  }) async {
    final dir = Directory(practitionerFolderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final target = File(p.join(practitionerFolderPath, 'auth_backup.json'));
    final tmp = File(p.join(
      practitionerFolderPath,
      '.auth_backup.tmp.${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32)}',
    ));

    final data = {
      'schema': 1,
      'email_canonical': emailCanonical,
      'security_question': question,
      'answer_hash': answer.hashB64,
      'answer_salt': answer.saltB64,
      'answer_iters': answer.iters,
      'written_at': DateTime.now().toIso8601String(),
    };

    const encoder = kDebugMode ? JsonEncoder.withIndent('  ') : JsonEncoder();

    try {
      await tmp.writeAsString(encoder.convert(data), flush: true);
      try {
        await tmp.rename(target.path); // atomic when possible
      } on FileSystemException {
        await tmp.copy(target.path);
        await tmp.delete();
      }
    } catch (e) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      debugPrint("❌ auth backup write failed: $e");
    }
  }

  /// Load auth backup (if exists)
  static Future<Map<String, dynamic>?> readAuthBackup(
      String practitionerFolderPath) async {
    final file = File(p.join(practitionerFolderPath, 'auth_backup.json'));
    if (!await file.exists()) return null;

    try {
      final s = await file.readAsString();
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (e) {
      debugPrint("⚠️ Could not read auth_backup.json: $e");
      return null;
    }
  }
}
