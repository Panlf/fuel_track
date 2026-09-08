import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/fuel_record.dart';
import '../models/vehicle.dart';

/// SQLite 数据库访问层（单例）。
///
/// 负责建表/迁移、车辆与加油记录的 CRUD，以及当前所选车辆的持久化。
class DatabaseHelper {
  DatabaseHelper._init();

  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;

  /// 缓存打开中的 Future，避免并发首访时重复初始化连接。
  static Future<Database>? _opening;

  Future<Database> get database {
    final existing = _database;
    if (existing != null) return Future.value(existing);
    return _opening ??= _initDB('fuel_track.db');
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
    _database = db;
    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE vehicles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT,
        model TEXT,
        year INTEGER,
        fuelType TEXT,
        tankCapacity REAL,
        odometer INTEGER DEFAULT 0,
        imagePath TEXT,
        createdAt INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE fuel_records (
        id TEXT PRIMARY KEY,
        vehicleId TEXT NOT NULL,
        date INTEGER NOT NULL,
        odometer INTEGER NOT NULL,
        liters REAL NOT NULL,
        pricePerLiter REAL NOT NULL,
        totalCost REAL NOT NULL,
        isFullTank INTEGER DEFAULT 1,
        fuelType TEXT,
        station TEXT,
        notes TEXT,
        FOREIGN KEY (vehicleId) REFERENCES vehicles(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_fuel_records_vehicle ON fuel_records(vehicleId)',
    );
    await db.execute(
      'CREATE INDEX idx_fuel_records_date ON fuel_records(date)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE vehicles ADD COLUMN imagePath TEXT');
    }
  }

  // ---------------------------------------------------------------------------
  // 当前所选车辆（SharedPreferences 持久化）
  // ---------------------------------------------------------------------------

  Future<String?> getSelectedVehicleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_vehicle_id');
  }

  Future<void> setSelectedVehicleId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_vehicle_id', id);
  }

  // ---------------------------------------------------------------------------
  // 车辆 CRUD
  // ---------------------------------------------------------------------------

  Future<void> insertVehicle(Vehicle vehicle) async {
    final db = await database;
    await db.insert(
      'vehicles',
      vehicle.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Vehicle>> getAllVehicles() async {
    final db = await database;
    final result = await db.query('vehicles', orderBy: 'createdAt DESC');
    return result.map(Vehicle.fromMap).toList();
  }

  Future<Vehicle?> getVehicle(String id) async {
    final db = await database;
    final result = await db.query('vehicles', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Vehicle.fromMap(result.first);
  }

  Future<void> updateVehicle(Vehicle vehicle) async {
    final db = await database;
    await db.update(
      'vehicles',
      vehicle.toMap(),
      where: 'id = ?',
      whereArgs: [vehicle.id],
    );
  }

  /// 删除车辆及其全部加油记录；两表操作在事务内保证原子性。
  /// 若删除的是当前所选车辆，自动切换到剩余的第一辆（或清除选择）。
  Future<void> deleteVehicle(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('fuel_records', where: 'vehicleId = ?', whereArgs: [id]);
      await txn.delete('vehicles', where: 'id = ?', whereArgs: [id]);
    });

    final selectedId = await getSelectedVehicleId();
    if (selectedId == id) {
      final vehicles = await getAllVehicles();
      if (vehicles.isNotEmpty) {
        await setSelectedVehicleId(vehicles.first.id);
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('selected_vehicle_id');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 加油记录 CRUD
  // ---------------------------------------------------------------------------

  /// 插入记录并同步车辆里程表；两步在事务内保证原子性。
  Future<void> insertFuelRecord(FuelRecord record) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'fuel_records',
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'vehicles',
        {'odometer': record.odometer},
        where: 'id = ?',
        whereArgs: [record.vehicleId],
      );
    });
  }

  Future<List<FuelRecord>> getFuelRecords(String vehicleId) async {
    final db = await database;
    final result = await db.query(
      'fuel_records',
      where: 'vehicleId = ?',
      whereArgs: [vehicleId],
      orderBy: 'date DESC, odometer DESC',
    );
    return result.map(FuelRecord.fromMap).toList();
  }

  Future<FuelRecord?> getFuelRecord(String id) async {
    final db = await database;
    final result = await db.query(
      'fuel_records',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isEmpty) return null;
    return FuelRecord.fromMap(result.first);
  }

  Future<void> updateFuelRecord(FuelRecord record) async {
    final db = await database;
    await db.update(
      'fuel_records',
      record.toMap(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<void> deleteFuelRecord(String id) async {
    final db = await database;
    await db.delete('fuel_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
    _opening = null;
  }
}
