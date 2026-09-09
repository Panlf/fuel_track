import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/dashboard_screen.dart';
import 'screens/fuel_records_screen.dart';
import 'screens/gps_speed_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/vehicle_management_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FuelTrackApp());
}

class FuelTrackApp extends StatelessWidget {
  const FuelTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuelTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const MainScreen(),
    );
  }
}

/// 主框架：底部五 Tab（概览/记录/统计/车库/速度）。
///
/// 数据变化时递增 [_refreshKey] 重建对应页面以触发重新加载。
/// 速度页常驻 IndexedStack 但仅在当前 Tab 激活时才订阅 GPS 与运行动画。
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const int _speedTabIndex = 4;

  int _currentIndex = 0;
  int _refreshKey = 0;

  void _onDataChanged() {
    setState(() => _refreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(
            key: ValueKey('dash_$_refreshKey'),
            onDataChanged: _onDataChanged,
          ),
          FuelRecordsScreen(
            key: ValueKey('records_$_refreshKey'),
            onDataChanged: _onDataChanged,
          ),
          StatisticsScreen(key: ValueKey('stats_$_refreshKey')),
          VehicleManagementScreen(onVehicleChanged: _onDataChanged),
          GpsSpeedScreen(isActive: _currentIndex == _speedTabIndex),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '概览',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_gas_station_outlined),
            selectedIcon: Icon(Icons.local_gas_station),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '统计',
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_car_outlined),
            selectedIcon: Icon(Icons.directions_car),
            label: '车库',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: '速度',
          ),
        ],
      ),
    );
  }
}
