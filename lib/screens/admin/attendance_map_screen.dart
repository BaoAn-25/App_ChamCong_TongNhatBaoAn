import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/app_theme.dart';
import '../../domain/app_controller.dart';
import '../../domain/models.dart';
import '../../widgets/app_widgets.dart';
import 'employee_history_screen.dart';

/// Màn hình Bản đồ Chấm công theo ngày (AttendanceMapScreen):
/// 1. Bản đồ flutter_map + OpenStreetMap, tự căn khung theo các điểm, marker & vòng tròn bán kính VP.
/// 2. Chọn ngày: nút ngày trước / sau, bấm vào ngày mở showDatePicker. Mặc định hôm nay.
/// 3. Marker nhân viên: Xanh lá = đúng giờ trong bán kính, Vàng = đi trễ, Đỏ = ngoài bán kính hoặc thiếu giờ ra.
/// 4. Bấm marker mở Bottom Sheet tóm tắt: họ tên, ca, giờ vào/ra, khoảng cách tới VP (mét), sai số GPS, nút "Lịch sử chấm công".
/// 5. DraggableScrollableSheet phía dưới: danh sách nhân viên hoạt động, trạng thái (Đã vào, Đã ra, Thiếu giờ ra, Chưa chấm công), bấm di chuyển bản đồ tới marker, chip lọc phòng ban.
/// 6. Dòng chú thích nhỏ cuối màn.
/// 7. Trạng thái rỗng, trạng thái lỗi có nút thử lại.
class AttendanceMapScreen extends StatefulWidget {
  final AppController controller;

  const AttendanceMapScreen({
    super.key,
    required this.controller,
  });

  @override
  State<AttendanceMapScreen> createState() => _AttendanceMapScreenState();
}

class _AttendanceMapScreenState extends State<AttendanceMapScreen> {
  final MapController _mapController = MapController();
  late DateTime _selectedDate;
  String? _selectedDeptFilter;
  bool _isLoading = false;

  AppController get c => widget.controller;
  Office get office => c.data.office;

  String _getEmployeeName(String empId) {
    return c.data.employees.where((e) => e.id == empId).firstOrNull?.name ?? 'Nhân viên';
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  // Danh sách chấm công trong ngày được chọn
  List<Attendance> get _attendancesOnDate {
    final targetDayStr = dayKey(_selectedDate);
    return c.data.attendance.where((a) {
      final aDate = a.checkIn.toUtc().add(const Duration(hours: 7));
      return dayKey(aDate) == targetDayStr;
    }).toList();
  }

  // Danh sách toàn bộ nhân viên đang hoạt động
  List<Employee> get _activeEmployees {
    return c.data.employees.where((e) {
      if (!e.active || e.isAdmin) return false;
      if (_selectedDeptFilter != null &&
          e.department.toLowerCase() != _selectedDeptFilter!.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();
  }

  // Tính khoảng cách từ điểm GPS tới văn phòng (mét)
  double? _calculateDistanceToOffice(double lat, double lng) {
    if (!office.configured || office.latitude == null || office.longitude == null) {
      return null;
    }
    return Geolocator.distanceBetween(lat, lng, office.latitude!, office.longitude!);
  }

  // Xác định màu marker dựa trên trạng thái và vị trí
  Color _getMarkerColor(Attendance a) {
    // Thiếu giờ ra
    if (a.checkOut == null && DateTime.now().isAfter(a.scheduledEnd)) {
      return AppColors.error;
    }

    // Kiểm tra ngoài bán kính văn phòng
    if (a.latitude != 0 && a.longitude != 0) {
      final dist = _calculateDistanceToOffice(a.latitude, a.longitude);
      if (dist != null && dist > office.radius) {
        return AppColors.error; // Ngoài bán kính
      }
    }

    // Đi trễ
    if (a.lateMinutes > 0) {
      return AppColors.warning;
    }

    // Đúng giờ và trong bán kính
    return AppColors.success;
  }

  void _changeDate(int offsetDays) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: offsetDays));
    });
    _fitMapToPoints();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Chọn ngày xem bản đồ chấm công',
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
      _fitMapToPoints();
    }
  }

  void _fitMapToPoints() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final points = <LatLng>[];
      if (office.configured && office.latitude != null && office.longitude != null) {
        points.add(LatLng(office.latitude!, office.longitude!));
      }
      for (final a in _attendancesOnDate) {
        if (a.latitude != 0 && a.longitude != 0) {
          points.add(LatLng(a.latitude, a.longitude));
        }
      }
      if (points.isNotEmpty) {
        if (points.length == 1) {
          _mapController.move(points.first, 15.5);
        } else {
          try {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(50),
              ),
            );
          } catch (_) {
            _mapController.move(points.first, 15.0);
          }
        }
      }
    });
  }

  void _moveToEmployeeMarker(Attendance a) {
    if (a.latitude != 0 && a.longitude != 0) {
      _mapController.move(LatLng(a.latitude, a.longitude), 16.5);
      _showAttendanceQuickDetail(a);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lượt chấm công này không có tọa độ GPS hợp lệ.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 4. Bấm marker mở Bottom Sheet tóm tắt thông tin
  void _showAttendanceQuickDetail(Attendance a) {
    final emp = c.data.employees.where((e) => e.id == a.employeeId).firstOrNull;
    final empName = emp?.name ?? a.employeeName ?? 'Nhân viên';
    final dist = _calculateDistanceToOffice(a.latitude, a.longitude);
    final isOutside = dist != null && dist > office.radius;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _getMarkerColor(a).withValues(alpha: 0.15),
                    child: Text(
                      empName.isNotEmpty ? empName[0].toUpperCase() : 'N',
                      style: TextStyle(
                        color: _getMarkerColor(a),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${emp?.department ?? ''} • ${a.shiftName}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.teal,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 14),

              // Giờ vào / giờ ra
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildQuickInfo(
                    label: 'Giờ vào',
                    value: clock(a.checkIn),
                    color: AppColors.success,
                  ),
                  _buildQuickInfo(
                    label: 'Giờ ra',
                    value: a.checkOut != null ? clock(a.checkOut) : 'Chưa ghi nhận',
                    color: a.checkOut != null ? AppColors.orange : AppColors.textSecondary,
                  ),
                  _buildQuickInfo(
                    label: 'Tổng giờ',
                    value: '${a.hours.toStringAsFixed(1)}h',
                    color: AppColors.teal,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Khoảng cách và sai số
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isOutside ? AppColors.errorBg : AppColors.input,
                        borderRadius: BorderRadius.circular(12),
                        border: isOutside ? Border.all(color: AppColors.error.withValues(alpha: 0.3)) : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Khoảng cách VP',
                            style: TextStyle(
                              fontSize: 11,
                              color: isOutside ? AppColors.error : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dist != null ? '${dist.round()} mét ${isOutside ? '(Ngoài bán kính)' : '(Hợp lệ)'}' : 'Chưa rõ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isOutside ? AppColors.error : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sai số GPS',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '±${a.accuracy.toStringAsFixed(1)} mét',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Nút Lịch sử chấm công
              PrimaryButton(
                title: 'Xem lịch sử chấm công',
                icon: Icons.history_rounded,
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmployeeHistoryScreen(
                        controller: c,
                        userId: a.employeeId,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickInfo({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final attendances = _attendancesOnDate;
    final activeEmployees = _activeEmployees;
    final hasOffice = office.configured && office.latitude != null && office.longitude != null;

    final initialCenter = hasOffice
        ? LatLng(office.latitude!, office.longitude!)
        : (attendances.isNotEmpty && attendances.first.latitude != 0
            ? LatLng(attendances.first.latitude, attendances.first.longitude)
            : const LatLng(10.7769, 106.7009));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Bản đồ chấm công',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Tải lại dữ liệu',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              setState(() => _isLoading = true);
              try {
                await c.syncAll();
                _fitMapToPoints();
              } catch (e) {
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Lỗi làm mới: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _isLoading = false);
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // ==================================================================
          // 1. BẢN ĐỒ OPENSTREETMAP (flutter_map)
          // ==================================================================
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 15.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app_cham_cong_tong_nhat_bao_an',
              ),

              // Vòng tròn bán kính văn phòng
              if (hasOffice)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(office.latitude!, office.longitude!),
                      radius: office.radius,
                      useRadiusInMeter: true,
                      color: AppColors.teal.withValues(alpha: 0.15),
                      borderColor: AppColors.teal,
                      borderStrokeWidth: 2.0,
                    ),
                  ],
                ),

              // Markers
              MarkerLayer(
                markers: [
                  // Marker Văn phòng
                  if (hasOffice)
                    Marker(
                      point: LatLng(office.latitude!, office.longitude!),
                      width: 50,
                      height: 50,
                      child: Tooltip(
                        message: office.name,
                        child: const Icon(
                          Icons.business_rounded,
                          color: AppColors.navy,
                          size: 40,
                        ),
                      ),
                    ),

                  // Markers các lượt chấm công của nhân viên
                  for (final a in attendances.where((x) => x.latitude != 0 && x.longitude != 0))
                    Marker(
                      point: LatLng(a.latitude, a.longitude),
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showAttendanceQuickDetail(a),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.location_on_rounded,
                              color: _getMarkerColor(a),
                              size: 42,
                            ),
                            Positioned(
                              top: 6,
                              child: Text(
                                _getEmployeeName(a.employeeId).isNotEmpty
                                    ? _getEmployeeName(a.employeeId)[0].toUpperCase()
                                    : 'N',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // ==================================================================
          // 2. THANH CHỌN NGÀY NỔI TRÊN CÙNG
          // ==================================================================
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Material(
              elevation: 4,
              shadowColor: AppColors.navy.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => _changeDate(-1),
                    ),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.teal),
                            const SizedBox(width: 8),
                            Text(
                              dateLabel(_selectedDate),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => _changeDate(1),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Chú giải màu sắc marker
          Positioned(
            top: 76,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppTheme.cardShadow,
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildLegendItem(AppColors.success, 'Đúng giờ trong VP'),
                  const SizedBox(height: 4),
                  _buildLegendItem(AppColors.warning, 'Đi trễ'),
                  const SizedBox(height: 4),
                  _buildLegendItem(AppColors.error, 'Ngoài VP / Thiếu giờ ra'),
                ],
              ),
            ),
          ),

          // Loading Indicator
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 3,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.teal),
              ),
            ),

          // ==================================================================
          // 5. DRAGGABLE SCROLLABLE SHEET LIỆT KÊ NHÂN VIÊN
          // ==================================================================
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.18,
            maxChildSize: 0.85,
            builder: (ctx, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Thanh gạt
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Header Sheet + Bộ lọc phòng ban
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Tình hình nhân sự (${attendances.length}/${activeEmployees.length})',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Có mặt: ${attendances.map((a) => a.employeeId).toSet().length}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Chip lọc phòng ban
                    if (c.data.departments.isNotEmpty)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            ChoiceChip(
                              label: const Text('Tất cả PB', style: TextStyle(fontSize: 11)),
                              selected: _selectedDeptFilter == null,
                              onSelected: (_) => setState(() => _selectedDeptFilter = null),
                            ),
                            for (final d in c.data.departments) ...[
                              const SizedBox(width: 6),
                              ChoiceChip(
                                label: Text(d.name, style: const TextStyle(fontSize: 11)),
                                selected: _selectedDeptFilter?.toLowerCase() == d.name.toLowerCase(),
                                onSelected: (sel) => setState(() => _selectedDeptFilter = sel ? d.name : null),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const Divider(height: 14, color: AppColors.border),

                    // Danh sách nhân viên
                    Expanded(
                      child: activeEmployees.isEmpty
                          ? const Center(
                              child: EmptyState(
                                title: 'Không có nhân sự',
                                description: 'Chưa có nhân viên hoạt động trong phòng ban đã chọn.',
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                              itemCount: activeEmployees.length + 1,
                              itemBuilder: (context, index) {
                                // 6. Dòng chú thích nhỏ ở cuối
                                if (index == activeEmployees.length) {
                                  return const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    child: Center(
                                      child: Text(
                                        'ℹ️ Vị trí chỉ được ghi tại thời điểm chấm công vào/ra.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final emp = activeEmployees[index];
                                final record = attendances
                                    .where((a) => a.employeeId == emp.id)
                                    .firstOrNull;

                                String statusLabel;
                                Color statusColor;
                                IconData statusIcon;

                                if (record == null) {
                                  statusLabel = 'Chưa chấm công';
                                  statusColor = AppColors.textSecondary;
                                  statusIcon = Icons.radio_button_unchecked;
                                } else if (record.checkOut != null) {
                                  statusLabel = 'Đã ra lúc ${clock(record.checkOut)}';
                                  statusColor = AppColors.teal;
                                  statusIcon = Icons.logout_rounded;
                                } else if (DateTime.now().isAfter(record.scheduledEnd)) {
                                  statusLabel = 'Thiếu giờ ra (vào ${clock(record.checkIn)})';
                                  statusColor = AppColors.error;
                                  statusIcon = Icons.warning_amber_rounded;
                                } else {
                                  statusLabel = 'Đã vào lúc ${clock(record.checkIn)}';
                                  statusColor = AppColors.success;
                                  statusIcon = Icons.login_rounded;
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: record != null
                                        ? AppColors.surface
                                        : AppColors.input.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: record != null ? AppColors.border : Colors.transparent,
                                      width: 0.8,
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                    leading: CircleAvatar(
                                      radius: 18,
                                      backgroundColor: record != null
                                          ? _getMarkerColor(record).withValues(alpha: 0.15)
                                          : Colors.grey.shade200,
                                      child: Text(
                                        emp.name.isNotEmpty ? emp.name[0].toUpperCase() : 'U',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: record != null
                                              ? _getMarkerColor(record)
                                              : Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      emp.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: record != null
                                            ? AppColors.textPrimary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Icon(statusIcon, size: 13, color: statusColor),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${emp.department.isNotEmpty ? '${emp.department} • ' : ''}$statusLabel',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: statusColor,
                                              fontWeight: record != null ? FontWeight.w600 : FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: record != null && record.latitude != 0
                                        ? IconButton(
                                            tooltip: 'Xem vị trí trên bản đồ',
                                            icon: const Icon(
                                              Icons.my_location_rounded,
                                              size: 20,
                                              color: AppColors.teal,
                                            ),
                                            onPressed: () => _moveToEmployeeMarker(record),
                                          )
                                        : null,
                                    onTap: () {
                                      if (record != null) {
                                        _moveToEmployeeMarker(record);
                                      } else {
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
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
