import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';

/// Màn hình Tổng quan Nhóm dành cho Quản lý (Manager Dashboard - Screen 10)
class ManagerDashboardScreen extends StatefulWidget {
  final AppController controller;
  final VoidCallback onNavigateToTeam;
  final VoidCallback onNavigateToRequests;
  final VoidCallback onNavigateToTimesheet;

  const ManagerDashboardScreen({
    super.key,
    required this.controller,
    required this.onNavigateToTeam,
    required this.onNavigateToRequests,
    required this.onNavigateToTimesheet,
  });

  @override
  State<ManagerDashboardScreen> createState() => _ManagerDashboardScreenState();
}

class _ManagerDashboardScreenState extends State<ManagerDashboardScreen> {
  AppController get c => widget.controller;

  // Lấy tên phòng ban của Quản lý hiện tại
  String get _managerDept => c.user?.department.isNotEmpty == true
      ? c.user!.department
      : (c.data.departments.isNotEmpty ? c.data.departments.first.name : 'Kinh doanh');

  String get _cleanDeptName {
    final dept = _managerDept.trim();
    if (dept.toLowerCase().startsWith('phòng')) {
      return dept.substring(5).trim();
    }
    return dept;
  }

  // Danh sách nhân viên thuộc phòng ban của Quản lý
  List<Employee> get _deptEmployees {
    return c.data.employees.where((e) {
      if (!e.active) return false;
      return e.department.toLowerCase() == _managerDept.toLowerCase();
    }).toList();
  }

  // Danh sách chấm công hôm nay của nhân viên trong phòng
  List<Attendance> get _todayDeptAttendances {
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    final todayStr = dayKey(now);
    final deptEmpIds = _deptEmployees.map((e) => e.id).toSet();

    return c.data.attendance.where((a) {
      if (!deptEmpIds.contains(a.employeeId)) return false;
      final aDate = a.checkIn.toUtc().add(const Duration(hours: 7));
      return dayKey(aDate) == todayStr;
    }).toList();
  }

  // Đơn từ đang chờ duyệt của nhân viên trong phòng
  List<WorkRequest> get _pendingDeptRequests {
    final deptEmpIds = _deptEmployees.map((e) => e.id).toSet();
    return c.data.requests.where((r) {
      if (r.employeeId == c.user?.id) return false; // Không tự duyệt đơn của mình
      if (!deptEmpIds.contains(r.employeeId)) return false;
      return r.status == 'pending';
    }).toList();
  }

  // Màu pastel cho avatar từng nhân viên
  Color _getAvatarBg(int index) {
    const colors = [
      Color(0xFFE0F2FE), // Light sky
      Color(0xFFFEF3C7), // Light amber
      Color(0xFFDCFCE7), // Light emerald
      Color(0xFFEDE9FE), // Light violet
      Color(0xFFFFE4E6), // Light rose
      Color(0xFFCCFBF1), // Light teal
    ];
    return colors[index % colors.length];
  }

  Color _getAvatarFg(int index) {
    const colors = [
      Color(0xFF0369A1),
      Color(0xFFB45309),
      Color(0xFF15803D),
      Color(0xFF6D28D9),
      Color(0xFFBE123C),
      Color(0xFF0F766E),
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final deptEmployees = _deptEmployees;
    final todayAttendances = _todayDeptAttendances;
    final presentIds = todayAttendances.map((a) => a.employeeId).toSet();
    final presentCount = presentIds.length;
    final totalDeptCount = deptEmployees.length;
    final lateCount = todayAttendances.where((a) => a.lateMinutes > 0).length;
    final notCheckedInCount = (totalDeptCount - presentCount).clamp(0, totalDeptCount);
    final pendingRequests = _pendingDeptRequests;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ====================================================================
        // 1. LƯỚI 4 STAT CARDS 2x2 CỦA PHÒNG BAN (Màn 10 - Screen 10)
        // ====================================================================
        _buildStatGrid(
          presentText: '$presentCount/$totalDeptCount',
          lateCount: lateCount,
          notCheckedInCount: notCheckedInCount,
          pendingRequestsCount: pendingRequests.length,
        ),
        const SizedBox(height: 14),

        // ====================================================================
        // 2. BANNER THÔNG BÁO ĐƠN CHỜ DUYỆT (Nếu có đơn pending)
        // ====================================================================
        if (pendingRequests.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.notifications_active_rounded, color: Color(0xFF059669), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pendingRequests.length} đơn đang chờ bạn duyệt',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Nghỉ phép, giải trình thiếu giờ ra',
                        style: TextStyle(fontSize: 12, color: Color(0xFF047857)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: widget.onNavigateToRequests,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Xem', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ====================================================================
        // 3. PHẦN NHÓM HÔM NAY (Màn 10 - Screen 10)
        // ====================================================================
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Nhóm hôm nay',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            TextButton(
              onPressed: widget.onNavigateToTimesheet,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Xem bảng công',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.teal,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildDepartmentTodayList(context, deptEmployees, todayAttendances),
        const SizedBox(height: 20),

        // ====================================================================
        // 4. GHI CHÚ BẢO MẬT PHÂN QUYỀN (FOOTER NOTICE - Screen 10)
        // ====================================================================
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Bạn chỉ xem được nhân viên phòng $_cleanDeptName',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // 1. Lưới StatCard 2x2 cho Quản lý chuẩn Màn 10
  Widget _buildStatGrid({
    required String presentText,
    required int lateCount,
    required int notCheckedInCount,
    required int pendingRequestsCount,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.person_outline_rounded,
                iconColor: const Color(0xFF059669),
                iconBg: const Color(0xFFDCFCE7),
                value: presentText,
                label: 'Có mặt hôm nay',
                onTap: widget.onNavigateToTeam,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.access_time_rounded,
                iconColor: const Color(0xFFD97706),
                iconBg: const Color(0xFFFEF3C7),
                value: '$lateCount',
                label: 'Đi trễ hôm nay',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                icon: Icons.person_off_outlined,
                iconColor: const Color(0xFF6B7280),
                iconBg: const Color(0xFFF3F4F6),
                value: '$notCheckedInCount',
                label: 'Chưa chấm công',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                icon: Icons.description_outlined,
                iconColor: const Color(0xFF0284C7),
                iconBg: const Color(0xFFE0F2FE),
                value: '$pendingRequestsCount',
                label: 'Đơn chờ duyệt',
                onTap: widget.onNavigateToRequests,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String value,
    required String label,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Danh sách nhân sự nhóm hôm nay (Màn 10 - Screen 10)
  Widget _buildDepartmentTodayList(
    BuildContext context,
    List<Employee> deptEmployees,
    List<Attendance> todayAttendances,
  ) {
    if (deptEmployees.isEmpty) {
      return const EmptyState(
        title: 'Chưa có nhân viên',
        description: 'Chưa có nhân viên nào được phân vào phòng ban này.',
        icon: Icons.people_outline_rounded,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: deptEmployees.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, index) {
        final emp = deptEmployees[index];
        final att = todayAttendances.where((a) => a.employeeId == emp.id).firstOrNull;

        String statusText;
        Color chipBg;
        Color chipFg;
        String timeInfo;

        if (att == null) {
          statusText = 'Chưa vào';
          chipBg = const Color(0xFFF3F4F6);
          chipFg = const Color(0xFF6B7280);
          timeInfo = 'Ca hành chính 08:00';
        } else if (att.lateMinutes > 0) {
          statusText = 'Trễ ${att.lateMinutes} phút';
          chipBg = const Color(0xFFFEF3C7);
          chipFg = const Color(0xFFD97706);
          final inLocal = att.checkIn.toLocal();
          timeInfo = 'Vào ${inLocal.hour.toString().padLeft(2, '0')}:${inLocal.minute.toString().padLeft(2, '0')}';
        } else {
          statusText = 'Đúng giờ';
          chipBg = const Color(0xFFDCFCE7);
          chipFg = const Color(0xFF15803D);
          final inLocal = att.checkIn.toLocal();
          timeInfo = 'Vào ${inLocal.hour.toString().padLeft(2, '0')}:${inLocal.minute.toString().padLeft(2, '0')}';
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _getAvatarBg(index),
                child: Text(
                  emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'N',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: _getAvatarFg(index),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emp.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeInfo,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: chipFg,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
