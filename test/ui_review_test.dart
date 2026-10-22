import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/api_client.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/api_repositories.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/app_controller.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/models.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/ui/home_page.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/ui/auth_page.dart';

class ReviewAuth extends AuthService {
  final Employee employee;
  ReviewAuth(super.client, this.employee);
  @override
  Future<Employee?> getMe() async => employee;
}

void main() {
  for (final role in ['admin', 'manager', 'employee']) {
    testWidgets('$role mobile pages render and navigate', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final employee = Employee(
        id: 'review',
        name: 'Nhân viên kiểm thử',
        username: 'review',
        email: 'review@example.test',
        role: role,
      );
      final client = ApiClient(
        httpClient: MockClient((request) async {
          final Object body = switch (request.url.path) {
            '/api/office' => {'name': 'Văn phòng', 'radius': 150},
            '/api/attendance' => {'items': [], 'total': 0},
            '/api/employees' => [employee.toJson()],
            _ => [],
          };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final c = AppController.withServices(
        apiClient: client,
        authService: ReviewAuth(client, employee),
      );
      await c.load();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: RepaintBoundary(
            key: boundary,
            child: HomePage(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var page = 0; page < 6; page++) {
        if (page < 3) {
          await tester.tap(find.byType(NavigationDestination).at(page));
        } else {
          await tester.tap(find.byType(NavigationDestination).at(3));
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .widgetWithText(
                  ListTile,
                  ['Thống kê', 'Đơn từ', 'Tài khoản'][page - 3],
                )
                .last,
          );
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$role page $page');
        if (role == 'employee') {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('.dart_tool/ui-review/page-$page.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      }
      await tester.pumpWidget(MaterialApp(home: AuthPage(controller: c)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
