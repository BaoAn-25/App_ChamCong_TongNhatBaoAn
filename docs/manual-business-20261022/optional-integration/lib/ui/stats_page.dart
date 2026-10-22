import 'dart:math';
import 'dart:async';
import '../data/api_repositories.dart';
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
  static DateTime _vn(DateTime d) => d.toUtc().add(const Duration(hours: 7));
  StatisticsSummary? _summary;
  List<dynamic> _ranking = [];
  String? _statsError;
  DateTime? _observedSync;
  String? _observedUser;
  int _generation = 0;

  ({DateTime start, DateTime end}) get _period {
    final day = _vn(_now);
    final start = _viewMode == 0
        ? DateTime.utc(day.year, day.month, day.day - day.weekday + 1)
        : DateTime.utc(day.year, day.month, 1);
    final end = _viewMode == 0
        ? start.add(const Duration(days: 7))
        : DateTime.utc(day.year, day.month + 1, 1);
    return (start: start, end: end);
  }

  @override
  void initState() {
    super.initState();
    c.addListener(_onControllerChange);
    scheduleMicrotask(_loadStats);
  }

  @override
  void didUpdateWidget(covariant StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.removeListener(_onControllerChange);
      c.addListener(_onControllerChange);
      unawaited(_loadStats());
    }
  }

  @override
  void dispose() {
    c.removeListener(_onControllerChange);
    _generation++;
    super.dispose();
  }

  void _onControllerChange() {
    if (c.lastSyncedAt != _observedSync || c.user?.id != _observedUser) {
      unawaited(_loadStats());
    }
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    final generation = ++_generation;
    _observedSync = c.lastSyncedAt;
    _observedUser = c.user?.id;
    final period = _period;
    final uid = c.user?.id;
    setState(() {
      _summary = null;
      _ranking = [];
      _statsError = null;
    });
    if (uid == null) return;
    try {
      final repo = StatisticsRepository(c.client);
      final last = period.end.subtract(const Duration(days: 1));
      StatisticsSummary summary;
      List<dynamic> ranking = [];
      if (c.isStaff) {
        final result = await repo.company(period.start, last);
        summary = StatisticsSummary.fromJson(
          Map<String, dynamic>.from(result['summary']),
        );
        ranking = List<dynamic>.from(result['ranking']);
      } else {
        summary = await repo.mine(period.start, last);
      }
      if (mounted && generation == _generation && c.user?.id == uid) {
        setState(() {
          _summary = summary;
          _ranking = ranking;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _statsError =
              'Không tải được thống kê. Kiểm tra kết nối rồi đồng bộ lại.';
        });
      }
    }
  }

  List<Attendance> get _scopedRecords {
    final period = _period;
    final active = c.data.employees
        .where((e) => e.active && !e.isAdmin && e.approvalStatus == 'Approved')
        .map((e) => e.id)
        .toSet();
    return c.data.attendance.where((a) {
      final day = _vn(a.scheduledStart ?? a.checkIn);
      final inScope = c.isStaff
          ? active.contains(a.employeeId)
          : a.employeeId == c.user?.id;
      return inScope && !day.isBefore(period.start) && day.isBefore(period.end);
    }).toList();
  }

  double get _totalHours => _summary?.netHours ?? 0;
  int get _totalLateMinutes => _summary?.totalLateMinutes ?? 0;
  int get _lateDays => _summary?.lateShifts ?? 0;
  int get _completedShifts => _summary?.actualCheckouts ?? 0;
  int get _attendanceScore => (_summary?.score ?? 0).round();

  // Dữ liệu biểu đồ giờ công theo ngày trong tuần
  List<({String label, double hours, int late})> get _dailyData {
    final Map<String, ({double hours, int late})> grouped = {};

    if (_viewMode == 0) {
      // 7 ngày trong tuần
      final weekStart = _period.start;
      for (int i = 0; i < 7; i++) {
        final day = weekStart.add(Duration(days: i));
        final key = dayKey(day);
        final label = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][i];
        final dayRecords = _scopedRecords.where(
          (a) => dayKey(_vn(a.scheduledStart ?? a.checkIn)) == key,
        );
        grouped[label] = (
          hours: dayRecords.fold(0.0, (sum, a) => sum + a.hours),
          late: dayRecords.where((a) => a.lateMinutes > 0).length,
        );
      }
    } else {
      // Tuần 1-4 trong tháng
      for (
        int w = 0;
        w <
            (DateTime.utc(_vn(_now).year, _vn(_now).month + 1, 0).day / 7)
                .ceil();
        w++
      ) {
        final label = 'Tuần ${w + 1}';
        final weekStart = DateTime.utc(
          _vn(_now).year,
          _vn(_now).month,
          1 + w * 7,
        );
        final weekEnd = DateTime.utc(
          _vn(_now).year,
          _vn(_now).month,
          min(
            1 + (w + 1) * 7,
            DateTime.utc(_vn(_now).year, _vn(_now).month + 1, 0).day + 1,
          ),
        );
        final weekRecords = _scopedRecords.where(
          (a) =>
              !_vn(a.scheduledStart ?? a.checkIn).isBefore(weekStart) &&
              _vn(a.scheduledStart ?? a.checkIn).isBefore(weekEnd),
        );
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

  List<({IconData icon, Color color, String title, String desc})>
  get _insights {
    final summary = _summary;
    if (summary == null) {
      return [
        (
          icon: Icons.info_outline,
          color: const Color(0xFF64748B),
          title: _statsError == null
              ? 'Đang tải thống kê'
              : 'Chưa tải được thống kê',
          desc: _statsError ?? 'Đang lấy kết quả từ máy chủ.',
        ),
      ];
    }
    if (summary.netHours <= 0) {
      return [
        (
          icon: Icons.info_outline,
          color: const Color(0xFF64748B),
          title: 'Chưa có giờ công hợp lệ',
          desc:
              'Chưa đủ dữ liệu để khen thưởng hoặc xếp hạng. Ca quên check-out cần được đối soát.',
        ),
      ];
    }
    final missing = summary.eligibleShifts - summary.actualCheckouts;
    return [
      (
        icon: Icons.schedule_rounded,
        color: const Color(0xFFF59E0B),
        title: summary.lateShifts == 0
            ? 'Không ghi nhận đi trễ trong dữ liệu kỳ này'
            : 'Có ${summary.lateShifts} ca đi trễ',
        desc:
            'Có ${summary.adequateShifts}/${summary.eligibleShifts} ca đủ giờ công.',
      ),
      if (missing > 0)
        (
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFEA580C),
          title: '$missing ca chưa có checkout hợp lệ',
          desc: 'Kiểm tra bản ghi hoặc gửi đơn giải trình.',
        ),
      (
        icon: Icons.info_outline,
        color: const Color(0xFF64748B),
        title: summary.rating,
        desc:
            'Điểm ${summary.score.toStringAsFixed(1)}/100: đúng giờ 40%, đủ giờ 30%, checkout thật 30%.',
      ),
    ];
  }

  List<({String name, double hours, int lateCount, String rating})>
  get _topEmployees => _ranking
      .where((row) => (row['summary']['netHours'] as num) > 0)
      .map((row) {
        final summary = StatisticsSummary.fromJson(
          Map<String, dynamic>.from(row['summary']),
        );
        return (
          name: row['name'].toString(),
          hours: summary.netHours,
          lateCount: summary.lateShifts,
          rating: summary.rating,
        );
      })
      .toList();

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
                    _lateDays > 0
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981),
                  ),
                  _statCard(
                    'Phút trễ',
                    '$_totalLateMinutes',
                    Icons.timer_off_rounded,
                    _totalLateMinutes > 30
                        ? const Color(0xFFEA580C)
                        : const Color(0xFF64748B),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Biểu đồ
        Section(
          title: 'Biểu đồ giờ công',
          subtitle: _viewMode == 0
              ? 'Theo từng ngày trong tuần'
              : 'Theo từng tuần trong tháng',
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
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() >= data.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  data[value.toInt()].label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
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
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                              gradient: d.late > 0
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFFFCA5A5),
                                        Color(0xFFEF4444),
                                      ],
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                    )
                                  : const LinearGradient(
                                      colors: [
                                        Color(0xFF6EE7B7),
                                        Color(0xFF087F8C),
                                      ],
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
          title: '🤖 Phân tích tự động',
          subtitle: 'Phát hiện bất thường & gợi ý cải thiện',
          child: Column(
            children: _insights
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: item.color.withValues(alpha: 0.2),
                        ),
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
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),

        // Bảng xếp hạng (Admin only)
        if (c.isStaff && _topEmployees.isNotEmpty)
          Section(
            title: '🏆 Bảng xếp hạng nhân viên',
            subtitle: 'Theo giờ công ${_viewMode == 0 ? "tuần" : "tháng"} này',
            child: Column(
              children: _topEmployees.take(10).toList().asMap().entries.map((
                entry,
              ) {
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: e.lateCount == 0
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      e.rating,
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
        onTap: () {
          setState(() => _viewMode = mode);
          unawaited(_loadStats());
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
              color: selected
                  ? const Color(0xFF1E293B)
                  : const Color(0xFF64748B),
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
          colors: [
            color.withValues(alpha: 0.06),
            color.withValues(alpha: 0.02),
          ],
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
                  _summary?.rating ?? 'Chưa có thống kê',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                  ),
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
