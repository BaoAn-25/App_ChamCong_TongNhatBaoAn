import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:latlong2/latlong.dart';
import '../core/app_theme.dart';
import '../domain/models.dart';
import 'app_widgets.dart';

/// Bottom Sheet hiển thị chi tiết chấm công:
/// - Tái sử dụng cho màn Tổng quan và màn Bảng công
/// - Dòng thời gian vào/ra, GPS vào/ra, sai số đo lường
/// - Giải thích đi trễ/ra sớm (chi tiết dung sai)
/// - Bản đồ nhỏ (flutter_map + OpenStreetMap) có marker vào, ra và vòng tròn bán kính văn phòng
class AttendanceDetailSheet extends StatefulWidget {
  final Attendance attendance;
  final String employeeName;
  final String? department;
  final Office? office;

  const AttendanceDetailSheet({
    super.key,
    required this.attendance,
    required this.employeeName,
    this.department,
    this.office,
  });

  /// Hàm tiện ích mở Bottom Sheet chi tiết chấm công
  static Future<void> show(
    BuildContext context, {
    required Attendance attendance,
    required String employeeName,
    String? department,
    Office? office,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AttendanceDetailSheet(
        attendance: attendance,
        employeeName: employeeName,
        department: department,
        office: office,
      ),
    );
  }

  @override
  State<AttendanceDetailSheet> createState() => _AttendanceDetailSheetState();
}

class _AttendanceDetailSheetState extends State<AttendanceDetailSheet> {
  static final Map<String, String> _addressCache = {};

  String? _inAddress;
  String? _outAddress;
  bool _loadingIn = true;
  bool _loadingOut = false;

  Attendance get a => widget.attendance;
  Office? get office => widget.office;

  @override
  void initState() {
    super.initState();
    _fetchAddresses();
  }

  Future<void> _fetchAddresses() async {
    _resolveAddress(a.latitude, a.longitude).then((addr) {
      if (mounted) {
        setState(() {
          _inAddress = addr;
          _loadingIn = false;
        });
      }
    });

    if (a.outLatitude != null && a.outLongitude != null) {
      setState(() => _loadingOut = true);
      _resolveAddress(a.outLatitude!, a.outLongitude!).then((addr) {
        if (mounted) {
          setState(() {
            _outAddress = addr;
            _loadingOut = false;
          });
        }
      });
    }
  }

  Future<String> _resolveAddress(double lat, double lng) async {
    if (lat == 0 && lng == 0) return 'Không có dữ liệu GPS';
    final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    if (_addressCache.containsKey(key)) return _addressCache[key]!;

    try {
      final entries = await geo.Geocoding()
          .placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 4));
      if (entries.isNotEmpty) {
        final pm = entries.first;
        final parts = [
          pm.street,
          pm.subLocality,
          pm.locality,
          pm.subAdministrativeArea,
          pm.administrativeArea,
        ]
            .whereType<String>()
            .map((s) => s.trim())
            .where((v) => v.isNotEmpty)
            .toSet()
            .toList();

        if (parts.isNotEmpty) {
          final res = parts.join(', ');
          _addressCache[key] = res;
          return res;
        }
      }
    } catch (_) {}

    final fallback = 'Tọa độ: ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    _addressCache[key] = fallback;
    return fallback;
  }

  Widget _buildStatusChip() {
    if (a.lateMinutes > 0) {
      return StatusChip('Đi trễ ${a.lateMinutes}p', icon: Icons.alarm_off_outlined);
    }
    if (a.checkOut != null && a.checkOut!.isBefore(a.scheduledEnd)) {
      final earlyMinutes = a.scheduledEnd.difference(a.checkOut!).inMinutes;
      return StatusChip('Ra sớm ${earlyMinutes}p', icon: Icons.directions_walk_outlined);
    }
    if (a.checkOut == null && DateTime.now().isAfter(a.scheduledEnd)) {
      return const StatusChip('Thiếu giờ ra', icon: Icons.warning_amber_rounded);
    }
    if (a.checkOut == null) {
      return const StatusChip('Đang trong ca', icon: Icons.access_time_rounded);
    }
    return const StatusChip('Đúng giờ', icon: Icons.check_circle_outline);
  }

  @override
  Widget build(BuildContext context) {
    final hasInLocation = a.latitude != 0 && a.longitude != 0;
    final hasOutLocation = a.outLatitude != null &&
        a.outLongitude != null &&
        (a.outLatitude != 0 || a.outLongitude != 0);

    final hasOffice = office != null &&
        office!.latitude != null &&
        office!.longitude != null &&
        office!.latitude != 0;

    // Tọa độ tâm bản đồ: ưu tiên vị trí vào, hoặc văn phòng
    final centerPoint = hasInLocation
        ? LatLng(a.latitude, a.longitude)
        : (hasOffice
            ? LatLng(office!.latitude!, office!.longitude!)
            : const LatLng(10.7769, 106.7009));

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Thanh kéo (Drag handle)
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),

              // Header Sheet
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.teal.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.fact_check_outlined,
                        color: AppColors.teal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.employeeName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.department != null && widget.department!.isNotEmpty ? '${widget.department} • ' : ''}${a.shiftName}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.teal,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildStatusChip(),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.border, height: 1),

              // Nội dung chi tiết cuộn được
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // 1. Khối thời gian vào / ra & tổng giờ
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildTimeRow(
                            icon: Icons.login_rounded,
                            iconColor: AppColors.success,
                            title: 'Thời gian vào',
                            time: clock(a.checkIn),
                            date: dateLabel(a.checkIn),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(color: AppColors.border, height: 1),
                          ),
                          _buildTimeRow(
                            icon: Icons.logout_rounded,
                            iconColor: a.checkOut != null ? AppColors.orange : AppColors.textSecondary,
                            title: 'Thời gian ra',
                            time: a.checkOut != null ? clock(a.checkOut) : 'Chưa ghi nhận',
                            date: a.checkOut != null ? dateLabel(a.checkOut!) : 'Chưa kết thúc ca',
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Divider(color: AppColors.border, height: 1),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Tổng thời gian làm việc',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${a.hours.toStringAsFixed(1)} giờ',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.teal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 2. Khối GPS & Sai số đo lường
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Thông tin vị trí & GPS',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Vị trí vào
                          _buildLocationDetailItem(
                            label: 'Vị trí vào:',
                            coords: hasInLocation
                                ? '${a.latitude.toStringAsFixed(5)}, ${a.longitude.toStringAsFixed(5)}'
                                : 'Không có GPS',
                            accuracy: hasInLocation ? '±${a.accuracy.toStringAsFixed(1)}m' : null,
                            address: _inAddress,
                            loading: _loadingIn,
                            iconColor: AppColors.teal,
                          ),
                          const SizedBox(height: 12),

                          // Vị trí ra
                          _buildLocationDetailItem(
                            label: 'Vị trí ra:',
                            coords: hasOutLocation
                                ? '${a.outLatitude!.toStringAsFixed(5)}, ${a.outLongitude!.toStringAsFixed(5)}'
                                : (a.checkOut != null ? 'Không có GPS' : 'Chưa ghi nhận'),
                            accuracy: null,
                            address: a.checkOut != null ? _outAddress : 'Chưa kết thúc ca',
                            loading: _loadingOut,
                            iconColor: AppColors.orange,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Bản đồ nhỏ (flutter_map) với Marker vào/ra và Vòng tròn bán kính văn phòng
                    if (hasInLocation || hasOffice) ...[
                      AppCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Bản đồ vị trí điểm danh',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                if (hasOffice)
                                  Text(
                                    'Bán kính VP: ${office!.radius.round()}m',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                height: 200,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter: centerPoint,
                                    initialZoom: 15.5,
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.example.app_cham_cong_tong_nhat_bao_an',
                                    ),
                                    // Vòng tròn bán kính văn phòng
                                    if (hasOffice)
                                      CircleLayer(
                                        circles: [
                                          CircleMarker(
                                            point: LatLng(office!.latitude!, office!.longitude!),
                                            radius: office!.radius,
                                            useRadiusInMeter: true,
                                            color: AppColors.teal.withValues(alpha: 0.15),
                                            borderColor: AppColors.teal,
                                            borderStrokeWidth: 1.5,
                                          ),
                                        ],
                                      ),
                                    // Markers
                                    MarkerLayer(
                                      markers: [
                                        // Marker văn phòng
                                        if (hasOffice)
                                          Marker(
                                            point: LatLng(office!.latitude!, office!.longitude!),
                                            width: 44,
                                            height: 44,
                                            child: const Icon(
                                              Icons.business_rounded,
                                              color: AppColors.navy,
                                              size: 36,
                                            ),
                                          ),
                                        // Marker điểm check-in
                                        if (hasInLocation)
                                          Marker(
                                            point: LatLng(a.latitude, a.longitude),
                                            width: 40,
                                            height: 40,
                                            child: const Icon(
                                              Icons.location_on,
                                              color: AppColors.teal,
                                              size: 36,
                                            ),
                                          ),
                                        // Marker điểm check-out
                                        if (hasOutLocation)
                                          Marker(
                                            point: LatLng(a.outLatitude!, a.outLongitude!),
                                            width: 40,
                                            height: 40,
                                            child: const Icon(
                                              Icons.location_on,
                                              color: AppColors.orange,
                                              size: 36,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Chú thích bản đồ
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (hasOffice) ...[
                                  _buildMapLegend(AppColors.navy, 'Văn phòng'),
                                  const SizedBox(width: 14),
                                ],
                                if (hasInLocation) ...[
                                  _buildMapLegend(AppColors.teal, 'Vị trí vào'),
                                  const SizedBox(width: 14),
                                ],
                                if (hasOutLocation)
                                  _buildMapLegend(AppColors.orange, 'Vị trí ra'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 4. Giải thích đi trễ / ra sớm (chi tiết dung sai)
                    if (a.explanation.isNotEmpty) ...[
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.teal),
                                SizedBox(width: 8),
                                Text(
                                  'Giải thích chấm công chi tiết',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              a.explanation,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    PrimaryButton(
                      title: 'Đóng',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMapLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildTimeRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String time,
    required String date,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
        Text(
          date,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildLocationDetailItem({
    required String label,
    required String coords,
    required String? accuracy,
    required String? address,
    required bool loading,
    required Color iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.place_outlined, size: 18, color: iconColor),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    coords,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  if (accuracy != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Sai số: $accuracy',
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              loading
                  ? const Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.teal),
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Đang tra cứu địa chỉ...',
                          style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                        ),
                      ],
                    )
                  : Text(
                      address ?? 'Chưa xác định',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}
