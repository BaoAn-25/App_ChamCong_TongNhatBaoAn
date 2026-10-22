import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'common.dart';

/// Trang Thống kê thông minh — Tính năng mới sáng tạo
/// Phân tích dữ liệu chấm công tự động, phát hiện bất thường,
/// biểu đồ trực quan theo tuần/tháng — chức năng mà các app chấm công
/// hiện tại chưa tích hợp trực tiếp trên mobile.
class StatsPage extends StatefulWidget {
  final AppController controller;
  const StatsPage({super.key, required this.controller});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  AppController get c => widget.controller;
  int _viewMode = 0; // 0: Tuần, 1: Tháng

  DateTime get _now => DateTime.now();

  // Lấy records theo scope (tuần hoặc tháng)
  List<Attendance> get _scopedRecords {
    final all = c.data.attendance
        .where((a) => c.isStaff || a.employeeId == c.user!.id)
        .toList();

    if (_viewMode == 0) {
      // Tuần hiện tại (Thứ 2 → Chủ nhật)
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

  // Tính tổng giờ công
  double get _totalHours =>
      _scopedRecords.fold(0, (sum, a) => sum + a.hours);

  // Tính số ngày đi trễ
  int get _lateDays =>
      _scopedRecords.where((a) => a.lateMinutes > 0).length;

  // Tính số ca hoàn tất
  int get _completedShifts =>
      _scopedRecords.where((a) => a.checkOut != null).length;

  // Tính tổng phút đi trễ
  int get _totalLateMinutes =>
      _scopedRecords.fold(0, (sum, a) => sum + a.lateMinutes);

  // Tính điểm chuyên cần (100 = hoàn hảo)
  int get _attendanceScore {
    if (_scopedRecords.isEmpty) return 100;
    final total = _scopedRecords.length;
    final late = _lateDays;
    final incomplete = _scopedRecords.where((a) => a.checkOut == null).length;
    final penalty = (late * 5 + incomplete * 15);
    return max(0, 100 - (penalty * 100 ~/ max(1, total * 20)));
  }

  // Dữ liệu biểu đồ giờ công theo ngày trong tuần
  List<({String label, double hours, int late})> get _dailyData {
    final Map<String, ({double hours, int late})> grouped = {};

    if (_viewMode == 0) {
      // 7 ngày trong tuần
      final weekStart = _now.subtract(Duration(days: _now.weekday - 1));
      for (int i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        final key = dayKey(day);
        final label = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][i];
        final dayRecords = _scopedRecords.where((a) => dayKey(a.checkIn) == key);
        grouped[label] = (
          hours: dayRecords.fold(0.0, (sum, a) => sum + a.hours),
          late: dayRecords.where((a) => a.lateMinutes > 0).length,
        );
      }
    } else {
      // Tuần 1-4 trong tháng
      for (int w = 0; w < 4; w++) {
        final label = 'Tuần ${w + 1}';
        final weekStart = DateTime(_now.year, _now.month, 1 + w * 7);
        final weekEnd = DateTime(_now.year, _now.month, min(1 + (w + 1) * 7, DateTime(_now.year, _now.month + 1, 0).day + 1));
        final weekRecords = _scopedRecords.where((a) =>
            !a.checkIn.isBefore(weekStart) && a.checkIn.isBefore(weekEnd));
        grouped[label] = (
          hours: weekRecords.fold(0.0, (sum, a) => sum + a.hours),
          late: weekRecords.where((a) => a.lateMinutes > 0).length,
        );
      }
    }

    return grouped.entries
        .map((e) => (label: e.key, hours: e.value.hours, late: e.value.late))
        .toList();
  }

  // Phát hiện bất thường (AI Insights)
  List<({IconData icon, Color color, String title, String desc})> get _insights {
    final items = <({IconData icon, Color color, String title, String desc})>[];

    if (_scopedRecords.isEmpty) {
      items.add((
        icon: Icons.info_outline,
        color: const Color(0xFF64748B),
        title: 'Chưa có dữ liệu',
        desc: 'Dữ liệu chấm công sẽ xuất hiện sau khi có bản ghi đầu tiên.',
      ));
      return items;
    }

    // Phân tích đi trễ
    if (_lateDays == 0) {
      items.add((
        icon: Icons.emoji_events_rounded,
        color: const Color(0xFF10B981),
        title: 'Tuyệt vời! Không đi trễ',
        desc: 'Bạn luôn đến đúng giờ trong kỳ này. Tiếp tục duy trì nhé! 🎉',
      ));
    } else if (_lateDays > _scopedRecords.length * 0.5) {
      items.add((
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFEF4444),
        title: 'Cảnh báo: Đi trễ nhiều',
        desc: 'Bạn đi trễ $_lateDays/${_scopedRecords.length} ca, tổng trễ $_totalLateMinutes phút. Hãy điều chỉnh thời gian.',
      ));
    } else if (_lateDays > 0) {
      items.add((
        icon: Icons.schedule_rounded,
        color: const Color(0xFFF59E0B),
        title: 'Có $_lateDays lần đi trễ',
        desc: 'Tổng $_totalLateMinutes phút trễ. Cố gắng cải thiện thêm nhé.',
      ));
    }

    // Phân tích ca chưa hoàn tất
    final incomplete = _scopedRecords.where((a) => a.checkOut == null).length;
    if (incomplete > 0) {
      items.add((
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFEA580C),
        title: '$incomplete ca chưa check-out',
        desc: 'Hãy kiểm tra và gửi đơn giải trình nếu quên chấm công ra.',
      ));
    }

    // Phân tích giờ công trung bình
    final avgHours = _totalHours / max(1, _completedShifts);
    if (avgHours > 0 && avgHours < 7) {
      items.add((
        icon: Icons.timer_off_outlined,
        color: const Color(0xFF7C3AED),
        title: 'Giờ công trung bình thấp',
        desc: 'TB ${avgHours.toStringAsFixed(1)}h/ca. Mức thông thường là 8h. Kiểm tra lại giờ ra.',
      ));
    } else if (avgHours >= 9) {
      items.add((
        icon: Icons.favorite_rounded,
        color: const Color(0xFFEC4899),
        title: 'Tăng ca nhiều!',
        desc: 'TB ${avgHours.toStringAsFixed(1)}h/ca. Hãy chú ý sức khỏe khi làm thêm giờ.',
      ));
    }

    // Gợi ý chung
    if (_attendanceScore >= 90) {
      items.add((
        icon: Icons.stars_rounded,
        color: const Color(0xFF10B981),
        title: 'Điểm chuyên cần xuất sắc',
        desc: 'Điểm $_attendanceScore/100. Bạn đang có thành tích rất tốt! 🌟',
      ));
    }

    return items;
  }

  // Top nhân viên (Admin view)
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

  @override
  Widget build(BuildContext context) {
    final data = _dailyData;
    final maxHours = data.fold<double>(0, (m, d) => max(m, d.hours));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header
        Section(
          title: '📊 Thống kê thông minh',
          subtitle: 'Phân tích tự động • Phát hiện bất thường',
          child: Column(
            children: [
              // Toggle Tuần / Tháng
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    _toggleButton('Tuần này', 0),
                    _toggleButton('Tháng này', 1),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Score Circle
              _buildScoreCircle(),
              const SizedBox(height: 20),

              // Quick Stats Grid
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _statCard(
                    'Tổng giờ công',
                    '${_totalHours.toStringAsFixed(1)}h',
                    Icons.access_time_filled_rounded,
                    const Color(0xFF0284C7),
                  ),
                  _statCard(
                    'Ca hoàn tất',
                    '$_completedShifts',
                    Icons.check_circle_rounded,
                    const Color(0xFF10B981),
                  ),
                  _statCard(
                    'Lần đi trễ',
                    '$_lateDays',
                    Icons.watch_later_rounded,
                    _lateDays > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                  ),
                  _statCard(
                    'Phút trễ',
                    '$_totalLateMinutes',
                    Icons.timer_off_rounded,
                    _totalLateMinutes > 30 ? const Color(0xFFEA580C) : const Color(0xFF64748B),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Biểu đồ
        Section(
          title: 'Biểu đồ giờ công',
          subtitle: _viewMode == 0 ? 'Theo từng ngày trong tuần' : 'Theo từng tuần trong tháng',
          child: SizedBox(
            height: 220,
            child: data.every((d) => d.hours == 0)
                ? const Center(
                    child: EmptyState('Chưa có dữ liệu để hiển thị biểu đồ.'),
                  )
                : BarChart(
                    BarChartData(
                      maxY: max(maxHours * 1.2, 1),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final d = data[group.x];
                            return BarTooltipItem(
                              '${d.label}\n${d.hours.toStringAsFixed(1)}h${d.late > 0 ? ' • ${d.late} trễ' : ''}',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                            getTitlesWidget: (value, meta) => Text(
                              '${value.toInt()}h',
                              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= data.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  data[value.toInt()].label,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
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
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: const Color(0xFFE2E8F0),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(data.length, (i) {
                        final d = data[i];
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: d.hours,
                              width: _viewMode == 0 ? 20 : 32,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                              gradient: d.late > 0
                                  ? const LinearGradient(
                                      colors: [Color(0xFFFCA5A5), Color(0xFFEF4444)],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    )
                                  : const LinearGradient(
                                      colors: [Color(0xFF6EE7B7), Color(0xFF087F8C)],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
          ),
        ),

        // AI Insights
        Section(
          title: '🤖 Phân tích AI',
          subtitle: 'Phát hiện bất thường & gợi ý cải thiện',
          child: Column(
            children: _insights.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: item.color.withValues(alpha: 0.2)),
                ),
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
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: item.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.desc,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )).toList(),
          ),
        ),

        // Bảng xếp hạng (Admin only)
        if (c.isStaff && _topEmployees.isNotEmpty)
          Section(
            title: '🏆 Bảng xếp hạng nhân viên',
            subtitle: 'Theo giờ công ${_viewMode == 0 ? "tuần" : "tháng"} này',
            child: Column(
              children: _topEmployees.take(10).toList().asMap().entries.map((entry) {
                final rank = entry.key + 1;
                final e = entry.value;
                final medalColor = rank == 1
                    ? Colors.amber
                    : rank == 2
                        ? Colors.grey.shade400
                        : rank == 3
                            ? Colors.brown.shade300
                            : null;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: medalColor != null
                      ? CircleAvatar(
                          backgroundColor: medalColor.withValues(alpha: 0.2),
                          child: Text(
                            '$rank',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: medalColor,
                            ),
                          ),
                        )
                      : CircleAvatar(
                          backgroundColor: const Color(0xFFF1F5F9),
                          child: Text(
                            '$rank',
                            style: const TextStyle(color: Color(0xFF64748B)),
                          ),
                        ),
                  title: Text(
                    e.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    '${e.hours.toStringAsFixed(1)} giờ${e.lateCount > 0 ? ' • ${e.lateCount} lần trễ' : ''}',
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: e.lateCount == 0
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      e.lateCount == 0 ? 'Xuất sắc' : 'Cần cải thiện',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: e.lateCount == 0
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _toggleButton(String label, int mode) {
    final selected = _viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _viewMode = mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
              color: selected ? const Color(0xFF1E293B) : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreCircle() {
    final score = _attendanceScore;
    final color = score >= 80
        ? const Color(0xFF10B981)
        : score >= 50
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.06), color.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 8,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Điểm chuyên cần',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  score >= 90
                      ? 'Xuất sắc! Tiếp tục duy trì phong độ.'
                      : score >= 70
                          ? 'Khá tốt. Cố gắng cải thiện thêm.'
                          : score >= 50
                              ? 'Trung bình. Cần chú ý giờ giấc.'
                              : 'Cần cải thiện ngay lập tức!',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 155,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
