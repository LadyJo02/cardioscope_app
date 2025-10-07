import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _databaseName = "cardioscope.db";
  static const _databaseVersion = 5; // bump when schema changes

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
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE practitioners (
        practitioner_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        pin TEXT NOT NULL,
        security_question TEXT,
        security_answer TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE patients (
        patient_id INTEGER PRIMARY KEY AUTOINCREMENT,
        practitioner_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        birthday TEXT,
        age INTEGER,
        gender TEXT,
        folder_path TEXT,
        FOREIGN KEY (practitioner_id)
          REFERENCES practitioners (practitioner_id)
          ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE heart_sound_records (
        record_id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        record_date TEXT,
        FOREIGN KEY (patient_id)
          REFERENCES patients (patient_id)
          ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE mitral_valve_analysis (
        analysis_id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id INTEGER NOT NULL,
        diagnosis TEXT,
        probabilities TEXT,
        analysis_date TEXT,
        FOREIGN KEY (record_id)
          REFERENCES heart_sound_records (record_id)
          ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE practitioners ADD COLUMN security_question TEXT;");
      await db.execute(
          "ALTER TABLE practitioners ADD COLUMN security_answer TEXT;");
    }

    if (oldVersion < 3) {
      await db.execute("ALTER TABLE patients ADD COLUMN birthday TEXT;");
      await db.execute("ALTER TABLE patients ADD COLUMN folder_path TEXT;");
    }

    // ensure proper settings table structure
    final cols = await db.rawQuery("PRAGMA table_info(settings);");
    final colNames = cols.map((c) => c['name'] as String).toList();

    if (colNames.contains('vaalue')) {
      debugPrint('⚠️ Found typo column `vaalue` → rebuilding settings table...');
      await db.execute('ALTER TABLE settings RENAME TO settings_old;');
      await db.execute('''
        CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT);
      ''');
      await db.execute('''
        INSERT INTO settings (key, value)
        SELECT key, vaalue FROM settings_old;
      ''');
      await db.execute('DROP TABLE settings_old;');
      debugPrint('✅ Settings table fixed.');
    } else {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key TEXT PRIMARY KEY,
          value TEXT
        );
      ''');
    }
  }

  // ---------------- PRACTITIONERS ----------------

  Future<List<Map<String, dynamic>>> getAllPractitioners() async {
    final db = await database;
    return db.query('practitioners');
  }

  Future<int> insertPractitioner(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('practitioners', row,
        conflictAlgorithm: ConflictAlgorithm.ignore);
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

  Future<Map<String, dynamic>?> getPractitionerByName(String name) async {
    final db = await database;
    final res = await db.query('practitioners',
        where: 'name = ?', whereArgs: [name], limit: 1);
    return res.isNotEmpty ? res.first : null;
  }

  Future<int> updatePractitionerPin(int id, String newPin) async {
    final db = await database;
    return db.update('practitioners', {'pin': newPin},
        where: 'practitioner_id = ?', whereArgs: [id]);
  }

  // ---------------- PATIENTS ----------------

  Future<int> findOrCreatePatient(
      int practitionerId, Map<String, dynamic> patientData) async {
    final db = await database;

    final existing = await db.query(
      'patients',
      where:
          'practitioner_id = ? AND name = ? AND birthday = ? AND gender = ?',
      whereArgs: [
        practitionerId,
        patientData['name'],
        patientData['birthday'],
        patientData['gender']
      ],
    );

    if (existing.isNotEmpty) {
      return existing.first['patient_id'] as int;
    }

    patientData['practitioner_id'] = practitionerId;
    return db.insert('patients', patientData);
  }

  Future<List<Map<String, dynamic>>> getAllPatients(int practitionerId) async {
    final db = await database;
    return db.query('patients',
        where: 'practitioner_id = ?', whereArgs: [practitionerId]);
  }

  Future<List<String>> getPatientSuggestions(String query) async {
    final db = await database;
    final result = await db.query(
      'patients',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
      limit: 5,
    );
    return result.map((e) => e['name'] as String).toList();
  }

  Future<Map<String, dynamic>?> getPatientDetails(String name) async {
    final db = await database;
    final result = await db.query(
      'patients',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

/// Retrieve patient by ID (used for reloading current patient)
  Future<Map<String, dynamic>?> getPatientById(int patientId) async {
    final db = await database;
    final result = await db.query(
      'patients',
      where: 'patient_id = ?',
      whereArgs: [patientId],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  } 


  Future<int> updatePatientFolderPath(int patientId, String folderPath) async {
    final db = await database;
    return db.update('patients', {'folder_path': folderPath},
        where: 'patient_id = ?', whereArgs: [patientId]);
  }

  // ---------------- RECORDS & ANALYSIS ----------------

  Future<int> insertRecord(Map<String, dynamic> record) async {
    final db = await database;
    return db.insert('heart_sound_records', record);
  }

  Future<int> insertAnalysis(Map<String, dynamic> analysis) async {
    final db = await database;
    return db.insert('mitral_valve_analysis', analysis);
  }

  /// Original method used by exports and reports filtering
  Future<List<Map<String, dynamic>>> getAllReports(int practitionerId,
      {DateTime? startDate, DateTime? endDate}) async {
    final db = await database;
    String whereClause = 'p.practitioner_id = ?';
    List<Object> whereArgs = [practitionerId];

    if (startDate != null) {
      whereClause += ' AND r.record_date >= ?';
      whereArgs.add(DateFormat('yyyy-MM-dd').format(startDate));
    }
    if (endDate != null) {
      whereClause += ' AND r.record_date < ?';
      whereArgs.add(
          DateFormat('yyyy-MM-dd').format(endDate.add(const Duration(days: 1))));
    }

    return db.rawQuery('''
      SELECT 
        p.patient_id, p.name, p.birthday, p.age, p.gender, p.folder_path,
        r.record_id, r.file_path, r.record_date,
        a.analysis_id, a.diagnosis, a.probabilities, a.analysis_date
      FROM patients p
      JOIN heart_sound_records r ON p.patient_id = r.patient_id
      LEFT JOIN mitral_valve_analysis a ON r.record_id = a.record_id
      WHERE $whereClause
      ORDER BY r.record_date DESC;
    ''', whereArgs);
  }

  /// ✅ NEW: used by ReportsPage to load joined patient data easily
  Future<List<Map<String, dynamic>>> getAllReportsWithPatients(
      int practitionerId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT 
        p.patient_id, p.name, p.birthday, p.age, p.gender, p.folder_path,
        r.record_id, r.file_path, r.record_date,
        a.analysis_id, a.diagnosis, a.probabilities, a.analysis_date
      FROM patients p
      JOIN heart_sound_records r ON p.patient_id = r.patient_id
      LEFT JOIN mitral_valve_analysis a ON r.record_id = a.record_id
      WHERE p.practitioner_id = ?
      ORDER BY r.record_date DESC;
    ''', [practitionerId]);
  }

  // ---------------- SETTINGS ----------------

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final res = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return res.isNotEmpty ? res.first['value'] as String : null;
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  // ---------------- UTILITIES ----------------

  Future<void> verifyDatabaseStructure() async {
    final db = await database;
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';");
    debugPrint("📋 Tables: ${tables.map((t) => t['name']).toList()}");

    for (final t in tables) {
      final name = t['name'] as String;
      final cols = await db.rawQuery("PRAGMA table_info($name);");
      debugPrint("🧩 $name columns: ${cols.map((c) => c['name']).toList()}");
    }
  }

  String formatPatientId(int id) => 'CS${id.toString().padLeft(7, '0')}';

  Future<void> deleteDatabaseFile() async {
    final path = join(await getDatabasesPath(), _databaseName);
    await deleteDatabase(path);
    _database = null;
    debugPrint("🗑️ Database deleted.");
  }
}
