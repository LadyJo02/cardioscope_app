// 📁 lib/database_helper.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _databaseName = "cardioscope.db";
  static const _databaseVersion = 11; // ✅ current

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

    final db = await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // ✅ Pragmas for better reliability/perf
    await db.rawQuery('PRAGMA synchronous = NORMAL;');
    await db.rawQuery('PRAGMA journal_mode = WAL;');

    return db;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SCHEMA
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE practitioners (
        practitioner_id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT,
        email_canonical TEXT UNIQUE,
        clinic_name TEXT,
        pin_hash TEXT,
        pin_salt TEXT,
        pin_iters INTEGER DEFAULT 120000,
        security_question TEXT,
        answer_hash TEXT,
        answer_salt TEXT,
        answer_iters INTEGER DEFAULT 120000,
        consent_agreed BOOLEAN DEFAULT 0
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
        symptoms TEXT,
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
    CREATE UNIQUE INDEX IF NOT EXISTS idx_records_file_path
    ON heart_sound_records(file_path);
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
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
  }

  /// Robust, idempotent upgrades v1 → v11
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("🔄 Upgrading DB from v$oldVersion → v$newVersion");

    // v2 — add security Q&A (legacy)
    if (oldVersion < 2) {
      try {
        await db.execute("ALTER TABLE practitioners ADD COLUMN security_question TEXT;");
      } catch (_) {}
      try {
        // Legacy column name; replaced by hashed fields later
        await db.execute("ALTER TABLE practitioners ADD COLUMN security_answer TEXT;");
      } catch (_) {}
    }
      try {
        await db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_records_file_path
        ON heart_sound_records(file_path);
        ''');
      } catch (_) {}


    // v3 — add birthday & folder_path
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE patients ADD COLUMN birthday TEXT;");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE patients ADD COLUMN folder_path TEXT;");
      } catch (_) {}
    }

    // v7 — add symptoms to patients (guarded)
    if (oldVersion < 7) {
      final cols = await db.rawQuery("PRAGMA table_info(patients);");
      final names = cols.map((c) => (c['name'] as String)).toList();
      if (!names.contains('symptoms')) {
        await db.execute("ALTER TABLE patients ADD COLUMN symptoms TEXT;");
        debugPrint("✅ Added patients.symptoms");
      }
    }

    // v8 — add email + consent_agreed
    if (oldVersion < 8) {
      final cols = await db.rawQuery("PRAGMA table_info(practitioners);");
      final names = cols.map((c) => (c['name'] as String)).toList();
      if (!names.contains('email')) {
        await db.execute("ALTER TABLE practitioners ADD COLUMN email TEXT;");
      }
      if (!names.contains('consent_agreed')) {
        await db.execute("ALTER TABLE practitioners ADD COLUMN consent_agreed BOOLEAN DEFAULT 0;");
      }
    }

    // v9 — add email_canonical + unique index (with safe backfill & cleanup)
    if (oldVersion < 9) {
      final cols = await db.rawQuery("PRAGMA table_info(practitioners);");
      final names = cols.map((c) => (c['name'] as String)).toList();

      if (!names.contains('email_canonical')) {
        await db.execute("ALTER TABLE practitioners ADD COLUMN email_canonical TEXT;");
        debugPrint("✅ Added practitioners.email_canonical");
      }

      // backfill
      await db.execute('''
        UPDATE practitioners
        SET email_canonical = LOWER(COALESCE(email,''))
        WHERE email_canonical IS NULL OR email_canonical = '';
      ''');

      // dedupe (keep lowest rowid)
      try {
        await db.execute('''
          DELETE FROM practitioners
          WHERE rowid NOT IN (
            SELECT MIN(rowid) FROM practitioners GROUP BY email_canonical
          )
          AND email_canonical != '';
        ''');
      } catch (e) {
        debugPrint("⚠️ Dedupe skipped: $e");
      }

      // unique index
      try {
        await db.execute('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_practitioners_email_canonical
          ON practitioners(email_canonical);
        ''');
      } catch (e) {
        debugPrint("⚠️ Index create skipped: $e");
      }
    }

    // v10 — introduce hashed auth fields & remove any UNIQUE(name) from legacy builds
    if (oldVersion < 10) {
      final cols = await db.rawQuery("PRAGMA table_info(practitioners);");
      final names = cols.map((c) => (c['name'] as String)).toList();

      Future<void> addColumn(String col) async {
        if (!names.contains(col)) {
          await db.execute("ALTER TABLE practitioners ADD COLUMN $col ${_colTypeFor(col)};");
        }
      }

      await addColumn('pin_hash');
      await addColumn('pin_salt');
      await addColumn('pin_iters');
      await addColumn('answer_hash');
      await addColumn('answer_salt');
      await addColumn('answer_iters');

      // Rebuild table to safely drop any UNIQUE(name) constraint if it exists
      try {
        final pragma = await db.rawQuery("PRAGMA table_info(practitioners);");
        final hasClinic = pragma.any((c) => c['name'] == 'clinic_name');

        await db.execute("ALTER TABLE practitioners RENAME TO tmp_pract2;");
        await db.execute('''
          CREATE TABLE practitioners (
            practitioner_id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT,
            email_canonical TEXT UNIQUE,
            clinic_name TEXT,
            pin_hash TEXT,
            pin_salt TEXT,
            pin_iters INTEGER DEFAULT 120000,
            security_question TEXT,
            answer_hash TEXT,
            answer_salt TEXT,
            answer_iters INTEGER DEFAULT 120000,
            consent_agreed BOOLEAN DEFAULT 0
          );
        ''');

        // Move data (best-effort map of legacy columns)
        final selectCols = <String>[
          'practitioner_id','name','email','email_canonical',
          if (hasClinic) 'clinic_name' else "'' AS clinic_name",
          'pin_hash','pin_salt','pin_iters',
          'security_question',
          // prefer hashed answer if present; legacy security_answer ignored
          'answer_hash','answer_salt','answer_iters',
          'consent_agreed'
        ].join(', ');

        await db.execute('''
          INSERT INTO practitioners (
            practitioner_id,name,email,email_canonical,clinic_name,
            pin_hash,pin_salt,pin_iters,
            security_question,answer_hash,answer_salt,answer_iters,
            consent_agreed
          )
          SELECT $selectCols FROM tmp_pract2;
        ''');

        await db.execute("DROP TABLE tmp_pract2;");
      } catch (e) {
        debugPrint("⚠️ v10 rebuild skipped/already applied: $e");
      }
    }

    // v11 — ensure clinic_name exists
    if (oldVersion < 11) {
      try {
        await db.execute("ALTER TABLE practitioners ADD COLUMN clinic_name TEXT;");
        debugPrint("✅ Added practitioners.clinic_name");
      } catch (_) {}
    }

    // Patch: if somehow clinic_name still missing
    final cols = await db.rawQuery("PRAGMA table_info(practitioners);");
    final names = cols.map((c) => (c['name'] as String)).toList();
    if (!names.contains('clinic_name')) {
      await db.execute("ALTER TABLE practitioners ADD COLUMN clinic_name TEXT;");
      debugPrint("🩺 v11 patch: re-added clinic_name");
    }
  }

  String _colTypeFor(String name) {
    switch (name) {
      case 'pin_iters':
      case 'answer_iters':
        return 'INTEGER DEFAULT 120000';
      default:
        return 'TEXT';
    }
  }

  

  // ────────────────────────────────────────────────────────────────────────────
  // PRACTITIONERS
  // ────────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllPractitioners() async =>
      (await database).query('practitioners');

  Future<int> insertPractitioner(Map<String, dynamic> row) async =>
      (await database).insert('practitioners', row,
          // keep strict to surface duplicates on email_canonical
          conflictAlgorithm: ConflictAlgorithm.fail);

  Future<Map<String, dynamic>?> getPractitionerByName(String name) async {
    final db = await database;
    final res =
        await db.query('practitioners', where: 'name = ?', whereArgs: [name]);
    return res.isNotEmpty ? res.first : null;
  }

  Future<Map<String, dynamic>?> getPractitionerById(int id) async {
    final db = await database;
    final res = await db.query('practitioners',
        where: 'practitioner_id = ?', whereArgs: [id], limit: 1);
    return res.isNotEmpty ? res.first : null;
  }

  Future<Map<String, dynamic>?> getPractitionerByEmailCanonical(
      String emailCanonical) async {
    final db = await database;
    final res = await db.query(
      'practitioners',
      where: 'email_canonical = ?',
      whereArgs: [emailCanonical],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  /// Update consent flag (used when user confirms consent dialogs)
  Future<int> updatePractitionerConsent(int id, bool agreed) async {
    final db = await database;
    return db.update(
      'practitioners',
      {'consent_agreed': agreed ? 1 : 0},
      where: 'practitioner_id = ?',
      whereArgs: [id],
    );
  }

  /// Update profile fields commonly edited in Settings (name/email/clinic)
  Future<int> updatePractitionerProfile(
    int id, {
    String? name,
    String? email,
    String? clinicName,
  }) async {
    final db = await database;
    final data = <String, Object?>{};
    if (name != null) data['name'] = name;
    if (email != null) {
      data['email'] = email;
      data['email_canonical'] = email.toLowerCase();
    }
    if (clinicName != null) data['clinic_name'] = clinicName;
    if (data.isEmpty) return 0;
    return db.update('practitioners', data,
        where: 'practitioner_id = ?', whereArgs: [id]);
  }

  /// Set hashed PIN secret values
  Future<int> setPractitionerPinSecret(
    int id, {
    required String hash,
    required String salt,
    required int iters,
  }) async {
    final db = await database;
    return db.update(
      'practitioners',
      {'pin_hash': hash, 'pin_salt': salt, 'pin_iters': iters},
      where: 'practitioner_id = ?',
      whereArgs: [id],
    );
  }

  /// Set hashed Security Answer secret values
  Future<int> setSecurityAnswerSecret(
    int id, {
    required String hash,
    required String salt,
    required int iters,
  }) async {
    final db = await database;
    return db.update(
      'practitioners',
      {'answer_hash': hash, 'answer_salt': salt, 'answer_iters': iters},
      where: 'practitioner_id = ?',
      whereArgs: [id],
    );
  }

  /// Legacy method kept for compatibility (no-op for plain 'pin' column)
  Future<int> updatePractitionerPin(int id, String newPinUnused) async {
    // Your app no longer stores raw PINs; keep method to avoid crashes.
    // Return 1 to indicate "updated" (harmless) or 0 to be strict.
    return 1;
  }

  /// Remove duplicate practitioner rows on email_canonical (keep oldest row)
  Future<void> removeDuplicatePractitioners() async {
    final db = await database;
    try {
      final result = await db.rawQuery('''
        SELECT COUNT(*) AS duplicates FROM practitioners
        WHERE rowid NOT IN (
          SELECT MIN(rowid) FROM practitioners GROUP BY email_canonical
        )
        AND email_canonical != '';
      ''');
      final count = (result.first['duplicates'] as int?) ?? 0;

      if (count > 0) {
        await db.execute('''
          DELETE FROM practitioners
          WHERE rowid NOT IN (
            SELECT MIN(rowid) FROM practitioners GROUP BY email_canonical
          )
          AND email_canonical != '';
        ''');
        debugPrint("🧹 Removed $count duplicate practitioner(s).");
      } else {
        debugPrint("✅ No duplicate practitioners found.");
      }
    } catch (e) {
      debugPrint("⚠️ Failed to remove duplicate practitioners: $e");
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // PATIENTS
  // ────────────────────────────────────────────────────────────────────────────

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
      limit: 1,
    );

    if (existing.isNotEmpty) {
      return existing.first['patient_id'] as int;
    }

    final data = Map<String, Object?>.from(patientData);
    data['practitioner_id'] = practitionerId;
    return db.insert('patients', data);
  }

  Future<List<Map<String, dynamic>>> getAllPatients(int practitionerId) async {
    final db = await database;
    return db.query('patients',
        where: 'practitioner_id = ?', whereArgs: [practitionerId]);
  }

  Future<List<String>> getPatientSuggestions(String query) async {
    if (query.isEmpty) return [];
    final db = await database;
    final result = await db.rawQuery('''
      SELECT name FROM patients
      WHERE LOWER(name) LIKE LOWER(?)
      ORDER BY name ASC
      LIMIT 10;
    ''', ['%$query%']);
    return result.map((e) => e['name'] as String).toList();
  }

  Future<Map<String, dynamic>?> getPatientDetails(String name) async {
    final db = await database;
    final res = await db.query('patients', where: 'name = ?', whereArgs: [name]);
    return res.isNotEmpty ? res.first : null;
  }

  Future<Map<String, dynamic>?> getPatientById(int id) async {
    final db = await database;
    final res =
        await db.query('patients', where: 'patient_id = ?', whereArgs: [id]);
    return res.isNotEmpty ? res.first : null;
  }

  Future<int> updatePatientFolderPath(int id, String path) async {
    final db = await database;
    return db.update('patients', {'folder_path': path},
        where: 'patient_id = ?', whereArgs: [id]);
  }

  /// Used during recovery to match a patient by stored folder path
  Future<Map<String, dynamic>?> getPatientByFolderPath(
      String folderPath) async {
    final db = await database;
    final res = await db.query(
      'patients',
      where: 'folder_path = ?',
      whereArgs: [folderPath],
      limit: 1,
    );
    return res.isNotEmpty ? res.first : null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // RECORDS & ANALYSIS
  // ────────────────────────────────────────────────────────────────────────────

  Future<int> insertRecord(Map<String, dynamic> record) async =>
      (await database).insert('heart_sound_records', record);

  Future<int> insertAnalysis(Map<String, dynamic> analysis) async =>
      (await database).insert('mitral_valve_analysis', analysis);

  Future<Map<String, dynamic>?> getAnalysisByRecordId(int recordId) async {
    final db = await database;
    final res = await db.query('mitral_valve_analysis',
        where: 'record_id = ?', whereArgs: [recordId], limit: 1);
    return res.isNotEmpty ? res.first : null;
  }

  Future<void> upsertAnalysisByRecordId(
    int recordId, {
    required String diagnosis,
    required String probabilitiesJson,
    required String analysisDateIso,
  }) async {
    final db = await database;
    final exists = await getAnalysisByRecordId(recordId);
    final data = {
      'record_id': recordId,
      'diagnosis': diagnosis,
      'probabilities': probabilitiesJson,
      'analysis_date': analysisDateIso,
    };
    if (exists == null) {
      await db.insert('mitral_valve_analysis', data);
    } else {
      await db.update('mitral_valve_analysis', data,
          where: 'record_id = ?', whereArgs: [recordId]);
    }
  }

  Future<void> deleteRecordById(int recordId) async {
    final db = await database;
    await db.delete('mitral_valve_analysis',
        where: 'record_id = ?', whereArgs: [recordId]);
    await db.delete('heart_sound_records',
        where: 'record_id = ?', whereArgs: [recordId]);
    debugPrint("🗑 Deleted record $recordId and its analysis");
  }

  // ────────────────────────────────────────────────────────────────────────────
  // REPORTS (JOINS)
  // ────────────────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllReports(
    int practitionerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;

    String whereClause = 'p.practitioner_id = ?';
    final whereArgs = <Object>[practitionerId];

    if (startDate != null) {
      whereClause += ' AND r.record_date >= ?';
      whereArgs.add(DateFormat('yyyy-MM-dd').format(startDate));
    }
    if (endDate != null) {
      whereClause += ' AND r.record_date < ?';
      whereArgs.add(DateFormat('yyyy-MM-dd').format(endDate.add(const Duration(days: 1))));
    }

    return db.rawQuery('''
      SELECT 
        p.patient_id, p.name, p.birthday, p.age, p.gender, p.symptoms, p.folder_path,
        r.record_id, r.file_path, r.record_date,
        a.analysis_id, a.diagnosis, a.probabilities, a.analysis_date,
        pr.email AS practitioner_email,
        pr.clinic_name AS clinic_name
      FROM patients p
      JOIN practitioners pr ON pr.practitioner_id = p.practitioner_id
      JOIN heart_sound_records r ON p.patient_id = r.patient_id
      LEFT JOIN mitral_valve_analysis a ON r.record_id = a.record_id
      WHERE $whereClause
      ORDER BY r.record_date DESC;
    ''', whereArgs);
  }

  Future<List<Map<String, dynamic>>> getAllReportsWithPatients(
      int practitionerId) async {
    final db = await database;
    return db.rawQuery('''
      SELECT 
        p.patient_id, p.name, p.birthday, p.age, p.gender, p.symptoms, p.folder_path,
        r.record_id, r.file_path, r.record_date,
        a.analysis_id, a.diagnosis, a.probabilities, a.analysis_date,
        pr.email AS practitioner_email,
        pr.clinic_name AS clinic_name
      FROM patients p
      JOIN practitioners pr ON pr.practitioner_id = p.practitioner_id
      JOIN heart_sound_records r ON p.patient_id = r.patient_id
      LEFT JOIN mitral_valve_analysis a ON r.record_id = a.record_id
      WHERE p.practitioner_id = ?
      ORDER BY r.record_date DESC;
    ''', [practitionerId]);
  }

  // ────────────────────────────────────────────────────────────────────────────
  // SETTINGS KV
  // ────────────────────────────────────────────────────────────────────────────

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

  // ────────────────────────────────────────────────────────────────────────────
  // UTILITIES
  // ────────────────────────────────────────────────────────────────────────────

  String formatPatientId(int id) => 'CS${id.toString().padLeft(7, '0')}';

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

Future<void> deleteDatabaseFile() async {
  final path = join(await getDatabasesPath(), _databaseName);
  if (await File(path).exists()) {
    await deleteDatabase(path);
    debugPrint("🗑️ Database file deleted: $path");
  } else {
    debugPrint("ℹ️ No database file to delete.");
  }
  _database = null;
}


  /// Used by StorageService.rebuildDatabaseFromExistingFiles()
  Future<void> insertRecoveredRecord(Map<String, dynamic> data) async {
    final db = await database;
    try {
      await db.insert('heart_sound_records', {
        'patient_id': data['patient_id'] ?? 0,
        'file_path': data['file_path'],
        'record_date': data['record_date'],
      });
      debugPrint("🩺 Recovered record inserted: ${data['file_path']}");
    } catch (e) {
      debugPrint("⚠️ Skipped existing/recovered record: $e");
    }
  }
}
