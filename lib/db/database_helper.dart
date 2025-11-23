import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/customer.dart';
import '../models/package.dart';

class DatabaseHelper {
  // Singleton instance to ensure only one instance of the database helper
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // Getter for the database, initializes if null
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('rafiq_internet_db.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // Open/Create the database
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const doubleType = 'REAL NOT NULL';

    // 1. Packages Table
    await db.execute('''
      CREATE TABLE packages ( 
        id $idType, 
        name $textType UNIQUE,
        description $textType,
        rate $doubleType
      )
    ''');
    
    // 2. Customers Table
    await db.execute('''
      CREATE TABLE customers ( 
        id $idType,
        customerId $textType UNIQUE,
        name $textType,
        phone $textType,
        address $textType,
        packageId $textType, 
        monthlyRate $doubleType,
        status $textType,
        expiryDate $textType,
        lastPaymentDate $textType
      )
    ''');
  }

  // --- CRUD OPERATIONS ---

  // Create/Update/Read/Delete Packages
  Future<Package> createPackage(Package package) async {
    final db = await instance.database;
    final id = await db.insert('packages', package.toMap());
    return package.copyWith(id: id);
  }
  Future<List<Package>> readAllPackages() async {
    final db = await instance.database;
    final result = await db.query('packages', orderBy: 'name ASC');
    return result.map((json) => Package.fromMap(json)).toList();
  }
  Future<int> updatePackage(Package package) async {
    final db = await instance.database;
    return db.update('packages', package.toMap(), where: 'id = ?', whereArgs: [package.id]);
  }
  Future<int> deletePackage(int id) async {
    final db = await instance.database;
    return await db.delete('packages', where: 'id = ?', whereArgs: [id]);
  }

  // Create/Update/Read/Delete Customers
  Future<Customer> createCustomer(Customer customer) async {
    final db = await instance.database;
    final id = await db.insert('customers', customer.toMap());
    return customer.copyWith(id: id);
  }
  Future<List<Customer>> readAllCustomers() async {
    final db = await instance.database;
    final result = await db.query('customers', orderBy: 'name ASC');
    return result.map((json) => Customer.fromMap(json)).toList();
  }
  Future<int> updateCustomer(Customer customer) async {
    final db = await instance.database;
    return db.update('customers', customer.toMap(), where: 'id = ?', whereArgs: [customer.id]);
  }
  Future<int> deleteCustomer(int id) async {
    final db = await instance.database;
    return await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }
  
  // Utility to find a single package by ID (used for Customer details)
  Future<Package?> readPackageById(int id) async {
    final db = await instance.database;
    final maps = await db.query(
      'packages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Package.fromMap(maps.first);
    }
    return null;
  }
}