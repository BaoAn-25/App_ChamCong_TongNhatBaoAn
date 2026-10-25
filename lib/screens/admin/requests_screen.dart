import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';

/// Màn hình Quản lý Đơn từ dành cho Admin (Requests):
/// 6. Hai tab rõ ràng:
///    - Tab "Cần duyệt": Đơn của nhân viên, có nút Duyệt / Từ chối kèm ô nhập phản hồi, Admin không tự duyệt đơn của mình.
///    - Tab "Đơn của tôi": Đơn do Admin tự gửi (nghỉ phép, giải trình).
/// 7. Thẻ đơn full chiều ngang: loại đơn, người gửi, khoảng ngày, lý do, StatusChip, phản hồi.
///    Chip lọc (Tất cả / Chờ duyệt / Đã duyệt / Từ chối), FAB "+ Tạo đơn" có nhãn, EmptyState khi trống.
class AdminRequestsScreen extends StatefulWidget {
  final AppController controller;

  const AdminRequestsScreen({
    super.key,
    required this.controller,
  });

  @override
  State<AdminRequestsScreen> createState() => _AdminRequestsScreenState();
}

class _AdminRequestsScreenState extends State<AdminRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _statusFilter = 'all'; // all, pending, approved, rejected

  AppController get c => widget.controller;
  String get _currentUserId => c.user?.id ?? '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _getEmployeeName(String employeeId) {
    final emp = c.data.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.name ?? 'Nhân viên';
  }

  String? _getEmployeeDept(String employeeId) {
    final emp = c.data.employees.where((e) => e.id == employeeId).firstOrNull;
    return emp?.department;
  }

  // Danh sách đơn nhân viên gửi lên (Admin cần duyệt)
  List<WorkRequest> get _pendingApprovalRequests {
    final list = c.data.requests.where((r) {
      final isStaffSelf = r.employeeId == _currentUserId;
      if (isStaffSelf) return false; // Không tự duyệt đơn của mình
      if (_statusFilter != 'all' && r.status != _statusFilter) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.from.compareTo(a.from));
    return list;
  }

  // Danh sách đơn của chính Admin
  List<WorkRequest> get _myRequests {
    final list = c.data.requests.where((r) {
      final isStaffSelf = r.employeeId == _currentUserId;
      if (!isStaffSelf) return false;
      if (_statusFilter != 'all' && r.status != _statusFilter) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.from.compareTo(a.from));
    return list;
  }

  // Số lượng đơn nhân viên đang chờ duyệt
  int get _badgePendingCount {
    return c.data.requests
        .where((r) => r.employeeId != _currentUserId && r.status == 'pending')
        .length;
  }

  /// Xử lý duyệt / từ chối đơn kèm ô nhập phản hồi
  Future<void> _handleReview(WorkRequest request, bool approve) async {
    final noteController = TextEditingController();
    bool busy = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusCard),
          title: Row(
            children: [
              Icon(
                approve ? Icons.check_circle_outline : Icons.highlight_off_rounded,
                color: approve ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 8),
              Text(
                approve ? 'Phê duyệt đơn' : 'Từ chối đơn',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${request.type} • ${_getEmployeeName(request.employeeId)}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Lý do: ${request.reason}',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: approve ? 'Ghi chú duyệt (tuỳ chọn)' : 'Lý do từ chối *',
                  hintText: approve
                      ? 'Nhập phản hồi cho nhân viên...'
                      : 'Nêu rõ lý do không thể duyệt...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Huỷ'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: approve ? AppColors.teal : AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      if (!approve && noteController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vui lòng nhập lý do từ chối')),
                        );
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        await c.reviewRequest(
                          request.id,
                          approve,
                          noteController.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
                          );
                        }
                      } finally {
                        if (ctx.mounted) setDialogState(() => busy = false);
                      }
                    },
              child: Text(approve ? 'Xác nhận duyệt' : 'Xác nhận từ chối'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Đã duyệt đơn thành công!' : 'Đã từ chối đơn!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Mở Form tạo hoặc chỉnh sửa đơn
  Future<void> _openCreateOrEditRequestDialog([WorkRequest? existing]) async {
    String selectedType = existing?.type ?? 'Nghỉ phép';
    final reasonCtrl = TextEditingController(text: existing?.reason ?? '');
    DateTime startDate = existing?.from ?? DateTime.now();
    DateTime endDate = existing?.to ?? DateTime.now();
    bool busy = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SafeArea(
            child: SingleChildScrollView(
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
                  Text(
                    existing == null ? 'Tạo đơn mới' : 'Chỉnh sửa đơn',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),

                  // Chọn loại đơn
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Loại đơn *'),
                    items: const [
                      DropdownMenuItem(value: 'Nghỉ phép', child: Text('Nghỉ phép')),
                      DropdownMenuItem(
                        value: 'Giải trình chấm công',
                        child: Text('Giải trình chấm công (Quên check-in/out)'),
                      ),
                      DropdownMenuItem(value: 'Làm việc từ xa', child: Text('Làm việc từ xa (Remote)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setSheetState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 14),

                  // Chọn khoảng ngày
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: startDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setSheetState(() {
                                startDate = picked;
                                if (endDate.isBefore(startDate)) endDate = startDate;
                              });
                            }
                          },
                          icon: const Icon(Icons.date_range, size: 16),
                          label: Text('Từ: ${dateLabel(startDate)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: endDate,
                              firstDate: startDate,
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setSheetState(() => endDate = picked);
                            }
                          },
                          icon: const Icon(Icons.event, size: 16),
                          label: Text('Đến: ${dateLabel(endDate)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Lý do
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Lý do / Giải trình chi tiết *',
                      hintText: 'Nhập lý do xin nghỉ hoặc lý do giải trình...',
                    ),
                  ),
                  const SizedBox(height: 24),

                  PrimaryButton(
                    title: existing == null ? 'Gửi đơn' : 'Lưu thay đổi',
                    isLoading: busy,
                    onPressed: () async {
                      if (reasonCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vui lòng nhập lý do')),
                        );
                        return;
                      }

                      setSheetState(() => busy = true);
                      try {
                        final req = WorkRequest(
                          id: existing?.id ?? newId(),
                          employeeId: _currentUserId,
                          type: selectedType,
                          reason: reasonCtrl.text.trim(),
                          from: startDate,
                          to: endDate,
                          status: existing?.status ?? 'pending',
                          reviewerNote: existing?.reviewerNote ?? '',
                        );

                        await c.saveRequest(req);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Lỗi: $e'), backgroundColor: AppColors.error),
                          );
                        }
                      } finally {
                        if (ctx.mounted) setSheetState(() => busy = false);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {});
    }
  }

  /// Xóa đơn
  Future<void> _handleDeleteRequest(WorkRequest request) async {
    final empName = _getEmployeeName(request.employeeId);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa đơn'),
        content: Text('Bạn có chắc chắn muốn xóa vĩnh viễn đơn "${request.type}" của $empName?'),
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
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await c.deleteRequest(request.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa đơn thành công!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingBadge = _badgePendingCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateOrEditRequestDialog(),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Tạo đơn',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // ==================================================================
          // 6. HAI TAB: CẦN DUYỆT (Nhân viên) & ĐƠN CỦA TÔI
          // ==================================================================
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.teal,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.teal,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Cần duyệt'),
                      if (pendingBadge > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warning,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$pendingBadge',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Tab(text: 'Đơn của tôi'),
              ],
            ),
          ),

          // Thanh lọc trạng thái: Tất cả / Chờ duyệt / Đã duyệt / Từ chối
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusFilterChip('Tất cả', 'all'),
                  const SizedBox(width: 6),
                  _buildStatusFilterChip('Chờ duyệt', 'pending'),
                  const SizedBox(width: 6),
                  _buildStatusFilterChip('Đã duyệt', 'approved'),
                  const SizedBox(width: 6),
                  _buildStatusFilterChip('Từ chối', 'rejected'),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // Nội dung 2 Tab
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: CẦN DUYỆT (Đơn của nhân viên gửi)
                _buildRequestsList(
                  items: _pendingApprovalRequests,
                  isReviewMode: true,
                  emptyMessage: 'Không có đơn nào cần xử lý trong mục này.',
                ),

                // TAB 2: ĐƠN CỦA TÔI (Đơn Admin tự gửi)
                _buildRequestsList(
                  items: _myRequests,
                  isReviewMode: false,
                  emptyMessage: 'Bạn chưa tạo đơn nào.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => setState(() => _statusFilter = value),
      selectedColor: AppColors.teal.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected ? AppColors.teal : AppColors.textSecondary,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }

  // 7. Danh sách thẻ đơn full chiều ngang
  Widget _buildRequestsList({
    required List<WorkRequest> items,
    required bool isReviewMode,
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return Center(
        child: EmptyState(
          title: 'Danh sách đơn trống',
          description: emptyMessage,
          icon: Icons.assignment_turned_in_outlined,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final request = items[index];
        return _buildRequestCard(request, isReviewMode: isReviewMode);
      },
    );
  }

  // 7. Thẻ đơn full chiều ngang
  Widget _buildRequestCard(WorkRequest r, {required bool isReviewMode}) {
    final empName = _getEmployeeName(r.employeeId);
    final empDept = _getEmployeeDept(r.employeeId);

    // StatusChip tương ứng
    Widget statusChip;
    if (r.status == 'approved') {
      statusChip = const StatusChip('Đã duyệt', icon: Icons.check_circle_rounded);
    } else if (r.status == 'rejected') {
      statusChip = const StatusChip('Từ chối', icon: Icons.cancel_outlined);
    } else {
      statusChip = const StatusChip('Chờ duyệt', icon: Icons.hourglass_empty_rounded);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dòng 1: Avatar + Tên người gửi + Loại đơn + StatusChip
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.teal.withValues(alpha: 0.1),
                  child: Text(
                    empName.isNotEmpty ? empName[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
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
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${empDept != null && empDept.isNotEmpty ? '$empDept • ' : ''}${r.type}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                statusChip,
                const SizedBox(width: 4),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.error,
                  ),
                  tooltip: 'Xóa đơn',
                  onPressed: () => _handleDeleteRequest(r),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Dòng 2: Khoảng thời gian
            Row(
              children: [
                const Icon(Icons.date_range_rounded, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '${dateLabel(r.from)} → ${dateLabel(r.to)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Dòng 3: Lý do gửi
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.input,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                r.reason.isNotEmpty ? r.reason : 'Không có ghi chú lý do',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ),

            // Dòng 4: Phản hồi của người duyệt (nếu có)
            if (r.reviewerNote.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.comment_outlined, size: 14, color: AppColors.teal),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Phản hồi: ${r.reviewerNote}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Dòng 5: Các nút hành động
            if (r.status == 'pending') ...[
              const SizedBox(height: 14),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 10),

              // Nếu là đơn của nhân viên gửi -> Admin có nút Duyệt / Từ chối
              if (isReviewMode)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _handleReview(r, false),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Từ chối'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: () => _handleReview(r, true),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Duyệt đơn'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ],
                )
              // Nếu là đơn cá nhân của Admin -> Nút Sửa / Xóa
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _handleDeleteRequest(r),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                      label: const Text('Xóa đơn', style: TextStyle(color: AppColors.error)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _openCreateOrEditRequestDialog(r),
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Chỉnh sửa'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.teal,
                        side: const BorderSide(color: AppColors.teal),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
