import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';
import '../admin/employee_history_screen.dart';

/// Màn hình Nhóm (Danh sách nhân sự phòng ban) dành cho Quản lý (Manager Team Screen)
class ManagerTeamScreen extends StatefulWidget {
  final AppController controller;

  const ManagerTeamScreen({super.key, required this.controller});

  @override
  State<ManagerTeamScreen> createState() => _ManagerTeamScreenState();
}

class _ManagerTeamScreenState extends State<ManagerTeamScreen> {
  AppController get c => widget.controller;
  String _searchQuery = '';

  String get _managerDept => c.user?.department.isNotEmpty == true
      ? c.user!.department
      : (c.data.departments.isNotEmpty ? c.data.departments.first.name : 'Kinh doanh');

  List<Employee> get _teamEmployees {
    return c.data.employees.where((e) {
      if (!e.active) return false;
      if (e.department.toLowerCase() != _managerDept.toLowerCase()) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!e.name.toLowerCase().contains(q) && !e.username.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  void _viewEmployeeHistory(Employee emp) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeHistoryScreen(
          controller: c,
          userId: emp.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employees = _teamEmployees;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // ====================================================================
        // THANH TÌM KIẾM NHÂN SỰ TRONG NHÓM
        // ====================================================================
        TextField(
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
          decoration: InputDecoration(
            hintText: 'Tìm kiếm nhân viên phòng $_managerDept...',
            prefixIcon: const Icon(Icons.search_rounded),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ====================================================================
        // THẺ THỐNG KÊ NHÓM NHỎ
        // ====================================================================
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.groups_rounded, color: Colors.deepPurple, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phòng $_managerDept',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tổng số ${employees.length} thành viên đang hoạt động',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ====================================================================
        // DANH SÁCH THÀNH VIÊN TRONG NHÓM
        // ====================================================================
        if (employees.isEmpty)
          const EmptyState(
            title: 'Không tìm thấy nhân viên',
            description: 'Không có nhân viên nào phù hợp với từ khóa tìm kiếm.',
            icon: Icons.person_search_rounded,
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: employees.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (ctx, index) {
              final emp = employees[index];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.teal.withValues(alpha: 0.15),
                      child: Text(
                        emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'N',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.teal, fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  emp.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.navy),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (emp.id == c.user?.id) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('Bạn', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepPurple)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '@${emp.username} • ${emp.email}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history_rounded, color: AppColors.teal, size: 22),
                      tooltip: 'Lịch sử chấm công',
                      onPressed: () => _viewEmployeeHistory(emp),
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
