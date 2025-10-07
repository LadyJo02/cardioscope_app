import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// ✅ FINAL VERSION — Stable for both debug & release builds
class StorageService {
  static const _keyStoragePath = 'storagePath';
  static const _keyCurrentPatient = 'currentPatientId';

  // ========== BASE FOLDER MANAGEMENT ==========

  /// Retrieve the saved CardioScope folder path (if any)
  Future<String?> getSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoragePath);
  }

  /// Save a base folder path to preferences
  Future<void> savePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStoragePath, path);
  }

  /// Ask the user to pick a base folder (and ensure `/CardioScope` exists)
  Future<String?> pickFolder() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath();
    if (selectedPath == null) return null;

    const folderName = "CardioScope";
    String targetPath;

    // ✅ Prevent “CardioScope/CardioScope” duplication
    if (selectedPath.split('/').last.toLowerCase() == folderName.toLowerCase()) {
      targetPath = selectedPath;
    } else {
      targetPath = p.join(selectedPath, folderName);
    }

    final folder = Directory(targetPath);
    if (!(await folder.exists())) {
      await folder.create(recursive: true);
    }

    await savePath(targetPath);
    return targetPath;
  }

  // ========== PATIENT FOLDER CREATION ==========

  /// Creates a safe subfolder for the given patient inside basePath
  Future<String> createPatientFolder(String basePath, String patientName) async {
    final safeName = patientName.replaceAll(RegExp(r'[^a-zA-Z0-9_ ]'), "_");
    final patientFolder = Directory(p.join(basePath, safeName));
    if (!(await patientFolder.exists())) {
      await patientFolder.create(recursive: true);
    }
    return patientFolder.path;
  }

  // ========== CURRENT PATIENT CONTEXT ==========

  /// Save the currently active patient ID
  Future<void> setCurrentPatient(int patientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCurrentPatient, patientId);
  }

  /// ✅ Retrieve the active patient ID (used in record.dart line 65)
  Future<int?> getCurrentPatient() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyCurrentPatient)) return null;
    return prefs.getInt(_keyCurrentPatient);
  }

  /// Clear saved patient context
  Future<void> clearCurrentPatient() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentPatient);
  }
}
