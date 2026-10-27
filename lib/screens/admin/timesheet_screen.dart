import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/attendance_detail_sheet.dart';
import 'employee_history_screen.dart';

/// Màn hình Bảng công dành cho Admin (Timesheet):
/// 1. Thanh tóm tắt đầu danh sách: số bản ghi, tổng giờ, số lần đi trễ
/// 2. Mỗi dòng: avatar chữ cái, họ tên, ca, giờ vào – giờ ra, tổng giờ bên phải, StatusChip
/// 3. Lọc: ô tìm kiếm, chip nhanh (Hôm nay, 7 ngày, Tháng này, Tất cả), showDateRangePicker
/// 4. Xuất CSV ra file và mở bảng chia sẻ hệ thống (share_plus + path_provider); nút sao chép phụ
/// 5. Bấm vào dòng mở AttendanceDetailSheet
class AdminTimesheetScreen extends StatefulWidget {
  final AppController controller;
  final String? departmentFilter;

  const AdminTimesheetScreen({
    super.key,
    required this.controller,
    this.departmentFilter,
  });

  @override
  State<AdminTimesheetScreen> createState() => _AdminTimesheetScreenState();
}

class _AdminTimesheetScreenState extends State<AdminTimesheetScreen> {
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  String _quickFilter = 'all'; // all, today, 7days, this_month

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
  }

  // Danh sách chấm công đã lọc
  List<Attendance> get _filteredRecords {
    final list = List<Attendance>.from(c.data.attendance);

    return list.where((a) {
      final empName = _getEmployeeName(a.employeeId);
      final searchTarget = '$empName ${a.shiftName} ${dateLabel(a.checkIn)}'.toLowerCase();
      if (_searchQuery.isNotEmpty && !searchTarget.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      final scopedDept = widget.departmentFilter ?? (c.isManager ? c.user?.department : null);
      if (scopedDept != null && scopedDept.isNotEmpty) {
        final dept = _getEmployeeDept(a.employeeId);
        if (dept?.toLowerCase() != scopedDept.toLowerCase()) {
          return false;
        }
      }

      if (_dateRange != null) {
        final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
        final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day, 23, 59, 59);
        if (a.checkIn.isBefore(start) || a.checkIn.isAfter(end)) {
          return false;
        }
      }

      return true;
    }).toList()
      ..sort((x, y) => y.checkIn.compareTo(x.checkIn));
  }

  String _getEmployeeName(String employeeId) {
    final emp = c.data.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.name ?? 'Nhân viên';
  }

  String? _getEmployeeDept(String employeeId) {
    final emp = c.data.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.department;
  }

  void _applyQuickDateFilter(String type) {
    final now = DateTime.now();
    setState(() {
      _quickFilter = type;
      if (type == 'today') {
        _dateRange = DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day),
        );
      } else if (type == '7days') {
        _dateRange = DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: DateTime(now.year, now.month, now.day),
        );
      } else if (type == 'this_month') {
        _dateRange = DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: DateTime(now.year, now.month, now.day),
        );
      } else {
        _dateRange = null;
      }
    });
  }

  /// 4. Xuất CSV ra file và chia sẻ qua hệ điều hành (share_plus + path_provider)
  Future<void> _exportAndShareCsv(List<Attendance> records) async {
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu để xuất CSV')),
      );
      return;
    }

    try {
      String sanitize(Object? val) {
        var s = '$val';
        if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
        return '"${s.replaceAll('"', '""')}"';
      }

      final csvContent = StringBuffer();
      csvContent.writeln('\uFEFF"Họ và tên","Phòng ban","Ca làm việc","Ngày","Giờ vào","Giờ ra","Đi trễ (phút)","Tổng giờ"');

      for (final a in records) {
        final name = _getEmployeeName(a.employeeId);
        final dept = _getEmployeeDept(a.employeeId) ?? '';
        csvContent.writeln([
          sanitize(name),
          sanitize(dept),
          sanitize(a.shiftName),
          sanitize(dateLabel(a.checkIn)),
          sanitize(clock(a.checkIn)),
          sanitize(a.checkOut != null ? clock(a.checkOut) : 'Chưa ghi nhận'),
          sanitize(a.lateMinutes),
          sanitize(a.hours.toStringAsFixed(2)),
        ].join(','));
      }

      final tempDir = await getTemporaryDirectory();
      final dateStr = dayKey(DateTime.now());
      final file = File('${tempDir.path}/bang_cong_$dateStr.csv');
      await file.writeAsString(csvContent.toString());

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          text: 'Bảng công xuất ngày $dateStr',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất file: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Sao chép CSV vào Clipboard (lựa chọn phụ)
  Future<void> _copyCsvToClipboard(List<Attendance> records) async {
    if (records.isEmpty) return;
    String sanitize(Object? val) {
      var s = '$val';
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final csvContent = StringBuffer();
    csvContent.writeln('"Họ và tên","Phòng ban","Ca làm việc","Ngày","Giờ vào","Giờ ra","Đi trễ (phút)","Tổng giờ"');
    for (final a in records) {
      final name = _getEmployeeName(a.employeeId);
      final dept = _getEmployeeDept(a.employeeId) ?? '';
      csvContent.writeln([
        sanitize(name),
        sanitize(dept),
        sanitize(a.shiftName),
        sanitize(dateLabel(a.checkIn)),
        sanitize(clock(a.checkIn)),
        sanitize(a.checkOut != null ? clock(a.checkOut) : ''),
        sanitize(a.lateMinutes),
        sanitize(a.hours.toStringAsFixed(2)),
      ].join(','));
    }

    await Clipboard.setData(ClipboardData(text: csvContent.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã sao chép dữ liệu CSV vào bộ nhớ tạm!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;
    final totalHours = filtered.fold<double>(0, (sum, a) => sum + a.hours);
    final lateCount = filtered.where((a) => a.lateMinutes > 0).length;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ====================================================================
        // 1. THANH TÓM TẮT ĐẦU DANH SÁCH (Số bản ghi, Tổng giờ, Số lần đi trễ)
        // ====================================================================
        _buildSummaryBar(
          recordsCount: filtered.length,
          totalHours: totalHours,
          lateCount: lateCount,
        ),
        const SizedBox(height: 16),

        // ====================================================================
        // 3. Ô TÌM KIẾM VÀ BỘ LỌC NGÀY (Hôm nay, 7 ngày, Tháng này, Picker)
        // ====================================================================
        _buildSearchAndFilters(),
        const SizedBox(height: 12),

        // Hàng nút Thao tác Xuất CSV
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Danh sách chấm công (${filtered.length})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nút phụ: Sao chép
                IconButton(
                  tooltip: 'Sao chép CSV vào bộ nhớ tạm',
                  icon: const Icon(Icons.copy_rounded, size: 18, color: AppColors.textSecondary),
                  onPressed: filtered.isEmpty ? null : () => _copyCsvToClipboard(filtered),
                ),
                // Nút chính: Xuất file CSV & Chia sẻ
                FilledButton.icon(
                  onPressed: filtered.isEmpty ? null : () => _exportAndShareCsv(filtered),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Chia sẻ CSV'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ====================================================================
        // 2. DANH SÁCH BẢN GHI BẢNG CÔNG
        // ====================================================================
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: EmptyState(
              title: 'Không có bản ghi chấm công',
              description: 'Không tìm thấy dữ liệu điểm danh phù hợp với từ khoá hoặc khoảng ngày đã chọn.',
              icon: Icons.calendar_today_rounded,
            ),
          )
        else
          ...filtered.map((attendance) {
            return _buildAttendanceRecordItem(attendance);
          }),
        const SizedBox(height: 24),
      ],
    );
  }

  // 1. Thanh tóm tắt 3 chỉ số
  Widget _buildSummaryBar({
    required int recordsCount,
    required double totalHours,
    required int lateCount,
  }) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryColumn(
              label: 'Số bản ghi',
              value: '$recordsCount',
              icon: Icons.list_alt_rounded,
              color: AppColors.info,
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.border),
          Expanded(
            child: _buildSummaryColumn(
              label: 'Tổng giờ',
              value: '${totalHours.toStringAsFixed(1)}h',
              icon: Icons.access_time_rounded,
              color: AppColors.teal,
            ),
          ),
          Container(width: 1, height: 36, color: AppColors.border),
          Expanded(
            child: _buildSummaryColumn(
              label: 'Đi trễ',
              value: '$lateCount',
              icon: Icons.alarm_off_outlined,
              color: lateCount > 0 ? AppColors.warning : AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryColumn({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // 3. Ô tìm kiếm và Bộ lọc khoảng ngày
  Widget _buildSearchAndFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Ô tìm kiếm
        TextField(
          onChanged: (val) => setState(() => _searchQuery = val),
          decoration: InputDecoration(
            hintText: 'Tìm nhân viên, ca làm hoặc ngày...',
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => setState(() => _searchQuery = ''),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 10),

        // Hàng chip lọc nhanh + nút DateRangePicker
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip('Tất cả', 'all'),
              const SizedBox(width: 6),
              _buildFilterChip('Hôm nay', 'today'),
              const SizedBox(width: 6),
              _buildFilterChip('7 ngày qua', '7days'),
              const SizedBox(width: 6),
              _buildFilterChip('Tháng này', 'this_month'),
              const SizedBox(width: 8),
              Container(width: 1, height: 20, color: AppColors.border),
              const SizedBox(width: 8),

              // Nút mở showDateRangePicker
              OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                    initialDateRange: _dateRange,
                    helpText: 'Chọn khoảng ngày chấm công',
                    saveText: 'Áp dụng',
                  );
                  if (range != null && mounted) {
                    setState(() {
                      _dateRange = range;
                      _quickFilter = 'custom';
                    });
                  }
                },
                icon: const Icon(Icons.calendar_month_outlined, size: 15),
                label: Text(
                  _dateRange == null
                      ? 'Tuỳ chọn ngày'
                      : '${dateLabel(_dateRange!.start)} – ${dateLabel(_dateRange!.end)}',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _quickFilter == 'custom' ? AppColors.teal : AppColors.textPrimary,
                  side: BorderSide(
                    color: _quickFilter == 'custom' ? AppColors.teal : AppColors.border,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              if (_dateRange != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Bỏ lọc ngày',
                  icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textSecondary),
                  onPressed: () => _applyQuickDateFilter('all'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _quickFilter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => _applyQuickDateFilter(value),
      selectedColor: AppColors.teal.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.teal : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  // 2. Dòng bản ghi Bảng công
  Widget _buildAttendanceRecordItem(Attendance a) {
    final empName = _getEmployeeName(a.employeeId);
    final empDept = _getEmployeeDept(a.employeeId);

    // Xác định StatusChip: Đúng giờ / Đi trễ Xp / Ra sớm Xp / Thiếu giờ ra
    String statusText;
    IconData statusIcon;
    if (a.lateMinutes > 0) {
      statusText = 'Đi trễ ${a.lateMinutes}p';
      statusIcon = Icons.alarm_off_outlined;
    } else if (a.checkOut != null && a.checkOut!.isBefore(a.scheduledEnd)) {
      final earlyMinutes = a.scheduledEnd.difference(a.checkOut!).inMinutes;
      statusText = 'Ra sớm ${earlyMinutes}p';
      statusIcon = Icons.directions_walk_outlined;
    } else if (a.checkOut == null && DateTime.now().isAfter(a.scheduledEnd)) {
      statusText = 'Thiếu giờ ra';
      statusIcon = Icons.warning_amber_rounded;
    } else if (a.checkOut == null) {
      statusText = 'Đang làm';
      statusIcon = Icons.access_time_rounded;
    } else {
      statusText = 'Đúng giờ';
      statusIcon = Icons.check_circle_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        onTap: () {
          // 5. Mở AttendanceDetailSheet
          AttendanceDetailSheet.show(
            context,
            attendance: a,
            employeeName: empName,
            department: empDept,
            office: c.data.office,
          );
        },
        child: Row(
          children: [
            // Avatar chữ cái đầu của tên
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.teal.withValues(alpha: 0.1),
              child: Text(
                empName.isNotEmpty ? empName[0].toUpperCase() : 'N',
                style: const TextStyle(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Thông tin nhân viên, ca làm, giờ vào – giờ ra
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EmployeeHistoryScreen(
                            controller: c,
                            userId: a.employeeId,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Text(
                      empName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.teal,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.teal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${a.shiftName} • ${dateLabel(a.checkIn)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '${clock(a.checkIn)} – ${clock(a.checkOut)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Cột bên phải: Tổng giờ làm và StatusChip
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${a.hours.toStringAsFixed(1)}h',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                StatusChip(statusText, icon: statusIcon),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
