import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../domain/app_controller.dart';
import '../domain/attendance_analytics.dart';
import 'common.dart';

class StatsPage extends StatefulWidget {
  final AppController controller;
  const StatsPage({super.key, required this.controller});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  bool monthly = false;
  bool personal = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final stats = AttendanceAnalytics(
      c.data.attendance,
      now: DateTime.now(),
      monthly: monthly,
      employeeId: !c.isStaff || personal ? c.user?.id : null,
    );
    final buckets = stats.buckets;
    final maxY = max(
      1.0,
      buckets.fold<double>(0, (v, b) => max(v, b.hours)) * 1.2,
    );
    return RefreshIndicator(
      onRefresh: c.syncAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Section(
            title: 'Hiểu rõ thời gian làm việc',
            subtitle:
                'Tổng hợp theo giờ Việt Nam • Chỉ tính giờ của ca đã chấm ra',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Tuần này')),
                    ButtonSegment(value: true, label: Text('Tháng này')),
                  ],
                  selected: {monthly},
                  onSelectionChanged: (v) => setState(() => monthly = v.first),
                ),
                if (c.isStaff)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Toàn bộ nhân viên'),
                        ),
                        ButtonSegment(value: true, label: Text('Cá nhân')),
                      ],
                      selected: {personal},
                      onSelectionChanged: (v) =>
                          setState(() => personal = v.first),
                    ),
                  ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children:
                        [
                              (
                                'Giờ đã ghi nhận',
                                '${stats.hours.toStringAsFixed(1)} giờ',
                                Icons.schedule,
                              ),
                              (
                                'Ca hoàn tất',
                                '${stats.completed}',
                                Icons.task_alt,
                              ),
                              (
                                'Đúng giờ',
                                stats.onTimePercent == null
                                    ? 'Chưa có dữ liệu'
                                    : '${stats.onTimePercent!.toStringAsFixed(0)}%',
                                Icons.verified_outlined,
                              ),
                              (
                                'Đi trễ',
                                '${stats.late} ca / ${stats.lateMinutes} phút',
                                Icons.more_time,
                              ),
                            ]
                            .map(
                              (item) => SizedBox(
                                width: constraints.maxWidth < 340
                                    ? constraints.maxWidth
                                    : (constraints.maxWidth - 12) / 2,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF0F7F8),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        item.$3,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        item.$2,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(item.$1),
                                    ],
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
          Section(
            title: 'Nhịp làm việc',
            subtitle: monthly
                ? 'Giờ công theo nhóm ngày trong tháng'
                : 'Giờ công theo ngày trong tuần',
            child: stats.records.isEmpty
                ? const EmptyState(
                    'Chưa có bản ghi trong khoảng thời gian này.',
                  )
                : SizedBox(
                    height: 240,
                    child: BarChart(
                      BarChartData(
                        maxY: maxY,
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(drawVerticalLine: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (v, _) => Text(
                                '${v.toInt()}h',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              getTitlesWidget: (v, _) =>
                                  v < 0 || v >= buckets.length
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        buckets[v.toInt()].label,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                              '${buckets[group.x].label}: ${rod.toY.toStringAsFixed(1)} giờ',
                              const TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        barGroups: List.generate(
                          buckets.length,
                          (i) => BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: buckets[i].hours,
                                width: 20,
                                color: const Color(0xFF087F8C),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Section(
            title: 'Nhận xét tự động',
            subtitle:
                'Phân tích theo quy tắc từ dữ liệu đã tải, chưa sử dụng mô hình AI.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (stats.records.isEmpty)
                  const EmptyState('Chưa đủ dữ liệu để đưa ra nhận xét.')
                else ...[
                  _insight(
                    Icons.timer_outlined,
                    'Đi trễ',
                    '${stats.late}/${stats.records.length} ca có ghi nhận trễ, tổng ${stats.lateMinutes} phút. Số phút đã trừ dung sai của ca.',
                  ),
                  _insight(
                    Icons.pending_actions,
                    'Cần kiểm tra',
                    '${stats.overdue} ca đã qua giờ kết thúc nhưng chưa chấm ra. Kiểm tra bảng công và gửi đơn giải trình nếu cần.',
                  ),
                  _insight(
                    Icons.work_outline,
                    'Đang làm việc',
                    '${stats.working} ca đang trong giờ làm; không tính là quên chấm ra.',
                  ),
                ],
                const Divider(height: 28),
                const Text(
                  'Cách đọc: tỷ lệ đúng giờ = số ca không trễ / số ca đã chấm vào. Không suy ra ngày vắng vì hệ thống chưa có lịch làm việc đầy đủ. Giờ công chưa trừ giờ nghỉ và không dùng để tự động tính lương.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF536579)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _insight(IconData icon, String title, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF087F8C)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(text),
            ],
          ),
        ),
      ],
    ),
  );
}
