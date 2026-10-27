import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../session_storage.dart';
import '../../widgets/app_widgets.dart';
import 'dashboard_screen.dart';
import 'manage_screen.dart';
import 'timesheet_screen.dart';
import 'requests_screen.dart';
import 'admin_more_screen.dart';

/// Khung điều hướng Quản trị viên (Admin Shell) theo chuẩn thiết kế mới (Screens 6–11):
/// - NavigationBar 5 tab cố định:
///   [0: Tổng quan, 1: Nhân sự, 2: Bảng công, 3: Đơn từ (có Badge), 4: Thêm]
/// - Tab 4 "Thêm" là màn hình AdminMoreScreen (Screen 10)
/// - AppHeader tích hợp: Tiêu đề + Phụ đề + Chip vai trò Admin + Thời gian đồng bộ
/// - Kéo vuốt làm mới dữ liệu
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

  static const List<String> _pageTitles = [
    'Tổng quan',
    'Nhân sự',
    'Bảng công',
    'Quản lý đơn từ',
    'Thêm',
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

  void _onNavDestinationSelected(int index) {
    setState(() => _currentPage = index);
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

  String _formatTodayVietnamese() {
    final now = DateTime.now();
    const days = [
      'Chủ nhật',
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
    ];
    final weekday = days[now.weekday % 7];
    return '$weekday, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    final title = _currentPage < _pageTitles.length
        ? _pageTitles[_currentPage]
        : 'Quản trị';

    final totalEmployees = c.data.employees.length;

    final String subtitle = switch (_currentPage) {
      0 => '${_formatTodayVietnamese()} • $totalEmployees nhân viên',
      1 => 'Tổng số $totalEmployees nhân sự',
      2 => 'Theo dõi và xuất dữ liệu công',
      3 => 'Duyệt đơn nghỉ phép, bổ sung công',
      4 => 'Quản trị hệ thống & Cài đặt',
      _ => 'Chấm công • Tống Nhật Bảo An',
    };

    final pendingCount = _pendingRequestsCount;

    final currentContent = widget.pageBuilder != null
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
            2 => AdminTimesheetScreen(
                controller: c,
              ),
            3 => AdminRequestsScreen(
                controller: c,
              ),
            4 => AdminMoreScreen(
                controller: c,
                onLogout: _handleLogout,
                onNavigateTab: (idx) => setState(() => _currentPage = idx),
              ),
            _ => Center(
                child: Text(
                  'Trang: $title',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Thanh tiến trình đồng bộ mỏng
            if (c.isSyncing)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.tealLight),
              ),

            // Header gradient chéo navy -> teal, đáy bo 28, huy hiệu Quản trị
            AppHeader(
              title: title,
              subtitle: subtitle,
              roleName: 'Quản trị',
              roleIcon: Icons.shield_outlined,
              lastUpdated: c.lastSyncedAt,
              onRefresh: c.isSyncing ? null : c.syncAll,
            ),

            // Nội dung chính đè lên header 24px + Chuyển tab fade-through 250ms
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -24),
                child: RefreshIndicator(
                  onRefresh: () async {
                    await c.syncAll();
                  },
                  color: AppColors.teal,
                  backgroundColor: AppColors.surface,
                  child: PageTransitionSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, primaryAnimation, secondaryAnimation) {
                      return FadeThroughTransition(
                        animation: primaryAnimation,
                        secondaryAnimation: secondaryAnimation,
                        child: child,
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<int>(_currentPage),
                      child: currentContent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // NavigationBar 5 tab cố định: [Tổng quan, Nhân sự, Bảng công, Đơn từ, Thêm]
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: AppTheme.navBarShadow,
        ),
        child: NavigationBar(
          selectedIndex: _currentPage.clamp(0, 4),
          onDestinationSelected: _onNavDestinationSelected,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded, color: AppColors.teal),
              label: 'Tổng quan',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_alt_outlined),
              selectedIcon: Icon(Icons.people_alt_rounded, color: AppColors.teal),
              label: 'Nhân sự',
            ),
            const NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded, color: AppColors.teal),
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
                      child: const Icon(Icons.assignment_rounded, color: AppColors.teal),
                    )
                  : const Icon(Icons.assignment_rounded, color: AppColors.teal),
              label: 'Đơn từ',
            ),
            const NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded, color: AppColors.teal),
              label: 'Thêm',
            ),
          ],
        ),
      ),
    );
  }
}
