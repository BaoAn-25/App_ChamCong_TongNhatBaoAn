import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';

/// Tiện ích xuất dữ liệu bảng chấm công sang file CSV / Excel
class CsvExportService {
  /// Format ô CSV an toàn (chuẩn RFC 4180): bọc trong dấu ngoặc kép và escape nháy kép
  static String escapeCell(dynamic val) {
    if (val == null) return '""';
    final str = val.toString().replaceAll('"', '""');
    return '"$str"';
  }

  /// Xuất bảng chấm công ra file CSV và mở hộp thoại chia sẻ/lưu về máy
  static Future<bool> exportTimesheet({
    required BuildContext context,
    required AppController controller,
    required List<Attendance> records,
    required String title,
    required String fileNamePrefix,
    DateTime? month,
  }) async {
    try {
      final selectedMonth = month ?? DateTime.now();
      final monthStr = 'Tháng ${selectedMonth.month}/${selectedMonth.year}';

      // 1. Dựng nội dung CSV có UTF-8 BOM (\uFEFF) để Excel hiển thị đúng dấu tiếng Việt 100%
      final buffer = StringBuffer();
      buffer.write('\uFEFF'); // UTF-8 BOM

      // Tiêu đề báo cáo
      buffer.writeln(escapeCell('BÁO CÁO BẢNG CHẤM CÔNG - $title - $monthStr'));
      buffer.writeln('${escapeCell("Thời gian xuất:")},${escapeCell(DateTime.now().toLocal().toString().substring(0, 19))}');
      buffer.writeln('${escapeCell("Tổng số lượt chấm:")},${escapeCell(records.length)}');
      buffer.writeln(''); // dòng trống

      // Header các cột
      final headers = [
        'STT',
        'Tên đăng nhập',
        'Họ và tên',
        'Phòng ban',
        'Ca làm việc',
        'Ngày',
        'Giờ vào',
        'Giờ ra',
        'Đi trễ (phút)',
        'Tổng giờ làm',
        'Trạng thái',
      ];
      buffer.writeln(headers.map(escapeCell).join(','));

      // Sắp xếp theo ngày tăng dần
      final sortedRecords = List<Attendance>.from(records)
        ..sort((a, b) => a.checkIn.compareTo(b.checkIn));

      // Dữ liệu từng dòng
      int stt = 1;
      for (final a in sortedRecords) {
        final emp = controller.data.employees.where((e) => e.id == a.employeeId).firstOrNull;
        final empName = emp?.name ?? a.employeeName ?? 'Nhân viên';
        final empUsername = emp?.username ?? '';
        final dept = emp?.department.isNotEmpty == true ? emp!.department : 'Chưa phân phòng';

        final inLocal = a.checkIn.toLocal();
        final outLocal = a.checkOut?.toLocal();
        final dateStr = '${inLocal.day.toString().padLeft(2, '0')}/${inLocal.month.toString().padLeft(2, '0')}/${inLocal.year}';
        final checkInStr = '${inLocal.hour.toString().padLeft(2, '0')}:${inLocal.minute.toString().padLeft(2, '0')}';
        final checkOutStr = outLocal != null
            ? '${outLocal.hour.toString().padLeft(2, '0')}:${outLocal.minute.toString().padLeft(2, '0')}'
            : 'Chưa ra ca';

        String status = 'Đúng giờ';
        if (a.lateMinutes > 0) {
          status = 'Trễ ${a.lateMinutes} phút';
        } else if (a.checkOut == null) {
          status = 'Đang trong ca';
        }

        final row = [
          stt++,
          empUsername,
          empName,
          dept,
          a.shiftName,
          dateStr,
          checkInStr,
          checkOutStr,
          a.lateMinutes,
          (a.checkOut != null ? a.hours.toStringAsFixed(2) : '0.00'),
          status,
        ];
        buffer.writeln(row.map(escapeCell).join(','));
      }

      final csvContent = buffer.toString();

      // Sao chép sẵn vào Clipboard để người dùng có thể dán ngay nếu muốn
      try {
        await Clipboard.setData(ClipboardData(text: csvContent));
      } catch (_) {}

      // 2. Ghi ra file CSV trong thư mục tạm
      final tempDir = await getTemporaryDirectory();
      final cleanPrefix = fileNamePrefix
          .replaceAll(RegExp(r'[\\/:*?"<>| ]'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final fileName = '${cleanPrefix}_Thang${selectedMonth.month}_${selectedMonth.year}.csv';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvContent, flush: true);

      // 3. Mở Share Sheet để người dùng Lưu vào máy / gửi qua Zalo, Email, Drive...
      if (context.mounted) {
        final box = context.findRenderObject() as RenderBox?;
        final originRect = box != null && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : null;

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv', name: fileName)],
            subject: 'Báo cáo bảng chấm công $title - $monthStr',
            sharePositionOrigin: originRect,
          ),
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã xuất file "$fileName" thành công!\n(Đồng thời đã sao chép CSV vào bộ nhớ tạm)'),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }

      return true;
    } catch (e) {
      debugPrint('Export CSV error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xuất báo cáo: $e'),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }
  }
}
