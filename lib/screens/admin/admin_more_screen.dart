import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../widgets/app_widgets.dart';
import 'account_screen.dart';
import 'statistics_screen.dart';
import 'manage_screen.dart';
import 'admin_management_dialogs.dart';

/// Màn hình "Thêm" dành cho Quản trị viên (Admin More Screen - Screen 10)
class AdminMoreScreen extends StatelessWidget {
  final AppController controller;
  final VoidCallback onLogout;
  final Function(int pageIndex)? onNavigateTab;

  const AdminMoreScreen({
    super.key,
    required this.controller,
    required this.onLogout,
    this.onNavigateTab,
  });

  AppController get c => controller;

  void _showOfficeConfig(BuildContext context) {
    OfficeConfigSheet.show(context, c);
  }

  void _showActivityLog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, color: Color(0xFFD97706), size: 22),
                  SizedBox(width: 10),
                  Text('Nhật ký hoạt động hệ thống', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: c.data.attendance.take(20).length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final a = c.data.attendance[i];
                  final emp = c.data.employees.where((e) => e.id == a.employeeId).firstOrNull;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fingerprint_rounded, color: AppColors.teal, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${emp?.name ?? "Nhân viên"} điểm danh', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                              const SizedBox(height: 2),
                              Text('Vào lúc ${a.checkIn.toLocal().toString().substring(11, 16)} • ${a.shiftName}', style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        StatusChip(a.lateMinutes > 0 ? 'Trễ ${a.lateMinutes}p' : 'Đúng giờ'),
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

  void _exportCsvReport(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đang chuẩn bị file báo cáo chấm công định dạng CSV / Excel...'),
        backgroundColor: AppColors.teal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = c.user;
    final userName = user?.name ?? 'Tống Nhật Bảo An';
    final userEmail = user?.email ?? 'admin@gmail.com';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        // ====================================================================
        // THẺ HỒ SƠ QUẢN TRỊ VIÊN (Bấm vào xem Screen 11 Tài khoản)
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
                  backgroundColor: AppColors.teal.withValues(alpha: 0.15),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.teal,
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
                          color: AppColors.teal.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
                        ),
                        child: const Text(
                          'Admin - Toàn quyền',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.teal,
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
        // PHẦN 1: QUẢN TRỊ CÔNG TY
        // ====================================================================
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'QUẢN TRỊ CÔNG TY',
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
                icon: Icons.apartment_rounded,
                iconColor: const Color(0xFF0284C7),
                title: 'Phòng ban',
                subtitle: 'Danh sách, phân bổ nhân sự, quản lý trưởng phòng',
                onTap: () => DepartmentManagementSheet.show(context, c),
              ),
              const Divider(height: 1, indent: 56),
              _buildMenuItem(
                icon: Icons.schedule_rounded,
                iconColor: const Color(0xFF0D9488),
                title: 'Ca làm việc',
                subtitle: 'Giờ vào, giờ ra, ca sáng, chiều, hành chính',
                onTap: () => ShiftManagementSheet.show(context, c),
              ),
              const Divider(height: 1, indent: 56),
              _buildMenuItem(
                icon: Icons.pin_drop_rounded,
                iconColor: const Color(0xFFE11D48),
                title: 'Vùng & quy tắc chấm công',
                subtitle: 'Tọa độ GPS văn phòng, bán kính cho phép, mã QR',
                onTap: () => _showOfficeConfig(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ====================================================================
        // PHẦN 2: BÁO CÁO VÀ HỆ THỐNG
        // ====================================================================
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'BÁO CÁO VÀ HỆ THỐNG',
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
                icon: Icons.insert_chart_outlined_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Thống kê & Báo cáo',
                subtitle: 'Biểu đồ công, tỷ lệ chuyên cần, cảnh báo bất thường',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminStatisticsScreen(controller: c),
                    ),
                  );
                },
              ),
              const Divider(height: 1, indent: 56),
              _buildMenuItem(
                icon: Icons.file_download_outlined,
                iconColor: const Color(0xFF059669),
                title: 'Xuất báo cáo',
                subtitle: 'Xuất file Excel / CSV dữ liệu chấm công tháng',
                onTap: () => _exportCsvReport(context),
              ),
              const Divider(height: 1, indent: 56),
              _buildMenuItem(
                icon: Icons.history_rounded,
                iconColor: const Color(0xFFD97706),
                title: 'Nhật ký hoạt động',
                subtitle: 'Lịch sử chấm công, phê duyệt đơn, phân quyền',
                onTap: () => _showActivityLog(context),
              ),
              const Divider(height: 1, indent: 56),
              _buildMenuItem(
                icon: Icons.admin_panel_settings_outlined,
                iconColor: const Color(0xFF2563EB),
                title: 'Phân quyền vai trò',
                subtitle: 'Gán quyền Quản trị viên, Quản lý phòng ban',
                onTap: () => RoleAssignmentSheet.show(context, c),
              ),
              const Divider(height: 1, indent: 56),
              _buildMenuItem(
                icon: Icons.settings_outlined,
                iconColor: const Color(0xFF64748B),
                title: 'Cài đặt chung',
                subtitle: 'Cấu hình hệ thống, thông báo, làm mới dữ liệu',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hệ thống đang hoạt động phiên bản 2.4 (Build 2026)'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // ====================================================================
        // NÚT ĐĂNG XUẤT (Nền đỏ nhạt, chữ đỏ nổi bật)
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
