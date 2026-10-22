import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/api_client.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/api_repositories.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/app_controller.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/ui/auth_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('All default repositories share the authenticated API client', () {
    final c = AppController();
    expect(identical(c.client, c.auth.client), isTrue);
    expect(identical(c.client, c.employeeRepo.client), isTrue);
    expect(identical(c.client, c.attendanceRepo.client), isTrue);
  });

  test(
    'Incorrect public OTP does not refresh or retry with an old session',
    () async {
      var calls = 0;
      final client = ApiClient(
        httpClient: MockClient((r) async {
          calls++;
          expect(r.url.path, '/api/auth/verify-otp');
          expect(r.headers.containsKey('Authorization'), isFalse);
          return http.Response(
            jsonEncode({'error': 'OTP không đúng.'}),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await client.setTokens(access: 'old-access', refresh: 'old-refresh');
      await expectLater(
        AuthService(client).verifyOtp(challengeId: 'id', code: '000000'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'OTP không đúng.',
          ),
        ),
      );
      expect(calls, 1);
    },
  );

  test(
    'Logout sends refresh token for server revocation and clears local tokens',
    () async {
      final client = ApiClient(
        httpClient: MockClient((r) async {
          expect(r.url.path, '/api/auth/logout');
          expect(r.headers.containsKey('Authorization'), isFalse);
          expect(jsonDecode(r.body)['refreshToken'], 'refresh-to-revoke');
          return http.Response('', 204);
        }),
      );
      await client.setTokens(access: 'access', refresh: 'refresh-to-revoke');
      await AuthService(client).logout();
      expect(client.hasTokens, isFalse);
    },
  );

  test('Delivery failure preserves backend message for the user', () async {
    final client = ApiClient(
      httpClient: MockClient(
        (r) async => http.Response(
          jsonEncode({'error': 'Email chưa gửi được'}),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      AuthService(client).login(username: 'user', password: 'password'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 503)
            .having((e) => e.message, 'message', 'Email chưa gửi được'),
      ),
    );
  });

  testWidgets('Registration tab moves to OTP, then resend and verify work', (
    tester,
  ) async {
    final api = ApiClient();
    final auth = FakeAuth(api);
    final controller = AppController.withServices(
      apiClient: api,
      authService: auth,
    );
    await tester.pumpWidget(
      MaterialApp(home: AuthPage(controller: controller)),
    );
    await tester.tap(find.text('Đăng ký').first);
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    for (var i = 0; i < 5; i++) {
      await tester.enterText(
        fields.at(i),
        [
          'Tester',
          'test@example.com',
          'tester',
          'password123',
          'password123',
        ][i],
      );
    }
    await tester.ensureVisible(find.text('Đăng ký tài khoản'));
    await tester.tap(find.text('Đăng ký tài khoản'));
    await tester.pumpAndSettle();
    expect(find.text('Xác minh Email đăng ký'), findsOneWidget);
    expect(auth.registrations, 1);
    await tester.ensureVisible(find.text('Gửi lại mã OTP'));
    await tester.tap(find.text('Gửi lại mã OTP'));
    await tester.pumpAndSettle();
    expect(auth.registrations, 2);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.ensureVisible(find.text('Xác nhận & Hoàn tất đăng ký'));
    await tester.tap(find.text('Xác nhận & Hoàn tất đăng ký'));
    await tester.pumpAndSettle();
    expect(auth.verifiedChallenge, 'challenge-2');
    expect(find.text('Xác minh Email đăng ký'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });
}

class FakeAuth extends AuthService {
  FakeAuth(super.client);
  int registrations = 0;
  String? verifiedChallenge;
  @override
  Future<String> register({
    required String name,
    required String email,
    required String username,
    required String password,
  }) async => 'challenge-${++registrations}';
  @override
  Future<void> verifyEmail({
    required String challengeId,
    required String code,
  }) async {
    expect(code, '123456');
    verifiedChallenge = challengeId;
  }
}
