import 'package:flutter_test/flutter_test.dart';
import 'package:fuel_track/main.dart';

void main() {
  testWidgets('App should render', (WidgetTester tester) async {
    await tester.pumpWidget(const FuelTrackApp());
    expect(find.text('油耗记录'), findsOneWidget);
  });
}
