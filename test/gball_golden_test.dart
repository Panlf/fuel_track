// G 值球可视化验证：渲染 GBallPainter 输出 golden PNG，用于人工核对样式。
// 运行：flutter test --update-goldens test/gball_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fuel_track/screens/gps_speed_screen.dart';

void main() {
  testWidgets('G 值球 golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(120, 120));
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(360, 360);
    addTearDown(tester.view.reset);

    // 模拟一次带 G 值的行驶：纵 G 1.07（参考图数值）、横向微偏，含拖尾
    final trail = <(double, double)>[
      (0.0, 0.0), (0.05, 0.15), (0.1, 0.3), (0.18, 0.45),
      (0.22, 0.6), (0.15, 0.75), (0.08, 0.9), (0.12, 1.0), (0.1, 1.07),
    ];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ColoredBox(
          color: const Color(0xFF0D1119),
          child: Center(
            child: SizedBox(
              width: 104,
              height: 104,
              child: CustomPaint(
                painter: GBallPainter(
                  latG: 0.10,
                  lonG: 1.07,
                  trail: trail,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await expectLater(
      find.byType(CustomPaint),
      matchesGoldenFile('gball_preview.png'),
    );
  });
}
