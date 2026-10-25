import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:latlong2/latlong.dart';
import '../core/app_theme.dart';
import '../domain/models.dart';
import 'app_widgets.dart';

/// Bottom Sheet hiển thị chi tiết chấm công:
/// - Tái sử dụng cho màn Tổng quan và màn Bảng công
/// - Hiển thị địa chỉ thực tế (reverse geocoded) thay vì tọa độ số thô
/// - Tích hợp bản đồ trực quan bằng OpenStreetMap (flutter_map)
/// - Hiển thị StatusChip và thời gian vào/ra rõ ràng
class AttendanceDetailSheet extends StatefulWidget {
  final Attendance attendance;
  final String employeeName;
  final String? department;

  const AttendanceDetailSheet({
    super.key,
    required this.attendance,
    required this.employeeName,
    this.department,
  });

  /// Hàm tiện ích mở Bottom Sheet chi tiết chấm công
  static Future<void> show(
    BuildContext context, {
    required Attendance attendance,
    required String employeeName,
    String? department,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AttendanceDetailSheet(
        attendance: attendance,
        employeeName: employeeName,
        department: department,
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
  bool _showMap = false;
  LatLng? _selectedMapPoint;

  Attendance get a => widget.attendance;

  @override
  void initState() {
    super.initState();
    _fetchAddresses();
    if (a.latitude != 0 || a.longitude != 0) {
      _selectedMapPoint = LatLng(a.latitude, a.longitude);
    }
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

  /// Xác định loại chip trạng thái hiển thị
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

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
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

              // Tiêu đề Sheet
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
                    // Khối thời gian vào / ra
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildTimeRow(
                            context: context,
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
                            context: context,
                            icon: Icons.logout_rounded,
                            iconColor: a.checkOut != null ? AppColors.orange : AppColors.textSecondary,
                            title: 'Thời gian ra',
                            time: a.checkOut != null ? clock(a.checkOut) : 'Chưa ghi nhận',
                            date: a.checkOut != null ? dateLabel(a.checkOut!) : 'Chưa kết thúc ca',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Khối địa điểm và vị trí thực tế
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Vị trí điểm danh',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (hasInLocation || hasOutLocation)
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() => _showMap = !_showMap);
                                  },
                                  icon: Icon(
                                    _showMap ? Icons.map_outlined : Icons.pin_drop_outlined,
                                    size: 16,
                                  ),
                                  label: Text(_showMap ? 'Ẩn bản đồ' : 'Xem bản đồ'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.teal,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Vị trí vào
                          _buildLocationItem(
                            label: 'Vị trí vào:',
                            address: _inAddress,
                            loading: _loadingIn,
                            iconColor: AppColors.teal,
                            onViewOnMap: hasInLocation
                                ? () => setState(() {
                                      _showMap = true;
                                      _selectedMapPoint = LatLng(a.latitude, a.longitude);
                                    })
                                : null,
                          ),
                          const SizedBox(height: 12),

                          // Vị trí ra
                          _buildLocationItem(
                            label: 'Vị trí ra:',
                            address: a.checkOut != null
                                ? _outAddress
                                : 'Chưa có dữ liệu ra ca',
                            loading: _loadingOut,
                            iconColor: AppColors.orange,
                            onViewOnMap: hasOutLocation
                                ? () => setState(() {
                                      _showMap = true;
                                      _selectedMapPoint =
                                          LatLng(a.outLatitude!, a.outLongitude!);
                                    })
                                : null,
                          ),

                          // Khung bản đồ OpenStreetMap
                          if (_showMap && _selectedMapPoint != null) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 180,
                                decoration: BoxDecoration(
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: FlutterMap(
                                  options: MapOptions(
                                    initialCenter: _selectedMapPoint!,
                                    initialZoom: 16.0,
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.example.app_cham_cong_tong_nhat_bao_an',
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point: _selectedMapPoint!,
                                          width: 40,
                                          height: 40,
                                          child: const Icon(
                                            Icons.location_on,
                                            color: AppColors.error,
                                            size: 38,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Ghi chú & Giải thích của hệ thống
                    if (a.explanation.isNotEmpty) ...[
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 18, color: AppColors.teal),
                                SizedBox(width: 8),
                                Text(
                                  'Ghi chú hệ thống',
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
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Nút đóng
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

  Widget _buildTimeRow({
    required BuildContext context,
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
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Text(
          date,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildLocationItem({
    required String label,
    required String? address,
    required bool loading,
    required Color iconColor,
    VoidCallback? onViewOnMap,
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
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: loading
              ? const Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.teal,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Đang tra cứu địa chỉ...',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                )
              : Text(
                  address ?? 'Chưa xác định',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
        ),
        if (onViewOnMap != null)
          IconButton(
            tooltip: 'Xem trên bản đồ',
            onPressed: onViewOnMap,
            icon: const Icon(Icons.map_rounded, size: 18, color: AppColors.teal),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
      ],
    );
  }
}
