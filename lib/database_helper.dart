import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static const _databaseName = "cardioscope.db";
  static const _databaseVersion = 1;

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  Database? _database;

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    return await openDatabase(path, version: _databaseVersion, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        age INTEGER,
        gender TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE heart_sound_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        file_path TEXT NOT NULL,
        record_date TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE mitral_valve_analysis (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id INTEGER,
        diagnosis TEXT,
        confidence REAL,
        analysis_date TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (record_id) REFERENCES heart_sound_records (id) ON DELETE CASCADE
      );
    ''');
  }

  // ----------------- INSERTS -----------------
  Future<int> insertUser(Map<String, dynamic> user) async {
    final db = await database;
    // Check if user already exists (same name, age, gender)
    final existing = await db.query('users',
        where: 'name = ? AND age = ? AND gender = ?',
        whereArgs: [user['name'], user['age'], user['gender']]);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await db.insert('users', user);
  }

  Future<int> insertRecord(Map<String, dynamic> record) async {
    final db = await database;
    return await db.insert('heart_sound_records', record);
  }

  Future<int> insertAnalysis(Map<String, dynamic> analysis) async {
    final db = await database;
    return await db.insert('mitral_valve_analysis', analysis);
  }

  // ----------------- FETCH -----------------
  Future<List<Map<String, dynamic>>> getAllReports() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT u.id as user_id, u.name, u.age, u.gender,
             r.id as record_id, r.file_path, r.record_date,
             a.diagnosis, a.confidence, a.analysis_date
      FROM users u
      JOIN heart_sound_records r ON u.id = r.user_id
      JOIN mitral_valve_analysis a ON r.id = a.record_id
      ORDER BY a.analysis_date DESC;
    ''');
    return result;
  }

  /// Format patient ID as CS0000001, CS0000002, etc.
  String formatPatientId(int id) {
    return 'CS${id.toString().padLeft(7, '0')}';
  }


  // ----------------- UTILS -----------------
  Future<void> deleteDatabaseFile() async {
    final path = join((await getDatabasesPath()), _databaseName);
    try {
      await deleteDatabase(path);
    } catch (_) {}
  }
}
