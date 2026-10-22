import 'models.dart';

/// Deterministic analysis, not an AI model. Business calendar uses Vietnam time.
class AttendanceAnalytics {
  final DateTime now;
  final bool monthly;
  final List<Attendance> records;
  static DateTime vietnam(DateTime value) =>
      value.toUtc().add(const Duration(hours: 7));

  AttendanceAnalytics(
    Iterable<Attendance> source, {
    required this.now,
    required this.monthly,
    String? employeeId,
  }) : records = source.where((a) {
         final today = vietnam(now);
         final start = monthly
             ? DateTime.utc(today.year, today.month, 1)
             : DateTime.utc(
                 today.year,
                 today.month,
                 today.day - today.weekday + 1,
               );
         final end = monthly
             ? DateTime.utc(today.year, today.month + 1, 1)
             : start.add(const Duration(days: 7));
         final date = vietnam(a.checkIn);
         return (employeeId == null || a.employeeId == employeeId) &&
             !date.isBefore(start) &&
             date.isBefore(end) &&
             !a.checkIn.isAfter(now);
       }).toList();

  double get hours => records.fold(0, (sum, a) => sum + safeHours(a));
  static double safeHours(Attendance a) =>
      a.checkOut == null || a.checkOut!.isBefore(a.checkIn)
      ? 0
      : a.checkOut!.difference(a.checkIn).inMinutes / 60;
  int get completed => records.where((a) => a.checkOut != null).length;
  int get late => records.where((a) => a.lateMinutes > 0).length;
  int get lateMinutes => records.fold(
    0,
    (sum, a) => sum + (a.lateMinutes < 0 ? 0 : a.lateMinutes),
  );
  int get overdue => records
      .where((a) => a.checkOut == null && a.scheduledEnd.isBefore(now))
      .length;
  int get working => records
      .where((a) => a.checkOut == null && !a.scheduledEnd.isBefore(now))
      .length;
  double? get onTimePercent =>
      records.isEmpty ? null : 100 * (records.length - late) / records.length;

  List<({String label, double hours})> get buckets {
    final today = vietnam(now);
    final days = DateTime.utc(today.year, today.month + 1, 0).day;
    final count = monthly ? (days / 7).ceil() : 7;
    final start = monthly
        ? DateTime.utc(today.year, today.month, 1)
        : DateTime.utc(today.year, today.month, today.day - today.weekday + 1);
    return List.generate(count, (i) {
      final lower = start.add(Duration(days: monthly ? i * 7 : i));
      final upper = lower.add(Duration(days: monthly ? 7 : 1));
      return (
        label: monthly
            ? '${i * 7 + 1}–${((i + 1) * 7).clamp(1, days)}'
            : ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][i],
        hours: records
            .where((a) {
              final day = vietnam(a.checkIn);
              return !day.isBefore(lower) && day.isBefore(upper);
            })
            .fold<double>(0, (sum, a) => sum + safeHours(a)),
      );
    });
  }
}
