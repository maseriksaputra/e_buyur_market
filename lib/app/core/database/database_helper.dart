// lib/app/core/database/database_helper.dart
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class DatabaseHelper {
  static final _databaseName = "EBuyurDB.db";
  static final _databaseVersion = 1;

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    return await openDatabase(path,
        version: _databaseVersion, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    // Tabel Users
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        phone TEXT,
        password TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'buyer',
        storeName TEXT,
        storeAddress TEXT
      )
    ''');
    // Tabel Products
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY,
        sellerId INTEGER,
        name TEXT,
        price REAL,
        unit TEXT,
        description TEXT,
        nutrition TEXT,
        storageTips TEXT,
        freshnessPercentage REAL,
        freshnessLabel TEXT,
        FOREIGN KEY (sellerId) REFERENCES users (id)
      )
    ''');
    // Tabel Product Images
    await db.execute('''
      CREATE TABLE product_images (
        id INTEGER PRIMARY KEY,
        productId INTEGER,
        imageUrl TEXT,
        FOREIGN KEY (productId) REFERENCES products (id)
      )
    ''');
    // Tabel Carts
    await db.execute('''
      CREATE TABLE carts (
        id INTEGER PRIMARY KEY,
        userId INTEGER,
        productId INTEGER,
        quantity INTEGER,
        FOREIGN KEY (userId) REFERENCES users (id),
        FOREIGN KEY (productId) REFERENCES products (id)
      )
    ''');
  }

  // Metode untuk operasi CRUD
  Future<int> insert(String table, Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert(table, row);
  }

  Future<List<Map<String, dynamic>>> queryAll(String table) async {
    Database db = await instance.database;
    return await db.query(table);
  }

  // Tambahkan metode lain sesuai kebutuhan (update, delete, query spesifik)
}
