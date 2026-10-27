import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/widgets/shared_navy_header.dart';

void main() {
  group('getGreeting tests', () {
    test('Chào buổi sáng (05:00 - 10:59)', () {
      expect(getGreeting(DateTime(2026, 10, 27, 5, 0)), 'Chào buổi sáng');
      expect(getGreeting(DateTime(2026, 10, 27, 8, 30)), 'Chào buổi sáng');
      expect(getGreeting(DateTime(2026, 10, 27, 10, 59)), 'Chào buổi sáng');
    });

    test('Chào buổi trưa (11:00 - 12:59)', () {
      expect(getGreeting(DateTime(2026, 10, 27, 11, 0)), 'Chào buổi trưa');
      expect(getGreeting(DateTime(2026, 10, 27, 12, 0)), 'Chào buổi trưa');
      expect(getGreeting(DateTime(2026, 10, 27, 12, 59)), 'Chào buổi trưa');
    });

    test('Chào buổi chiều (13:00 - 17:59)', () {
      expect(getGreeting(DateTime(2026, 10, 27, 13, 0)), 'Chào buổi chiều');
      expect(getGreeting(DateTime(2026, 10, 27, 15, 30)), 'Chào buổi chiều');
      expect(getGreeting(DateTime(2026, 10, 27, 17, 58)), 'Chào buổi chiều');
      expect(getGreeting(DateTime(2026, 10, 27, 17, 59)), 'Chào buổi chiều');
    });

    test('Chào buổi tối (18:00 - 04:59)', () {
      expect(getGreeting(DateTime(2026, 10, 27, 18, 0)), 'Chào buổi tối');
      expect(getGreeting(DateTime(2026, 10, 27, 21, 0)), 'Chào buổi tối');
      expect(getGreeting(DateTime(2026, 10, 27, 23, 59)), 'Chào buổi tối');
      expect(getGreeting(DateTime(2026, 10, 27, 0, 0)), 'Chào buổi tối');
      expect(getGreeting(DateTime(2026, 10, 27, 4, 59)), 'Chào buổi tối');
    });
  });

  group('SharedNavyHeader & GreetingText Widget tests', () {
    testWidgets('GreetingText renders current greeting', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GreetingText(),
          ),
        ),
      );

      final current = getGreeting();
      expect(find.text(current), findsOneWidget);
    });

    testWidgets('SharedNavyHeader renders title and employee badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SharedNavyHeader(
              title: 'Chấm công',
            ),
          ),
        ),
      );

      expect(find.text('Chấm công'), findsOneWidget);
      expect(find.text('Nhân viên'), findsOneWidget);
    });

    testWidgets('SharedNavyHeader renders custom trailing when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SharedNavyHeader(
              title: 'Bảng công',
              showSubtitle: false,
              customTrailing: Text('Tháng 10/2026'),
            ),
          ),
        ),
      );

      expect(find.text('Bảng công'), findsOneWidget);
      expect(find.text('Tháng 10/2026'), findsOneWidget);
    });
  });
}
