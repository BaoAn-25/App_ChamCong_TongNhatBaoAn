import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import '../../app_config.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';
import 'employee_history_screen.dart';
import 'admin_management_dialogs.dart';

/// Màn hình Quản lý Nhân sự dành cho Admin:
/// 5. Khối Văn phòng chấm công: Tên, bán kính, tọa độ rút gọn; 2 nút Cấu hình & Dùng vị trí hiện tại bằng nhau; nút QR chỉ hiện khi requireQr = true; form cấu hình là Bottom Sheet.
/// 6. Hướng dẫn quy trình 3 bước có icon (Văn phòng, Ca làm, Phân ca), không dùng ký tự mũi tên.
/// 7. Danh sách tài khoản dạng thẻ: avatar chữ cái, tên, @username, phòng ban, role badge, trạng thái hoạt động/khóa; Menu ⋮ (Sửa, Phân ca, Khóa/Mở, Xóa - chỉ xóa khi chưa có lịch sử).
/// 8. Ô tìm kiếm cố định phía trên, chip lọc cuộn ngang, FAB nổi "Thêm nhân viên".
/// 9. Form Thêm/Sửa nhân viên dạng Bottom Sheet chia nhóm (Thông tin, Phân quyền, Ca làm, Mật khẩu), lỗi dưới từng ô, nút gửi có loading.
class AdminManageScreen extends StatefulWidget {
  final AppController controller;
  final VoidCallback? onOfficeUpdated;

  const AdminManageScreen({
    super.key,
    required this.controller,
    this.onOfficeUpdated,
  });

  @override
  State<AdminManageScreen> createState() => _AdminManageScreenState();
}

class _AdminManageScreenState extends State<AdminManageScreen> {
  String _searchQuery = '';
  String _roleFilter = 'all';
  String? _deptFilter;
  bool _isGettingLocation = false;

  AppController get c => widget.controller;

  // Lọc danh sách nhân viên theo tìm kiếm và bộ lọc
  List<Employee> get _filteredEmployees {
    return c.data.employees.where((e) {
      final searchStr = '${e.name} ${e.username} ${e.department}'.toLowerCase();
      if (_searchQuery.isNotEmpty && !searchStr.contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (_roleFilter == 'admin' && !e.isAdmin) return false;
      if (_roleFilter == 'manager' && !e.isManager) return false;
      if (_roleFilter == 'employee' && (e.isAdmin || e.isManager)) return false;
      if (_roleFilter == 'locked' && e.active) return false;

      if (_deptFilter != null &&
          e.department.toLowerCase() != _deptFilter!.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  // Kiểm tra nhân viên đã từng có bản ghi chấm công nào chưa
  bool _hasAttendanceHistory(String employeeId) {
    return c.data.attendance.any((a) => a.employeeId == employeeId);
  }

  /// Lấy GPS nhanh cho văn phòng
  Future<void> _useCurrentLocationForOffice() async {
    setState(() => _isGettingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Vui lòng bật dịch vụ định vị (GPS) trên thiết bị.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw StateError('Quyền truy cập vị trí bị từ chối.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError('Quyền vị trí bị từ chối vĩnh viễn. Vui lòng mở Cài đặt ứng dụng để cấp quyền.');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final currentOffice = c.data.office;
      final updatedOffice = Office(
        name: currentOffice.name.isEmpty ? 'Văn phòng chính' : currentOffice.name,
        qrSecret: currentOffice.qrSecret,
        latitude: pos.latitude,
        longitude: pos.longitude,
        radius: currentOffice.radius <= 0 ? 150 : currentOffice.radius,
        isServerConfigured: true,
      );

      await c.saveOffice(updatedOffice);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật tọa độ văn phòng theo vị trí hiện tại thành công!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '')}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  /// Mở Bottom Sheet cấu hình văn phòng
  void _openOfficeConfigSheet() {
    OfficeConfigSheet.show(context, c, onSaved: () => setState(() {}));
  }

  /// Mở Bottom Sheet thêm hoặc chỉnh sửa nhân viên
  void _openEmployeeSheet([Employee? employee]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeFormSheet(
        controller: c,
        employee: employee,
        onSaved: () => setState(() {}),
      ),
    );
  }

  /// Phân ca nhanh cho nhân viên
  Future<void> _openAssignShiftDialog(Employee employee) async {
    String? selectedShiftId = employee.shiftId;

    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusCard),
          title: Row(
            children: [
              const Icon(Icons.schedule_rounded, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Phân ca cho ${employee.name}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Chưa phân ca'),
                  trailing: selectedShiftId == null
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.teal)
                      : null,
                  onTap: () => setDialogState(() => selectedShiftId = null),
                ),
                for (final s in c.data.shifts)
                  ListTile(
                    title: Text(s.name),
                    subtitle: Text(
                      '${(s.startMinute ~/ 60).toString().padLeft(2, '0')}:${(s.startMinute % 60).toString().padLeft(2, '0')} - '
                      '${(s.endMinute ~/ 60).toString().padLeft(2, '0')}:${(s.endMinute % 60).toString().padLeft(2, '0')}',
                    ),
                    trailing: selectedShiftId == s.id
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.teal)
                        : null,
                    onTap: () => setDialogState(() => selectedShiftId = s.id),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Huỷ'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.teal,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, selectedShiftId ?? ''),
              child: const Text('Lưu ca làm'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      final copy = Employee.fromJson(employee.toJson());
      copy.shiftId = result.isEmpty ? null : result;
      await c.saveEmployee(copy);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = _filteredEmployees;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEmployeeSheet(),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Thêm nhân viên',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ==========================================================
                  // 5. KHỐI VĂN PHÒNG CHẤM CÔNG
                  // ==========================================================
                  _buildOfficeSection(),
                  const SizedBox(height: 16),

                  // ==========================================================
                  // 6. QUY TRÌNH HƯỚNG DẪN 3 BƯỚC (Không dùng mũi tên ->)
                  // ==========================================================
                  _buildWorkflowStepsCard(),
                  const SizedBox(height: 20),

                  // ==========================================================
                  // 8. TÌM KIẾM CỐ ĐỊNH & BỘ LỌC
                  // ==========================================================
                  _buildSearchAndFilters(),
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Danh sách tài khoản (${employees.length})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tổng: ${c.data.employees.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ==================================================================
          // 7. DANH SÁCH TÀI KHOẢN DẠNG THẺ
          // ==================================================================
          if (employees.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: EmptyState(
                  title: 'Không tìm thấy tài khoản',
                  description: 'Thử thay đổi từ khoá tìm kiếm hoặc đặt lại bộ lọc vai trò/phòng ban.',
                  icon: Icons.person_search_rounded,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final employee = employees[index];
                    return _buildEmployeeCard(employee);
                  },
                  childCount: employees.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 5. Khối Văn phòng chấm công
  Widget _buildOfficeSection() {
    final office = c.data.office;
    final hasCoords = office.latitude != null && office.longitude != null;
    final coordStr = hasCoords
        ? '${office.latitude!.toStringAsFixed(4)}, ${office.longitude!.toStringAsFixed(4)}'
        : 'Chưa ghim tọa độ';

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.business_rounded, color: AppColors.teal, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      office.name.isEmpty ? 'Văn phòng chính' : office.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bán kính: ${office.radius.round()}m • Tọa độ: $coordStr',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasCoords ? AppColors.successBg : AppColors.warningBg,
                  borderRadius: AppTheme.radiusChip,
                ),
                child: Text(
                  hasCoords ? 'Đã ghim' : 'Chưa ghim',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: hasCoords ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Hai nút cùng kiểu, chiều rộng bằng nhau
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  title: 'Cấu hình',
                  icon: Icons.tune_rounded,
                  height: 44,
                  onPressed: _openOfficeConfigSheet,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  title: _isGettingLocation ? 'Đang lấy...' : 'Vị trí hiện tại',
                  icon: Icons.my_location_rounded,
                  height: 44,
                  onPressed: _isGettingLocation ? null : _useCurrentLocationForOffice,
                ),
              ),
            ],
          ),

          // Nút QR chỉ xuất hiện khi requireQr = true
          if (AppConfig.requireQr) ...[
            const SizedBox(height: 10),
            SecondaryButton(
              title: 'Mã QR chấm công',
              icon: Icons.qr_code_2_rounded,
              height: 44,
              onPressed: () {
                // Hiển thị dialog QR
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Mã QR văn phòng'),
                    content: const Text('Mã QR động dành cho nhân viên quét check-in/out.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // 6. Quy trình hướng dẫn 3 bước (Không có dấu mũi tên ->)
  Widget _buildWorkflowStepsCard() {
    return AppCard(
      color: AppColors.input,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: _buildStepItem('1', 'Văn phòng', Icons.location_on_outlined, true)),
          Container(width: 8, height: 1, color: AppColors.border),
          Flexible(child: _buildStepItem('2', 'Ca làm', Icons.schedule_rounded, c.data.shifts.isNotEmpty)),
          Container(width: 8, height: 1, color: AppColors.border),
          Flexible(
            child: _buildStepItem(
              '3',
              'Phân ca',
              Icons.people_outline_rounded,
              c.data.employees.any((e) => e.shiftId != null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem(String number, String label, IconData icon, bool done) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: done ? AppColors.teal : AppColors.border,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : Text(
                    number,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: done ? FontWeight.w700 : FontWeight.w500,
              color: done ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  // 8. Ô tìm kiếm cố định và bộ lọc
  Widget _buildSearchAndFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hàng ô tìm kiếm + nút Quản lý Phòng ban
        Row(
          children: [
            Expanded(
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên, tài khoản, phòng ban...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => DepartmentManagementSheet.show(context, c),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: const Row(
                  children: [
                    Icon(Icons.apartment_rounded, size: 18, color: AppColors.teal),
                    SizedBox(width: 4),
                    Text(
                      'Phòng ban',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.teal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Hàng chip lọc vai trò và phòng ban cuộn ngang
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildRoleFilterChip('Tất cả', 'all'),
              const SizedBox(width: 6),
              _buildRoleFilterChip('Admin', 'admin'),
              const SizedBox(width: 6),
              _buildRoleFilterChip('Quản lý', 'manager'),
              const SizedBox(width: 6),
              _buildRoleFilterChip('Nhân viên', 'employee'),
              const SizedBox(width: 6),
              _buildRoleFilterChip('Đã khóa', 'locked'),
              if (c.data.departments.isNotEmpty) ...[
                const SizedBox(width: 12),
                Container(width: 1, height: 20, color: AppColors.border),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Mọi phòng ban', style: TextStyle(fontSize: 12)),
                  selected: _deptFilter == null,
                  onSelected: (_) => setState(() => _deptFilter = null),
                ),
                for (final d in c.data.departments) ...[
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: Text(d.name, style: const TextStyle(fontSize: 12)),
                    selected: _deptFilter?.toLowerCase() == d.name.toLowerCase(),
                    onSelected: (sel) => setState(() => _deptFilter = sel ? d.name : null),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoleFilterChip(String label, String value) {
    final isSelected = _roleFilter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => setState(() => _roleFilter = value),
      selectedColor: AppColors.teal.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.teal : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  // 7. Thẻ nhân viên
  Widget _buildEmployeeCard(Employee employee) {
    final hasHistory = _hasAttendanceHistory(employee.id);
    final shiftName = c.data.shifts
            .where((s) => s.id == employee.shiftId)
            .firstOrNull
            ?.name ??
        'Chưa phân ca';

    Color roleColor;
    String roleLabel;
    if (employee.isAdmin) {
      roleColor = Colors.deepPurple;
      roleLabel = 'ADMIN';
    } else if (employee.isManager) {
      roleColor = AppColors.teal;
      roleLabel = 'QUẢN LÝ';
    } else {
      roleColor = AppColors.info;
      roleLabel = 'NHÂN VIÊN';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar chữ cái
            CircleAvatar(
              radius: 22,
              backgroundColor: roleColor.withValues(alpha: 0.12),
              child: Text(
                employee.name.isNotEmpty ? employee.name[0].toUpperCase() : 'U',
                style: TextStyle(
                  color: roleColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Thông tin tài khoản
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          employee.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Chấm trạng thái hoạt động/khóa
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: employee.active ? AppColors.success : AppColors.error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${employee.username} • ${employee.department.isEmpty ? 'Chưa có phòng ban' : employee.department}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Chip vai trò & Ca làm
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: roleColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: roleColor.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: roleColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                shiftName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: employee.shiftId == null
                                      ? AppColors.warning
                                      : AppColors.textSecondary,
                                  fontWeight: employee.shiftId == null
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Menu thao tác ⋮
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (val) async {
                if (val == 'history') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmployeeHistoryScreen(
                        controller: c,
                        userId: employee.id,
                      ),
                    ),
                  );
                } else if (val == 'edit') {
                  _openEmployeeSheet(employee);
                } else if (val == 'assign_shift') {
                  _openAssignShiftDialog(employee);
                } else if (val == 'toggle_lock') {
                  final copy = Employee.fromJson(employee.toJson())..active = !employee.active;
                  await c.saveEmployee(copy);
                  setState(() {});
                } else if (val == 'delete') {
                  if (hasHistory) return;
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xác nhận xóa tài khoản'),
                      content: Text('Bạn có chắc chắn muốn xóa tài khoản ${employee.name}? Hành động này không thể hoàn tác.'),
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
                          child: const Text('Xóa vĩnh viễn'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    await c.deleteEmployee(employee.id);
                    setState(() {});
                  }
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'history',
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, size: 18, color: AppColors.teal),
                      SizedBox(width: 8),
                      Text('Lịch sử chấm công'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Sửa thông tin'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'assign_shift',
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Phân ca làm việc'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle_lock',
                  child: Row(
                    children: [
                      Icon(
                        employee.active ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(employee.active ? 'Khóa tài khoản' : 'Mở khóa tài khoản'),
                    ],
                  ),
                ),
                // Mục XÓA: vô hiệu hóa nếu có lịch sử
                PopupMenuItem(
                  value: 'delete',
                  enabled: !hasHistory,
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_outline_rounded,
                        size: 18,
                        color: hasHistory ? Colors.grey : AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Xóa tài khoản',
                            style: TextStyle(
                              color: hasHistory ? Colors.grey : AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (hasHistory)
                            const Text(
                              'Có lịch sử, hãy khóa tài khoản',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 9. FORM THÊM / SỬA NHÂN VIÊN (BOTTOM SHEET, 4 NHÓM RÕ RÀNG)
// ============================================================================
class _EmployeeFormSheet extends StatefulWidget {
  final AppController controller;
  final Employee? employee;
  final VoidCallback onSaved;

  const _EmployeeFormSheet({
    required this.controller,
    this.employee,
    required this.onSaved,
  });

  @override
  State<_EmployeeFormSheet> createState() => _EmployeeFormSheetState();
}

class _EmployeeFormSheetState extends State<_EmployeeFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;

  late String _role;
  late bool _active;
  String? _shiftId;
  String? _dept;
  bool _obscurePass = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _usernameCtrl = TextEditingController(text: e?.username ?? '');
    _passwordCtrl = TextEditingController();
    _role = e?.role ?? 'employee';
    _active = e?.active ?? true;
    _shiftId = e?.shiftId;
    _dept = (e?.department.isNotEmpty ?? false) ? e!.department : null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    try {
      final isNew = widget.employee == null;
      final emp = Employee(
        id: widget.employee?.id ?? newId(),
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        department: _dept ?? '',
        role: _role,
        active: _active,
        shiftId: _shiftId,
      );

      final pass = _passwordCtrl.text.trim();
      await widget.controller.saveEmployee(
        emp,
        password: pass.isEmpty ? null : pass,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isNew ? 'Đã thêm nhân viên thành công!' : 'Đã cập nhật thông tin nhân viên!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.employee == null;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    isNew ? Icons.person_add_alt_1_rounded : Icons.edit_note_rounded,
                    color: AppColors.teal,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isNew ? 'Thêm nhân viên mới' : 'Chỉnh sửa nhân viên',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // --- NHÓM 1: THÔNG TIN CƠ BẢN ---
                    _buildGroupHeader('1. Thông tin cơ bản'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Họ và tên *',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (val) =>
                          (val == null || val.trim().isEmpty) ? 'Vui lòng nhập họ và tên' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ Email *',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Vui lòng nhập Email';
                        if (!val.contains('@')) return 'Email không hợp lệ';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên đăng nhập *',
                        prefixIcon: Icon(Icons.account_circle_outlined),
                      ),
                      validator: (val) =>
                          (val == null || val.trim().isEmpty) ? 'Vui lòng nhập tên đăng nhập' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: _dept,
                      decoration: const InputDecoration(
                        labelText: 'Phòng ban trực thuộc',
                        prefixIcon: Icon(Icons.corporate_fare_outlined),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Chưa phân phòng ban')),
                        for (final d in widget.controller.data.departments)
                          DropdownMenuItem(value: d.name, child: Text(d.name)),
                      ],
                      onChanged: (val) => setState(() => _dept = val),
                    ),
                    const SizedBox(height: 24),

                    // --- NHÓM 2: PHÂN QUYỀN & TRẠNG THÁI ---
                    _buildGroupHeader('2. Phân quyền & Trạng thái'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: const InputDecoration(
                        labelText: 'Vai trò tài khoản *',
                        prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'employee', child: Text('Nhân viên (Employee)')),
                        DropdownMenuItem(value: 'manager', child: Text('Quản lý (Manager)')),
                        DropdownMenuItem(value: 'admin', child: Text('Quản trị viên (Admin)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _role = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<bool>(
                      initialValue: _active,
                      decoration: const InputDecoration(
                        labelText: 'Trạng thái hoạt động *',
                        prefixIcon: Icon(Icons.toggle_on_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: true, child: Text('Đang hoạt động (Active)')),
                        DropdownMenuItem(value: false, child: Text('Đang khóa (Locked)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _active = val);
                      },
                    ),
                    const SizedBox(height: 24),

                    // --- NHÓM 3: CA LÀM VIỆC ---
                    _buildGroupHeader('3. Ca làm việc'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      initialValue: _shiftId,
                      decoration: const InputDecoration(
                        labelText: 'Phân ca mặc định',
                        prefixIcon: Icon(Icons.schedule_rounded),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Chưa phân ca')),
                        for (final s in widget.controller.data.shifts)
                          DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              '${s.name} (${(s.startMinute ~/ 60).toString().padLeft(2, '0')}:${(s.startMinute % 60).toString().padLeft(2, '0')} - ${(s.endMinute ~/ 60).toString().padLeft(2, '0')}:${(s.endMinute % 60).toString().padLeft(2, '0')})',
                            ),
                          ),
                      ],
                      onChanged: (val) => setState(() => _shiftId = val),
                    ),
                    const SizedBox(height: 24),

                    // --- NHÓM 4: MẬT KHẨU ---
                    _buildGroupHeader('4. Mật khẩu tài khoản'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePass,
                      decoration: InputDecoration(
                        labelText: isNew
                            ? 'Mật khẩu khởi tạo * (tối thiểu 8 ký tự)'
                            : 'Mật khẩu mới (để trống nếu giữ nguyên)',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                      validator: (val) {
                        if (isNew && (val == null || val.length < 8)) {
                          return 'Mật khẩu khởi tạo phải từ 8 ký tự trở lên';
                        }
                        if (!isNew && val != null && val.isNotEmpty && val.length < 8) {
                          return 'Mật khẩu mới phải từ 8 ký tự trở lên';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),

                    // Nút lưu có loading
                    PrimaryButton(
                      title: isNew ? 'Thêm nhân viên' : 'Lưu thay đổi',
                      isLoading: _busy,
                      onPressed: _handleSubmit,
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.teal,
      ),
    );
  }
}

// ============================================================================
// FORM CẤU HÌNH VĂN PHÒNG (BOTTOM SHEET)
// ============================================================================
class OfficeConfigSheet extends StatefulWidget {
  final AppController controller;
  final VoidCallback onSaved;

  const OfficeConfigSheet({
    super.key,
    required this.controller,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context,
    AppController controller, {
    VoidCallback? onSaved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OfficeConfigSheet(
        controller: controller,
        onSaved: onSaved ?? () {},
      ),
    );
  }

  @override
  State<OfficeConfigSheet> createState() => _OfficeConfigSheetState();
}

class _OfficeConfigSheetState extends State<OfficeConfigSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _radiusCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _addressCtrl;
  bool _busy = false;
  bool _isGeocoding = false;

  @override
  void initState() {
    super.initState();
    final o = widget.controller.data.office;
    _nameCtrl = TextEditingController(text: o.name);
    _radiusCtrl = TextEditingController(text: o.radius.round().toString());
    _latCtrl = TextEditingController(text: o.latitude?.toString() ?? '');
    _lngCtrl = TextEditingController(text: o.longitude?.toString() ?? '');
    _addressCtrl = TextEditingController();

    if (o.latitude != null && o.longitude != null && o.latitude != 0) {
      geo.Geocoding().placemarkFromCoordinates(o.latitude!, o.longitude!).then((placemarks) {
        if (placemarks.isNotEmpty && mounted) {
          final p = placemarks.first;
          final addr = [p.street, p.subAdministrativeArea, p.administrativeArea]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(', ');
          if (addr.isNotEmpty && _addressCtrl.text.isEmpty) {
            _addressCtrl.text = addr;
          }
        }
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _radiusCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchAddress() async {
    final query = _addressCtrl.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập địa chỉ cần tìm.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isGeocoding = true);
    try {
      final locations = await geo.Geocoding().locationFromAddress(query);
      if (locations.isNotEmpty) {
        final loc = locations.first;
        _latCtrl.text = loc.latitude.toStringAsFixed(6);
        _lngCtrl.text = loc.longitude.toStringAsFixed(6);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã định vị tọa độ: ${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không tìm thấy tọa độ cho địa chỉ này.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi tìm địa chỉ: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isGeocoding = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _latCtrl.text = pos.latitude.toStringAsFixed(6);
      _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      try {
        final placemarks = await geo.Geocoding().placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty && mounted) {
          final p = placemarks.first;
          final addr = [p.street, p.subAdministrativeArea, p.administrativeArea]
              .whereType<String>()
              .where((s) => s.trim().isNotEmpty)
              .join(', ');
          if (addr.isNotEmpty) _addressCtrl.text = addr;
        }
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã lấy vị trí hiện tại: ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi lấy GPS: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final name = _nameCtrl.text.trim();
      final radius = double.tryParse(_radiusCtrl.text) ?? 150.0;
      final lat = double.tryParse(_latCtrl.text);
      final lng = double.tryParse(_lngCtrl.text);

      final office = Office(
        name: name.isEmpty ? 'Văn phòng chính' : name,
        radius: radius,
        latitude: lat,
        longitude: lng,
        qrSecret: widget.controller.data.office.qrSecret,
        isServerConfigured: true,
      );

      await widget.controller.saveOffice(office);
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật cấu hình văn phòng thành công!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.business_rounded, color: AppColors.teal),
                    SizedBox(width: 10),
                    Text(
                      'Cấu hình văn phòng chấm công',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên văn phòng *'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên văn phòng' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _radiusCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bán kính cho phép (mét) *',
                    suffixText: 'm',
                  ),
                  validator: (v) => (double.tryParse(v ?? '') == null) ? 'Bán kính không hợp lệ' : null,
                ),
                const SizedBox(height: 12),
                // Ô tìm vị trí theo địa chỉ
                TextFormField(
                  controller: _addressCtrl,
                  decoration: InputDecoration(
                    labelText: 'Tìm tọa độ theo địa chỉ',
                    hintText: 'VD: 227 Nguyễn Văn Cừ, Quận 5, TP.HCM',
                    prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.teal),
                    suffixIcon: _isGeocoding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.teal),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search_rounded, color: AppColors.teal),
                            tooltip: 'Tìm tọa độ',
                            onPressed: _searchAddress,
                          ),
                  ),
                  onFieldSubmitted: (_) => _searchAddress(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isGeocoding ? null : _searchAddress,
                        icon: const Icon(Icons.search_rounded, size: 16),
                        label: const Text('Tìm từ địa chỉ', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.teal,
                          side: const BorderSide(color: AppColors.teal),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isGeocoding ? null : _useCurrentLocation,
                        icon: const Icon(Icons.my_location_rounded, size: 16),
                        label: const Text('Lấy GPS hiện tại', style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.teal,
                          side: const BorderSide(color: AppColors.teal),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Vĩ độ (Latitude)'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _lngCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Kinh độ (Longitude)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  title: 'Lưu cấu hình văn phòng',
                  isLoading: _busy,
                  onPressed: _handleSave,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
