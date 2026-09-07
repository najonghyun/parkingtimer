// Basic smoke test: the app boots and shows the idle home screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:parking_timer/main.dart';

void main() {
  testWidgets('앱이 정상적으로 기동되고 대기 화면을 보여준다', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ParkingTimerApp());
    // Notification plugin platform channels aren't mocked in widget tests,
    // so bootstrap's 5s defensive timeout has to actually elapse before the
    // loading spinner clears. The home screen also keeps a 1s
    // Timer.periodic ticking, so pumpAndSettle never quiesces — pump a
    // bounded number of frames instead.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('주차 타이머'), findsOneWidget);
    expect(find.text('🅿️ 지금 주차했어요'), findsOneWidget);
  });
}
