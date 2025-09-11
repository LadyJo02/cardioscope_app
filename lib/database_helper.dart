// lib/database_helper.dart

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
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
    final dbPath = await getApplicationDocumentsDirectory();
    final path = join(dbPath.path, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textTypeNull = 'TEXT';
    
    await db.execute('''
    CREATE TABLE reports (
      id $idType,
      patientName $textType,
      filePath $textType,
      recordedDate $textType,
      classification $textTypeNull,
      confidence $textTypeNull
    )
    ''');
  }

  Future<int> createReport(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('reports', row);
  }

  Future<List<Map<String, dynamic>>> getAllReports() async {
    final db = await instance.database;
    return await db.query('reports', orderBy: 'recordedDate DESC');
  }
  
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}