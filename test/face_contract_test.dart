import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/api_client.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/api_repositories.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/face_service.dart';

void main() {
  test(
    'Face service keeps enrollment OTP, consent and both captures together',
    () async {
      final api = ApiClient(
        httpClient: MockClient((r) async {
          expect(r.url.path, '/api/face/enroll');
          final body = jsonDecode(r.body);
          expect(body['challengeId'], 'challenge');
          expect(body['code'], '123456');
          expect(body['image'], 'first');
          expect(body['confirmImage'], 'second');
          expect(body['consent'], isTrue);
          expect(body['allowLogin'], isFalse);
          return http.Response('{"enrolled":true}', 200);
        }),
      );
      await FaceService(api).enroll('challenge', ' 123456 ', 'first', 'second');
    },
  );

  test(
    'Face login authenticates directly and saves tokens',
    () async {
      final api = ApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/auth/face-login');
          expect(request.headers.containsKey('Authorization'), isFalse);
          final body = jsonDecode(request.body);
          expect(body['username'], 'employee');
          expect(body['image'], 'live-camera-image');
          expect(body.containsKey('password'), isFalse);
          return http.Response(
            jsonEncode({
              'accessToken': 'jwt-access-token',
              'refreshToken': 'jwt-refresh-token',
              'user': {
                'id': 'emp-1',
                'name': 'Staff Member',
                'email': 'staff@gmail.com',
                'username': 'employee',
                'role': 'employee',
              },
            }),
            200,
          );
        }),
      );
      final user = await AuthService(
        api,
      ).faceLogin(username: ' employee ', image: 'live-camera-image');
      expect(user.id, 'emp-1');
      expect(user.email, 'staff@gmail.com');
      expect(api.hasTokens, isTrue);
    },
  );

  test('Face enrollment can explicitly opt in to login', () async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        expect(jsonDecode(request.body)['allowLogin'], isTrue);
        return http.Response('{"enrolled":true}', 200);
      }),
    );
    await FaceService(
      api,
    ).enroll('challenge', '123456', 'first', 'second', allowLogin: true);
  });

  test('Wrong face cannot create a login challenge or local session', () async {
    final api = ApiClient(
      httpClient: MockClient(
        (_) async => http.Response('{"error":"Face mismatch"}', 401),
      ),
    );
    await expectLater(
      AuthService(api).faceLogin(username: 'employee', image: 'wrong-person'),
      throwsA(isA<ApiException>()),
    );
    expect(api.hasTokens, isFalse);
  });

  for (final action in ['check-in', 'check-out']) {
    test('Face proof is included for $action', () async {
      final api = ApiClient(
        httpClient: MockClient((r) async {
          expect(r.url.path, '/api/attendance/$action');
          expect(jsonDecode(r.body)['faceProof'], 'single-use-proof');
          return http.Response(
            jsonEncode({
              'id': 'record',
              'employeeId': 'employee',
              'shiftName': 'Ca',
              'checkIn': '2026-10-22T01:00:00Z',
              'scheduledEnd': '2026-10-22T09:00:00Z',
              'lateMinutes': 0,
              'latitude': 10,
              'longitude': 106,
              'accuracy': 5,
            }),
            200,
          );
        }),
      );
      final repo = AttendanceRepository(api);
      final call = action == 'check-in' ? repo.checkIn : repo.checkOut;
      await call(
        qr: 'qr',
        latitude: 10,
        longitude: 106,
        accuracy: 5,
        capturedAt: DateTime.utc(2026, 10, 22),
        idempotencyKey: 'request',
        faceProof: 'single-use-proof',
      );
    });
  }

  test(
    'Verification failures are not converted into a successful proof',
    () async {
      final api = ApiClient(
        httpClient: MockClient(
          (_) async =>
              http.Response(jsonEncode({'error': 'Face mismatch'}), 403),
        ),
      );
      await expectLater(
        FaceService(api).verify('image', 'check-in'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
