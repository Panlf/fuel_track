import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_track/main.dart';

void main() {
  testWidgets('应用启动后应展示概览页底部导航', (WidgetTester tester) async {
    await tester.pumpWidget(const FuelTrackApp());
    // 等待首页异步加载完成（测试环境下数据库不可用，页面降级为空态）
    await tester.pumpAndSettle();

    expect(find.text('概览'), findsOneWidget);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('车库'), findsOneWidget);
  });
}
