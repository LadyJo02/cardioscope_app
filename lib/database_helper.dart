// lib/database_helper.dart
import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();
  static Database? _database;

  DatabaseHelper._privateConstructor();

  Future<Database> get database async => _database ??= await _initDatabase();

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'cardioscope.db');
    return await openDatabase(
      path,
      version: 3, // **INCREMENT VERSION TO 3**
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE recordings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_name TEXT,
        file_path TEXT,
        diagnosis TEXT,
        confidence REAL, 
        created_at TEXT
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE recordings ADD COLUMN patient_name TEXT");
    }
    if (oldVersion < 3) {
      // **ADD CONFIDENCE COLUMN**
      await db.execute("ALTER TABLE recordings ADD COLUMN confidence REAL");
    }
  }

  Future<int> createReport(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('recordings', {
      'patient_name': row['patientName'],
      'file_path': row['filePath'],
      'diagnosis': row['classification'],
      'confidence': row['confidence'], // **SAVE CONFIDENCE**
      'created_at': row['recordedDate'],
    });
  }

  Future<List<Map<String, dynamic>>> getAllReports() async {
    final db = await instance.database;
    return await db.query('recordings', orderBy: 'created_at DESC');
  }

  // --- Insight Helpers ---

  Future<int> getTodayScreeningCount() async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final res = await db.rawQuery(
        "SELECT COUNT(*) as cnt FROM recordings WHERE substr(created_at,1,10)=?",
        [today]);
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<int> _getDailyCountForCondition(String condition) async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final res = await db.rawQuery(
        "SELECT COUNT(*) FROM recordings WHERE diagnosis = ? AND substr(created_at,1,10) = ?",
        [condition, today]);
    return Sqflite.firstIntValue(res) ?? 0;
  }
  
  Future<int> getTodayMRCount() async => _getDailyCountForCondition('MR');
  Future<int> getTodayMSCount() async => _getDailyCountForCondition('MS');
  Future<int> getTodayMVPCount() async => _getDailyCountForCondition('MVP');
}