// lib/services/storage_service.dart
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class StorageService {
  static const _keyStoragePath = 'storagePath';

  // Retrieve saved path
  Future<String?> getSavedPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyStoragePath);
  }

  // Save new path
  Future<void> savePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStoragePath, path);
  }

  // Ask user to pick a folder
  Future<String?> pickFolder() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath();
    if (selectedPath == null) return null;

    const folderName = "CardioScope";
    final dirName = p.basename(selectedPath);
    String targetPath;

    // Prevent duplicate “CardioScope/CardioScope”
    if (dirName.toLowerCase() == folderName.toLowerCase()) {
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
}
