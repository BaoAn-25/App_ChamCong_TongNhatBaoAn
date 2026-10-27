import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../session_storage.dart';
import '../../widgets/app_widgets.dart';
import '../admin/timesheet_screen.dart';
import '../admin/requests_screen.dart';
import 'manager_dashboard_screen.dart';
import 'manager_team_screen.dart';
import 'manager_more_screen.dart';

/// Khung điều hướng Quản lý (Manager Shell):
/// - 5 tab: [0: Tổng quan, 1: Nhóm, 2: Bảng công, 3: Đơn từ (có badge), 4: Thêm]
/// - Toàn bộ dữ liệu được giới hạn trong phòng ban của Quản lý (c.user?.department)
class ManagerShell extends StatefulWidget {
  final AppController controller;
  final int initialPage;
  final VoidCallback? onLogout;

  const ManagerShell({
    super.key,
    required this.controller,
    this.initialPage = 0,
    this.onLogout,
  });

  @override
  State<ManagerShell> createState() => _ManagerShellState();
}

class _ManagerShellState extends State<ManagerShell> {
  late int _currentPage;

  static const List<String> _pageTitles = [
    'Tổng quan nhóm',
    'Nhân sự phòng ban',
    'Bảng công nhóm',
    'Quản lý đơn từ',
    'Thêm',
  ];

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialPage;
  }

  AppController get c => widget.controller;

  String get _managerDept => c.user?.department.isNotEmpty == true
      ? c.user!.department
      : (c.data.departments.isNotEmpty ? c.data.departments.first.name : 'Kinh doanh');

  int get _pendingRequestsCount {
    try {
      final deptEmployees = c.data.employees
          .where((e) => e.department.toLowerCase() == _managerDept.toLowerCase())
          .map((e) => e.id)
          .toSet();

      return c.data.requests
          .where((r) => r.employeeId != c.user?.id && deptEmployees.contains(r.employeeId) && r.status == 'pending')
          .length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản Quản lý?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await SessionStorage.clearSession();
      await c.logout();
      if (widget.onLogout != null) widget.onLogout!();
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
    final deptEmployeesCount = c.data.employees
        .where((e) => e.active && e.department.toLowerCase() == _managerDept.toLowerCase())
        .length;

    final String title = _currentPage < _pageTitles.length ? _pageTitles[_currentPage] : 'Quản lý';

    final String subtitle = switch (_currentPage) {
      0 => '${_formatTodayVietnamese()} • Phòng $_managerDept',
      1 => 'Phòng $_managerDept • $deptEmployeesCount thành viên',
      2 => 'Bảng chấm công phòng $_managerDept',
      3 => 'Duyệt đơn phòng $_managerDept',
      4 => 'Quản lý phòng $_managerDept',
      _ => 'Quản lý phòng $_managerDept',
    };

    final pendingCount = _pendingRequestsCount;

    final currentContent = switch (_currentPage) {
      0 => ManagerDashboardScreen(
          controller: c,
          onNavigateToTeam: () => setState(() => _currentPage = 1),
          onNavigateToTimesheet: () => setState(() => _currentPage = 2),
          onNavigateToRequests: () => setState(() => _currentPage = 3),
        ),
      1 => ManagerTeamScreen(controller: c),
      2 => AdminTimesheetScreen(controller: c),
      3 => AdminRequestsScreen(controller: c),
      4 => ManagerMoreScreen(
          controller: c,
          onLogout: _handleLogout,
          onNavigateTab: (idx) => setState(() => _currentPage = idx),
        ),
      _ => Center(child: Text('Trang: $title')),
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (c.isSyncing)
              const LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.tealLight),
              ),

            // Header gradient chéo navy -> teal, có huy hiệu Quản lý
            AppHeader(
              title: title,
              subtitle: subtitle,
              roleName: 'Quản lý',
              roleIcon: Icons.groups_rounded,
              lastUpdated: c.lastSyncedAt,
              onRefresh: c.isSyncing ? null : c.syncAll,
            ),

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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: AppTheme.navBarShadow,
        ),
        child: NavigationBar(
          selectedIndex: _currentPage.clamp(0, 4),
          onDestinationSelected: (idx) => setState(() => _currentPage = idx),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded, color: AppColors.teal),
              label: 'Tổng quan',
            ),
            const NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded, color: AppColors.teal),
              label: 'Nhóm',
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
