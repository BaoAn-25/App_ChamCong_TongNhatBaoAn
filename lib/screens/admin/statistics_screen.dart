import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';

/// Màn hình Thống kê dành cho Quản trị viên (Admin Statistics):
/// 1. Thay toàn bộ emoji bằng icon outlined. Bỏ hoàn toàn chữ "AI" khỏi giao diện.
/// 2. Đổi mục "Phân tích AI" thành "Cảnh báo bất thường" với chú thích 12px theo quy tắc;
///    khi không có vi phạm thì hiện EmptyState "Chưa có bất thường".
/// 3. Thẻ Điểm chuyên cần dạng vòng tròn tiến độ, đổi màu theo 4 mức (>=90 xanh, 75-89 teal, 50-74 vàng, <50 đỏ).
///    Nút "Cách tính điểm" mở Bottom Sheet hiển thị đúng công thức logic trong code.
/// 4. Biểu đồ giờ công: maxY = max(maxHours * 1.2, 8.0), nhãn trục Y hiển thị mỗi 2h, tooltip khi chạm,
///    cột phân màu: đủ giờ (>=8h) xanh, thiếu giờ (<8h) vàng, 0h xám.
/// 5. Bảng xếp hạng bị ẩn khỏi giao diện nhưng hàm _topEmployees được giữ lại an toàn.
/// 6. Chuyển đổi Tuần này / Tháng này có animation 200ms; hỗ trợ SkeletonLoader và ErrorState.
class AdminStatisticsScreen extends StatefulWidget {
  final AppController controller;

  const AdminStatisticsScreen({
    super.key,
    required this.controller,
  });

  @override
  State<AdminStatisticsScreen> createState() => _AdminStatisticsScreenState();
}

class _AdminStatisticsScreenState extends State<AdminStatisticsScreen> {
  AppController get c => widget.controller;

  int _viewMode = 0; // 0: Tuần này, 1: Tháng này
  bool _isLoading = false;
  String? _errorMessage;

  DateTime get _now => DateTime.now();

  /// Lọc các bản ghi theo tuần hoặc tháng (toàn bộ nhân viên đối với Admin/Staff)
  List<Attendance> get _scopedRecords {
    final all = c.data.attendance
        .where((a) => c.isStaff || (c.user != null && a.employeeId == c.user!.id))
        .toList();

    if (_viewMode == 0) {
      // Tuần hiện tại (Thứ 2 -> Chủ nhật theo múi giờ địa phương)
      final weekStart = _now.subtract(Duration(days: _now.weekday - 1));
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
      return all
          .where((a) => a.checkIn.isAfter(start.subtract(const Duration(seconds: 1))))
          .toList();
    } else {
      // Tháng hiện tại
      final start = DateTime(_now.year, _now.month, 1);
      return all
          .where((a) => a.checkIn.isAfter(start.subtract(const Duration(seconds: 1))))
          .toList();
    }
  }

  // Tổng số giờ công tích lũy
  double get _totalHours => _scopedRecords.fold(0.0, (sum, a) => sum + a.hours);

  // Số ca đi trễ
  int get _lateDays => _scopedRecords.where((a) => a.lateMinutes > 0).length;

  // Số ca đã hoàn tất (có check-out)
  int get _completedShifts => _scopedRecords.where((a) => a.checkOut != null).length;

  // Tổng phút đi trễ
  int get _totalLateMinutes => _scopedRecords.fold(0, (sum, a) => sum + a.lateMinutes);

  // Số ca chưa check-out
  int get _incompleteShifts => _scopedRecords.where((a) => a.checkOut == null).length;

  /// Công thức tính điểm chuyên cần hiện có trong hệ thống (100 là tối đa)
  int get _attendanceScore {
    if (_scopedRecords.isEmpty) return 100;
    final total = _scopedRecords.length;
    final late = _lateDays;
    final incomplete = _incompleteShifts;
    final penalty = (late * 5 + incomplete * 15);
    return max(0, 100 - (penalty * 100 ~/ max(1, total * 20)));
  }

  /// Màu đại diện theo 4 mốc điểm chuyên cần
  Color _getScoreColor(int score) {
    if (score >= 90) return AppColors.success;
    if (score >= 75) return AppColors.teal;
    if (score >= 50) return AppColors.warning;
    return AppColors.error;
  }

  String _getScoreRatingText(int score) {
    if (score >= 90) return 'Xuất sắc';
    if (score >= 75) return 'Tốt';
    if (score >= 50) return 'Trung bình';
    return 'Cần chấn chỉnh';
  }

  /// Dữ liệu biểu đồ giờ công
  List<({String label, double hours, int lateCount})> get _dailyData {
    final Map<String, ({double hours, int lateCount})> grouped = {};

    if (_viewMode == 0) {
      // 7 ngày trong tuần: Thứ 2 -> Chủ nhật
      final weekStart = _now.subtract(Duration(days: _now.weekday - 1));
      for (int i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        final key = dayKey(day);
        final label = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][i];
        final dayRecords = _scopedRecords.where((a) => dayKey(a.checkIn) == key);
        grouped[label] = (
          hours: dayRecords.fold(0.0, (sum, a) => sum + a.hours),
          lateCount: dayRecords.where((a) => a.lateMinutes > 0).length,
        );
      }
    } else {
      // 4 tuần trong tháng
      for (int w = 0; w < 4; w++) {
        final label = 'Tuần ${w + 1}';
        final weekStart = DateTime(_now.year, _now.month, 1 + w * 7);
        final weekEnd = DateTime(
          _now.year,
          _now.month,
          min(1 + (w + 1) * 7, DateTime(_now.year, _now.month + 1, 0).day + 1),
        );
        final weekRecords = _scopedRecords.where(
          (a) => !a.checkIn.isBefore(weekStart) && a.checkIn.isBefore(weekEnd),
        );
        grouped[label] = (
          hours: weekRecords.fold(0.0, (sum, a) => sum + a.hours),
          lateCount: weekRecords.where((a) => a.lateMinutes > 0).length,
        );
      }
    }

    return grouped.entries
        .map((e) => (label: e.key, hours: e.value.hours, lateCount: e.value.lateCount))
        .toList();
  }

  /// Danh sách Cảnh báo bất thường theo quy tắc chuẩn
  List<({IconData icon, Color color, Color bgColor, String title, String desc})> get _abnormalAlerts {
    final alerts = <({IconData icon, Color color, Color bgColor, String title, String desc})>[];

    if (_scopedRecords.isEmpty) {
      return alerts;
    }

    // 1. Phân tích đi trễ
    if (_lateDays > _scopedRecords.length * 0.5) {
      alerts.add((
        icon: Icons.error_outline_rounded,
        color: AppColors.error,
        bgColor: AppColors.errorBg,
        title: 'Cảnh báo: Tỷ lệ đi trễ cao',
        desc: 'Có $_lateDays/${_scopedRecords.length} ca đi trễ, tổng thời gian trễ $_totalLateMinutes phút.',
      ));
    } else if (_lateDays > 0) {
      alerts.add((
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        bgColor: AppColors.warningBg,
        title: 'Có $_lateDays lần đi trễ trong kỳ',
        desc: 'Tổng số phút trễ ghi nhận là $_totalLateMinutes phút. Cần nhắc nhở nhân viên đúng giờ.',
      ));
    } else {
      alerts.add((
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
        bgColor: AppColors.successBg,
        title: 'Toàn bộ chấm công đúng giờ',
        desc: 'Không ghi nhận trường hợp đi trễ nào trong kỳ theo dõi.',
      ));
    }

    // 2. Phân tích ca chưa hoàn tất (thiếu check-out)
    if (_incompleteShifts > 0) {
      alerts.add((
        icon: Icons.warning_amber_rounded,
        color: AppColors.warning,
        bgColor: AppColors.warningBg,
        title: '$_incompleteShifts ca làm việc chưa ghi nhận giờ ra',
        desc: 'Nhân viên chưa chấm công ra. Hãy kiểm tra hoặc yêu cầu nộp đơn giải trình.',
      ));
    }

    // 3. Phân tích giờ công trung bình
    final avgHours = _totalHours / max(1, _completedShifts);
    if (_completedShifts > 0 && avgHours < 7.0) {
      alerts.add((
        icon: Icons.timer_off_outlined,
        color: const Color(0xFF6366F1),
        bgColor: const Color(0xFFEEF2FF),
        title: 'Giờ công trung bình thấp',
        desc: 'Trung bình đạt ${avgHours.toStringAsFixed(1)} giờ/ca (mức tiêu chuẩn là 8 giờ). Cần kiểm tra lại các ca ngắn.',
      ));
    } else if (avgHours >= 9.0) {
      alerts.add((
        icon: Icons.alarm_on_outlined,
        color: AppColors.teal,
        bgColor: AppColors.teal.withValues(alpha: 0.1),
        title: 'Ghi nhận làm thêm giờ (tăng ca)',
        desc: 'Trung bình đạt ${avgHours.toStringAsFixed(1)} giờ/ca, vượt định mức thông thường.',
      ));
    }

    // 4. Khen ngợi nếu chuyên cần xuất sắc
    if (_attendanceScore >= 90 && _scopedRecords.isNotEmpty) {
      alerts.add((
        icon: Icons.verified_outlined,
        color: AppColors.success,
        bgColor: AppColors.successBg,
        title: 'Chỉ số chuyên cần đạt mức xuất sắc',
        desc: 'Điểm chuyên cần kỳ này đạt $_attendanceScore/100 điểm.',
      ));
    }

    return alerts;
  }

  /// 5. Top nhân viên (Giữ lại logic & API để không lỗi biên dịch, không gọi trong build)
  // ignore: unused_element
  List<({String name, double hours, int lateCount})> get _topEmployees {
    if (!c.isStaff) return [];
    final Map<String, ({double hours, int lateCount})> map = {};
    for (final a in _scopedRecords) {
      final old = map[a.employeeId] ?? (hours: 0.0, lateCount: 0);
      map[a.employeeId] = (
        hours: old.hours + a.hours,
        lateCount: old.lateCount + (a.lateMinutes > 0 ? 1 : 0),
      );
    }
    return map.entries.map((e) {
      final emp = c.data.employees.where((emp) => emp.id == e.key).firstOrNull;
      return (
        name: emp?.name ?? 'Không rõ',
        hours: e.value.hours,
        lateCount: e.value.lateCount,
      );
    }).toList()
      ..sort((a, b) => b.hours.compareTo(a.hours));
  }

  /// Tải lại dữ liệu đồng bộ
  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await c.syncAll();
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Mở Bottom Sheet giải thích cách tính điểm chuyên cần
  void _showScoreCalculationSheet() {
    final total = _scopedRecords.length;
    final late = _lateDays;
    final incomplete = _incompleteShifts;
    final penalty = (late * 5 + incomplete * 15);
    final score = _attendanceScore;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh gạt (Drag handle)
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

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.calculate_outlined, color: AppColors.teal, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Cách tính điểm chuyên cần',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: AppColors.border, height: 24),

              const Text(
                'Điểm chuyên cần được tính toán tự động dựa trên quy tắc chấm công thực tế của nhân sự trong kỳ:',
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),

              // Quy tắc trừ điểm
              _buildRuleItem(
                icon: Icons.check_circle_outline,
                color: AppColors.success,
                title: 'Điểm khởi tạo tối đa: 100 điểm',
                subtitle: 'Áp dụng cho mọi nhân viên khi bắt đầu chu kỳ tính công.',
              ),
              _buildRuleItem(
                icon: Icons.alarm_off_outlined,
                color: AppColors.warning,
                title: 'Đi trễ: -5 điểm phạt / lần',
                subtitle: 'Mỗi ca chấm công sau giờ quy định (đã trừ dung sai ca).',
              ),
              _buildRuleItem(
                icon: Icons.logout_rounded,
                color: AppColors.error,
                title: 'Thiếu giờ ra (chưa check-out): -15 điểm phạt / ca',
                subtitle: 'Ca kết thúc nhưng nhân viên không thực hiện chấm công ra.',
              ),

              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Công thức toán học áp dụng:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'Điểm = max(0, 100 - [Tổng phạt × 100] / [Tổng số ca × 20])',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: AppColors.teal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hiện tại: $total ca ghi nhận • $late ca trễ (+$penalty điểm phạt) → Điểm: $score/100',
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  title: 'Đã hiểu',
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRuleItem({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_errorMessage != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                'Không thể tải dữ liệu thống kê',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _refreshData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    } else if (_isLoading) {
      content = ListView(
        padding: const EdgeInsets.all(AppTheme.space16),
        children: const [
          SkeletonLoader(width: double.infinity, height: 48),
          SizedBox(height: 16),
          SkeletonLoader(width: double.infinity, height: 120),
          SizedBox(height: 16),
          SkeletonLoader(width: double.infinity, height: 260),
          SizedBox(height: 16),
          SkeletonLoader(width: double.infinity, height: 140),
        ],
      );
    } else {
      content = RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.space16),
          children: [
            // ====================================================================
            // 6. TOGGLE TUẦN / THÁNG VỚI ANIMATION 200MS
            // ====================================================================
            _buildPeriodToggle(),
            const SizedBox(height: 16),

            // ====================================================================
            // 3. THẺ ĐIỂM CHUYÊN CẦN (Vòng tròn tiến độ, đổi màu theo 4 mức)
            // ====================================================================
            _buildAttendanceScoreCard(),
            const SizedBox(height: 16),

            // 4 THẺ TÓM TẮT NHANH CHỈ SỐ
            _buildQuickStatCards(),
            const SizedBox(height: 24),

            // ====================================================================
            // 4. BIỂU ĐỒ GIỜ CÔNG (maxY, nhãn mỗi 2h, tooltip, màu cột)
            // ====================================================================
            SectionHeader(
              title: 'Biểu đồ giờ công',
              subtitle: _viewMode == 0 ? 'Phân bố theo từng ngày trong tuần' : 'Phân bố theo từng tuần trong tháng',
            ),
            const SizedBox(height: 8),
            _buildHoursBarChartCard(),
            const SizedBox(height: 24),

            // ====================================================================
            // 2. CẢNH BÁO BẤT THƯỜNG (Dựa trên quy tắc)
            // ====================================================================
            SectionHeader(
              title: 'Cảnh báo bất thường',
              subtitle: 'Dựa trên quy tắc: đi trễ, thiếu check-out, giờ công trung bình',
            ),
            const SizedBox(height: 8),
            _buildAbnormalAlertsSection(),
            const SizedBox(height: 24),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Thống kê & Báo cáo',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Làm mới',
            onPressed: _refreshData,
          ),
        ],
        centerTitle: false,
      ),
      body: content,
    );
  }

  /// 6. Bộ chuyển đổi Tuần này / Tháng này với hiệu ứng mượt 200ms
  Widget _buildPeriodToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          _buildToggleOption(label: 'Tuần này', modeIndex: 0),
          _buildToggleOption(label: 'Tháng này', modeIndex: 1),
        ],
      ),
    );
  }

  Widget _buildToggleOption({required String label, required int modeIndex}) {
    final isSelected = _viewMode == modeIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_viewMode != modeIndex) {
            setState(() => _viewMode = modeIndex);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? AppColors.navy : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// 3. Thẻ Điểm chuyên cần (vòng tròn tiến độ, nút Cách tính điểm)
  Widget _buildAttendanceScoreCard() {
    final score = _attendanceScore;
    final scoreColor = _getScoreColor(score);
    final ratingText = _getScoreRatingText(score);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          // Vòng tròn tiến độ điểm
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 82,
                  height: 82,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    backgroundColor: scoreColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: scoreColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),

          // Mô tả và nút bấm xem công thức
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Text(
                      'Điểm chuyên cần',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ratingText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scoreColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 90
                      ? 'Thành tích xuất sắc! Tiếp tục duy trì kỷ luật.'
                      : score >= 75
                          ? 'Tỷ lệ đúng giờ tốt. Cần giảm bớt số ca trễ.'
                          : score >= 50
                              ? 'Tỷ lệ vi phạm ở mức trung bình, cần chấn chỉnh.'
                              : 'Tỷ lệ đi trễ hoặc thiếu giờ ra ở mức báo động!',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _showScoreCalculationSheet,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: AppColors.teal),
                        SizedBox(width: 4),
                        Text(
                          'Cách tính điểm',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.teal,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 4 thẻ thống kê số liệu
  Widget _buildQuickStatCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: StatCard(
                title: 'Tổng giờ công',
                value: '${_totalHours.toStringAsFixed(1)}h',
                subtitle: 'Ghi nhận thực tế',
                icon: Icons.access_time_rounded,
                iconColor: AppColors.info,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: StatCard(
                title: 'Ca hoàn tất',
                value: '$_completedShifts',
                subtitle: 'Có đủ giờ vào và ra',
                icon: Icons.check_circle_outline_rounded,
                iconColor: AppColors.success,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: StatCard(
                title: 'Số ca đi trễ',
                value: '$_lateDays',
                subtitle: _lateDays > 0 ? 'Tổng $_totalLateMinutes phút trễ' : 'Đúng giờ tuyệt đối',
                icon: Icons.alarm_off_outlined,
                iconColor: _lateDays > 0 ? AppColors.warning : AppColors.success,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: StatCard(
                title: 'Chưa check-out',
                value: '$_incompleteShifts',
                subtitle: _incompleteShifts > 0 ? 'Cần bổ sung đơn' : 'Đã check-out đủ',
                icon: Icons.logout_rounded,
                iconColor: _incompleteShifts > 0 ? AppColors.error : AppColors.success,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 4. Biểu đồ giờ công cột fl_chart
  Widget _buildHoursBarChartCard() {
    final data = _dailyData;
    final maxHours = data.fold<double>(0.0, (m, d) => max(m, d.hours));
    // Yêu cầu: maxY = max(giá trị lớn nhất * 1.2, 8.0)
    final double calculatedMaxY = max(maxHours * 1.2, 8.0);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildLegendDot(color: AppColors.teal, label: 'Đủ ca (≥8h)'),
              _buildLegendDot(color: AppColors.warning, label: 'Thiếu giờ (<8h)'),
              _buildLegendDot(color: Colors.grey.shade400, label: '0 giờ'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: data.every((d) => d.hours == 0)
                ? const Center(
                    child: EmptyState(
                      title: 'Chưa có dữ liệu',
                      description: 'Chưa ghi nhận giờ công nào trong khoảng thời gian này.',
                      icon: Icons.bar_chart_outlined,
                    ),
                  )
                : BarChart(
                    BarChartData(
                      maxY: calculatedMaxY,
                      minY: 0,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => AppColors.navy,
                          tooltipRoundedRadius: 10,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final d = data[group.x];
                            return BarTooltipItem(
                              '${d.label}\n${d.hours.toStringAsFixed(1)} giờ${d.lateCount > 0 ? '\n(${d.lateCount} ca trễ)' : ''}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        // Trục Y bên trái: hiển thị nhãn mỗi 2 giờ
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 2.0,
                            getTitlesWidget: (value, meta) {
                              if (value < 0 || value > calculatedMaxY) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                '${value.toInt()}h',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
                          ),
                        ),
                        // Trục X bên dưới
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= data.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  data[idx].label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 2.0,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: AppColors.border,
                          strokeWidth: 0.8,
                          dashArray: [4, 4],
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(data.length, (i) {
                        final d = data[i];
                        // Quy tắc màu cột:
                        // - Đủ giờ ca (>= 8.0h): Xanh (AppColors.teal)
                        // - Thiếu giờ (< 8.0h và > 0h): Vàng (AppColors.warning)
                        // - 0 giờ: Xám
                        Color barColor;
                        if (d.hours >= 8.0) {
                          barColor = AppColors.teal;
                        } else if (d.hours > 0) {
                          barColor = AppColors.warning;
                        } else {
                          barColor = Colors.grey.shade300;
                        }

                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: d.hours,
                              color: barColor,
                              width: _viewMode == 0 ? 22 : 32,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  /// 2. Danh mục Cảnh báo bất thường (EmptyState khi không có cảnh báo)
  Widget _buildAbnormalAlertsSection() {
    final alerts = _abnormalAlerts;

    if (alerts.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.all(24),
        child: EmptyState(
          title: 'Chưa có bất thường',
          description: 'Hệ thống không phát hiện vi phạm đi trễ, thiếu check-out hay giờ công thấp trong kỳ này.',
          icon: Icons.check_circle_outline_rounded,
        ),
      );
    }

    return Column(
      children: alerts.map((item) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            color: item.bgColor.withValues(alpha: 0.5),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: item.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: item.color,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.desc,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
