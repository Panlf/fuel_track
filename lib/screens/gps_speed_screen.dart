import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/gps_speed_service.dart';
import '../theme/app_theme.dart' show AppColors;
import '../utils/gps_speed_calculator.dart';
/// 表盘量程与红线区（km/h）。
const double _kGaugeMax = 260;
const double _kRedline = 200;

/// 表盘扫过角度：135° 起、顺时针 270°，底部留数字读数窗口。
const double _kStartDeg = 135;
const double _kSweepDeg = 270;

/// 遥测曲线时间窗（秒）。
const int _kTelemetryWindowS = 60;

/// GPS 竞速仪表盘 Tab：GNSS 高频差分测速 + 赛车风格霓虹速度表。
///
/// 仅在 Tab 激活时订阅高频定位流并运行动画（切走即暂停省电）；页面不
/// 留历史数据——每次进入（切 Tab 回来或重开 App）所有统计从 0 开始，
/// 「重置」按钮同样全量归零；激活期间保持屏幕常亮。
class GpsSpeedScreen extends StatefulWidget {
  const GpsSpeedScreen({super.key, this.isActive = true});

  /// 是否为当前显示的 Tab。
  final bool isActive;

  @override
  State<GpsSpeedScreen> createState() => _GpsSpeedScreenState();
}

class _GpsSpeedScreenState extends State<GpsSpeedScreen>
    with SingleTickerProviderStateMixin {
  final GpsSpeedCalculator _calculator = GpsSpeedCalculator();
  StreamSubscription<GpsEvent>? _subscription;

  // 定位质量状态
  bool _permissionGranted = false;
  bool _permissionAsked = false;
  bool _bootstrapped = false;
  bool _subscribed = false;
  bool _hasFix = false;
  DateTime _lastFixTime = DateTime.now();
  double _accuracy = 0;
  int _satellites = 0;
  String _provider = '';
  final List<DateTime> _fixTimes = [];

  // 测速显示状态
  double _targetSpeed = 0; // 最新测速结果，表针追踪目标
  double _displaySpeed = 0; // 表针平滑逼近值
  double _maxSpeed = 0;
  double _avgSpeed = 0;
  double _gForce = 0;
  double _lateralG = 0; // 横向 G，右转为正
  double _distanceM = 0; // 本次会话累计行驶路程（米）
  double _maxFlash = 0; // 刷新最高速度时的爆发高光（1→0 衰减）

  // 遥测缓冲：(时间, 平滑速度)
  final List<(DateTime, double)> _telemetry = [];

  // G 球全程拖尾：(横向 G, 纵向 G)。G 盘是封闭圆形，轨迹不会超出量程，
  // 无需像速度轨迹那样做 60s 滚动窗口，本次页面会话内全程保留，
  // 仅在手动重置或切 Tab（全量重置）时清空。
  final List<(double, double)> _gTrail = [];

  /// 拖尾采样阈值：新点距上一记录点超过该值（合 G 空间）才追加，
  /// 过滤静止漂移与匀速巡航的重复点，控制点数规模。
  static const double _kGTrailMinStep = 0.04;

  /// 拖尾硬上限（极端长时间激烈驾驶的内存保护，超出丢弃最旧点）。
  static const int _kGTrailMaxPoints = 6000;

  // 逐帧动画
  Ticker? _ticker;
  Duration? _lastTick;
  double _elapsedS = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.isActive) {
      _bootstrapped = true;
      _activate();
    }
  }

  @override
  void didUpdateWidget(covariant GpsSpeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      widget.isActive ? _activate() : _deactivate();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _subscription?.cancel();
    GpsSpeedService.setKeepScreenOn(false);
    super.dispose();
  }

  /// Tab 激活：恢复指针动画与定位流；页面不留历史数据，
  /// 每次进入所有统计（最高/平均/路程/G 值/轨迹）全部从 0 开始。
  void _activate() {
    _lastTick = null;
    _resetAllStats();
    if (!_ticker!.isActive) _ticker!.start();
    if (_permissionGranted) {
      _subscribe();
      GpsSpeedService.setKeepScreenOn(true);
    }
    if (!_bootstrapped) {
      _bootstrapped = true;
      _bootstrap();
    }
  }

  /// Tab 切走：停动画、断定位流、取消屏幕常亮。
  void _deactivate() {
    if (_ticker!.isActive) _ticker!.stop();
    _subscription?.cancel();
    _subscription = null;
    if (mounted) setState(() => _subscribed = false);
    GpsSpeedService.setKeepScreenOn(false);
  }

  Future<void> _bootstrap() async {
    var granted = await GpsSpeedService.requestPermission();
    if (!granted) {
      // 首次误拒后再给一次机会；永久拒绝仍为 false，走引导设置页 UI
      granted = await GpsSpeedService.requestPermission();
    }
    if (!mounted || !widget.isActive) return;
    setState(() {
      _permissionGranted = granted;
      _permissionAsked = true;
    });
    if (granted) {
      GpsSpeedService.setKeepScreenOn(true);
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = GpsSpeedService.events().listen(
      _onEvent,
      onError: (Object e) {
        debugPrint('[GpsSpeed] 测速流出错: $e');
        if (mounted) setState(() => _subscribed = false);
      },
      onDone: () {
        if (mounted) setState(() => _subscribed = false);
      },
    );
    if (mounted) setState(() => _subscribed = true);
  }

  void _onEvent(GpsEvent event) {
    if (event is GpsStatusEvent) {
      if (!mounted) return;
      setState(() {
        if (event.satellites != null) _satellites = event.satellites!;
        if (event.provider != null) _provider = event.provider!;
      });
      return;
    }
    if (event is GpsFixEvent) {
      final reading = _calculator.process(event.fix);
      final now = DateTime.now();

      // 5s 滑动窗口统计采样频率（展示用 _sampleHz getter）
      _fixTimes.add(now);
      while (_fixTimes.isNotEmpty && now.difference(_fixTimes.first).inSeconds > 5) {
        _fixTimes.removeAt(0);
      }

      _telemetry.add((now, reading?.speedKmh ?? 0));
      while (_telemetry.isNotEmpty &&
          now.difference(_telemetry.first.$1).inSeconds > _kTelemetryWindowS) {
        _telemetry.removeAt(0);
      }

      if (!mounted) return;
      setState(() {
        _hasFix = true;
        _lastFixTime = now;
        _accuracy = event.fix.accuracy;
        _provider = _provider.isEmpty ? 'gnss' : _provider;
        if (reading != null) {
          _targetSpeed = reading.speedKmh;
          _avgSpeed = reading.avgKmh;
          _gForce = reading.gForce;
          _lateralG = reading.lateralG;
          _distanceM = reading.totalDistanceM;

          // G 球拖尾：与上一记录点距离超过阈值才记录，全程保留
          final last = _gTrail.isEmpty ? null : _gTrail.last;
          final dLat = _lateralG - (last?.$1 ?? 0);
          final dLon = _gForce - (last?.$2 ?? 0);
          if (last == null ||
              dLat * dLat + dLon * dLon >
                  _kGTrailMinStep * _kGTrailMinStep) {
            _gTrail.add((_lateralG, _gForce));
            if (_gTrail.length > _kGTrailMaxPoints) {
              _gTrail.removeAt(0);
            }
          }

          if (reading.speedKmh > _maxSpeed + 0.5 && reading.speedKmh >= 5) {
            _maxSpeed = reading.speedKmh;
            _maxFlash = 1.0;
          }
        }
      });
    }
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == null
        ? 1 / 60
        : (elapsed - _lastTick!).inMicroseconds / 1e6;
    _lastTick = elapsed;
    _elapsedS = elapsed.inMicroseconds / 1e6;

    // 信号丢失超过 6s：表针归零，避免展示过期速度
    if (_hasFix && DateTime.now().difference(_lastFixTime).inSeconds >= 6) {
      _targetSpeed = 0;
    }

    // 表针指数逼近，时间常数 100ms → 赛用级响应又不抖动
    final k = 1.0 - math.exp(-dt / 0.10);
    _displaySpeed += (_targetSpeed - _displaySpeed) * k;
    if (_targetSpeed == 0 && _displaySpeed < 0.05) _displaySpeed = 0;
    if (_maxFlash > 0) _maxFlash = math.max(0.0, _maxFlash - dt * 1.2);

    if (mounted) setState(() {});
  }

  /// 重置按钮：页面所有统计数据归零。
  void _resetStats() {
    setState(_resetAllStats);
  }

  /// 全量重置：最高/平均/路程/G 值/采样率/遥测轨迹清空。
  /// 进入页面（Tab 激活）与手动重置共用。
  void _resetAllStats() {
    _calculator.resetStats();
    _maxSpeed = 0;
    _avgSpeed = 0;
    _distanceM = 0;
    _gForce = 0;
    _lateralG = 0;
    _maxFlash = 0;
    _fixTimes.clear();
    _telemetry.clear();
    _gTrail.clear();
  }

  bool get _signalStale =>
      _hasFix && DateTime.now().difference(_lastFixTime).inSeconds >= 6;

  /// 5s 滑动窗口内的采样频率（Hz）。
  double get _sampleHz {
    if (_fixTimes.length < 2) return 0;
    final windowS =
        _fixTimes.last.difference(_fixTimes.first).inMilliseconds / 1000.0;
    return windowS > 0 ? _fixTimes.length / windowS : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07090D),
      body: SafeArea(
        child: !_permissionAsked
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : !_permissionGranted
                ? _buildPermissionDenied()
                : _buildDashboard(),
      ),
    );
  }

  // ==================== 主仪表布局 ====================

  Widget _buildDashboard() {
    return Column(
      children: [
        _buildTopBar(),
        _buildStatusChips(),
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // 不设上限，表盘吃满剩余空间成为页面主体
                final side = math.min(constraints.maxWidth, constraints.maxHeight);
                return SizedBox(
                  width: side,
                  height: side,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _SpeedometerPainter(
                          speed: _displaySpeed,
                          maxRecorded: _maxSpeed,
                          pulse: _elapsedS,
                          maxFlash: _maxFlash,
                          signalStale: _signalStale,
                        ),
                      ),
                      _buildDigitalReadout(side),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        _buildGBall(),
        _buildTelemetry(),
        _buildBottomStats(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          const SizedBox(width: 48),
          const Expanded(
            child: Text(
              'GPS 竞速仪表',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: TextButton(
              onPressed: _resetStats,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
              child: const Text(
                '重置',
                style: TextStyle(color: Color(0xFF8A93A6), fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 状态区：第一行为定位状态，第二行为卫星/精度/采样率三等分指标条，
  /// 等分宽度自适应屏幕与系统字体缩放，窄屏大字体下不会溢出。
  Widget _buildStatusChips() {
    final locked = _hasFix && !_signalStale;
    final statusColor = _subscribed
        ? (locked ? const Color(0xFF00E676) : const Color(0xFFFFC400))
        : const Color(0xFFFF5252);
    final statusText = _subscribed
        ? (locked ? 'GNSS 已锁定' : '搜索卫星中…')
        : '定位流已断开';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              _statusDot(statusColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_provider.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '源: $_provider',
                  style: const TextStyle(color: Color(0xFF5A6578), fontSize: 11),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141A26),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF232B3C)),
            ),
            child: Row(
              children: [
                _buildMetricCell(
                  Icons.satellite_alt,
                  '卫星',
                  _satellites > 0 ? '$_satellites 颗' : '—',
                ),
                _metricDivider(),
                _buildMetricCell(
                  Icons.gps_fixed,
                  '精度',
                  _accuracy > 0 ? '±${_accuracy.toStringAsFixed(1)}m' : '—',
                ),
                _metricDivider(),
                _buildMetricCell(
                  Icons.speed,
                  '采样率',
                  '${_sampleHz.toStringAsFixed(1)} Hz',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricDivider() =>
      Container(width: 1, height: 30, color: const Color(0xFF232B3C));

  Widget _buildMetricCell(IconData icon, String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 11, color: const Color(0xFF8A93A6)),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF8A93A6),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // FittedBox 兜底：极端长值时缩放而不是溢出
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  color: Color(0xFFB8C0D0),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
      ),
    );
  }

  /// 数字读数：主体速度值放大展示，置于表盘 270° 开口的下方空区，
  /// 不遮挡表盘中心；REDLINE 警示与单位同行，进入红线时出现。
  Widget _buildDigitalReadout(double side) {
    final fraction = (_displaySpeed / _kGaugeMax).clamp(0.0, 1.0);
    final color = fraction >= _kRedline / _kGaugeMax
        ? const Color(0xFFFF1744)
        : fraction >= 0.6
            ? const Color(0xFFFFEA00)
            : Colors.white;
    final inRedline = fraction >= _kRedline / _kGaugeMax;

    return Align(
      alignment: const Alignment(0, 0.58),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _displaySpeed.round().toString(),
              style: TextStyle(
                fontSize: side * 0.22,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: color,
                fontFeatures: [FontFeature.tabularFigures()],
                shadows: [
                  Shadow(
                    color: color.withValues(alpha: 0.45),
                    blurRadius: side * 0.08,
                  ),
                ],
              ),
            ),
            SizedBox(height: side * 0.012),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'km/h',
                  style: TextStyle(
                    fontSize: side * 0.045,
                    color: const Color(0xFF8A93A6),
                    letterSpacing: side * 0.016,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (inRedline) ...[
                  SizedBox(width: side * 0.03),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: side * 0.025,
                      vertical: side * 0.007,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF1744).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(side * 0.026),
                      border: Border.all(
                        color: const Color(0xFFFF1744).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      'REDLINE',
                      style: TextStyle(
                        color: const Color(0xFFFF1744),
                        fontSize: side * 0.026,
                        fontWeight: FontWeight.w900,
                        letterSpacing: side * 0.006,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// G 球卡片：左侧圆形 G-G 球（横向 G 左右、纵向 G 上下），
  /// 右侧当前行驶路程大读数与横/纵 G 数值。
  Widget _buildGBall() {
    final latColor = _gColor(_lateralG.abs());
    final lonColor = _gColor(_gForce.abs());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        height: 120,
        padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1119),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1C2333)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              height: 104,
              child: CustomPaint(
                painter: GBallPainter(
                  latG: _lateralG,
                  lonG: _gForce,
                  trail: _gTrail,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '当前行驶路程',
                    style: TextStyle(
                      color: Color(0xFF5A6578),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _formatDistance(_distanceM),
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _distanceM >= 1000 ? 'km' : 'm',
                        style: const TextStyle(
                          color: Color(0xFF5A6578),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '横 ${_lateralG >= 0 ? '+' : ''}${_lateralG.toStringAsFixed(2)}G',
                        style: TextStyle(
                          color: latColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '纵 ${_gForce >= 0 ? '+' : ''}${_gForce.toStringAsFixed(2)}G',
                        style: TextStyle(
                          color: lonColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 按 |G| 分档取色：<0.5 绿，<1.0 黄，其余红。
  Color _gColor(double absG) {
    if (absG < 0.5) return const Color(0xFF00E676);
    if (absG < 1.0) return const Color(0xFFFFEA00);
    return const Color(0xFFFF1744);
  }

  /// 路程格式化：≥1km 显示公里（两位小数），否则显示整米。
  String _formatDistance(double m) {
    if (m >= 1000) return (m / 1000).toStringAsFixed(2);
    return m.toStringAsFixed(0);
  }

  /// 60 秒实时速度轨迹（压缩高度，把空间让给表盘主体）。
  Widget _buildTelemetry() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 84,
        padding: const EdgeInsets.fromLTRB(12, 7, 12, 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1119),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1C2333)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '实时速度轨迹 · 60s',
              style: TextStyle(color: Color(0xFF5A6578), fontSize: 10, letterSpacing: 1),
            ),
            Expanded(
              child: CustomPaint(
                size: Size.infinite,
                painter: _TelemetryPainter(samples: _telemetry, maxRecorded: _maxSpeed),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部统计：单行紧凑布局。
  Widget _buildBottomStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          _buildSlimStat('最高', _maxSpeed, const Color(0xFFFF6B35)),
          const SizedBox(width: 8),
          _buildSlimStat('平均', _avgSpeed, const Color(0xFF00E5FF)),
          const SizedBox(width: 8),
          _buildSlimStat('当前', _displaySpeed, const Color(0xFF00E676)),
        ],
      ),
    );
  }

  Widget _buildSlimStat(String label, double value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(color: color.withValues(alpha: 0.85), fontSize: 11),
            ),
            const SizedBox(width: 6),
            Text(
              value.toStringAsFixed(0),
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 2),
            Text(
              'km/h',
              style: TextStyle(color: color.withValues(alpha: 0.55), fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 权限被拒视图 ====================

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: const Color(0xFFFF1744).withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFFF1744).withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(Icons.speed, color: Color(0xFFFF1744), size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              '需要定位权限',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '测速依赖 GPS 实时定位，请在系统设置中\n允许本应用获取位置信息',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8A93A6), fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => GpsSpeedService.openAppSettings(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B30),
                foregroundColor: Colors.white,
              ),
              child: const Text('打开系统设置'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _bootstrap,
              child: const Text('重新尝试', style: TextStyle(color: Color(0xFF8A93A6))),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 表盘绘制 ====================

/// 赛车风格速度表：霓虹渐变弧、红线区脉冲辉光、旋转装饰环、
/// 刻度数字、峰值标记与赛车指针。
class _SpeedometerPainter extends CustomPainter {
  _SpeedometerPainter({
    required this.speed,
    required this.maxRecorded,
    required this.pulse,
    required this.maxFlash,
    required this.signalStale,
  });

  final double speed;
  final double maxRecorded;

  /// 页面累计运行秒数，驱动脉冲/旋转动画相位。
  final double pulse;

  /// 刷新最高速度高光强度（1→0）。
  final double maxFlash;
  final bool signalStale;

  static const _trackColor = Color(0xFF1A2130);
  static const _redlineColor = Color(0xFFFF1744);
  static const List<Color> _sweepColors = [
    Color(0xFF00E5FF), // 青
    Color(0xFF00E676), // 绿
    Color(0xFFFFEA00), // 黄
    Color(0xFFFF6B35), // 橙
    Color(0xFFFF1744), // 红
  ];

  double _angleFor(double value) =>
      (_kStartDeg + _kSweepDeg * (value / _kGaugeMax).clamp(0.0, 1.0)) * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    _paintDialBackground(canvas, center, radius);
    _paintRedlineBand(canvas, center, radius);
    _paintTrackAndProgress(canvas, center, radius);
    _paintTicks(canvas, center, radius);
    _paintPeakMarker(canvas, center, radius);
    _paintNeedle(canvas, center, radius);
    _paintHub(canvas, center, radius);
  }

  /// 表盘底色、外圈与旋转装饰环。
  void _paintDialBackground(Canvas canvas, Offset center, double radius) {
    // 深色表底 + 中心微光
    canvas.drawCircle(
      center,
      radius * 0.985,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFF141B29), const Color(0xFF0A0E16)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    // 外沿细环
    canvas.drawCircle(
      center,
      radius * 0.985,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF2A3242),
    );

    // 旋转虚线装饰环：转速越快旋转越快，营造"涡轮"感
    final dashRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF3A4356);
    final spin = pulse * (0.15 + 0.9 * (speed / _kGaugeMax).clamp(0.0, 1.0));
    final dashCount = 48;
    final dashArc = 2 * math.pi / dashCount * 0.45;
    for (var i = 0; i < dashCount; i++) {
      final start = spin * 2 * math.pi + i * 2 * math.pi / dashCount;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.995),
        start,
        dashArc,
        false,
        dashRing,
      );
    }

    // 表盘内部径向高光（信号丢失时转为琥珀色警示）
    final glowColor = signalStale
        ? const Color(0xFFFFC400).withValues(alpha: 0.05)
        : const Color(0xFF00E5FF).withValues(alpha: 0.05);
    canvas.drawCircle(
      center,
      radius * 0.72,
      Paint()
        ..shader = RadialGradient(
          colors: [glowColor, Colors.transparent],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 0.72)),
    );
  }

  /// 红线区（200-260）底带，速度越高脉冲越急促。
  void _paintRedlineBand(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius * 0.86);
    final bandWidth = radius * 0.115;
    final pulseAlpha =
        0.30 + 0.18 * (0.5 + 0.5 * math.sin(pulse * 2 * math.pi * (1 + 6 * (speed / _kGaugeMax))));

    // 辉光层
    canvas.drawArc(
      rect,
      _angleFor(_kRedline),
      _kSweepDeg * (1 - _kRedline / _kGaugeMax) * math.pi / 180,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bandWidth + 8
        ..color = _redlineColor.withValues(alpha: pulseAlpha * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // 底带
    canvas.drawArc(
      rect,
      _angleFor(_kRedline),
      _kSweepDeg * (1 - _kRedline / _kGaugeMax) * math.pi / 180,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bandWidth
        ..color = _redlineColor.withValues(alpha: pulseAlpha * 0.5),
    );
  }

  /// 轨道弧与当前速度渐变弧（霓虹辉光）。
  void _paintTrackAndProgress(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius * 0.86);
    final strokeWidth = radius * 0.115;
    final startRad = _kStartDeg * math.pi / 180;
    final sweepRad = _kSweepDeg * math.pi / 180;

    // 轨道
    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = _trackColor,
    );

    final fraction = (speed / _kGaugeMax).clamp(0.0, 1.0);
    if (fraction <= 0) return;
    final activeSweep = sweepRad * fraction;

    final shader = SweepGradient(
      startAngle: startRad,
      endAngle: startRad + sweepRad,
      colors: _sweepColors,
    ).createShader(rect);

    // 外层辉光（模糊放大）
    canvas.drawArc(
      rect,
      startRad,
      activeSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 9
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    // 主体弧
    canvas.drawArc(
      rect,
      startRad,
      activeSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
    // 弧端亮点
    final endAngle = startRad + activeSweep;
    canvas.drawCircle(
      Offset(
        center.dx + math.cos(endAngle) * radius * 0.86,
        center.dy + math.sin(endAngle) * radius * 0.86,
      ),
      strokeWidth * 0.30,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }

  /// 刻度：小刻度每 10、大刻度每 20（带数字），红线区后数字转红。
  void _paintTicks(Canvas canvas, Offset center, double radius) {
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (var v = 0; v <= _kGaugeMax; v += 10) {
      final major = v % 20 == 0;
      final angle = _angleFor(v.toDouble());
      final inRedline = v >= _kRedline;
      final color = inRedline
          ? _redlineColor.withValues(alpha: 0.9)
          : const Color(0xFFB8C0D0);

      tickPaint
        ..strokeWidth = major ? 3 : 1.5
        ..color = major ? color : color.withValues(alpha: 0.45);
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * radius * (major ? 0.72 : 0.75),
          center.dy + math.sin(angle) * radius * (major ? 0.72 : 0.75),
        ),
        Offset(
          center.dx + math.cos(angle) * radius * 0.80,
          center.dy + math.sin(angle) * radius * 0.80,
        ),
        tickPaint,
      );

      if (major) {
        final labelRadius = radius * 0.60;
        final tp = TextPainter(
          text: TextSpan(
            text: '$v',
            style: TextStyle(
              color: inRedline
                  ? _redlineColor
                  : const Color(0xFF8A93A6),
              fontSize: radius * 0.072,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            center.dx + math.cos(angle) * labelRadius - tp.width / 2,
            center.dy + math.sin(angle) * labelRadius - tp.height / 2,
          ),
        );
      }
    }
  }

  /// 历史最高速度峰值标记（熄火后仍保留的"最速刻度"）。
  void _paintPeakMarker(Canvas canvas, Offset center, double radius) {
    if (maxRecorded < 1) return;
    final angle = _angleFor(maxRecorded);
    final glow = math.max(maxFlash, 0.25);
    canvas.drawLine(
      Offset(
        center.dx + math.cos(angle) * radius * 0.82,
        center.dy + math.sin(angle) * radius * 0.82,
      ),
      Offset(
        center.dx + math.cos(angle) * radius * 0.94,
        center.dy + math.sin(angle) * radius * 0.94,
      ),
      Paint()
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFFEA00).withValues(alpha: glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 8 * maxFlash),
    );
  }

  /// 赛车指针：辉光尾迹 + 锥形针体。
  void _paintNeedle(Canvas canvas, Offset center, double radius) {
    final angle = _angleFor(speed);
    final fraction = (speed / _kGaugeMax).clamp(0.0, 1.0);
    final needleColor = fraction >= _kRedline / _kGaugeMax
        ? _redlineColor
        : fraction >= 0.6
            ? const Color(0xFFFFEA00)
            : const Color(0xFF00E676);
    final dir = Offset(math.cos(angle), math.sin(angle));

    // 辉光尾迹
    canvas.drawLine(
      center - dir * radius * 0.14,
      center + dir * radius * 0.68,
      Paint()
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = needleColor.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 锥形针体
    final tip = center + dir * radius * 0.70;
    final tail = center - dir * radius * 0.16;
    final perp = Offset(-dir.dy, dir.dx);
    final needlePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(center.dx + perp.dx * 3.2, center.dy + perp.dy * 3.2)
      ..lineTo(tail.dx, tail.dy)
      ..lineTo(center.dx - perp.dx * 3.2, center.dy - perp.dy * 3.2)
      ..close();
    canvas.drawPath(
      needlePath,
      Paint()
        ..shader = LinearGradient(
          colors: [needleColor.withValues(alpha: 0.7), Colors.white],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(Rect.fromPoints(tail, tip)),
    );
  }

  /// 中心轴帽。
  void _paintHub(Canvas canvas, Offset center, double radius) {
    final hubRadius = radius * 0.085;
    canvas.drawCircle(
      center,
      hubRadius,
      Paint()
        ..shader = RadialGradient(colors: [
          const Color(0xFF4A5568),
          const Color(0xFF141A26),
        ]).createShader(Rect.fromCircle(center: center, radius: hubRadius)),
    );
    canvas.drawCircle(
      center,
      hubRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF5A6578),
    );
    canvas.drawCircle(
      center,
      hubRadius * 0.35,
      Paint()..color = const Color(0xFFB8C0D0),
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter old) =>
      old.speed != speed ||
      old.maxRecorded != maxRecorded ||
      old.pulse != pulse ||
      old.maxFlash != maxFlash ||
      old.signalStale != signalStale;
}

// ==================== G 球绘制 ====================

/// 圆形 G-G 球：球心位置 = (横向 G, 纵向 G)，
/// 上加速、下制动，左转球向左、右转球向右；
/// 1.0G / 2.0G 两档同心环，纯绿色小球。
/// 附全程拖尾：本次会话内所有 G 点连成轨迹（盘为封闭圆形不会超出，
/// 无需滚动窗口），重置或切 Tab 才清空。
class GBallPainter extends CustomPainter {
  GBallPainter({
    required this.latG,
    required this.lonG,
    required this.trail,
  });

  final double latG;
  final double lonG;

  /// 全程拖尾采样：(横向 G, 纵向 G)，会话内持续累计。
  final List<(double, double)> trail;

  static const double _range = 2.0;

  /// G 值 → 盘面坐标：径向 clamp。单轴超出 2.0G 或合 G 超出量程时，
  /// 保持方向不变、把向量整体缩到圆边上，确保任何点都不会画出圆外。
  /// （旧实现两轴各自独立 clamp，对角方向的合向量会落到 √2 倍半径处越界。）
  Offset _mapG(double latG, double lonG, Offset center, double radius) {
    var nx = latG / _range;
    var ny = -lonG / _range; // 屏幕向上为加速
    final mag = math.sqrt(nx * nx + ny * ny);
    if (mag > 1.0) {
      nx /= mag;
      ny /= mag;
    }
    return Offset(center.dx + nx * radius, center.dy + ny * radius);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.92;

    _paintPad(canvas, center, radius);
    _paintTrail(canvas, center, radius);
    _paintBall(canvas, center, radius);
  }

  /// 圆形垫盘：底色、同心环、十字线与上下方位标签。
  void _paintPad(Canvas canvas, Offset center, double radius) {
    // 深色底盘 + 中心微光
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFF141B29), const Color(0xFF0A0E16)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // 同心环：1.0G 细环，2.0G（外沿）实线
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF1C2333);
    canvas.drawCircle(
      center,
      radius * (1.0 / _range),
      ring,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF2A3242),
    );

    // 十字线（横纵零轴）：虚线
    _drawDashedLine(
      canvas,
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      ring,
    );
    _drawDashedLine(
      canvas,
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      ring,
    );

    // 方位标签：上加速、下制动
    for (final (label, dy) in [('加速', -1.0), ('制动', 1.0)]) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF5A6578),
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          center.dx - tp.width / 2,
          center.dy + dy * (radius - 1) - tp.height / 2 * (dy + 1) - (dy < 0 ? 1 : 0),
        ),
      );
    }
  }

  /// 虚线段：dash 3px、间隔 3px，沿直线均匀绘制。
  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLen = 3.0;
    const gapLen = 3.0;
    final total = (end - start).distance;
    if (total <= 0) return;
    final unit = (end - start) / total;
    for (var d = 0.0; d < total; d += dashLen + gapLen) {
      final segEnd = math.min(d + dashLen, total);
      canvas.drawLine(start + unit * d, start + unit * segEnd, paint);
    }
  }

  /// 全程拖尾：历史 G 点连成青色半透明轨迹，越靠近当前点越亮。
  void _paintTrail(Canvas canvas, Offset center, double radius) {
    if (trail.isEmpty) return;

    final path = Path();
    final first = _mapG(trail.first.$1, trail.first.$2, center, radius);
    path.moveTo(first.dx, first.dy);
    for (final p in trail.skip(1)) {
      final o = _mapG(p.$1, p.$2, center, radius);
      path.lineTo(o.dx, o.dy);
    }

    // 底层辉光 + 主体线
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.45),
    );

    // 最近一小段渐亮（越接近当前球越亮），表现"刚刚经历的 G 值"
    const recentCount = 24;
    final recent = trail.length < 2
        ? const <(double, double)>[]
        : trail.sublist(math.max(0, trail.length - recentCount));
    for (var i = 1; i < recent.length; i++) {
      final a = _mapG(recent[i - 1].$1, recent[i - 1].$2, center, radius);
      final b = _mapG(recent[i].$1, recent[i].$2, center, radius);
      final t = i / math.max(1, recent.length - 1);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + t * 1.5
          ..color = Color.lerp(
            const Color(0xFF00E5FF).withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0.85),
            t,
          )!,
      );
    }
  }

  /// G 球本体：位置映射 + 纯色绿色小球，无辉光。
  void _paintBall(Canvas canvas, Offset center, double radius) {
    final pos = _mapG(latG, lonG, center, radius * 0.96);

    final ballRadius = radius * 0.10;

    // 球体：纯绿色实心圆
    canvas.drawCircle(
      pos,
      ballRadius,
      Paint()..color = const Color(0xFF00E676),
    );
  }

  @override
  bool shouldRepaint(covariant GBallPainter old) =>
      old.latG != latG ||
      old.lonG != lonG ||
      old.trail.length != trail.length;
}

// ==================== 遥测曲线绘制 ====================

/// 最近 60s 速度轨迹：青色霓虹曲线 + 渐变填充，纵轴自适应量程。
class _TelemetryPainter extends CustomPainter {
  _TelemetryPainter({required this.samples, required this.maxRecorded});

  final List<(DateTime, double)> samples;
  final double maxRecorded;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) {
      _paintHint(canvas, size);
      return;
    }

    // 纵轴量程：至少 60，按最高速度向上取整到 60 的倍数
    final yMax = math.max(60.0, (maxRecorded / 60).ceil() * 60.0);
    final now = samples.last.$1;

    // 网格线
    final grid = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFF1C2333);
    for (final f in [1 / 3, 2 / 3]) {
      final y = size.height * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final points = <Offset>[];
    for (final (t, v) in samples) {
      final ageS = now.difference(t).inMilliseconds / 1000.0;
      final x = size.width * (1 - ageS / _kTelemetryWindowS);
      final y = size.height * (1 - (v / yMax).clamp(0.0, 1.0));
      points.add(Offset(x, y));
    }

    // 曲线下渐变填充
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath.lineTo(points.last.dx, size.height);
    fillPath.close();
    final fillRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF00E5FF).withValues(alpha: 0.28),
            const Color(0xFF00E5FF).withValues(alpha: 0.0),
          ],
        ).createShader(fillRect),
    );

    // 辉光曲线 + 主体曲线
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      linePath.lineTo(p.dx, p.dy);
    }
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, glowPaint);
    canvas.drawPath(
      linePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF00E5FF)
        ..strokeJoin = StrokeJoin.round,
    );

    // 当前值端点
    canvas.drawCircle(
      points.last,
      3,
      Paint()
        ..color = Colors.white
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  void _paintHint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: '行驶后此处显示速度轨迹',
        style: TextStyle(color: Color(0xFF3A4356), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        size.width / 2 - tp.width / 2,
        size.height / 2 - tp.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _TelemetryPainter old) =>
      old.samples != samples || old.maxRecorded != maxRecorded;
}
