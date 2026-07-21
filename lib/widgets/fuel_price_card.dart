import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/fuel_price_service.dart';

class FuelPriceCard extends StatefulWidget {
  final int refreshKey;

  const FuelPriceCard({super.key, this.refreshKey = 0});

  @override
  State<FuelPriceCard> createState() => _FuelPriceCardState();
}

class _FuelPriceCardState extends State<FuelPriceCard> {
  FuelPrice? _fuelPrice;
  String? _currentProvince;
  bool _isLoading = false;
  bool _isExpanded = false;
  bool _hasLoaded = false;

  @override
  void didUpdateWidget(covariant FuelPriceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshKey != oldWidget.refreshKey && _isExpanded) {
      _loadFuelPrice(forceRefresh: true);
    }
  }

  Future<void> _loadFuelPrice({bool forceRefresh = false, bool useCurrentProvince = false}) async {
    setState(() => _isLoading = true);

    try {
      String? province;

      if (useCurrentProvince) {
        // 手动切换：直接用当前省份，不定位
        province = _currentProvince;
      } else {
        // 优先定位，定位失败才用缓存
        province = await FuelPriceService.detectProvinceFromLocation();
        if (province != null) {
          await FuelPriceService.setSelectedProvince(province);
        } else {
          province = await FuelPriceService.getSelectedProvince();
        }
      }

      if (province == null) {
        setState(() {
          _currentProvince = null;
          _isLoading = false;
        });
        return;
      }

      final price = await FuelPriceService.fetchFuelPrice(province, forceRefresh: forceRefresh || useCurrentProvince);
      if (mounted) {
        setState(() {
          _currentProvince = province;
          _fuelPrice = price;
          _isLoading = false;
          _hasLoaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasLoaded = true;
        });
      }
    }
  }

  void _toggleExpand() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded && !_hasLoaded) {
      _loadFuelPrice();
    }
  }

  void _showProvinceSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '选择省份',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                '定位获取当前省份',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: FuelPriceService.provinces.length,
                itemBuilder: (ctx, index) {
                  final province = FuelPriceService.provinces[index];
                  final isSelected = province == _currentProvince;
                  return ListTile(
                    leading: Icon(
                      Icons.location_on,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      size: 20,
                    ),
                    title: Text(
                      province,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppColors.primary : AppColors.textPrimary,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await FuelPriceService.setSelectedProvince(province);
                      _currentProvince = province;
                      _loadFuelPrice(useCurrentProvince: true);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          GestureDetector(
            onTap: _toggleExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.local_gas_station,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '今日油价',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (_currentProvince != null && !_isExpanded) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _currentProvince!,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  if (_currentProvince != null)
                    GestureDetector(
                      onTap: _showProvinceSelector,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              color: AppColors.primary,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _currentProvince!,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down,
                              color: AppColors.primary,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (_currentProvince == null)
                    _buildSelectProvince()
                  else if (_fuelPrice != null)
                    _buildPriceGrid()
                  else
                    _buildErrorState(),
                ],
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectProvince() {
    return GestureDetector(
      onTap: _showProvinceSelector,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.location_searching,
                color: AppColors.primary.withValues(alpha: 0.5),
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                '点击选择省份查看油价',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '或开启定位自动获取',
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceGrid() {
    final now = DateTime.now();
    final fetchTime = _fuelPrice!.fetchTime;
    final isToday = fetchTime.year == now.year &&
        fetchTime.month == now.month &&
        fetchTime.day == now.day;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildPriceItem('92号', _fuelPrice!.p92, AppColors.chartBlue),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPriceItem('95号', _fuelPrice!.p95, AppColors.chartOrange),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildPriceItem('98号', _fuelPrice!.p98, AppColors.chartPurple),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildPriceItem('0号柴油', _fuelPrice!.p0, AppColors.chartGreen),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isToday ? Icons.check_circle_outline : Icons.access_time,
              size: 12,
              color: AppColors.textSecondary.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              isToday ? '今日已更新' : '点击刷新获取最新',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPriceItem(String label, double price, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '¥${price.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Text(
            '/升',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return GestureDetector(
      onTap: _loadFuelPrice,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 32,
              ),
              const SizedBox(height: 8),
              const Text(
                '获取油价失败',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '点击重试',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
