import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/main.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/app_controller.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/models.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/local_store.dart';

class MemoryStore implements DataStore {
  AppData data = AppData();
  @override
  Future<AppData> load() async => data;
  @override
  Future<void> save(AppData value) async {
    data = value;
  }
}

void main() {
  testWidgets('First launch explains local mode and offers admin setup', (
    tester,
  ) async {
    await tester.pumpWidget(
      AttendanceApp(controller: AppController(MemoryStore())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thiết lập lần đầu'), findsOneWidget);
    expect(find.textContaining('CHƯA KẾT NỐI WEB API'), findsOneWidget);
    await tester.tap(find.text('Thiết lập lần đầu'));
    await tester.pumpAndSettle();
    expect(find.text('Khởi tạo Admin trên máy này'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
