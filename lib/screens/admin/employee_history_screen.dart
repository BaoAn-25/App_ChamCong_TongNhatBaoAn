import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/attendance_detail_sheet.dart';

/// Màn hình Lịch sử Chấm công của một Nhân viên (EmployeeHistoryScreen):
/// 8. Header: avatar chữ cái, họ tên, @tên đăng nhập, phòng ban, huy hiệu vai trò.
/// 9. Chọn tháng (mũi tên trước / sau), hàng tóm tắt: ngày đủ công, đi trễ, ra sớm, thiếu giờ ra, tổng giờ.
/// 10. Danh sách bản ghi trong tháng: ngày, ca, giờ vào – giờ ra, StatusChip. Bấm mở AttendanceDetailSheet.
class EmployeeHistoryScreen extends StatefulWidget {
  final AppController controller;
  final String userId;

  const EmployeeHistoryScreen({
    super.key,
    required this.controller,
    required this.userId,
  });

  @override
  State<EmployeeHistoryScreen> createState() => _EmployeeHistoryScreenState();
}

class _EmployeeHistoryScreenState extends State<EmployeeHistoryScreen> {
  late DateTime _selectedMonth;

  AppController get c => widget.controller;

  Employee? get _employee {
    return c.data.employees.where((e) => e.id == widget.userId).firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
  }

  // Lọc danh sách chấm công của nhân viên theo tháng được chọn
  List<Attendance> get _monthRecords {
    return c.data.attendance.where((a) {
      if (a.employeeId != widget.userId) return false;
      return a.checkIn.year == _selectedMonth.year && a.checkIn.month == _selectedMonth.month;
    }).toList()
      ..sort((x, y) => y.checkIn.compareTo(x.checkIn));
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final emp = _employee;
    final empName = emp?.name ?? 'Nhân viên';
    final empUsername = emp?.username ?? '';
    final empDept = emp?.department ?? 'Chưa phân phòng ban';
    final roleName = emp?.isAdmin ?? false
        ? 'Admin'
        : (emp?.isManager ?? false ? 'Quản lý' : 'Nhân viên');
    final roleColor = emp?.isAdmin ?? false
        ? Colors.deepPurple
        : (emp?.isManager ?? false ? AppColors.teal : AppColors.info);

    final records = _monthRecords;
    final totalHours = records.fold<double>(0, (sum, a) => sum + a.hours);
    final lateCount = records.where((a) => a.lateMinutes > 0).length;
    final earlyLeaveCount = records.where((a) => a.checkOut != null && a.checkOut!.isBefore(a.scheduledEnd)).length;
    final missingCheckoutCount = records.where((a) => a.checkOut == null && DateTime.now().isAfter(a.scheduledEnd)).length;
    final completedDaysCount = records.where((a) => a.checkOut != null && a.lateMinutes == 0 && !a.checkOut!.isBefore(a.scheduledEnd)).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Lịch sử chấm công',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ==================================================================
          // 8. HEADER THÔNG TIN NHÂN VIÊN
          // ==================================================================
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: roleColor.withValues(alpha: 0.12),
                  child: Text(
                    empName.isNotEmpty ? empName[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: roleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              empName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: roleColor.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              roleName.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: roleColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '@$empUsername • ${empDept.isEmpty ? 'Chưa phân phòng ban' : empDept}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ==================================================================
          // 9. CHỌN THÁNG (Mũi tên trước / sau) & THANH TÓM TẮT CHỈ SỐ
          // ==================================================================
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _changeMonth(-1),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.teal),
                    const SizedBox(width: 8),
                    Text(
                      'Tháng ${_selectedMonth.month.toString().padLeft(2, '0')}/${_selectedMonth.year}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Hàng tóm tắt 5 chỉ số
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMetricBox('Đủ công', '$completedDaysCount', AppColors.success),
                    _buildMetricBox('Đi trễ', '$lateCount', AppColors.warning),
                    _buildMetricBox('Ra sớm', '$earlyLeaveCount', AppColors.orange),
                    _buildMetricBox('Thiếu giờ ra', '$missingCheckoutCount', AppColors.error),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(color: AppColors.border, height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tổng giờ làm tích lũy trong tháng:',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    Text(
                      '${totalHours.toStringAsFixed(1)} giờ',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.teal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tiêu đề danh sách
          Text(
            'Chi tiết các ngày làm việc (${records.length})',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // ==================================================================
          // 10. DANH SÁCH BẢN GHI TRONG THÁNG
          // ==================================================================
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: EmptyState(
                title: 'Không có dữ liệu chấm công',
                description: 'Nhân viên chưa có lượt điểm danh nào trong tháng ${_selectedMonth.month}/${_selectedMonth.year}.',
                icon: Icons.history_toggle_off_rounded,
              ),
            )
          else
            ...records.map((a) {
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.input,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${a.checkIn.day}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.navy,
                              ),
                            ),
                            Text(
                              'Th ${a.checkIn.weekday + 1 == 8 ? 'CN' : a.checkIn.weekday + 1}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.shiftName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${clock(a.checkIn)} – ${clock(a.checkOut)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.teal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${a.hours.toStringAsFixed(1)}h',
                            style: const TextStyle(
                              fontSize: 14,
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
            }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildMetricBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
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
}
