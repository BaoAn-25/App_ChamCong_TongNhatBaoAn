import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/attendance_detail_sheet.dart';
import 'attendance_map_screen.dart';
import 'admin_management_dialogs.dart';

/// Màn hình Tổng quan dành cho Quản trị viên (Admin Dashboard):
/// 1. Thẻ chào gradient navy → teal, tên, huy hiệu vai trò, ngày hôm nay, nút "Đi tới Nhân sự"
/// 2. Thao tác nhanh lưới 4 ô: Thêm nhân viên, Tạo ca làm, Duyệt đơn (có badge), Bản đồ chấm công
/// 3. Lưới StatCard 2x2: Có mặt hôm nay (dạng 1/16), Đi trễ hôm nay, Chưa check-out, Đơn chờ duyệt
/// 4. Hoạt động gần đây: mỗi dòng có StatusChip, bấm mở AttendanceDetailSheet
class AdminDashboardScreen extends StatefulWidget {
  final AppController controller;
  final VoidCallback onNavigateToStaff;
  final VoidCallback onNavigateToRequests;
  final VoidCallback? onAddEmployee;
  final VoidCallback? onCreateShift;

  const AdminDashboardScreen({
    super.key,
    required this.controller,
    required this.onNavigateToStaff,
    required this.onNavigateToRequests,
    this.onAddEmployee,
    this.onCreateShift,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  AppController get c => widget.controller;

  // Lọc các bản ghi chấm công của ngày hôm nay (múi giờ GMT+7)
  List<Attendance> get _todayRecords {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final todayStr = dayKey(now);
    return c.data.attendance.where((a) {
      final aDate = a.checkIn.toUtc().add(const Duration(hours: 7));
      return dayKey(aDate) == todayStr;
    }).toList();
  }

  // Danh sách chấm công gần đây (sắp xếp mới nhất lên đầu)
  List<Attendance> get _recentRecords {
    final list = List<Attendance>.from(c.data.attendance);
    list.sort((x, y) => y.checkIn.compareTo(x.checkIn));
    return list;
  }



  String _getEmployeeName(String employeeId) {
    final emp = c.data.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.name ?? 'Nhân viên';
  }

  String? _getEmployeeDept(String employeeId) {
    final emp = c.data.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.department;
  }

  @override
  Widget build(BuildContext context) {
    final today = _todayRecords;
    final totalEmployees = c.data.employees.where((e) => e.active && !e.isAdmin).length;
    final presentEmployeesCount = today.map((a) => a.employeeId).toSet().length;
    final lateCount = today.where((a) => a.lateMinutes > 0).length;
    final notCheckedOutCount = today.where((a) => a.checkOut == null).length;
    final pendingRequestsCount =
        c.data.requests.where((r) => r.status == 'pending').length;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ====================================================================
        // 1. LƯỚI STAT CARD 2x2 CHUẨN SCREEN 6
        // ====================================================================
        _buildStatGrid(
          presentText: '$presentEmployeesCount/${totalEmployees > 0 ? totalEmployees : c.data.employees.length}',
          lateCount: lateCount,
          notCheckedOutCount: notCheckedOutCount,
          pendingRequestsCount: pendingRequestsCount,
        ),
        const SizedBox(height: 16),

        // ====================================================================
        // 2. THAO TÁC NHANH LƯỚI 4 Ô
        // ====================================================================
        const SectionHeader(
          title: 'Thao tác nhanh',
          subtitle: 'Truy cập nhanh các nghiệp vụ quản trị',
        ),
        const SizedBox(height: 8),
        _buildQuickActionsGrid(context, pendingRequestsCount),
        const SizedBox(height: 20),

        // ====================================================================
        // 3. HOẠT ĐỘNG CHẤM CÔNG GẦN ĐÂY
        // ====================================================================
        SectionHeader(
          title: 'Hoạt động chấm công gần đây',
          subtitle: 'Cập nhật trực tiếp từ hệ thống',
          actionText: 'Xem tất cả',
          onAction: widget.onNavigateToStaff,
        ),
        const SizedBox(height: 8),
        _buildRecentActivitiesList(context),
        const SizedBox(height: 24),
      ],
    );
  }



  // 2. Thao tác nhanh lưới 4 ô
  Widget _buildQuickActionsGrid(BuildContext context, int pendingRequestsCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12 * 3) / 4;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildActionItem(
              width: itemWidth,
              icon: Icons.person_add_alt_1_rounded,
              color: const Color(0xFF0284C7),
              label: 'Thêm NV',
              onTap: widget.onAddEmployee ?? widget.onNavigateToStaff,
            ),
            _buildActionItem(
              width: itemWidth,
              icon: Icons.more_time_rounded,
              color: const Color(0xFF0D9488),
              label: 'Tạo ca làm',
              onTap: widget.onCreateShift ?? () => ShiftManagementSheet.show(context, c),
            ),
            _buildActionItem(
              width: itemWidth,
              icon: Icons.fact_check_outlined,
              color: AppColors.warning,
              label: 'Duyệt đơn',
              badgeCount: pendingRequestsCount,
              onTap: widget.onNavigateToRequests,
            ),
            _buildActionItem(
              width: itemWidth,
              icon: Icons.map_rounded,
              color: AppColors.teal,
              label: 'Bản đồ',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendanceMapScreen(controller: c),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionItem({
    required double width,
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border, width: 0.8),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (badgeCount != null && badgeCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. Lưới StatCard 2x2
  Widget _buildStatGrid({
    required String presentText,
    required int lateCount,
    required int notCheckedOutCount,
    required int pendingRequestsCount,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: 'Có mặt hôm nay',
                value: presentText,
                icon: Icons.how_to_reg_rounded,
                iconColor: AppColors.success,
                subtitle: 'Tỷ lệ đi làm thực tế',
                onTap: widget.onNavigateToStaff,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: 'Đi trễ hôm nay',
                value: '$lateCount',
                icon: Icons.alarm_off_outlined,
                iconColor: AppColors.warning,
                subtitle: 'Số ca vào trễ giờ',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: 'Chưa check-out',
                value: '$notCheckedOutCount',
                icon: Icons.hourglass_bottom_rounded,
                iconColor: AppColors.orange,
                subtitle: 'Đang làm việc',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: 'Đơn chờ duyệt',
                value: '$pendingRequestsCount',
                icon: Icons.pending_actions_rounded,
                iconColor: pendingRequestsCount > 0 ? AppColors.error : AppColors.textSecondary,
                subtitle: 'Nghỉ phép & giải trình',
                onTap: widget.onNavigateToRequests,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 4. Hoạt động gần đây
  Widget _buildRecentActivitiesList(BuildContext context) {
    final recents = _recentRecords.take(6).toList();

    if (recents.isEmpty) {
      return const EmptyState(
        title: 'Chưa có lượt chấm công nào',
        description: 'Khi nhân viên thực hiện điểm danh, hoạt động sẽ hiển thị tại đây.',
        icon: Icons.history_toggle_off_rounded,
      );
    }

    return Column(
      children: recents.map((attendance) {
        final empName = _getEmployeeName(attendance.employeeId);
        final empDept = _getEmployeeDept(attendance.employeeId);

        String statusLabel;
        IconData statusIcon;
        if (attendance.lateMinutes > 0) {
          statusLabel = 'Đi trễ ${attendance.lateMinutes}p';
          statusIcon = Icons.alarm_off_outlined;
        } else if (attendance.checkOut == null && DateTime.now().isAfter(attendance.scheduledEnd)) {
          statusLabel = 'Thiếu giờ ra';
          statusIcon = Icons.warning_amber_rounded;
        } else if (attendance.checkOut == null) {
          statusLabel = 'Đang làm';
          statusIcon = Icons.access_time_rounded;
        } else {
          statusLabel = 'Đúng giờ';
          statusIcon = Icons.check_circle_outline;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            padding: const EdgeInsets.all(12),
            onTap: () {
              AttendanceDetailSheet.show(
                context,
                attendance: attendance,
                employeeName: empName,
                department: empDept,
              );
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.teal.withValues(alpha: 0.1),
                  child: Text(
                    empName.isNotEmpty ? empName[0].toUpperCase() : 'N',
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              empName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (empDept != null && empDept.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AppColors.teal.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.teal.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                empDept.toLowerCase().startsWith('phòng') ? empDept : 'Phòng $empDept',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.teal,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${dateLabel(attendance.checkIn)} • ${clock(attendance.checkIn)} → ${clock(attendance.checkOut)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusChip(statusLabel, icon: statusIcon),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
