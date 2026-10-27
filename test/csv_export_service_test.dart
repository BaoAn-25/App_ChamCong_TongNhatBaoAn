import 'package:flutter_test/flutter_test.dart';
import 'package:app_cham_cong_tong_nhat_bao_an/data/csv_export_service.dart';

void main() {
  group('CsvExportService tests', () {
    test('escapeCell handles null, plain text, quotes, and commas', () {
      expect(CsvExportService.escapeCell(null), '""');
      expect(CsvExportService.escapeCell(''), '""');
      expect(CsvExportService.escapeCell('Phòng Kỹ thuật'), '"Phòng Kỹ thuật"');
      expect(CsvExportService.escapeCell('Tên có "dấu ngoặc kép"'), '"Tên có ""dấu ngoặc kép"""');
      expect(CsvExportService.escapeCell('Dòng 1, Dòng 2'), '"Dòng 1, Dòng 2"');
      expect(CsvExportService.escapeCell(123), '"123"');
    });
  });
}
