import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vehicle.dart';
import '../models/fuel_record.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('fuel_track.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
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
        'CREATE INDEX idx_fuel_records_vehicle ON fuel_records(vehicleId)');
    await db.execute(
        'CREATE INDEX idx_fuel_records_date ON fuel_records(date)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE vehicles ADD COLUMN imagePath TEXT');
    }
  }

  // Selected vehicle persistence
  Future<String?> getSelectedVehicleId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_vehicle_id');
  }

  Future<void> setSelectedVehicleId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_vehicle_id', id);
  }

  // Vehicle CRUD
  Future<void> insertVehicle(Vehicle vehicle) async {
    final db = await database;
    await db.insert('vehicles', vehicle.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Vehicle>> getAllVehicles() async {
    final db = await database;
    final result = await db.query('vehicles', orderBy: 'createdAt DESC');
    return result.map((map) => Vehicle.fromMap(map)).toList();
  }

  Future<Vehicle?> getVehicle(String id) async {
    final db = await database;
    final result = await db.query('vehicles', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Vehicle.fromMap(result.first);
  }

  Future<void> updateVehicle(Vehicle vehicle) async {
    final db = await database;
    await db.update('vehicles', vehicle.toMap(),
        where: 'id = ?', whereArgs: [vehicle.id]);
  }

  Future<void> deleteVehicle(String id) async {
    final db = await database;
    await db.delete('fuel_records', where: 'vehicleId = ?', whereArgs: [id]);
    await db.delete('vehicles', where: 'id = ?', whereArgs: [id]);

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

  // FuelRecord CRUD
  Future<void> insertFuelRecord(FuelRecord record) async {
    final db = await database;
    await db.insert('fuel_records', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);

    await db.update(
      'vehicles',
      {'odometer': record.odometer},
      where: 'id = ?',
      whereArgs: [record.vehicleId],
    );
  }

  Future<List<FuelRecord>> getFuelRecords(String vehicleId) async {
    final db = await database;
    final result = await db.query('fuel_records',
        where: 'vehicleId = ?',
        whereArgs: [vehicleId],
        orderBy: 'date DESC, odometer DESC');
    return result.map((map) => FuelRecord.fromMap(map)).toList();
  }

  Future<FuelRecord?> getFuelRecord(String id) async {
    final db = await database;
    final result =
        await db.query('fuel_records', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return FuelRecord.fromMap(result.first);
  }

  Future<void> updateFuelRecord(FuelRecord record) async {
    final db = await database;
    await db.update('fuel_records', record.toMap(),
        where: 'id = ?', whereArgs: [record.id]);
  }

  Future<void> deleteFuelRecord(String id) async {
    final db = await database;
    await db.delete('fuel_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<FuelRecord>> getRecordsForStats(
      String vehicleId, int limit) async {
    final db = await database;
    final result = await db.query('fuel_records',
        where: 'vehicleId = ?',
        whereArgs: [vehicleId],
        orderBy: 'date DESC, odometer DESC',
        limit: limit);
    return result.map((map) => FuelRecord.fromMap(map)).toList();
  }

  Future<void> close() async {
    final db = await database;
    db.close();
    _database = null;
  }
}
