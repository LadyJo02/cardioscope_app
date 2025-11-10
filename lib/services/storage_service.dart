// 📁 lib/services/storage_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cardioscope_app/database_helper.dart';
import 'package:cardioscope_app/services/reanalysis_queue.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';


/// StorageService
/// Phase-2 implementation:
/// - Primary secure storage: app documents dir (internal)
/// - External anonymized backup (survives uninstall): /storage/emulated/0/CardioScopeBackup/
/// - No PII in external backup (IDs + WAV only)
class StorageService {
  // ────────────────────────────────────────────────────────────────────────────
  // Pref keys
  static const _keyStoragePath = 'storagePath_secure'; // internal secure path
  static const _keyPractitionerId = 'practitioner_id';
  static const _keyPractitionerName = 'practitioner_name';
  static const _keyPractitionerEmail = 'practitioner_email';

  // ────────────────────────────────────────────────────────────────────────────
  // Paths

  /// External anonymized backup root (public, survives uninstall)
  Directory get _externalBackupRoot =>
      Directory('/storage/emulated/0/CardioScopeBackup');


  /// Backward-compat downloads root (legacy)
  Directory get _legacyDownloadsRoot =>
      Directory('/storage/emulated/0/Download');

  // Public safe accessor for backup directory
  Directory get externalBackupRoot => _externalBackupRoot;

  /// App-internal secure root (primary)
  Future<Directory> _secureRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'CardioScopeSecure'));
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Canonicalization & utilities (no external deps)

  String _canonicalizeEmail(String input) {
    final raw = input.trim().toLowerCase();
    final parts = raw.split('@');
    if (parts.length != 2) return raw;
    var local = parts[0];
    final domain = parts[1];

    if (domain == 'gmail.com' || domain == 'googlemail.com') {
      local = local.split('+').first.replaceAll('.', '');
    }
    return '$local@$domain';
  }

  /// Very small stable 32-bit FNV-1a hash → 8 hex chars (for folder suffix).
  String _fnv1a8(String text) {
    final t = text.trim();
    if (t.isEmpty) return '00000000'; 
    const int fnvPrime = 0x01000193;
    int hash = 0x811C9DC5;
    for (final code in utf8.encode(text)) {
      hash ^= code;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String sanitizeFileName(String name) => _sanitize(name);

  String _sanitize(String input) =>
      input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), "_");

  /// Practitioner anonymized folder: U{ID}_{hash8}
  String _practitionerFolderName({
    required int practitionerId,
    required String practitionerEmail,
  }) {
    final canon = _canonicalizeEmail(practitionerEmail);
    final h = _fnv1a8(canon);
    return 'U${practitionerId.toString().padLeft(6, '0')}_$h';
  }

  /// Patient code (no PII)
  String formatPatientCode(int patientId) =>
      'CS${patientId.toString().padLeft(7, '0')}';


String emailHash8(String input) => _fnv1a8(_canonicalizeEmail(input));
bool metaMatchesEmailHash(Map<String, dynamic> meta, String emailCanon) {
  final h = meta['email_hash']?.toString() ?? '';
  return h.isNotEmpty && h == _fnv1a8(emailCanon);
}

  // ────────────────────────────────────────────────────────────────────────────
  // Base folders

  /// Ensure internal secure base exists and persist path.
  /// Also prepares external anonymized practitioner folder + meta.json
  Future<String> ensureBaseFolderFor({
    required int practitionerId,
    required String practitionerName, // not written externally
    required String practitionerEmail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPractitionerId, practitionerId);
    await prefs.setString(_keyPractitionerName, practitionerName);
    await prefs.setString(_keyPractitionerEmail, practitionerEmail);

    // 1) Internal secure root
    final secure = await _secureRoot();
    if (!(await secure.exists())) {
      await secure.create(recursive: true);
    }
    await prefs.setString(_keyStoragePath, secure.path);

    // 2) External anonymized root
    final extRoot = _externalBackupRoot;
    if (!(await extRoot.exists())) {
      await extRoot.create(recursive: true);
    }

    // 3) Practitioner folder on external backup
    final practitionerFolderName = _practitionerFolderName(
      practitionerId: practitionerId,
      practitionerEmail: practitionerEmail,
    );
    final extPractitionerDir =
        Directory(p.join(extRoot.path, practitionerFolderName));
    if (!(await extPractitionerDir.exists())) {
      await extPractitionerDir.create(recursive: true);
    }

    // 4) Patients dir (external)
    final extPatients = Directory(p.join(extPractitionerDir.path, 'patients'));
    if (!(await extPatients.exists())) {
      await extPatients.create(recursive: true);
    }

    // 5) Write minimal meta (no PII)
    await _writePractitionerMeta(
      dir: extPractitionerDir,
      practitionerId: practitionerId,
      practitionerEmail: practitionerEmail,
    );

    // 6) Best-effort legacy merge (optional, safe)
    await _mergeLegacyPractitionerIfAny(
      practitionerId: practitionerId,
      practitionerEmail: practitionerEmail,
      secureRoot: secure,
    );

    return secure.path;
  }

  /// Returns existing secure path or creates it from saved prefs.
  Future<String> getOrCreateBaseFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_keyStoragePath);

    if (saved != null && saved.isNotEmpty && await Directory(saved).exists()) {
      return saved;
    }

    final pid = prefs.getInt(_keyPractitionerId) ?? 0;
    final name = prefs.getString(_keyPractitionerName) ?? '';
    final email = prefs.getString(_keyPractitionerEmail) ?? '';

    if (pid == 0 || name.isEmpty) {
      final secure = await _secureRoot();
      return secure.path;
    }

    return ensureBaseFolderFor(
      practitionerId: pid,
      practitionerName: name,
      practitionerEmail: email,
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Practitioner meta (external anonymized)

  Future<void> _writePractitionerMeta({
    required Directory dir,
    required int practitionerId,
    required String practitionerEmail,
  }) async {
    final metaFile = File(p.join(dir.path, 'practitioner.meta.json'));
    final emailHash = _fnv1a8(_canonicalizeEmail(practitionerEmail));
    final meta = {
      'practitioner_id': practitionerId,
      'email_hash': emailHash,
      'schema': 1,
      'note':
          'No PII. For disaster recovery only. App will prompt for PIN/Q&A again.',
    };
    await metaFile.writeAsString(jsonEncode(meta), flush: true);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Patient subfolders (INTERNAL SECURE)

  /// Creates internal secure patient folders.
  /// Returns the internal patient folder absolute path.
  Future<String> createPatientSubfolders(String basePath, int patientId) async {
    final formattedId = formatPatientCode(patientId);
    final patientFolder = Directory(p.join(basePath, 'Patients', formattedId));
    final recordings = Directory(p.join(patientFolder.path, 'Recordings'));
    final reports = Directory(p.join(patientFolder.path, 'Reports'));

    if (!(await recordings.exists())) await recordings.create(recursive: true);
    if (!(await reports.exists())) await reports.create(recursive: true);

    return patientFolder.path;
  }

  /// Internal Reports root (per practitioner)
  Future<String> createReportsFolder(String basePath) async {
    final dir = Directory(p.join(basePath, 'Reports'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Directories for exports (INTERNAL ONLY)

  Future<String> getSinglePdfDir(String basePath, String formattedId) async {
    final dir = Directory("$basePath/Patients/$formattedId/Reports/PDF");
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> getSingleExcelDir(String basePath, String formattedId) async {
    final dir = Directory("$basePath/Patients/$formattedId/Reports/Excel");
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> getBatchPdfDir(String basePath) async {
    final dir = Directory("$basePath/Batch_Report/PDF");
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> getBatchExcelDir(String basePath) async {
    final dir = Directory("$basePath/Batch_Report/Excel");
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Current patient helpers (unchanged)

  Future<String?> getSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoragePath);
  }

  String _keyCurrentPatientIdFor(int practitionerId) =>
      'current_patient_id_$practitionerId';

  Future<void> setCurrentPatient(int patientId) async {
    final prefs = await SharedPreferences.getInstance();
    final pid = prefs.getInt(_keyPractitionerId);
    if (pid != null) {
      await prefs.setInt(_keyCurrentPatientIdFor(pid), patientId);
    }
  }

  Future<int?> getCurrentPatient() async {
    final prefs = await SharedPreferences.getInstance();
    final pid = prefs.getInt(_keyPractitionerId);
    if (pid == null) return null;
    return prefs.getInt(_keyCurrentPatientIdFor(pid));
  }

  Future<void> clearCurrentPatient() async {
    final prefs = await SharedPreferences.getInstance();
    final pid = prefs.getInt(_keyPractitionerId);
    if (pid != null) await prefs.remove(_keyCurrentPatientIdFor(pid));
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Recording write/mirror helpers

  /// Build external anonymized recordings directory for a patient.
  Future<Directory> _externalPatientRecordingsDir({
    required int practitionerId,
    required String practitionerEmail,
    required int patientId,
  }) async {
    final practitionerFolder = _practitionerFolderName(
      practitionerId: practitionerId,
      practitionerEmail: practitionerEmail,
    );
    final patientCode = formatPatientCode(patientId);

    final dir = Directory(p.join(
      _externalBackupRoot.path,
      practitionerFolder,
      'patients',
      patientCode,
      'recordings',
    ));

    if (!(await dir.exists())) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Mirror a WAV file to external anonymized backup.
  /// `wavPathInternal` = absolute path of the INTERNAL file
  /// Returns the external path if copied, else null.
  Future<String?> mirrorWavToExternal({
    required int practitionerId,
    required String practitionerEmail,
    required int patientId,
    required String wavPathInternal,
  }) async {
    try {
      final src = File(wavPathInternal);
      if (!await src.exists()) return null;

      final extRecDir = await _externalPatientRecordingsDir(
        practitionerId: practitionerId,
        practitionerEmail: practitionerEmail,
        patientId: patientId,
      );

      // Keep same basename (no PII baked into filename per app constraints).
      final destPath = p.join(extRecDir.path, p.basename(src.path));

      // Avoid overwrite if already same content (best-effort)
      if (!await File(destPath).exists()) {
        await src.copy(destPath);
      }

      return destPath;
    } catch (e) {
      debugPrint("⚠️ mirrorWavToExternal error: $e");
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Delete/rename helpers (delete both copies when possible)

Future<void> deleteRecordFiles(String filePath) async {
  try {
    final wav = File(filePath);

    // ✅ Delete the main WAV file
    if (await wav.exists()) await wav.delete();

    // ✅ Delete same-name reports (PDF/Excel) and mel spectrograms
    final baseName = p.basenameWithoutExtension(filePath);
    final parentDir = Directory(p.dirname(filePath));

    if (await parentDir.exists()) {
      for (final f in parentDir.listSync()) {
        if (f is File && p.basenameWithoutExtension(f.path) == baseName) {
          await f.delete();
        }
      }
    }

    // ✅ Delete corresponding report folders if now empty
    final reportsDir = Directory(p.join(parentDir.path, '../Reports'));
    if (await reportsDir.exists()) {
      for (final f in reportsDir.listSync()) {
        if (f is File && p.basenameWithoutExtension(f.path) == baseName) {
          await f.delete();
        }
      }
    }

    // ✅ Delete parent folder if it only contained this recording
    if (await parentDir.exists()) {
      final remaining = parentDir.listSync();
      if (remaining.isEmpty) {
        await parentDir.delete(recursive: true);
      }
    }

    // ✅ Also try to remove external anonymized copy (backup)
    final prefs = await SharedPreferences.getInstance();
    final practitionerId = prefs.getInt(_keyPractitionerId) ?? 0;
    final practitionerEmail = prefs.getString(_keyPractitionerEmail) ?? '';

    final extGlob = await _maybeFindExternalByBasename(
      practitionerId: practitionerId,
      practitionerEmail: practitionerEmail,
      basename: p.basename(filePath),
    );
    if (extGlob != null && await File(extGlob).exists()) {
      await File(extGlob).delete();
    }

    debugPrint("🗑️ Fully deleted $filePath and related files");
  } catch (e) {
    debugPrint("⚠️ Delete failed: $e");
  }
}


  Future<void> renameOrMoveRecordFile({
    required String oldPath,
    required String newName,
  }) async {
    try {
      final f = File(oldPath);
      if (await f.exists()) {
        final newPath = p.join(p.dirname(oldPath), "$newName${p.extension(oldPath)}");
        await f.rename(newPath);

        // Try renaming the external copy if present
        final prefs = await SharedPreferences.getInstance();
        final practitionerId = prefs.getInt(_keyPractitionerId) ?? 0;
        final practitionerEmail = prefs.getString(_keyPractitionerEmail) ?? '';
        final extPath = await _maybeFindExternalByBasename(
          practitionerId: practitionerId,
          practitionerEmail: practitionerEmail,
          basename: p.basename(oldPath),
        );
        if (extPath != null && await File(extPath).exists()) {
          final newExtPath = p.join(p.dirname(extPath), "$newName${p.extension(extPath)}");
          await File(extPath).rename(newExtPath);
        }
      }
    } catch (e) {
      debugPrint("⚠️ Rename failed: $e");
    }
  }

  Future<String?> _maybeFindExternalByBasename({
    required int practitionerId,
    required String practitionerEmail,
    required String basename,
  }) async {
    try {
      final practitionerFolder = _practitionerFolderName(
        practitionerId: practitionerId,
        practitionerEmail: practitionerEmail,
      );
      final root = Directory(p.join(
        _externalBackupRoot.path,
        practitionerFolder,
        'patients',
      ));
      if (!await root.exists()) return null;

      for (final patientDir in root.listSync(recursive: true, followLinks: false)) {
        if (patientDir is! Directory) continue;
        if (!patientDir.path.endsWith('/recordings')) continue;
        final candidate = File(p.join(patientDir.path, basename));
        if (await candidate.exists()) return candidate.path;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Patient metadata JSON (INTERNAL ONLY)

  Future<void> savePatientInfoJson(Map<String, dynamic> patient) async {
    try {
      final folderPath = patient['folder_path'];
      if (folderPath == null) return;

      // Only write internally (no PII externally)
      final file = File(p.join(folderPath, 'patient_info.json'));

      await file.writeAsString(
        jsonEncode({
          'patient_id': patient['patient_id'],
          'practitioner_id': patient['practitioner_id'],
          'name': patient['name'],
          'birthday': patient['birthday'],
          'age': patient['age'],
          'gender': patient['gender'],
          'symptoms': patient['symptoms'],
          'folder_path': folderPath,
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint("⚠️ savePatientInfoJson error: $e");
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Recovery: Rebuild DB from EXTERNAL anonymized backup (no PII)

  /// Scans /CardioScopeBackup and rebuilds practitioners/patients/records.
  /// - Uses practitioner_id from meta
  /// - Patients inferred from folder names (CSxxxxxxx)
  /// - Records point to external WAV paths
Future<void> rebuildDatabaseFromExistingFiles({
  required String practitionerEmail,
  required int practitionerId,
}) async {  
  debugPrint("🧩 Launching EXTERNAL DB rebuild (scoped)...");
  final backupRoot = _externalBackupRoot;
  if (!await backupRoot.exists()) return;

  final emailCanon = _canonicalizeEmail(practitionerEmail);
  final emailH = _fnv1a8(emailCanon);

  // Practitioner folder name we expect
  final expectedFolder = _practitionerFolderName(
    practitionerId: practitionerId,
    practitionerEmail: practitionerEmail,
  );
  final pracDir = Directory(p.join(backupRoot.path, expectedFolder));
  if (!await pracDir.exists()) {
    debugPrint("ℹ️ No matching practitioner folder for $expectedFolder");
    return;
  }

  final metaFile = File(p.join(pracDir.path, 'practitioner.meta.json'));
  if (!await metaFile.exists()) return;

  try {
    final meta = jsonDecode(await metaFile.readAsString());
    if ((meta['email_hash']?.toString() ?? '') != emailH) {
      debugPrint("⚠️ Email hash mismatch; aborting scoped rebuild.");
      return;
    }
  } catch (_) {
    return;
  }

  final db = await DatabaseHelper.instance.database;
  await db.transaction((txn) async {
    // Ensure unique index on file_path (idempotent)
    try {
      await txn.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_records_file_path
        ON heart_sound_records(file_path);
      ''');
    } catch (_) {}

    // Upsert minimalist practitioner row if missing
    final existingP = await txn.query(
      'practitioners',
      where: 'practitioner_id = ?',
      whereArgs: [practitionerId],
      limit: 1,
    );
    if (existingP.isEmpty) {
      await txn.insert('practitioners', {
        'practitioner_id': practitionerId,
        'name': 'User $practitionerId',
        'email': practitionerEmail,
        'email_canonical': emailCanon,
        'consent_agreed': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final patientsRoot = Directory(p.join(pracDir.path, 'patients'));
    if (!await patientsRoot.exists()) return;

    int recoveredPt = 0, recoveredR = 0;

    for (final pDir in patientsRoot.listSync()) {
      if (pDir is! Directory) continue;
      final patientCode = p.basename(pDir.path);
      if (!RegExp(r'^CS\d{7}$').hasMatch(patientCode)) continue;

      // Find or create patient by folder_path = external path
      int patientId;
      final existingPt = await txn.query(
        'patients',
        where: 'folder_path = ?',
        whereArgs: [pDir.path],
        limit: 1,
      );
      if (existingPt.isNotEmpty) {
        patientId = existingPt.first['patient_id'] as int;
      } else {
        patientId = await txn.insert('patients', {
          'practitioner_id': practitionerId,
          'name': patientCode,
          'birthday': '',
          'gender': '',
          'symptoms': '',
          'folder_path': pDir.path,
        });
        recoveredPt++;

      // ✅ Restore patient_info.json metadata if exists (after patient insert)
final infoFile = File(p.join(pDir.path, 'patient_info.json'));
if (await infoFile.exists()) {
  try {
    final data = jsonDecode(await infoFile.readAsString());
    await txn.update(
      'patients',
      {
        'name': data['name'] ?? patientCode,
        'gender': data['gender'] ?? '',
        'age': (data['age'] == '' || data['age'] == null) ? null : data['age'],
        'birthday': data['birthday'] ?? '',
        'symptoms': data['symptoms'] ?? '',
      },
      where: 'patient_id = ?',
      whereArgs: [patientId],
    );
    debugPrint("✅ patient_info.json restored for $patientCode");
  } catch (e) {
    debugPrint("⚠️ Failed to parse patient_info.json for $patientCode: $e");
  }
}
      }

      final recDir = Directory(p.join(pDir.path, 'recordings'));
      if (!await recDir.exists()) continue;

      for (final f in recDir.listSync()) {
        if (f is! File || p.extension(f.path).toLowerCase() != '.wav') continue;
        try {
          final newId = await txn.insert('heart_sound_records', {
            'patient_id': patientId,
            'file_path': f.path,
            'record_date': DateTime.now().toIso8601String(),
          });
          // enqueue re-analysis task
          reanalysisQueue.add(newId);
          recoveredR++;
        } catch (_) {
          // unique index prevents duplicates
        }
      }
    }

    debugPrint("✅ Scoped rebuild done: $recoveredPt patients, $recoveredR files.");
  });
}



  // ────────────────────────────────────────────────────────────────────────────
  // Legacy merge (optional). Moves *old public Download* practitioner folders
  // into internal secure structure where reasonable (no deletes from external backup).

  Future<void> _mergeLegacyPractitionerIfAny({
    required int practitionerId,
    required String practitionerEmail,
    required Directory secureRoot,
  }) async {
    // Legacy location previously used by old code:
    final legacyRoot = Directory(
      p.join(_legacyDownloadsRoot.path, 'CardioScope', 'Practitioner'),
    );
    if (!await legacyRoot.exists()) return;

    final internalPatientsRoot = Directory(p.join(secureRoot.path, 'Patients'));
    if (!(await internalPatientsRoot.exists())) {
      await internalPatientsRoot.create(recursive: true);
    }

    try {
      for (final entity in legacyRoot.listSync()) {
        if (entity is! Directory) continue;

        // Move only Patients/* subtree safely
        final patients = Directory(p.join(entity.path, 'Patients'));
        if (!await patients.exists()) continue;

        for (final pDir in patients.listSync()) {
          if (pDir is! Directory) continue;

          final target = Directory(p.join(internalPatientsRoot.path, p.basename(pDir.path)));
          if (!(await target.exists())) {
            await target.create(recursive: true);
          }
          // Move contents
          for (final child in Directory(pDir.path).listSync()) {
            final destPath = p.join(target.path, p.basename(child.path));
            if (child is File) {
              if (!(await File(destPath).exists())) {
                await child.rename(destPath);
              }
            } else if (child is Directory) {
              final destDir = Directory(destPath);
              if (!(await destDir.exists())) {
                await destDir.create(recursive: true);
              }
              await _moveContents(child, destDir);
              await child.delete(recursive: true);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Legacy merge error: $e");
    }
  }

  Future<void> _moveContents(Directory src, Directory dst) async {
    for (final e in src.listSync()) {
      final destPath = p.join(dst.path, p.basename(e.path));
      if (e is Directory) {
        final dir = Directory(destPath);
        if (!(await dir.exists())) await dir.create(recursive: true);
        await _moveContents(e, dir);
        await e.delete(recursive: true);
      } else if (e is File) {
        if (!(await File(destPath).exists())) {
          await e.rename(destPath);
        } else {
          // If file exists, skip to avoid data loss
        }
      }
    }
  }
}
