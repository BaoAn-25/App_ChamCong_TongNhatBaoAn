import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../session_storage.dart';
import '../../widgets/app_widgets.dart';
import 'dashboard_screen.dart';
import 'manage_screen.dart';

/// Khung điều hướng Admin (Admin Shell) theo chuẩn thiết kế mới:
/// - NavigationBar 5 tab nhãn CỐ ĐỊNH:
///   [0: Tổng quan, 1: Nhân sự, 2: Bảng công, 3: Đơn từ (có Badge), 4: Thêm]
/// - Tab "Thêm" mở bottom sheet: Thống kê, Tài khoản, Đăng xuất
/// - Khi đang ở Thống kê (index 4) hoặc Tài khoản (index 5), tab "Thêm" vẫn sáng (selected)
/// - AppHeader tích hợp: Tiêu đề + Phụ đề + Chip vai trò nhỏ gọn + Thời gian cập nhật 12px
/// - RefreshIndicator kéo vuốt làm mới dữ liệu
class AdminShell extends StatefulWidget {
  final AppController controller;
  final int initialPage;
  final Widget Function(BuildContext context, int pageIndex)? pageBuilder;
  final VoidCallback? onLogout;

  const AdminShell({
    super.key,
    required this.controller,
    this.initialPage = 0,
    this.pageBuilder,
    this.onLogout,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  late int _currentPage;

  // Danh sách tiêu đề cho 6 màn hình
  static const List<String> _pageTitles = [
    'Tổng quan',
    'Quản lý nhân sự',
    'Bảng công',
    'Quản lý đơn từ',
    'Thống kê & Báo cáo',
    'Thông tin tài khoản',
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
  }

  AppController get c => widget.controller;

  // Đếm số lượng đơn từ đang chờ duyệt
  int get _pendingRequestsCount {
    try {
      return c.data.requests.where((r) => r.status == 'pending').length;
    } catch (_) {
      return 0;
    }
  }

  // Chuyển đổi giữa index thực tế (0..5) và index hiển thị trên NavigationBar (0..4)
  int get _navBarIndex {
    if (_currentPage >= 0 && _currentPage <= 3) {
      return _currentPage;
    }
    // Trang 4 (Thống kê) và Trang 5 (Tài khoản) đều thuộc tab 4 "Thêm"
    return 4;
  }

  void _onNavDestinationSelected(int index) {
    if (index < 4) {
      setState(() => _currentPage = index);
    } else {
      _showMoreBottomSheet();
    }
  }

  /// Mở Bottom Sheet cho tab "Thêm"
  Future<void> _showMoreBottomSheet() async {
    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _MoreOptionsSheet(
        currentPage: _currentPage,
        onLogout: _handleLogout,
      ),
    );

    if (result != null && mounted) {
      setState(() => _currentPage = result);
    }
  }

  /// Xử lý đăng xuất an toàn
  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản quản trị?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await SessionStorage.clearSession();
      await c.logout();
      if (widget.onLogout != null) {
        widget.onLogout!();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _currentPage < _pageTitles.length
        ? _pageTitles[_currentPage]
        : 'Quản trị';

    final roleName = c.isAdmin
        ? 'Admin'
        : (c.user?.role == 'manager' ? 'Quản lý' : 'Nhân viên');

    final roleIcon = c.isAdmin
        ? Icons.shield_outlined
        : (c.user?.role == 'manager'
            ? Icons.supervisor_account_outlined
            : Icons.badge_outlined);

    final pendingCount = _pendingRequestsCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Thanh tiến trình đồng bộ mỏng
            if (c.isSyncing)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal),
              ),

            // Header dùng chung chuẩn hoá: không còn thanh "Đã cập nhật lúc..." cồng kềnh
            AppHeader(
              title: title,
              subtitle: 'Chấm công • Nhóm 09',
              roleName: roleName,
              roleIcon: roleIcon,
              lastUpdated: c.lastSyncedAt,
              onRefresh: c.isSyncing ? null : c.syncAll,
            ),

            // Nội dung chính bọc trong RefreshIndicator hỗ trợ kéo để tải lại
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await c.syncAll();
                },
                color: AppColors.teal,
                backgroundColor: AppColors.surface,
                child: widget.pageBuilder != null
                    ? widget.pageBuilder!(context, _currentPage)
                    : switch (_currentPage) {
                        0 => AdminDashboardScreen(
                            controller: c,
                            onNavigateToStaff: () => setState(() => _currentPage = 1),
                            onNavigateToRequests: () => setState(() => _currentPage = 3),
                          ),
                        1 => AdminManageScreen(
                            controller: c,
                          ),
                        _ => Center(
                            child: Text(
                              'Trang: $title',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                      },
              ),
            ),
          ],
        ),
      ),

      // NavigationBar 5 tab cố định
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _navBarIndex,
          onDestinationSelected: _onNavDestinationSelected,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard, color: AppColors.teal),
              label: 'Tổng quan',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_alt_outlined),
              selectedIcon: Icon(Icons.people_alt, color: AppColors.teal),
              label: 'Nhân sự',
            ),
            const NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month, color: AppColors.teal),
              label: 'Bảng công',
            ),
            NavigationDestination(
              icon: pendingCount > 0
                  ? Badge(
                      label: Text('$pendingCount'),
                      backgroundColor: AppColors.warning,
                      child: const Icon(Icons.assignment_outlined),
                    )
                  : const Icon(Icons.assignment_outlined),
              selectedIcon: pendingCount > 0
                  ? Badge(
                      label: Text('$pendingCount'),
                      backgroundColor: AppColors.warning,
                      child: const Icon(Icons.assignment, color: AppColors.teal),
                    )
                  : const Icon(Icons.assignment, color: AppColors.teal),
              label: 'Đơn từ',
            ),
            NavigationDestination(
              icon: const Icon(Icons.grid_view_rounded),
              selectedIcon: const Icon(Icons.grid_view, color: AppColors.teal),
              label: 'Thêm',
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom Sheet danh mục "Thêm"
class _MoreOptionsSheet extends StatelessWidget {
  final int currentPage;
  final VoidCallback onLogout;

  const _MoreOptionsSheet({
    required this.currentPage,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thanh gạt (Drag handle)
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'Tính năng mở rộng',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Thống kê
            _buildOptionItem(
              context: context,
              index: 4,
              icon: Icons.bar_chart_rounded,
              title: 'Thống kê & Báo cáo',
              subtitle: 'Biểu đồ chấm công, tỷ lệ chuyên cần',
              isSelected: currentPage == 4,
              onTap: () => Navigator.pop(context, 4),
            ),

            // Tài khoản
            _buildOptionItem(
              context: context,
              index: 5,
              icon: Icons.person_outline_rounded,
              title: 'Tài khoản cá nhân',
              subtitle: 'Xem & cập nhật thông tin hồ sơ',
              isSelected: currentPage == 5,
              onTap: () => Navigator.pop(context, 5),
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: AppColors.border, height: 1),
            ),

            // Đăng xuất
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.error,
                  size: 22,
                ),
              ),
              title: const Text(
                'Đăng xuất tài khoản',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: AppColors.error,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.error,
              ),
              onTap: () {
                Navigator.pop(context);
                onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required BuildContext context,
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.teal.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: isSelected
            ? Border.all(color: AppColors.teal.withValues(alpha: 0.3), width: 1.2)
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.teal
                : AppColors.navy.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.white : AppColors.textPrimary,
            size: 22,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 15,
            color: isSelected ? AppColors.teal : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: isSelected ? AppColors.teal : AppColors.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}
