import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/domain/models.dart';
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
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

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

  test('Office QR ticket keeps code and expiry from the API', () async {
    final client = ApiClient(
      httpClient: MockClient((r) async {
        expect(r.url.path, '/api/office/qr');
        return http.Response(
          jsonEncode({
            'code': 'BAOAN:1:abc',
            'expiresAt': '2026-10-22T16:05:00Z',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final ticket = await OfficeRepository(client).createQr();
    expect(ticket.code, 'BAOAN:1:abc');
    expect(ticket.expiresAt.toUtc(), DateTime.utc(2026, 10, 22, 16, 5));
  });

  test('Login challenge keeps the destination email from the API', () async {
    final client = ApiClient(
      httpClient: MockClient(
        (r) async => http.Response(
          jsonEncode({
            'challengeId': 'login-challenge',
            'email': 'staff@gmail.com',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final started = await AuthService(
      client,
    ).login(username: 'staff', password: 'password123');
    expect(started.challengeId, 'login-challenge');
    expect(started.email, 'staff@gmail.com');
  });

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
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Forgot password navigates to request form, sends OTP, and resets password', (tester) async {
    final api = ApiClient();
    final auth = FakeAuth(api);
    final ctrl = AppController.withServices(
      apiClient: api,
      authService: auth,
    );

    await tester.pumpWidget(MaterialApp(home: AuthPage(controller: ctrl)));
    await tester.pumpAndSettle();

    // 1. Nhập username rồi nhấn "Quên mật khẩu?"
    await tester.enterText(find.byType(TextField).first, 'user@example.com');
    await tester.tap(find.text('Quên mật khẩu?'));
    await tester.pumpAndSettle();
    expect(find.text('Gửi mã OTP xác thực'), findsOneWidget);

    // 2. Bấm "Gửi mã OTP xác thực"
    await tester.ensureVisible(find.text('Gửi mã OTP xác thực'));
    await tester.tap(find.text('Gửi mã OTP xác thực'));
    await tester.pumpAndSettle();

    // 3. Chuyển sang màn hình Đặt lại mật khẩu
    expect(find.text('Đặt lại mật khẩu'), findsOneWidget);
    expect(auth.forgotRequests, 1);

    // 4. Nhập mã OTP 6 số và mật khẩu mới
    await tester.enterText(find.byType(TextField).at(0), '654321');
    await tester.enterText(find.byType(TextField).at(1), 'newPassword123');
    await tester.enterText(find.byType(TextField).at(2), 'newPassword123');

    // 5. Nhấn "Xác nhận & Đổi mật khẩu"
    await tester.ensureVisible(find.text('Xác nhận & Đổi mật khẩu'));
    await tester.tap(find.text('Xác nhận & Đổi mật khẩu'));
    await tester.pumpAndSettle();

    expect(auth.resetChallenge, 'forgot-1');
    expect(auth.resetCode, '654321');
    expect(auth.resetPass, 'newPassword123');
    expect(find.text('Đặt lại mật khẩu'), findsNothing);
  });
}

class FakeAuth extends AuthService {
  FakeAuth(super.client);
  int registrations = 0;
  String? verifiedChallenge;
  int forgotRequests = 0;
  String? resetChallenge;
  String? resetCode;
  String? resetPass;

  @override
  Future<OtpChallengeStart> forgotPassword(String identifier) async =>
      OtpChallengeStart(
        challengeId: 'forgot-${++forgotRequests}',
        email: 'user@example.com',
      );

  @override
  Future<void> resetPassword({
    required String challengeId,
    required String code,
    required String newPassword,
  }) async {
    resetChallenge = challengeId;
    resetCode = code;
    resetPass = newPassword;
  }

  @override
  Future<OtpChallengeStart> register({
    required String name,
    required String email,
    required String username,
    required String password,
  }) async => OtpChallengeStart(
    challengeId: 'challenge-${++registrations}',
    email: email,
  );

  @override
  Future<Employee?> verifyEmail({
    required String challengeId,
    required String code,
    String? deviceId,
  }) async {
    expect(code, '123456');
    verifiedChallenge = challengeId;
    return null;
  }
}
