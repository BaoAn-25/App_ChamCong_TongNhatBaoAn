import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../widgets/app_widgets.dart';
import '../admin/account_screen.dart';
import '../../data/csv_export_service.dart';

/// Màn hình "Thêm" dành cho Quản lý (Manager More Screen - Screen 13)
class ManagerMoreScreen extends StatelessWidget {
  final AppController controller;
  final VoidCallback onLogout;
  final Function(int pageIndex)? onNavigateTab;

  const ManagerMoreScreen({
    super.key,
    required this.controller,
    required this.onLogout,
    this.onNavigateTab,
  });

  AppController get c => controller;

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

  String _typeLabel(String type) => switch (type) {
    'leave' => 'Nghỉ phép',
    'late' => 'Đi trễ',
    'forgot_checkout' => 'Bổ sung giờ ra',
    _ => type,
  };

  void _showTeamShifts(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, color: Color(0xFF0D9488), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ca làm việc phòng $_cleanDeptName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: c.data.shifts.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final s = c.data.shifts[i];
                  final startHour = s.startMinute ~/ 60;
                  final startMin = s.startMinute % 60;
                  final endHour = s.endMinute ~/ 60;
                  final endMin = s.endMinute % 60;
                  final start = '${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}';
                  final end = '${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}';
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, color: Color(0xFF0D9488), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.navy)),
                              const SizedBox(height: 2),
                              Text('$start - $end • Cho phép trễ ${s.grace}p', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showApprovalHistory(BuildContext context) {
    final deptEmployees = c.data.employees.where((e) => e.department.toLowerCase() == _managerDept.toLowerCase()).map((e) => e.id).toSet();
    final reviewedRequests = c.data.requests.where((r) => deptEmployees.contains(r.employeeId) && r.status != 'pending').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.history_edu_rounded, color: Color(0xFF0284C7), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Lịch sử duyệt đơn phòng $_cleanDeptName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: reviewedRequests.isEmpty
                  ? const Center(
                      child: EmptyState(
                        title: 'Chưa có lịch sử',
                        description: 'Chưa có đơn từ nào được duyệt hoặc từ chối.',
                        icon: Icons.history_rounded,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: reviewedRequests.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final req = reviewedRequests[i];
                        final emp = c.data.employees.where((e) => e.id == req.employeeId).firstOrNull;
                        final isApproved = req.status == 'approved';
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isApproved ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                color: isApproved ? AppColors.success : AppColors.error,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${emp?.name ?? "Nhân viên"} • ${_typeLabel(req.type)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text('Lý do: ${req.reason}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              StatusChip(isApproved ? 'Đã duyệt' : 'Từ chối'),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = c.user;
    final userName = user?.name ?? 'Nguyễn Thị Quản Lý';
    final userEmail = user?.email ?? 'manager@gmail.com';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ====================================================================
        // THẺ HỒ SƠ QUẢN LÝ (Screen 13) - Nhấn vào để mở trang Tài khoản cá nhân
        // ====================================================================
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminAccountScreen(
                  controller: c,
                  onLogout: onLogout,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.deepPurple.withValues(alpha: 0.15),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'M',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.deepPurple,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        userEmail,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Quản lý • Phòng $_cleanDeptName',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ====================================================================
        // PHẦN 1: PHÒNG [TÊN PHÒNG]
        // ====================================================================
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'PHÒNG ${_cleanDeptName.toUpperCase()}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              _buildMenuItem(
                icon: Icons.schedule_rounded,
                iconColor: const Color(0xFF0D9488),
                title: 'Ca làm của nhóm',
                subtitle: 'Xem ca làm việc của nhân sự trong phòng',
                onTap: () => _showTeamShifts(context),
              ),
              const Divider(height: 1, indent: 56),
              _buildMenuItem(
                icon: Icons.bar_chart_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Báo cáo nhóm',
                subtitle: 'Xuất dữ liệu chấm công phòng ban',
                onTap: () async {
                  final deptEmpIds = c.data.employees
                      .where((e) => e.department.toLowerCase() == _managerDept.toLowerCase())
                      .map((e) => e.id)
                      .toSet();
                  final deptRecords = c.data.attendance
                      .where((a) => deptEmpIds.contains(a.employeeId))
                      .toList();
                  await CsvExportService.exportTimesheet(
                    context: context,
                    controller: c,
                    records: deptRecords,
                    title: 'Phòng $_cleanDeptName',
                    fileNamePrefix: 'BangCong_Phong_$_cleanDeptName',
                  );
                },
              ),
              const Divider(height: 1, indent: 56),
              _buildMenuItem(
                icon: Icons.history_edu_rounded,
                iconColor: const Color(0xFF0284C7),
                title: 'Lịch sử duyệt đơn',
                subtitle: 'Danh sách đơn nghỉ phép, giải trình đã xử lý',
                onTap: () => _showApprovalHistory(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ====================================================================
        // PHẦN 2: CÁ NHÂN (Đã loại bỏ nút Tài khoản cá nhân trùng lặp với thẻ đầu trang)
        // ====================================================================
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'CÁ NHÂN',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              _buildMenuItem(
                icon: Icons.notifications_none_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: 'Thông báo',
                subtitle: 'Cài đặt thông báo duyệt đơn & chấm công',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đang bật tất cả thông báo điểm danh nhóm.'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ====================================================================
        // THẺ THÔNG BÁO GIỚI HẠN QUYỀN (Screen 13)
        // ====================================================================
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFBBF7D0)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF16A34A), size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Thêm nhân viên, phòng ban, phân quyền và vùng chấm công chỉ dành cho Quản trị viên (Admin).',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Color(0xFF15803D),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // ====================================================================
        // NÚT ĐĂNG XUẤT
        // ====================================================================
        InkWell(
          onTap: onLogout,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.errorBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
                SizedBox(width: 8),
                Text(
                  'Đăng xuất tài khoản',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14.5,
            color: AppColors.navy,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
        onTap: onTap,
      ),
    );
  }
}
