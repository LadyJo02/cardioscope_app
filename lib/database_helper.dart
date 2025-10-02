import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _databaseName = "cardioscope.db";
  static const _databaseVersion = 1;

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Practitioners Table
    await db.execute('''
      CREATE TABLE practitioners (
        practitioner_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        pin TEXT NOT NULL
      );
    ''');

    // 2. Patients Table
    await db.execute('''
      CREATE TABLE patients (
        patient_id INTEGER PRIMARY KEY AUTOINCREMENT,
        practitioner_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        age INTEGER,
        gender TEXT,
        FOREIGN KEY (practitioner_id) REFERENCES practitioners (practitioner_id) ON DELETE CASCADE
      );
    ''');

    // 3. Heart Sound Records Table
    await db.execute('''
      CREATE TABLE heart_sound_records (
        record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        record_date TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (patient_id) REFERENCES patients (patient_id) ON DELETE CASCADE
      );
    ''');

    // 4. Mitral Valve Analysis Table
    await db.execute('''
      CREATE TABLE mitral_valve_analysis (
        analysis_id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id INTEGER NOT NULL,
        diagnosis TEXT,
        probabilities TEXT,
        analysis_date TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (record_id) REFERENCES heart_sound_records (record_id) ON DELETE CASCADE
      );
    ''');
  }

  // --- PRACTITIONER METHODS ---
  Future<int> insertPractitioner(Map<String, dynamic> row) async {
    final db = await database;
    return await db.insert(
      'practitioners',
      row,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<Map<String, dynamic>?> getPractitioner(String name, String pin) async {
    final db = await database;
    final res = await db.query(
      'practitioners',
      where: 'name = ? AND pin = ?',
      whereArgs: [name, pin],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  // --- REPORT CREATION AND FETCHING ---

  /// Finds a patient for a practitioner, or creates them if they don't exist.
  Future<int> findOrCreatePatient(int practitionerId, Map<String, dynamic> patientData) async {
    final db = await database;
    final existing = await db.query(
      'patients',
      where: 'practitioner_id = ? AND name = ? AND age = ? AND gender = ?',
      whereArgs: [
        practitionerId,
        patientData['name'],
        patientData['age'],
        patientData['gender']
      ],
    );

    if (existing.isNotEmpty) {
      return existing.first['patient_id'] as int;
    }

    patientData['practitioner_id'] = practitionerId;
    return await db.insert('patients', patientData);
  }

  Future<int> insertRecord(Map<String, dynamic> record) async {
    final db = await database;
    return await db.insert('heart_sound_records', record);
  }

  Future<int> insertAnalysis(Map<String, dynamic> analysis) async {
    final db = await database;
    return await db.insert('mitral_valve_analysis', analysis);
  }

  /// Fetches all combined report data for a specific practitioner.
  Future<List<Map<String, dynamic>>> getAllReports(int practitionerId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        p.patient_id,
        p.name,
        p.age,
        p.gender,
        r.record_id,
        r.file_path,
        r.record_date,
        a.analysis_id,
        a.diagnosis,
        a.probabilities,
        a.analysis_date
      FROM patients p
      JOIN heart_sound_records r ON p.patient_id = r.patient_id
      LEFT JOIN mitral_valve_analysis a ON r.record_id = a.record_id
      WHERE p.practitioner_id = ?
      ORDER BY r.record_date DESC;
    ''', [practitionerId]);
    return result;
  }

  // --- HELPER METHODS ---

  /// Formats patient ID as CS0000001, CS0000002, etc.
  String formatPatientId(int id) {
    return 'CS${id.toString().padLeft(7, '0')}';
  }

  /// Deletes the entire database file (for debugging purposes).
  Future<void> deleteDatabaseFile() async {
    final path = join((await getDatabasesPath()), _databaseName);
    try {
      await deleteDatabase(path);
      _database = null;
      if (kDebugMode) {
        print("Database deleted.");
      }
    } catch (_) {}
  }
}
