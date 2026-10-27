import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';

/// Modal Quản lý Phòng ban (Dành cho Admin)
class DepartmentManagementSheet extends StatefulWidget {
  final AppController controller;

  const DepartmentManagementSheet({super.key, required this.controller});

  static Future<void> show(BuildContext context, AppController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DepartmentManagementSheet(controller: controller),
    );
  }

  @override
  State<DepartmentManagementSheet> createState() => _DepartmentManagementSheetState();
}

class _DepartmentManagementSheetState extends State<DepartmentManagementSheet> {
  AppController get c => widget.controller;

  Future<void> _showEditDepartmentDialog([Department? dept]) async {
    final nameCtrl = TextEditingController(text: dept?.name ?? '');
    final descCtrl = TextEditingController(text: dept?.description ?? '');
    bool busy = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusDialog),
          title: Text(
            dept == null ? 'Thêm phòng ban mới' : 'Chỉnh sửa phòng ban',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      error!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12.5),
                    ),
                  ),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên phòng ban *',
                    hintText: 'Ví dụ: Kinh doanh, Kỹ thuật...',
                    prefixIcon: Icon(Icons.apartment_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả nhiệm vụ',
                    hintText: 'Mô tả vai trò hoạt động của phòng ban',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Huỷ'),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() => error = 'Vui lòng nhập tên phòng ban.');
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        final newDept = Department(
                          id: dept?.id ?? 'dept_${DateTime.now().millisecondsSinceEpoch}',
                          name: name,
                          description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                        );
                        await c.saveDepartment(newDept);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      } catch (e) {
                        setDialogState(() {
                          busy = false;
                          error = e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Lưu phòng ban'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Department dept) async {
    final employeesInDept = c.data.employees.where(
      (e) => e.department.toLowerCase() == dept.name.toLowerCase(),
    ).length;

    if (employeesInDept > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xóa: Có $employeesInDept nhân viên đang thuộc phòng ${dept.name}.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa phòng ban'),
        content: Text('Bạn có chắc chắn muốn xóa phòng "${dept.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await c.deleteDepartment(dept.id);
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final departments = c.data.departments;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quản lý phòng ban',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                    Text(
                      '${departments.length} phòng ban đang hoạt động',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showEditDepartmentDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Thêm mới'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: departments.isEmpty
                ? const Center(
                    child: EmptyState(
                      title: 'Chưa có phòng ban nào',
                      description: 'Bấm nút "Thêm mới" để tạo phòng ban cho công ty.',
                      icon: Icons.apartment_outlined,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: departments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (ctx, index) {
                      final dept = departments[index];
                      final empCount = c.data.employees.where(
                        (e) => e.department.toLowerCase() == dept.name.toLowerCase(),
                      ).length;

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.teal.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.apartment_rounded, color: AppColors.teal, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    dept.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    dept.description ?? 'Không có mô tả',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Text(
                                      '$empCount nhân sự',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.teal),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.teal),
                              onPressed: () => _showEditDepartmentDialog(dept),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                              onPressed: () => _confirmDelete(dept),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Modal Quản lý Ca làm việc (Dành cho Admin)
class ShiftManagementSheet extends StatefulWidget {
  final AppController controller;

  const ShiftManagementSheet({super.key, required this.controller});

  static Future<void> show(BuildContext context, AppController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShiftManagementSheet(controller: controller),
    );
  }

  @override
  State<ShiftManagementSheet> createState() => _ShiftManagementSheetState();
}

class _ShiftManagementSheetState extends State<ShiftManagementSheet> {
  AppController get c => widget.controller;

  Future<void> _showEditShiftDialog([Shift? shift]) async {
    final nameCtrl = TextEditingController(text: shift?.name ?? '');
    TimeOfDay start = shift != null
        ? TimeOfDay(hour: shift.startMinute ~/ 60, minute: shift.startMinute % 60)
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay end = shift != null
        ? TimeOfDay(hour: shift.endMinute ~/ 60, minute: shift.endMinute % 60)
        : const TimeOfDay(hour: 17, minute: 30);
    int graceMinutes = shift?.grace ?? 15;
    bool busy = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusDialog),
          title: Text(
            shift == null ? 'Tạo ca làm việc mới' : 'Chỉnh sửa ca làm việc',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 12.5)),
                  ),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên ca làm *',
                    hintText: 'Ví dụ: Ca hành chính, Ca sáng, Ca chiều...',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(context: ctx, initialTime: start);
                          if (picked != null) setDialogState(() => start = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Giờ bắt đầu', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(start.format(ctx), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showTimePicker(context: ctx, initialTime: end);
                          if (picked != null) setDialogState(() => end = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Giờ kết thúc', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              Text(end.format(ctx), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: graceMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Cho phép trễ tối đa (phút)',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Không cho phép (0 phút)', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 5, child: Text('5 phút', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 15, child: Text('15 phút', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 30, child: Text('30 phút', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => graceMinutes = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Huỷ'),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        setDialogState(() => error = 'Vui lòng nhập tên ca làm.');
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        final newShift = Shift(
                          id: shift?.id ?? 'shift_${DateTime.now().millisecondsSinceEpoch}',
                          name: name,
                          startMinute: start.hour * 60 + start.minute,
                          endMinute: end.hour * 60 + end.minute,
                          grace: graceMinutes,
                        );
                        await c.saveShift(newShift);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      } catch (e) {
                        setDialogState(() {
                          busy = false;
                          error = e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Lưu ca làm'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shifts = c.data.shifts;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
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
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quản lý ca làm việc',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                    Text(
                      '${shifts.length} ca làm việc được thiết lập',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _showEditShiftDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tạo ca'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: shifts.isEmpty
                ? const Center(
                    child: EmptyState(
                      title: 'Chưa có ca làm nào',
                      description: 'Nhấn "Tạo ca" để thêm ca làm cho nhân viên.',
                      icon: Icons.schedule_outlined,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: shifts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (ctx, index) {
                      final s = shifts[index];
                      final startHour = s.startMinute ~/ 60;
                      final startMin = s.startMinute % 60;
                      final endHour = s.endMinute ~/ 60;
                      final endMin = s.endMinute % 60;
                      final startStr = '${startHour.toString().padLeft(2, '0')}:${startMin.toString().padLeft(2, '0')}';
                      final endStr = '${endHour.toString().padLeft(2, '0')}:${endMin.toString().padLeft(2, '0')}';

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.access_time_filled_rounded, color: Color(0xFF0D9488), size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.navy),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Thời gian: $startStr - $endStr',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0D9488)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Dung sai: ${s.grace} phút',
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.teal),
                              onPressed: () => _showEditShiftDialog(s),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (c2) => AlertDialog(
                                    title: const Text('Xác nhận xóa ca làm'),
                                    content: Text('Xóa ca làm "${s.name}"?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('Huỷ')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
                                        onPressed: () => Navigator.pop(c2, true),
                                        child: const Text('Xóa'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await c.deleteShift(s.id);
                                  if (mounted) setState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Modal Phân quyền vai trò (Dành cho Admin)
class RoleAssignmentSheet extends StatefulWidget {
  final AppController controller;

  const RoleAssignmentSheet({super.key, required this.controller});

  static Future<void> show(BuildContext context, AppController controller) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RoleAssignmentSheet(controller: controller),
    );
  }

  @override
  State<RoleAssignmentSheet> createState() => _RoleAssignmentSheetState();
}

class _RoleAssignmentSheetState extends State<RoleAssignmentSheet> {
  AppController get c => widget.controller;
  String _search = '';

  Future<void> _changeRole(Employee emp) async {
    String currentRole = emp.role;
    String currentDept = emp.department;
    bool busy = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusDialog),
          title: Text('Phân quyền cho ${emp.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
                const SizedBox(height: 8),
              ],
              const Text('Chọn vai trò:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: currentRole,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.admin_panel_settings_outlined)),
                items: const [
                  DropdownMenuItem(value: 'admin', child: Text('🛡️ Quản trị viên (Admin)', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'manager', child: Text('👥 Quản lý (Manager)', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'employee', child: Text('👤 Nhân viên (Employee)', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => currentRole = val);
                },
              ),
              const SizedBox(height: 14),
              const Text('Phòng ban trực thuộc:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: c.data.departments.any((d) => d.name == currentDept) ? currentDept : (c.data.departments.isNotEmpty ? c.data.departments.first.name : ''),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.apartment_outlined)),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Chưa phân phòng ban', overflow: TextOverflow.ellipsis)),
                  ...c.data.departments.map((d) => DropdownMenuItem(value: d.name, child: Text(d.name, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => currentDept = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: const Text('Huỷ')),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      setDialogState(() => busy = true);
                      try {
                        if (emp.isAdmin && currentRole != 'admin') {
                          final adminCount = c.data.employees.where((e) => e.isAdmin && e.active).length;
                          if (adminCount <= 1) {
                            setDialogState(() {
                              busy = false;
                              error = 'Hệ thống phải có ít nhất 1 Quản trị viên (Admin). Bạn không thể hạ quyền Admin duy nhất này.';
                            });
                            return;
                          }
                        }
                        final updated = Employee(
                          id: emp.id,
                          name: emp.name,
                          username: emp.username,
                          email: emp.email,
                          department: currentDept,
                          shiftId: emp.shiftId,
                          role: currentRole,
                          active: emp.active,
                        );
                        await c.saveEmployee(updated);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) setState(() {});
                      } catch (e) {
                        setDialogState(() {
                          busy = false;
                          error = e.toString().replaceAll('Exception: ', '');
                        });
                      }
                    },
              child: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Cập nhật'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employees = c.data.employees.where((e) {
      if (_search.isNotEmpty && !e.name.toLowerCase().contains(_search.toLowerCase())) return false;
      return true;
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Phân quyền vai trò', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy)),
                const SizedBox(height: 2),
                const Text('Gán quyền Admin, Quản lý phòng ban hoặc Nhân viên', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _search = v.trim()),
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm nhân viên...',
                    prefixIcon: Icon(Icons.search_rounded),
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: employees.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (ctx, index) {
                final emp = employees[index];
                final roleBadgeText = emp.isAdmin ? 'Admin' : (emp.isManager ? 'Quản lý' : 'Nhân viên');
                final roleBadgeColor = emp.isAdmin ? AppColors.teal : (emp.isManager ? Colors.deepPurple : const Color(0xFF64748B));

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: roleBadgeColor.withValues(alpha: 0.15),
                        child: Text(
                          emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
                          style: TextStyle(color: roleBadgeColor, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(emp.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.navy)),
                            const SizedBox(height: 2),
                            Text(
                              '${emp.department.isEmpty ? "Chưa có phòng ban" : emp.department} • @${emp.username}',
                              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: roleBadgeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: roleBadgeColor.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          roleBadgeText,
                          style: TextStyle(color: roleBadgeColor, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.teal),
                        onPressed: () => _changeRole(emp),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
