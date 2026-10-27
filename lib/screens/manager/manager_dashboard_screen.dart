import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';
import '../admin/attendance_map_screen.dart';

/// Màn hình Tổng quan Nhóm dành cho Quản lý (Manager Dashboard - Screen 12)
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



  String _typeLabel(String type) => switch (type) {
    'leave' => 'Nghỉ phép',
    'late' => 'Giải trình trễ',
    'forgot_checkout' => 'Bổ sung giờ ra',
    _ => type,
  };

  Future<void> _handleQuickReview(WorkRequest request, bool approve) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusDialog),
        title: Row(
          children: [
            Icon(
              approve ? Icons.check_circle_outline : Icons.highlight_off_rounded,
              color: approve ? AppColors.success : AppColors.error,
              size: 26,
            ),
            const SizedBox(width: 10),
            Text(approve ? 'Xác nhận duyệt đơn' : 'Từ chối đơn từ'),
          ],
        ),
        content: Text(
          approve
              ? 'Bạn có đồng ý duyệt đơn ${_typeLabel(request.type)} của nhân viên ${_getEmployeeName(request.employeeId)}?'
              : 'Bạn có chắc chắn muốn từ chối đơn này?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Đóng'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? AppColors.success : AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(approve ? 'Duyệt đơn' : 'Từ chối'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await c.reviewRequest(
          request.id,
          approve,
          approve ? 'Quản lý phòng $_managerDept đã duyệt' : 'Quản lý từ chối',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(approve ? 'Đã duyệt đơn thành công!' : 'Đã từ chối đơn từ.'),
              backgroundColor: approve ? AppColors.success : AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi: ${e.toString().replaceAll("Exception: ", "")}'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  String _getEmployeeName(String employeeId) {
    final emp = c.data.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.name ?? 'Nhân viên';
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
        // 1. LƯỚI STAT CARD 2x2 CỦA PHÒNG BAN (Screen 12)
        // ====================================================================
        _buildStatGrid(
          presentText: '$presentCount/$totalDeptCount',
          lateCount: lateCount,
          notCheckedInCount: notCheckedInCount,
          pendingRequestsCount: pendingRequests.length,
        ),
        const SizedBox(height: 16),

        // ====================================================================
        // 2. BANNER THÔNG BÁO ĐƠN CHỜ DUYỆT (Nếu có đơn pending)
        // ====================================================================
        if (pendingRequests.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mark_email_unread_rounded, color: Colors.white, size: 18),
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
                          fontSize: 14,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Nghỉ phép, giải trình thiếu giờ ra',
                        style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: widget.onNavigateToRequests,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFFEF3C7),
                    foregroundColor: const Color(0xFF92400E),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Xem', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ====================================================================
        // 3. THAO TÁC NHANH LƯỚI 4 Ô DÀNH CHO QUẢN LÝ
        // ====================================================================
        const SectionHeader(
          title: 'Thao tác nhóm',
          subtitle: 'Truy cập nhanh nghiệp vụ quản lý phòng ban',
        ),
        const SizedBox(height: 8),
        _buildQuickActionsGrid(context, pendingRequests.length),
        const SizedBox(height: 20),

        // ====================================================================
        // 4. PHẦN DUYỆT ĐƠN NHANH (QUICK APPROVAL)
        // ====================================================================
        SectionHeader(
          title: 'Duyệt đơn nhanh',
          subtitle: 'Xử lý ngay các đơn từ của nhóm',
          actionText: 'Tất cả đơn',
          onAction: widget.onNavigateToRequests,
        ),
        const SizedBox(height: 8),
        if (pendingRequests.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 28),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Không có đơn chờ duyệt', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.navy)),
                      SizedBox(height: 2),
                      Text('Tất cả đơn từ của phòng ban đã được xử lý xong.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pendingRequests.take(3).length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final req = pendingRequests[i];
              final empName = _getEmployeeName(req.employeeId);
              return Container(
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          empName,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.navy),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _typeLabel(req.type),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.teal),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lý do: ${req.reason}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => _handleQuickReview(req, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('Từ chối', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _handleQuickReview(req, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                          child: const Text('Duyệt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 24),

        // ====================================================================
        // 5. PHẦN NHÓM HÔM NAY (DEPARTMENT EMPLOYEES TODAY)
        // ====================================================================
        SectionHeader(
          title: 'Nhóm hôm nay',
          subtitle: 'Tình trạng điểm danh phòng $_managerDept',
          actionText: 'Xem bảng công',
          onAction: widget.onNavigateToTimesheet,
        ),
        const SizedBox(height: 8),
        _buildDepartmentTodayList(context, deptEmployees, todayAttendances),
        const SizedBox(height: 20),

        // ====================================================================
        // 6. GHI CHÚ BẢO MẬT PHÂN QUYỀN (FOOTER NOTICE)
        // ====================================================================
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bạn chỉ xem và quản lý nhân viên thuộc phòng $_managerDept',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // 1. Lưới StatCard 2x2 cho Quản lý
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
              child: StatCard(
                title: 'Có mặt hôm nay',
                value: presentText,
                icon: Icons.how_to_reg_rounded,
                iconColor: AppColors.success,
                subtitle: 'Nhân sự trong phòng',
                onTap: widget.onNavigateToTeam,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: 'Đi trễ hôm nay',
                value: '$lateCount',
                icon: Icons.alarm_off_outlined,
                iconColor: AppColors.warning,
                subtitle: 'Vào trễ so với ca',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                title: 'Chưa chấm công',
                value: '$notCheckedInCount',
                icon: Icons.person_off_outlined,
                iconColor: AppColors.error,
                subtitle: 'Vắng hoặc chưa tới',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatCard(
                title: 'Đơn chờ duyệt',
                value: '$pendingRequestsCount',
                icon: Icons.assignment_turned_in_outlined,
                iconColor: const Color(0xFF8B5CF6),
                subtitle: 'Cần bạn xử lý',
                onTap: widget.onNavigateToRequests,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 2. Thao tác nhanh 4 ô
  Widget _buildQuickActionsGrid(BuildContext context, int pendingRequestsCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12 * 3) / 4;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildActionItem(
              width: itemWidth,
              icon: Icons.schedule_rounded,
              color: const Color(0xFF0D9488),
              label: 'Tạo ca làm',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chức năng phân ca cho nhóm phòng ban.'), behavior: SnackBarBehavior.floating),
                );
              },
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
              label: 'Bản đồ nhóm',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AttendanceMapScreen(controller: c),
                ),
              ),
            ),
            _buildActionItem(
              width: itemWidth,
              icon: Icons.bar_chart_rounded,
              color: const Color(0xFF8B5CF6),
              label: 'Báo cáo',
              onTap: widget.onNavigateToTimesheet,
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

  // Danh sách nhân sự nhóm hôm nay
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
        if (att == null) {
          statusText = 'Chưa chấm công';
        } else if (att.lateMinutes > 0) {
          statusText = 'Trễ ${att.lateMinutes} phút';
        } else {
          statusText = 'Đúng giờ';
        }

        final checkInTimeStr = att != null
            ? '${att.checkIn.toLocal().hour.toString().padLeft(2, '0')}:${att.checkIn.toLocal().minute.toString().padLeft(2, '0')}'
            : '--:--';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.teal.withValues(alpha: 0.15),
                child: Text(
                  emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'N',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.teal),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emp.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.navy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Vào lúc: $checkInTimeStr • Ca hành chính',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              StatusChip(statusText),
            ],
          ),
        );
      },
    );
  }
}
