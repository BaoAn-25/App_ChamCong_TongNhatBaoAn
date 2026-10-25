import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/attendance_detail_sheet.dart';

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

  String _formatTodayVietnamese() {
    final now = DateTime.now();
    const days = [
      'Chủ nhật',
      'Thứ hai',
      'Thứ ba',
      'Thứ tư',
      'Thứ năm',
      'Thứ sáu',
      'Thứ bảy',
    ];
    final weekday = days[now.weekday % 7];
    return '$weekday, ngày ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ====================================================================
        // 1. THẺ CHÀO MỪNG (Gradient Navy → Teal, tên, role, ngày, nút chuyển tab)
        // ====================================================================
        _buildWelcomeBanner(context),
        const SizedBox(height: 20),

        // ====================================================================
        // 2. THAO TÁC NHANH LƯỚI 4 Ô (Icon trên, nhãn dưới)
        // ====================================================================
        const SectionHeader(
          title: 'Thao tác nhanh',
          subtitle: 'Truy cập nhanh các nghiệp vụ quản trị',
        ),
        const SizedBox(height: 8),
        _buildQuickActionsGrid(context, pendingRequestsCount),
        const SizedBox(height: 20),

        // ====================================================================
        // 3. LƯỚI STAT CARD 2x2 (Bấm được, số liệu trực quan)
        // ====================================================================
        const SectionHeader(
          title: 'Chỉ số hôm nay',
          subtitle: 'Theo dõi tình hình điểm danh thời gian thực',
        ),
        const SizedBox(height: 8),
        _buildStatGrid(
          presentText: '$presentEmployeesCount/${totalEmployees > 0 ? totalEmployees : c.data.employees.length}',
          lateCount: lateCount,
          notCheckedOutCount: notCheckedOutCount,
          pendingRequestsCount: pendingRequestsCount,
        ),
        const SizedBox(height: 24),

        // ====================================================================
        // 4. HOẠT ĐỘNG GẦN ĐÂY (StatusChip, bấm mở AttendanceDetailSheet)
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

  // 1. Thẻ chào mừng
  Widget _buildWelcomeBanner(BuildContext context) {
    final user = c.user;
    final userName = user?.name ?? 'Quản trị viên';
    final roleName = c.isAdmin
        ? 'Admin'
        : (user?.role == 'manager' ? 'Quản lý' : 'Nhân viên');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: AppTheme.radiusCard,
        gradient: const LinearGradient(
          colors: [AppColors.navy, AppColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.teal.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                child: Text(
                  userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xin chào, $userName',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatTodayVietnamese(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: AppTheme.radiusChip,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_outlined, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      roleName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Hệ thống đang quản lý ${c.data.employees.length} tài khoản và ${c.data.shifts.length} ca làm việc.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: widget.onNavigateToStaff,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_alt_outlined, size: 16, color: AppColors.navy),
                    SizedBox(width: 6),
                    Text(
                      'Đi tới Nhân sự',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.navy),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
              onTap: widget.onCreateShift ?? widget.onNavigateToStaff,
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
              onTap: () => _openAttendanceMapView(context),
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
                      Text(
                        empName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
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

  /// Mở giao diện Bản đồ chấm công hôm nay
  void _openAttendanceMapView(BuildContext context) {
    final todayPoints = _todayRecords
        .where((a) => a.latitude != 0 && a.longitude != 0)
        .map((a) => LatLng(a.latitude, a.longitude))
        .toList();

    final office = c.data.office;
    final officePoint = office.configured && office.latitude != null && office.longitude != null
        ? LatLng(office.latitude!, office.longitude!)
        : (todayPoints.isNotEmpty ? todayPoints.first : const LatLng(10.7769, 106.7009));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.map_rounded, color: AppColors.teal),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Bản đồ vị trí chấm công hôm nay',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: officePoint,
                    initialZoom: 15.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.app_cham_cong_tong_nhat_bao_an',
                    ),
                    MarkerLayer(
                      markers: [
                        if (office.configured && office.latitude != null)
                          Marker(
                            point: officePoint,
                            width: 50,
                            height: 50,
                            child: const Icon(
                              Icons.business_rounded,
                              color: AppColors.navy,
                              size: 40,
                            ),
                          ),
                        for (final a in _todayRecords.where((x) => x.latitude != 0))
                          Marker(
                            point: LatLng(a.latitude, a.longitude),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: AppColors.teal,
                              size: 34,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
