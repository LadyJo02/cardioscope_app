import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cardioscope.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE reports (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patientName TEXT NOT NULL,
        filePath TEXT NOT NULL,
        recordedDate TEXT NOT NULL,
        classification TEXT,
        confidence TEXT
      )
    ''');
  }

  Future<int> createReport(Map<String, dynamic> report) async {
    final db = await instance.database;
    final id = await db.insert('reports', report);
    debugPrint("✅ Report saved to DB: $report");
    return id;
  }

  Future<List<Map<String, dynamic>>> getAllReports() async {
    final db = await instance.database;
    final reports = await db.query(
      'reports',
      orderBy: 'recordedDate DESC',
    );
    debugPrint("📂 Reports fetched: ${reports.length}");
    return reports;
  }

  Future<int> deleteReport(int id) async {
    final db = await instance.database;
    return await db.delete(
      'reports',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// ✅ Screenings per day for the last 7 days (Sun..Sat).
  Future<List<int>> fetchScreeningsPerDayLast7() async {
    final db = await instance.database;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fromDate = today.subtract(const Duration(days: 6)).toIso8601String();

    final rows = await db.query(
      'reports',
      where: 'recordedDate >= ?',
      whereArgs: [fromDate],
    );

    // Sun=0 .. Sat=6
    List<int> counts = List.filled(7, 0);
    for (var row in rows) {
      final d = DateTime.tryParse(row['recordedDate'] as String);
      if (d == null) continue;
      final weekday = DateTime(d.year, d.month, d.day).weekday; // Mon=1..Sun=7
      final index = weekday % 7; // Sun=0
      counts[index] += 1;
    }
    return counts;
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
