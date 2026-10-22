import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/api_client.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/api_repositories.dart';

void main() {
  test('Statistics load every attendance page, including record 101', () async {
    final pages = <int>[];
    final client = ApiClient(
      httpClient: MockClient((request) async {
        final page = int.parse(request.url.queryParameters['page']!);
        pages.add(page);
        final items = List.generate(
          page == 1 ? 100 : 1,
          (i) => {
            'id': '${(page - 1) * 100 + i}',
            'employeeId': 'e',
            'shiftName': 'Ca',
            'checkIn': '2026-10-22T01:00:00Z',
            'scheduledEnd': '2026-10-22T09:00:00Z',
            'lateMinutes': 0,
            'latitude': 10,
            'longitude': 106,
            'accuracy': 5,
          },
        );
        return http.Response(jsonEncode({'items': items, 'total': 101}), 200);
      }),
    );
    final records = await AttendanceRepository(client).list();
    expect(pages, [1, 2]);
    expect(records.length, 101);
  });
}
