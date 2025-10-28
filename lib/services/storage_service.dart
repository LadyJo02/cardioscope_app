// lib/services/storage_service.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 🩺 CardioScope Storage Service
/// Handles practitioner & patient folder organization for recordings and reports.
class StorageService {
  static const _keyStoragePath = 'storagePath';
  static const _keyCurrentPatient = 'currentPatientId';
  static const _keyPractitionerName = 'practitioner_name';
  static const _keyPractitionerEmail = 'practitioner_email';

  /// ✅ Create the base practitioner folder under public Download.
  Future<String> ensureBaseFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final practitionerName = prefs.getString(_keyPractitionerName) ?? 'Unknown';
    final practitionerEmail = prefs.getString(_keyPractitionerEmail) ?? 'unknown@example.com';
    final emailPrefix = practitionerEmail.contains('@')
        ? practitionerEmail.split('@').first
        : practitionerEmail.isNotEmpty
            ? practitionerEmail
            : 'unknown';

    final Directory downloadsDir = Directory('/storage/emulated/0/Download');

    final Directory practitionerFolder = Directory(
      p.join(
        downloadsDir.path,
        'CardioScope',
        'Practitioner',
        _sanitize('${practitionerName}_$emailPrefix'),
      ),
    );

    if (!(await practitionerFolder.exists())) {
      await practitionerFolder.create(recursive: true);
    }

    await prefs.setString(_keyStoragePath, practitionerFolder.path);
    return practitionerFolder.path;
  }

  /// ✅ Retrieve or recreate base practitioner folder.
  Future<String> getOrCreateBaseFolder() async {
    final prefs = await SharedPreferences.getInstance();
    String? saved = prefs.getString(_keyStoragePath);
    if (saved == null || saved.isEmpty || !(await Directory(saved).exists())) {
      saved = await ensureBaseFolder();
    }
    return saved;
  }

  /// ✅ Returns practitioner base path.
  Future<String?> getSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoragePath);
  }

  /// ✅ Creates per-patient folder structure:
  /// /Practitioner/[Name_EmailPrefix]/Patients/CS000012/Recordings + Reports
  Future<String> createPatientSubfolders(String basePath, int patientId) async {
    final formattedId = 'CS${patientId.toString().padLeft(6, '0')}';
    final patientFolder = Directory(p.join(basePath, 'Patients', formattedId));

    final recordings = Directory(p.join(patientFolder.path, 'Recordings'));
    final reports = Directory(p.join(patientFolder.path, 'Reports'));

    if (!(await recordings.exists())) await recordings.create(recursive: true);
    if (!(await reports.exists())) await reports.create(recursive: true);

    return patientFolder.path;
  }

  /// ✅ Create general practitioner Reports folder (for batch/export).
  Future<String> createReportsFolder(String basePath) async {
    final dir = Directory(p.join(basePath, 'Reports'));
    if (!(await dir.exists())) await dir.create(recursive: true);
    return dir.path;
  }

  /// ✅ Save practitioner info (used for folder naming).
  Future<void> setPractitionerInfo(String name, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPractitionerName, name);
    await prefs.setString(_keyPractitionerEmail, email);
  }

  /// ✅ Manage current patient
  Future<int?> getCurrentPatient() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyCurrentPatient);
  }

  Future<void> setCurrentPatient(int patientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCurrentPatient, patientId);
  }

  Future<void> clearCurrentPatient() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentPatient);
  }

  String _sanitize(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9_@.-]'), "_");
  }
}
