import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_config.dart';
import '../session_storage.dart';
import '../data/api_repositories.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'common.dart';
import 'punch_page.dart';
import 'stats_page.dart';
import 'biometric_page.dart';
import 'face_page.dart';
import '../widgets/attendance_detail_sheet.dart';
import '../screens/admin/attendance_map_screen.dart';

class HomePage extends StatefulWidget {
  final AppController controller;
  const HomePage({super.key, required this.controller});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int page = 0;
  bool performing = false;
  bool locating = false;
  String search = '', requestFilter = 'all', roleFilter = 'all';
  String? deptFilter;
  String? _avatarBase64;
  DateTimeRange? historyRange;
  bool _staffExpanded = false;
  DateTime _selectedTimesheetMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  Future<void> _loadAvatar() async {
    final uid = c.user?.id;
    if (uid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final b64 = prefs.getString('user_avatar_$uid');
      if (mounted && b64 != _avatarBase64) {
        setState(() => _avatarBase64 = b64);
      }
    } catch (_) {}
  }

  Future<void> _pickAvatar() async {
    final uid = c.user?.id;
    if (uid == null) return;

    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Ảnh đại diện',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: Color(0xFF087F8C),
              ),
              title: const Text('Chụp ảnh từ máy ảnh'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: Color(0xFF087F8C),
              ),
              title: const Text('Chọn ảnh từ thư viện'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (_avatarBase64 != null)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red,
                ),
                title: const Text(
                  'Xóa ảnh đại diện',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('user_avatar_$uid');
                  if (mounted) setState(() => _avatarBase64 = null);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã gỡ ảnh đại diện')),
                    );
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (pickedFile == null) return;

      final bytes = await pickedFile.readAsBytes();
      final b64 = base64Encode(bytes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_avatar_$uid', b64);
      if (mounted) {
        setState(() => _avatarBase64 = b64);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật ảnh đại diện thành công!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi tải ảnh: $e')));
      }
    }
  }

  Future<void> _openEditProfileDialog() async {
    final u = c.user;
    if (u == null) return;

    final nameCtrl = TextEditingController(text: u.name);
    final usernameCtrl = TextEditingController(text: u.username);
    final passwordCtrl = TextEditingController();
    bool obscurePass = true;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.badge_rounded, color: Color(0xFF087F8C)),
                SizedBox(width: 8),
                Text(
                  'Chỉnh sửa hồ sơ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên đăng nhập *',
                      prefixIcon: Icon(Icons.account_circle_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscurePass,
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu mới (tuỳ chọn)',
                      helperText: 'Để trống nếu không muốn đổi mật khẩu',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePass ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscurePass = !obscurePass),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Huỷ'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF087F8C),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final newName = nameCtrl.text.trim();
                  final newUsername = usernameCtrl.text.trim();
                  final newPass = passwordCtrl.text.trim();

                  if (newName.isEmpty || newUsername.isEmpty) {
                    setDialogState(
                      () => error =
                          'Họ tên và tên đăng nhập không được để trống.',
                    );
                    return;
                  }

                  try {
                    Navigator.pop(ctx);
                    await c.updateProfile(
                      name: newName,
                      username: newUsername,
                      password: newPass.isEmpty ? null : newPass,
                    );
                    if (mounted) {
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Cập nhật hồ sơ thành công!'),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Lỗi cập nhật: $e')),
                      );
                    }
                  }
                },
                child: const Text('Lưu thay đổi'),
              ),
            ],
          );
        },
      ),
    );
  }

  AppController get c => widget.controller;
  List<Attendance> get records =>
      c.data.attendance
          .where((a) => c.isStaff || a.employeeId == c.user!.id)
          .toList()
        ..sort((a, b) => b.checkIn.compareTo(a.checkIn));
  String employeeName(String id) =>
      c.data.employees.where((e) => e.id == id).firstOrNull?.name ??
      'Nhân viên đã xóa';
  Future<void> perform(
    Future<void> Function() work, [
    String success = 'Đã lưu thay đổi.',
  ]) async {
    if (performing) return;
    setState(() => performing = true);
    try {
      await work();
      if (mounted) message(context, success);
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => performing = false);
    }
  }

  Future<void> _showCurrentLocation() async {
    if (locating) return;
    setState(() => locating = true);
    try {
      final p = await acquirePosition();
      String? address;
      try {
        final entries = await geo.Geocoding()
            .placemarkFromCoordinates(p.latitude, p.longitude)
            .timeout(const Duration(seconds: 8));
        if (entries.isNotEmpty) {
          final pm = entries.first;
          address =
              [
                    pm.street,
                    pm.subLocality,
                    pm.locality,
                    pm.subAdministrativeArea,
                    pm.administrativeArea,
                    pm.country,
                  ]
                  .whereType<String>()
                  .where((v) => v.trim().isNotEmpty)
                  .toSet()
                  .join(', ');
        }
      } catch (_) {
        /* Coordinates remain available when address lookup fails. */
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Vị trí của bạn'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  address == null || address.isEmpty
                      ? 'Chưa tra được địa chỉ; tọa độ GPS vẫn dùng được.'
                      : address,
                ),
                const SizedBox(height: 16),
                SelectableText(
                  '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}\nSai số ±${p.accuracy.round()} m',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(
                      'https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}',
                    );
                    try {
                      if (!await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          ) &&
                          ctx.mounted) {
                        message(
                          ctx,
                          'Không mở được bản đồ. Hãy sao chép tọa độ.',
                        );
                      }
                    } catch (_) {
                      if (ctx.mounted) message(ctx, 'Không mở được bản đồ.');
                    }
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Xem Google Maps'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: '${p.latitude}, ${p.longitude}'),
                    );
                    if (ctx.mounted) message(ctx, 'Đã sao chép tọa độ.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Sao chép tọa độ'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) message(context, e);
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = c.data.requests
        .where((r) => r.status == 'pending' && (c.isStaff || r.employeeId == c.user?.id))
        .length;

    final isEmployee = !c.isStaff;

    final labels = isEmployee
        ? ['Chấm công', 'Bảng công', 'Đơn từ', 'Tài khoản']
        : [
            'Tổng quan',
            'Nhân sự',
            'Bảng công',
            'Thống kê',
            'Đơn từ',
            'Tài khoản',
          ];

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = isEmployee
        ? switch (page) {
            0 => PunchPage(controller: c),
            1 => _buildEmployeeTimesheetView(),
            2 => requests(),
            _ => profile(),
          }
        : switch (page) {
            0 => dashboard(),
            1 => management(),
            2 => history(),
            3 => StatsPage(controller: c),
            4 => requests(),
            _ => profile(),
          };

    final currentTitle = labels[page < labels.length ? page : 0];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentTitle,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            Text(
              c.lastSyncedAt == null
                  ? 'Chấm công thông minh • Nhóm 09'
                  : 'Cập nhật ${clock(c.lastSyncedAt)} • Kéo để làm mới',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Làm mới dữ liệu',
            icon: c.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF0F7C8A),
                    ),
                  )
                : const Icon(Icons.refresh_rounded, size: 22),
            onPressed: c.isSyncing ? null : () => c.syncAll(),
          ),
          Container(
            margin: const EdgeInsets.only(right: 16, left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: c.isAdmin
                  ? const Color(0xFF0F7C8A).withValues(alpha: 0.1)
                  : c.user?.role == 'manager'
                  ? Colors.deepPurple.withValues(alpha: 0.1)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: c.isAdmin
                    ? const Color(0xFF0F7C8A).withValues(alpha: 0.3)
                    : c.user?.role == 'manager'
                    ? Colors.deepPurple.withValues(alpha: 0.3)
                    : const Color(0xFFCBD5E1),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  c.isAdmin
                      ? Icons.shield_rounded
                      : c.user?.role == 'manager'
                      ? Icons.supervisor_account_rounded
                      : Icons.badge_rounded,
                  size: 13,
                  color: c.isAdmin
                      ? const Color(0xFF0F7C8A)
                      : c.user?.role == 'manager'
                      ? Colors.deepPurple
                      : const Color(0xFF475569),
                ),
                const SizedBox(width: 4),
                Text(
                  c.isAdmin
                      ? 'Admin'
                      : c.user?.role == 'manager'
                      ? 'Quản lý'
                      : 'Nhân viên',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.isAdmin
                        ? const Color(0xFF0F7C8A)
                        : c.user?.role == 'manager'
                        ? Colors.deepPurple
                        : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (performing || c.isSyncing)
            const LinearProgressIndicator(
              minHeight: 2.5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F7C8A)),
            ),
          if (c.syncError != null)
            Material(
              color: const Color(0xFFFFF7ED),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 16, color: Color(0xFFEA580C)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.syncError!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
                      ),
                    ),
                    InkWell(
                      onTap: c.isSyncing ? null : () => c.syncAll(),
                      child: const Text(
                        'Thử lại',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F7C8A)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: isEmployee
                        ? page.clamp(0, 3)
                        : switch (page) {
                            0 => 0,
                            1 => 1,
                            2 => 2,
                            4 => 3,
                            _ => 4,
                          },
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (v) => setState(() {
                      search = '';
                      page = isEmployee
                          ? v.clamp(0, 3)
                          : switch (v) {
                              0 => 0,
                              1 => 1,
                              2 => 2,
                              3 => 4,
                              _ => 5,
                            };
                    }),
                    destinations: isEmployee
                        ? [
                            const NavigationRailDestination(
                              icon: Icon(Icons.timer_outlined),
                              selectedIcon: Icon(Icons.timer_rounded),
                              label: Text('Chấm công'),
                            ),
                            const NavigationRailDestination(
                              icon: Icon(Icons.calendar_month_outlined),
                              selectedIcon: Icon(Icons.calendar_month_rounded),
                              label: Text('Bảng công'),
                            ),
                            NavigationRailDestination(
                              icon: Badge(
                                isLabelVisible: pendingCount > 0,
                                label: Text('$pendingCount'),
                                child: const Icon(Icons.assignment_outlined),
                              ),
                              selectedIcon: Badge(
                                isLabelVisible: pendingCount > 0,
                                label: Text('$pendingCount'),
                                child: const Icon(Icons.assignment_turned_in_rounded),
                              ),
                              label: const Text('Đơn từ'),
                            ),
                            const NavigationRailDestination(
                              icon: Icon(Icons.person_outline_rounded),
                              selectedIcon: Icon(Icons.person_rounded),
                              label: Text('Tài khoản'),
                            ),
                          ]
                        : [
                            const NavigationRailDestination(
                              icon: Icon(Icons.space_dashboard_outlined),
                              selectedIcon: Icon(Icons.space_dashboard_rounded),
                              label: Text('Tổng quan'),
                            ),
                            NavigationRailDestination(
                              icon: Icon(c.isStaff ? Icons.people_outline_rounded : Icons.fingerprint_rounded),
                              selectedIcon: Icon(c.isStaff ? Icons.people_rounded : Icons.fingerprint_rounded),
                              label: Text(c.isStaff ? 'Nhân sự' : 'Chấm công'),
                            ),
                            const NavigationRailDestination(
                              icon: Icon(Icons.calendar_month_outlined),
                              selectedIcon: Icon(Icons.calendar_month_rounded),
                              label: Text('Bảng công'),
                            ),
                            NavigationRailDestination(
                              icon: Badge(
                                isLabelVisible: pendingCount > 0,
                                label: Text('$pendingCount'),
                                child: const Icon(Icons.assignment_outlined),
                              ),
                              selectedIcon: Badge(
                                isLabelVisible: pendingCount > 0,
                                label: Text('$pendingCount'),
                                child: const Icon(Icons.assignment_turned_in_rounded),
                              ),
                              label: const Text('Đơn từ'),
                            ),
                            const NavigationRailDestination(
                              icon: Icon(Icons.person_outline_rounded),
                              selectedIcon: Icon(Icons.person_rounded),
                              label: Text('Tài khoản'),
                            ),
                          ],
                  ),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: content,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : isEmployee
              ? NavigationBar(
                  selectedIndex: page.clamp(0, 3),
                  onDestinationSelected: (v) {
                    setState(() {
                      search = '';
                      page = v.clamp(0, 3);
                    });
                  },
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.timer_outlined),
                      selectedIcon: Icon(Icons.timer_rounded),
                      label: 'Chấm công',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month_rounded),
                      label: 'Bảng công',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: pendingCount > 0,
                        label: Text('$pendingCount'),
                        child: const Icon(Icons.assignment_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: pendingCount > 0,
                        label: Text('$pendingCount'),
                        child: const Icon(Icons.assignment_turned_in_rounded),
                      ),
                      label: 'Đơn từ',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.person_outline_rounded),
                      selectedIcon: Icon(Icons.person_rounded),
                      label: 'Tài khoản',
                    ),
                  ],
                )
              : NavigationBar(
                  selectedIndex: switch (page) {
                    0 => 0,
                    1 => 1,
                    2 => 2,
                    4 => 3,
                    5 => 4, // Khi đang ở trang Tài khoản
                    _ => 0,
                  },
                  onDestinationSelected: (v) {
                    if (v == 4) {
                      _showUtilitiesSheet();
                      return;
                    }
                    setState(() {
                      search = '';
                      page = switch (v) {
                        0 => 0,
                        1 => 1,
                        2 => 2,
                        3 => 4,
                        _ => 0,
                      };
                    });
                  },
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(Icons.space_dashboard_outlined),
                      selectedIcon: Icon(Icons.space_dashboard_rounded),
                      label: 'Tổng quan',
                    ),
                    NavigationDestination(
                      icon: Icon(c.isStaff ? Icons.people_outline_rounded : Icons.fingerprint_rounded),
                      selectedIcon: Icon(c.isStaff ? Icons.people_rounded : Icons.fingerprint_rounded),
                      label: c.isStaff ? 'Nhân sự' : 'Chấm công',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      selectedIcon: Icon(Icons.calendar_month_rounded),
                      label: 'Bảng công',
                    ),
                    NavigationDestination(
                      icon: Badge(
                        isLabelVisible: pendingCount > 0,
                        label: Text('$pendingCount'),
                        child: const Icon(Icons.assignment_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: pendingCount > 0,
                        label: Text('$pendingCount'),
                        child: const Icon(Icons.assignment_turned_in_rounded),
                      ),
                      label: 'Đơn từ',
                    ),
                    const NavigationDestination(
                      icon: Icon(Icons.widgets_outlined),
                      selectedIcon: Icon(Icons.widgets_rounded),
                      label: 'Tiện ích',
                    ),
                  ],
                ),
    );
  }

  // Bảng mở rộng Tiện ích nhanh theo yêu cầu
  void _showUtilitiesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Tiện ích & Tính năng mở rộng',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Truy cập nhanh các công cụ và cài đặt tài khoản',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              _utilityItem(
                title: 'Hồ sơ tài khoản & Bảo mật',
                subtitle: 'Thông tin cá nhân, khuôn mặt & sinh trắc học',
                icon: Icons.person_rounded,
                color: const Color(0xFF0F7C8A),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => page = 5);
                },
              ),
              const SizedBox(height: 10),
              _utilityItem(
                title: 'Báo cáo thống kê & Chuyên cần',
                subtitle: 'Xem biểu đồ giờ công, tỷ lệ đúng giờ và phân tích',
                icon: Icons.bar_chart_rounded,
                color: const Color(0xFF7C3AED),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => page = 3);
                },
              ),
              const SizedBox(height: 10),
              _utilityItem(
                title: 'Bản đồ chấm công theo ngày',
                subtitle: 'Xem toàn cảnh vị trí chấm công và bán kính văn phòng',
                icon: Icons.map_rounded,
                color: const Color(0xFF0284C7),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceMapScreen(controller: c),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _utilityItem(
                title: 'Xác định vị trí GPS hiện tại',
                subtitle: 'Kiểm tra tọa độ và địa chỉ GPS nơi bạn đang đứng',
                icon: Icons.my_location_rounded,
                color: const Color(0xFF059669),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCurrentLocation();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _utilityItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Chào buổi sáng ☀️';
    if (h < 18) return 'Chào buổi chiều 🌤️';
    return 'Chào buổi tối 🌙';
  }

  Widget _quickActionItem({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageHint(String title, String description, IconData icon) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B1F3A).withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F7C8A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF0F7C8A), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: Color(0xFF0B1F3A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget list(List<Widget> children) => RefreshIndicator(
    onRefresh: c.syncAll,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: children,
    ),
  );

  Widget dashboard() {
    final today = records
        .where(
          (a) =>
              dayKey(a.checkIn.toUtc().add(const Duration(hours: 7))) ==
              dayKey(DateTime.now().toUtc().add(const Duration(hours: 7))),
        )
        .toList();
    final pending = c.data.requests
        .where(
          (r) =>
              r.status == 'pending' &&
              (c.isStaff || r.employeeId == c.user!.id),
        )
        .length;
    final month = records
        .where(
          (a) =>
              a.checkIn.year == DateTime.now().year &&
              a.checkIn.month == DateTime.now().month,
        )
        .toList();

    // Ca làm hôm nay của nhân viên hiện tại
    final myShift = c.data.shifts
        .where((s) => s.id == c.user!.shiftId)
        .firstOrNull;
    final myTodayRecord = today
        .where((a) => a.employeeId == c.user!.id)
        .firstOrNull;

    return list([
      // Banner Chào Mừng Hiện Đại
      Container(
        padding: const EdgeInsets.all(22),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF075B68), Color(0xFF087F8C), Color(0xFF0E7490)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF087F8C).withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  backgroundImage: _avatarBase64 != null
                      ? MemoryImage(base64Decode(_avatarBase64!))
                      : null,
                  child: _avatarBase64 == null
                      ? Text(
                          c.user!.name.isNotEmpty
                              ? c.user!.name[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        c.user!.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.isAdmin
                        ? Colors.amber.withValues(alpha: 0.25)
                        : c.user?.role == 'manager'
                        ? Colors.deepPurple.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: c.isAdmin
                          ? Colors.amber
                          : c.user?.role == 'manager'
                          ? Colors.deepPurple.shade200
                          : Colors.white54,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        c.isAdmin
                            ? Icons.shield_rounded
                            : c.user?.role == 'manager'
                            ? Icons.supervisor_account_rounded
                            : Icons.badge_rounded,
                        size: 14,
                        color: c.isAdmin
                            ? Colors.amber
                            : c.user?.role == 'manager'
                            ? Colors.deepPurple.shade100
                            : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        c.isAdmin
                            ? 'ADMIN'
                            : c.user?.role == 'manager'
                            ? 'QUẢN LÝ'
                            : 'NHÂN VIÊN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: c.isAdmin
                              ? Colors.amber
                              : c.user?.role == 'manager'
                              ? Colors.deepPurple.shade100
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              c.isAdmin
                  ? 'Bảng điều khiển quản trị: Theo dõi nhân sự, phân quyền, ca làm và duyệt đơn.'
                  : c.isManager
                  ? 'Bảng điều khiển quản lý: Theo dõi nhân sự, bảng công, thống kê và duyệt đơn.'
                  : 'Ghi nhận thời gian và vị trí điểm danh chuẩn xác bằng GPS & mã QR động.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => page = 1),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF075B68),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: Icon(
                c.isStaff ? Icons.tune_rounded : Icons.fingerprint_rounded,
              ),
              label: Text(
                c.isAdmin
                    ? 'Quản lý nhân sự & ca làm'
                    : c.isManager
                    ? 'Xem nhân sự & ca làm'
                    : 'Chấm công ngay (GPS / QR)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),

      // Lối tắt tác vụ nhanh (Quick Actions) dạng lưới 2x2 trực quan
      Container(
        margin: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 10),
              child: Text(
                'Thao tác nhanh',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B1F3A),
                ),
              ),
            ),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.3,
              children: c.isAdmin
                  ? [
                      _quickActionItem(
                        label: 'Thêm nhân viên',
                        icon: Icons.person_add_alt_1_rounded,
                        color: const Color(0xFF0284C7),
                        onTap: () => editEmployee(),
                      ),
                      _quickActionItem(
                        label: 'Tạo ca làm',
                        icon: Icons.more_time_rounded,
                        color: const Color(0xFF0D9488),
                        onTap: () => editShift(),
                      ),
                      _quickActionItem(
                        label: 'Duyệt đơn ($pending)',
                        icon: Icons.fact_check_outlined,
                        color: pending > 0
                            ? const Color(0xFFEA580C)
                            : const Color(0xFF64748B),
                        onTap: () => setState(() => page = 4),
                      ),
                      _quickActionItem(
                        label: 'Bản đồ chấm công',
                        icon: Icons.map_rounded,
                        color: const Color(0xFF7C3AED),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceMapScreen(controller: c),
                          ),
                        ),
                      ),
                    ]
                  : c.isManager
                  ? [
                      _quickActionItem(
                        label: 'Duyệt đơn ($pending)',
                        icon: Icons.fact_check_outlined,
                        color: pending > 0
                            ? const Color(0xFFEA580C)
                            : const Color(0xFF64748B),
                        onTap: () => setState(() => page = 4),
                      ),
                      _quickActionItem(
                        label: 'Bảng công',
                        icon: Icons.calendar_month_rounded,
                        color: const Color(0xFF0284C7),
                        onTap: () => setState(() => page = 2),
                      ),
                      _quickActionItem(
                        label: 'Bản đồ chấm công',
                        icon: Icons.map_rounded,
                        color: const Color(0xFF7C3AED),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AttendanceMapScreen(controller: c),
                          ),
                        ),
                      ),
                      _quickActionItem(
                        label: 'Báo cáo thống kê',
                        icon: Icons.bar_chart_rounded,
                        color: const Color(0xFF0D9488),
                        onTap: () => setState(() => page = 3),
                      ),
                    ]
                  : [
                      _quickActionItem(
                        label: 'Điểm danh ngay',
                        icon: Icons.fingerprint_rounded,
                        color: const Color(0xFF087F8C),
                        onTap: () => setState(() => page = 1),
                      ),
                      _quickActionItem(
                        label: 'Gửi đơn từ',
                        icon: Icons.post_add_rounded,
                        color: const Color(0xFFEA580C),
                        onTap: () => setState(() => page = 4),
                      ),
                      _quickActionItem(
                        label: 'Bảng công tháng',
                        icon: Icons.calendar_month_rounded,
                        color: const Color(0xFF0284C7),
                        onTap: () => setState(() => page = 2),
                      ),
                      _quickActionItem(
                        label: 'Thống kê công',
                        icon: Icons.bar_chart_rounded,
                        color: const Color(0xFF7C3AED),
                        onTap: () => setState(() => page = 3),
                      ),
                    ],
            ),
          ],
        ),
      ),

      // Thẻ Thống Kê Chỉ Số Đẹp Mắt
      LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            metric(
              c.isStaff ? 'Có mặt hôm nay' : 'Ca tháng này',
              c.isStaff
                  ? '${today.map((e) => e.employeeId).toSet().length} / ${c.data.employees.where((e) => !e.isStaff && e.active).length}'
                  : '${month.length}',
              Icons.verified_outlined,
              const Color(0xFF10B981),
              box.maxWidth,
              onTap: () => setState(() => page = 2),
            ),
            metric(
              c.isStaff ? 'Đi trễ hôm nay' : 'Giờ hoàn tất / tháng',
              c.isStaff
                  ? '${today.where((e) => e.lateMinutes > 0).length}'
                  : month.fold<double>(0, (sum, a) => sum + a.hours).toStringAsFixed(1),
              Icons.access_time_rounded,
              const Color(0xFFEA580C),
              box.maxWidth,
              onTap: () => setState(() => page = 2),
            ),
            metric(
              c.isStaff ? 'Chưa check-out' : 'Số lần đi trễ',
              c.isStaff
                  ? '${today.where((e) => e.checkOut == null).length}'
                  : '${month.where((a) => a.lateMinutes > 0).length}',
              Icons.timer_outlined,
              const Color(0xFF0284C7),
              box.maxWidth,
              onTap: () => setState(() => page = 2),
            ),
            metric(
              c.isStaff ? 'Đơn chờ duyệt' : 'Đơn từ của tôi',
              c.isStaff
                  ? '$pending'
                  : '${c.data.requests.where((r) => r.employeeId == c.user?.id).length}',
              Icons.pending_actions_rounded,
              pending > 0 ? const Color(0xFFEA580C) : const Color(0xFF64748B),
              box.maxWidth,
              onTap: () => setState(() => page = 4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),

      // Thẻ Ca Làm Của Bạn Hôm Nay (Dành riêng cho nhân viên)
      if (!c.isStaff)
        Section(
          title: 'Ca làm của bạn hôm nay',
          subtitle: dateLabel(DateTime.now()),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF087F8C).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.schedule_rounded,
                    color: Color(0xFF087F8C),
                    size: 28,
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
                              myShift?.name ?? 'Chưa bình chọn ca',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => registerMyShiftDialog(),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.how_to_vote_outlined,
                                    size: 13,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    myShift == null ? 'Bình chọn' : 'Đổi ca',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        myShift != null
                            ? '${minuteText(myShift.startMinute)} – ${minuteText(myShift.endMinute)} (Cho phép trễ ${myShift.grace}p)'
                            : 'Bấm "Bình chọn" để chọn ca làm mong muốn',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: myTodayRecord == null
                        ? Colors.amber.shade50
                        : myTodayRecord.checkOut == null
                        ? Colors.blue.shade50
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: myTodayRecord == null
                          ? Colors.amber.shade300
                          : myTodayRecord.checkOut == null
                          ? Colors.blue.shade300
                          : Colors.green.shade300,
                    ),
                  ),
                  child: Text(
                    myTodayRecord == null
                        ? 'Chưa vào ca'
                        : myTodayRecord.checkOut == null
                        ? 'Đang làm'
                        : 'Đã hoàn tất',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: myTodayRecord == null
                          ? Colors.amber.shade900
                          : myTodayRecord.checkOut == null
                          ? Colors.blue.shade900
                          : Colors.green.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

      if (c.isAdmin &&
          (!c.data.office.configured ||
              c.data.shifts.isEmpty ||
              c.data.employees.length < 2))
        Section(
          title: 'Thiết lập để bắt đầu',
          subtitle: 'Dữ liệu thật do nhóm tự nhập',
          child: Column(
            children: [
              setupLine(
                'Cấu hình tọa độ văn phòng & QR',
                c.data.office.configured,
              ),
              setupLine('Tạo ca làm', c.data.shifts.isNotEmpty),
              setupLine(
                'Thêm nhân viên và phân ca',
                c.data.employees.any((e) => !e.isAdmin && e.shiftId != null),
              ),
            ],
          ),
        ),
      Section(
        title: 'Trợ lý giải thích chấm công',
        subtitle: 'Quy tắc minh bạch • Không tự sửa giờ công',
        child: () {
          final explainRecords = (c.isStaff
                  ? records
                  : records.where((a) => a.employeeId == c.user?.id).toList())
              .take(4)
              .toList();
          if (explainRecords.isEmpty) {
            return const EmptyState('Chưa có dữ liệu chấm công để phân tích.');
          }
          return Column(
            children: explainRecords
                .map(
                  (a) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      a.lateMinutes > 0 ||
                              (a.checkOut == null &&
                                  DateTime.now().isAfter(a.scheduledEnd))
                          ? Icons.info_outline
                          : Icons.check_circle_outline,
                      color: const Color(0xFF087F8C),
                    ),
                    title: Text(
                      '${c.isStaff ? '${employeeName(a.employeeId)} • ' : ''}${dateLabel(a.checkIn)}',
                    ),
                    subtitle: Text(a.explanation),
                  ),
                )
                .toList(),
          );
        }(),
      ),
      Section(
        title: 'Hoạt động gần đây',
        child: records.isEmpty
            ? const EmptyState(
                'Bảng công sẽ xuất hiện sau lần chấm công đầu tiên.',
              )
            : Column(children: records.take(5).map(attendanceTile).toList()),
      ),
    ]);
  }

  Widget setupLine(String title, bool done) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      done ? Icons.check_circle : Icons.radio_button_unchecked,
      color: done ? Colors.teal : Colors.blueGrey,
    ),
    title: Text(title),
  );

  Widget metric(
    String title,
    String value,
    IconData icon,
    Color color,
    double width, {
    VoidCallback? onTap,
  }) => SizedBox(
    width: width >= 700 ? (width - 36) / 4 : (width - 12) / 2,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  if (onTap != null)
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 13,
                      color: Colors.grey.shade400,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget attendanceTile(Attendance a) {
    final isLate = a.lateMinutes > 0;
    final isMissingCheckout = a.checkOut == null && DateTime.now().isAfter(a.scheduledEnd);
    final inShift = a.checkOut == null && !isMissingCheckout;
    final empName = employeeName(a.employeeId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1F3A).withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          AttendanceDetailSheet.show(
            context,
            attendance: a,
            employeeName: empName,
            office: c.data.office,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isLate
                    ? const Color(0xFFFFF7ED)
                    : isMissingCheckout
                    ? const Color(0xFFFEF2F2)
                    : inShift
                    ? const Color(0xFFEFF6FF)
                    : const Color(0xFFECFDF5),
                child: Text(
                  empName.isNotEmpty ? empName[0].toUpperCase() : 'A',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isLate
                        ? const Color(0xFFEA580C)
                        : isMissingCheckout
                        ? const Color(0xFFDC2626)
                        : inShift
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF059669),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.isStaff ? empName : a.shiftName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: Color(0xFF0B1F3A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          a.checkOut == null
                              ? (isMissingCheckout ? 'Thiếu giờ ra' : 'Đang làm')
                              : '${a.hours.toStringAsFixed(1)} h',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: isMissingCheckout
                                ? const Color(0xFFDC2626)
                                : inShift
                                ? const Color(0xFF2563EB)
                                : const Color(0xFF0F7C8A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dateLabel(a.checkIn)} • ${clock(a.checkIn)} → ${clock(a.checkOut)}${c.isStaff ? ' • ${a.shiftName}' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isLate
                                ? const Color(0xFFFFF7ED)
                                : isMissingCheckout
                                ? const Color(0xFFFEF2F2)
                                : inShift
                                ? const Color(0xFFEFF6FF)
                                : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isLate
                                  ? const Color(0xFFFDBA74)
                                  : isMissingCheckout
                                  ? const Color(0xFFFCA5A5)
                                  : inShift
                                  ? const Color(0xFF93C5FD)
                                  : const Color(0xFF6EE7B7),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isLate
                                    ? Icons.warning_amber_rounded
                                    : isMissingCheckout
                                    ? Icons.error_outline_rounded
                                    : inShift
                                    ? Icons.timelapse_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 12,
                                color: isLate
                                    ? const Color(0xFFEA580C)
                                    : isMissingCheckout
                                    ? const Color(0xFFDC2626)
                                    : inShift
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF059669),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isLate
                                    ? 'Đi trễ ${a.lateMinutes}p'
                                    : isMissingCheckout
                                    ? 'Chưa check-out'
                                    : inShift
                                    ? 'Đang trong ca'
                                    : 'Đúng giờ',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isLate
                                      ? const Color(0xFFEA580C)
                                      : isMissingCheckout
                                      ? const Color(0xFFDC2626)
                                      : inShift
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFF94A3B8)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget management() {
    final employees = c.data.employees.where((e) {
      final matchesSearch = '${e.name} ${e.username} ${e.department}'
          .toLowerCase()
          .contains(search.toLowerCase());
      if (!matchesSearch) return false;

      if (roleFilter == 'admin' && !e.isAdmin) return false;
      if (roleFilter == 'manager' && !e.isManager) return false;
      if (roleFilter == 'employee' && (e.isAdmin || e.isManager)) return false;
      if (roleFilter == 'locked' && e.active) return false;

      if (deptFilter != null &&
          e.department.toLowerCase() != deptFilter!.toLowerCase()) {
        return false;
      }

      return true;
    }).toList();

    return list([
      _pageHint(
        'Quản lý nơi làm việc',
        'Thiết lập văn phòng → tạo ca → phân ca cho nhân viên. Tài khoản có lịch sử nên được khóa thay vì xóa.',
        Icons.manage_accounts_outlined,
      ),
      if (c.isAdmin)
        Section(
          icon: Icons.business_rounded,
          iconColor: const Color(0xFF0F7C8A),
          title: 'Văn phòng & Vị trí GPS',
          subtitle: c.data.office.configured
              ? '${c.data.office.name} • Bán kính ${c.data.office.radius.round()} m • Tọa độ: ${c.data.office.latitude?.toStringAsFixed(4)}, ${c.data.office.longitude?.toStringAsFixed(4)}'
              : 'Chưa cấu hình. Bấm "Lấy GPS vị trí hiện tại" ngay tại công ty.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => editOffice(),
                    icon: const Icon(Icons.edit_location_alt_outlined),
                    label: const Text('Cấu hình văn phòng'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F7C8A),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final position = await acquirePosition();
                        if (mounted) await editOffice(position);
                      } catch (e) {
                        if (mounted) message(context, e);
                      }
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('Lấy GPS vị trí hiện tại'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceMapScreen(controller: c),
                      ),
                    ),
                    icon: const Icon(Icons.map_rounded),
                    label: const Text('Bản đồ chấm công'),
                  ),
                  if (AppConfig.requireQr)
                    OutlinedButton.icon(
                      onPressed: showOfficeQr,
                      icon: const Icon(Icons.qr_code_2_rounded),
                      label: const Text('Hiển thị QR động'),
                    ),
                ],
              ),
            ],
          ),
        ),
      Section(
        icon: Icons.people_alt_rounded,
        iconColor: const Color(0xFF0D9488),
        title: 'Nhân sự & Người dùng',
        subtitle: c.isAdmin
            ? '${c.data.employees.length} tài khoản trên hệ thống'
            : '${c.data.employees.length} tài khoản • Quản lý chỉ được xem',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: _staffExpanded ? 'Thu gọn danh sách' : 'Mở rộng toàn bộ danh sách',
              onPressed: () => setState(() => _staffExpanded = !_staffExpanded),
              icon: Icon(
                _staffExpanded
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
                color: const Color(0xFF087F8C),
              ),
            ),
            IconButton(
              tooltip: 'Xem bảng quyền hạn các vai trò',
              onPressed: showRolePermissionsInfo,
              icon: const Icon(Icons.help_outline, color: Color(0xFF087F8C)),
            ),
            if (c.isAdmin)
              IconButton(
                tooltip: 'Thêm nhân viên mới',
                onPressed: () => editEmployee(),
                icon: const Icon(Icons.person_add_alt),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ô TÌM KIẾM
            TextField(
              decoration: InputDecoration(
                hintText: 'Tìm tên, tài khoản, phòng ban...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => search = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),

            // BỘ LỌC VAI TRÒ VÀ BỘ ĐẾM SỐ LƯỢNG
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterRoleChip('Tất cả', 'all', c.data.employees.length),
                  const SizedBox(width: 8),
                  _filterRoleChip(
                    'Admin',
                    'admin',
                    c.data.employees.where((e) => e.isAdmin).length,
                    activeColor: Colors.deepPurple,
                  ),
                  const SizedBox(width: 8),
                  _filterRoleChip(
                    'Quản lý',
                    'manager',
                    c.data.employees.where((e) => e.isManager).length,
                    activeColor: Colors.cyan.shade800,
                  ),
                  const SizedBox(width: 8),
                  _filterRoleChip(
                    'Nhân viên',
                    'employee',
                    c.data.employees
                        .where((e) => !e.isAdmin && !e.isManager)
                        .length,
                    activeColor: Colors.teal.shade800,
                  ),
                  if (c.data.employees.any((e) => !e.active)) ...[
                    const SizedBox(width: 8),
                    _filterRoleChip(
                      'Đã khóa',
                      'locked',
                      c.data.employees.where((e) => !e.active).length,
                      activeColor: Colors.red.shade700,
                    ),
                  ],
                ],
              ),
            ),

            // BỘ LỌC THEO PHÒNG BAN (NẾU CÓ)
            if (c.data.departments.isNotEmpty) ...[
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Text(
                      'Phòng ban:',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text(
                        'Tất cả',
                        style: TextStyle(fontSize: 11),
                      ),
                      selected: deptFilter == null,
                      onSelected: (_) => setState(() => deptFilter = null),
                    ),
                    for (final d in c.data.departments) ...[
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text(
                          d.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected:
                            deptFilter?.toLowerCase() == d.name.toLowerCase(),
                        onSelected: (sel) =>
                            setState(() => deptFilter = sel ? d.name : null),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (employees.isEmpty)
              const EmptyState('Không có nhân viên phù hợp bộ lọc.'),
            AnimatedSize(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                children: [
                  for (final e in (_staffExpanded ||
                          search.isNotEmpty ||
                          roleFilter != 'all' ||
                          deptFilter != null)
                      ? employees
                      : employees.take(5).toList())
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: e.isAdmin
                              ? const Color(0xFFEDE9FE)
                              : e.isManager
                              ? const Color(0xFFCCFBF1)
                              : const Color(0xFFE0F2FE),
                          child: Icon(
                            e.isAdmin
                                ? Icons.shield_outlined
                                : e.isManager
                                ? Icons.supervisor_account_outlined
                                : Icons.person_outline,
                            color: e.isAdmin
                                ? Colors.deepPurple
                                : e.isManager
                                ? Colors.teal
                                : const Color(0xFF0284C7),
                          ),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                e.name,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: e.isAdmin
                                    ? Colors.deepPurple.shade50
                                    : e.isManager
                                    ? Colors.cyan.shade50
                                    : Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: e.isAdmin
                                      ? Colors.deepPurple.shade200
                                      : e.isManager
                                      ? Colors.cyan.shade200
                                      : Colors.teal.shade200,
                                ),
                              ),
                              child: Text(
                                e.isAdmin
                                    ? 'ADMIN'
                                    : e.isManager
                                    ? 'QUẢN LÝ'
                                    : 'NHÂN VIÊN',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: e.isAdmin
                                      ? Colors.deepPurple
                                      : e.isManager
                                      ? Colors.cyan.shade800
                                      : Colors.teal.shade800,
                                ),
                              ),
                            ),
                            if (!e.active) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: const Text(
                                  'ĐÃ KHÓA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${e.username} • ${e.department.isEmpty ? 'Chưa có phòng ban' : e.department}',
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.schedule,
                                  size: 13,
                                  color: e.shiftId == null
                                      ? Colors.orange.shade800
                                      : Colors.blue.shade700,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    c.data.shifts
                                            .where((s) => s.id == e.shiftId)
                                            .firstOrNull
                                            ?.name ??
                                        'Chưa chọn / phân ca',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: e.shiftId == null
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: e.shiftId == null
                                          ? Colors.orange.shade800
                                          : Colors.blue.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: !c.isAdmin
                            ? null
                            : PopupMenuButton<String>(
                                position: PopupMenuPosition.under,
                                elevation: 8,
                                shadowColor: const Color(0x22000000),
                                color: Colors.white,
                                surfaceTintColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 200,
                                  maxWidth: 260,
                                ),
                                icon: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.more_vert_rounded,
                                    size: 18,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                onSelected: (v) async {
                                  if (v == 'edit') {
                                    editEmployee(e);
                                  } else if (v == 'role') {
                                    changeRole(e);
                                  } else if (v == 'shift') {
                                    assignShift(e);
                                  } else if (v == 'toggle_lock') {
                                    final copy = Employee.fromJson(e.toJson())
                                      ..active = !e.active;
                                    await perform(
                                      () => c.saveEmployee(copy),
                                      e.active
                                          ? 'Đã khóa tài khoản'
                                          : 'Đã mở khóa tài khoản',
                                    );
                                  } else if (v == 'delete') {
                                    final ok = await confirm(
                                      context,
                                      'Xóa tài khoản ${e.name}? Tài khoản đã có lịch sử chỉ có thể khóa.',
                                    );
                                    if (ok && mounted) {
                                      await perform(() => c.deleteEmployee(e.id));
                                    }
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined, size: 18),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Sửa thông tin',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'role',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.admin_panel_settings_outlined,
                                          size: 18,
                                          color: Colors.deepPurple,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Phân quyền vai trò',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'shift',
                                    child: Row(
                                      children: [
                                        Icon(Icons.access_time_rounded, size: 18),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Phân ca làm việc',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle_lock',
                                    child: Row(
                                      children: [
                                        Icon(
                                          e.active
                                              ? Icons.lock_outline_rounded
                                              : Icons.lock_open_rounded,
                                          size: 18,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            e.active
                                                ? 'Khóa tài khoản'
                                                : 'Mở khóa tài khoản',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Xóa tài khoản',
                                            style: TextStyle(color: Colors.red),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                ],
              ),
            ),
            if (!_staffExpanded &&
                employees.length > 5 &&
                search.isEmpty &&
                roleFilter == 'all' &&
                deptFilter == null)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _staffExpanded = true),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    'Xem toàn bộ ${employees.length} nhân sự (còn ${employees.length - 5} người)',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F7C8A),
                    side: const BorderSide(color: Color(0xFF0F7C8A)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              )
            else if (_staffExpanded && employees.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: TextButton.icon(
                  onPressed: () => setState(() => _staffExpanded = false),
                  icon: const Icon(Icons.expand_less_rounded),
                  label: const Text('Thu gọn danh sách nhân sự'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF64748B),
                  ),
                ),
              ),
          ],
        ),
      ),
      Section(
        icon: Icons.schedule_rounded,
        iconColor: const Color(0xFF0284C7),
        title: 'Ca làm việc',
        subtitle: 'Chạm vào ca để xem danh sách nhân sự đang phân ca',
        action: c.isAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.data.employees.any((e) => e.shiftId == null) &&
                      c.data.shifts.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => bulkAssignShiftDialog(),
                      icon: const Icon(Icons.flash_on, size: 16),
                      label: Text(
                        'Sắp ca nhanh (${c.data.employees.where((e) => e.shiftId == null).length})',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Thêm ca',
                    onPressed: () => editShift(),
                    icon: const Icon(Icons.add),
                  ),
                ],
              )
            : null,
        child: c.data.shifts.isEmpty
            ? const EmptyState('Chưa có ca làm nào.')
            : Column(
                children: c.data.shifts.map((s) {
                  final assignedEmps = c.data.employees
                      .where((e) => e.shiftId == s.id)
                      .toList();
                  final count = assignedEmps.length;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => showShiftDetails(s, assignedEmps),
                    leading: CircleAvatar(
                      backgroundColor: count > 0
                          ? const Color(0xFFE0F2FE)
                          : const Color(0xFFF1F5F9),
                      child: Icon(
                        Icons.schedule,
                        color: count > 0
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            s.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: count > 0
                                ? const Color(0xFFE0F2FE)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: count > 0
                                  ? const Color(0xFFBAE6FD)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Text(
                            count > 0 ? '$count người làm' : '0 người',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: count > 0
                                  ? const Color(0xFF0369A1)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      '${minuteText(s.startMinute)} – ${minuteText(s.endMinute)} • Cho phép trễ ${s.grace} phút${s.endMinute < s.startMinute ? ' • Qua đêm' : ''}',
                    ),
                    trailing: !c.isAdmin
                        ? null
                        : PopupMenuButton<String>(
                            position: PopupMenuPosition.under,
                            elevation: 8,
                            shadowColor: const Color(0x22000000),
                            color: Colors.white,
                            surfaceTintColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(
                                color: Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 160,
                              maxWidth: 220,
                            ),
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.more_vert_rounded,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            onSelected: (v) async {
                              if (v == 'edit') {
                                editShift(s);
                              } else if (v == 'delete') {
                                if (count == 0) {
                                  if (await confirm(
                                    context,
                                    'Xóa ca ${s.name}?',
                                  )) {
                                    await perform(() => c.deleteShift(s.id));
                                  }
                                } else {
                                  final names = assignedEmps
                                      .map(
                                        (e) =>
                                            '• ${e.name} (${e.department.isEmpty ? "Chưa có phòng ban" : e.department})',
                                      )
                                      .join('\n');
                                  final forceDelete = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      title: Text(
                                        'Ca ${s.name} đang có $count người làm',
                                      ),
                                      content: Text(
                                        'Ca này hiện đang được phân công cho các nhân viên:\n\n'
                                        '$names\n\n'
                                        'Nếu xóa, hệ thống sẽ tự động gỡ phân ca cho $count nhân viên trên.\n\n'
                                        'Bạn có chắc chắn muốn gỡ phân ca và xóa ca này không?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Hủy'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Gỡ & Xóa ca'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (forceDelete == true) {
                                    await perform(
                                      () => c.deleteShift(s.id, force: true),
                                      'Đã gỡ phân ca và xóa ca thành công!',
                                    );
                                  }
                                }
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 10),
                                    Expanded(child: Text('Sửa ca')),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Xóa ca',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  );
                }).toList(),
              ),
      ),
      Section(
        icon: Icons.apartment_rounded,
        iconColor: const Color(0xFF7C3AED),
        title: 'Phòng ban',
        subtitle: '${c.data.departments.length} phòng ban đang hoạt động',
        action: c.isAdmin
            ? IconButton(
                tooltip: 'Thêm phòng ban',
                onPressed: () => editDepartment(),
                icon: const Icon(Icons.add),
              )
            : null,
        child: c.data.departments.isEmpty
            ? const EmptyState('Chưa có phòng ban nào.')
            : Column(
                children: c.data.departments.map((d) {
                  final count = c.data.employees
                      .where(
                        (e) =>
                            e.department.toLowerCase() == d.name.toLowerCase(),
                      )
                      .length;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.business_outlined),
                    title: Text(
                      d.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '$count nhân sự${d.description != null && d.description!.isNotEmpty ? " • ${d.description}" : ""}',
                    ),
                    trailing: !c.isAdmin
                        ? null
                        : PopupMenuButton<String>(
                            position: PopupMenuPosition.under,
                            elevation: 8,
                            shadowColor: const Color(0x22000000),
                            color: Colors.white,
                            surfaceTintColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: const BorderSide(
                                color: Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 160,
                              maxWidth: 220,
                            ),
                            icon: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.more_vert_rounded,
                                size: 18,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            onSelected: (v) async {
                              if (v == 'edit') {
                                editDepartment(d);
                              } else if (await confirm(
                                context,
                                'Xóa phòng ban ${d.name}?',
                              )) {
                                await perform(() => c.deleteDepartment(d.id));
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 10),
                                    Expanded(child: Text('Sửa tên')),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Xóa',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  );
                }).toList(),
              ),
      ),
    ]);
  }

  Future<void> editDepartment([Department? d]) => editForm(
    context,
    title: d == null ? 'Thêm phòng ban mới' : 'Sửa phòng ban',
    fields: {'Tên phòng ban': d?.name ?? '', 'Mô tả': d?.description ?? ''},
    save: (v) {
      final name = v['Tên phòng ban']!.trim();
      if (name.isEmpty) throw ArgumentError('Vui lòng nhập tên phòng ban.');
      return c.saveDepartment(
        Department(
          id: d?.id ?? newId(),
          name: name,
          description: v['Mô tả']?.trim(),
        ),
      );
    },
  );

  Widget _filterRoleChip(
    String label,
    String value,
    int count, {
    Color? activeColor,
  }) {
    final selected = roleFilter == value;
    final color = activeColor ?? const Color(0xFF087F8C);
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: selected
          ? Icon(Icons.check_circle_rounded, size: 16, color: color)
          : null,
      label: Text('$label ($count)'),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? color : const Color(0xFF475569),
      ),
      backgroundColor: const Color(0xFFF1F5F9),
      selectedColor: color.withValues(alpha: 0.15),
      side: BorderSide(
        color: selected ? color : Colors.transparent,
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: (_) => setState(() => roleFilter = value),
    );
  }

  void showRolePermissionsInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF087F8C)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bảng phân quyền vai trò',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _roleInfoTile(
                badge: 'ADMIN',
                color: Colors.deepPurple,
                title: 'Quản trị viên (Toàn quyền)',
                desc:
                    '• Quản trị nhân sự: Thêm, sửa, xóa, phân quyền, khóa tài khoản\n'
                    '• Cấu hình văn phòng: Đặt tọa độ GPS, bán kính, hiển thị QR động\n'
                    '• Quản lý ca làm việc: Tạo ca mới, sửa giờ, xóa ca, phân ca\n'
                    '• Quản lý phòng ban: Thêm, sửa, xóa danh mục phòng ban\n'
                    '• Duyệt đơn từ: Duyệt / từ chối mọi đơn nghỉ phép & giải trình',
              ),
              const Divider(height: 24),
              _roleInfoTile(
                badge: 'QUẢN LÝ',
                color: Colors.cyan.shade800,
                bgColor: Colors.cyan.shade50,
                borderColor: Colors.cyan.shade200,
                title: 'Quản lý / Trưởng phòng (Đội ngũ)',
                desc:
                    '• Xem danh sách nhân sự & ca làm việc (chỉ xem, không xóa/sửa)\n'
                    '• Xem và duyệt / từ chối đơn nghỉ phép, giải trình của nhân viên\n'
                    '• Xem bảng xếp hạng & thống kê thi đua toàn công ty\n'
                    '• Chấm công bằng GPS + QR + Vân tay như nhân viên',
              ),
              const Divider(height: 24),
              _roleInfoTile(
                badge: 'NHÂN VIÊN',
                color: Colors.teal.shade800,
                bgColor: Colors.teal.shade50,
                borderColor: Colors.teal.shade200,
                title: 'Nhân viên (Tiêu chuẩn)',
                desc:
                    '• Chấm công vào / ra bằng GPS + QR văn phòng + Vân tay\n'
                    '• Xem ca làm việc được phân công hôm nay\n'
                    '• Tạo đơn xin nghỉ phép, giải trình đi trễ / quên chấm công\n'
                    '• Xem báo cáo giờ công cá nhân & bảng xếp hạng',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  Widget _roleInfoTile({
    required String badge,
    required Color color,
    Color? bgColor,
    Color? borderColor,
    required String title,
    required String desc,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: bgColor ?? color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: borderColor ?? color.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          desc,
          style: const TextStyle(
            fontSize: 12,
            height: 1.45,
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  String minuteText(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  int parseMinute(String s) {
    final parts = s.split(':');
    if (parts.length != 2) throw ArgumentError('Giờ theo định dạng HH:mm.');
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      throw ArgumentError('Giờ không hợp lệ.');
    }
    return h * 60 + m;
  }

  void showShiftDetails(Shift s, List<Employee> assignedEmps) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.schedule, color: Color(0xFF087F8C)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Khung giờ: ${minuteText(s.startMinute)} – ${minuteText(s.endMinute)}'
                '${s.endMinute < s.startMinute ? ' (Ca qua đêm)' : ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cho phép trễ tối đa: ${s.grace} phút',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(
                    Icons.people_outline,
                    size: 18,
                    color: Color(0xFF087F8C),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Nhân viên đang phân ca (${assignedEmps.length}):',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (assignedEmps.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Chưa có nhân viên nào được phân vào ca này.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                for (final e in assignedEmps)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: e.isAdmin
                              ? Colors.deepPurple.shade50
                              : e.isManager
                              ? Colors.cyan.shade50
                              : const Color(0xFFE0F2FE),
                          child: Icon(
                            e.isAdmin
                                ? Icons.shield_outlined
                                : e.isManager
                                ? Icons.supervisor_account_outlined
                                : Icons.person_outline,
                            size: 14,
                            color: e.isAdmin
                                ? Colors.deepPurple
                                : e.isManager
                                ? Colors.cyan.shade800
                                : const Color(0xFF0284C7),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                '${e.username} • ${e.department.isEmpty ? "Chưa có phòng ban" : e.department}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (c.isAdmin)
                          IconButton(
                            tooltip: 'Gỡ nhân viên khỏi ca này',
                            icon: const Icon(
                              Icons.person_remove_outlined,
                              color: Colors.red,
                              size: 18,
                            ),
                            onPressed: () async {
                              final ok = await confirm(
                                context,
                                'Gỡ nhân viên ${e.name} khỏi ca ${s.name}?',
                              );
                              if (ok && context.mounted) {
                                Navigator.pop(context);
                                final copy = Employee.fromJson(e.toJson())
                                  ..shiftId = null;
                                await perform(
                                  () => c.saveEmployee(copy),
                                  'Đã gỡ ${e.name} khỏi ca ${s.name}',
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          if (c.isAdmin) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Xóa ca này'),
              onPressed: () async {
                Navigator.pop(context);
                if (assignedEmps.isEmpty) {
                  if (await confirm(context, 'Xóa ca ${s.name}?')) {
                    await perform(() => c.deleteShift(s.id));
                  }
                } else {
                  final names = assignedEmps
                      .map((e) => '• ${e.name}')
                      .join('\n');
                  final ok = await confirm(
                    context,
                    'Ca ${s.name} đang có ${assignedEmps.length} người làm:\n$names\n\nHệ thống sẽ tự động gỡ phân ca và xóa ca này. Bạn có chắc không?',
                  );
                  if (ok) {
                    await perform(
                      () => c.deleteShift(s.id, force: true),
                      'Đã gỡ phân ca và xóa ca thành công!',
                    );
                  }
                }
              },
            ),
            if (assignedEmps.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.group_remove_outlined, size: 16),
                label: const Text('Gỡ tất cả'),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    'Gỡ toàn bộ ${assignedEmps.length} nhân viên khỏi ca ${s.name}?',
                  );
                  if (ok && context.mounted) {
                    Navigator.pop(context);
                    await perform(() async {
                      for (final emp in assignedEmps) {
                        final copy = Employee.fromJson(emp.toJson())
                          ..shiftId = null;
                        await c.saveEmployee(copy);
                      }
                    }, 'Đã gỡ toàn bộ nhân viên khỏi ca ${s.name}');
                  }
                },
              ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> editShift([Shift? s]) => editForm(
    context,
    title: s == null ? 'Tạo ca làm' : 'Sửa ca làm',
    fields: {
      'Tên ca': s?.name ?? '',
      'Giờ vào (HH:mm)': minuteText(s?.startMinute ?? 480),
      'Giờ ra (HH:mm)': minuteText(s?.endMinute ?? 1020),
      'Cho phép trễ (phút)': '${s?.grace ?? 5}',
    },
    save: (v) => c.saveShift(
      Shift(
        id: s?.id ?? newId(),
        name: v['Tên ca']!,
        startMinute: parseMinute(v['Giờ vào (HH:mm)']!),
        endMinute: parseMinute(v['Giờ ra (HH:mm)']!),
        grace: int.tryParse(v['Cho phép trễ (phút)']!) ?? -1,
      ),
    ),
  );
  Future<void> changeRole(Employee e) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Phân quyền tài khoản • ${e.name}'),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
        children: [
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: e.role == 'employee'
                    ? const Color(0xFF087F8C)
                    : Colors.grey.shade300,
                width: e.role == 'employee' ? 2 : 1,
              ),
            ),
            tileColor: e.role == 'employee'
                ? const Color(0xFF087F8C).withValues(alpha: 0.05)
                : null,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE0F2FE),
              child: Icon(Icons.person_outline, color: Color(0xFF0284C7)),
            ),
            title: const Text(
              'Nhân viên (Employee)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Chấm công GPS/QR, làm đơn xin nghỉ, xem lịch sử cá nhân.',
            ),
            trailing: e.role == 'employee'
                ? const Icon(Icons.check_circle, color: Color(0xFF087F8C))
                : null,
            onTap: () => Navigator.pop(context, 'employee'),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: e.role == 'manager' ? Colors.teal : Colors.grey.shade300,
                width: e.role == 'manager' ? 2 : 1,
              ),
            ),
            tileColor: e.role == 'manager'
                ? Colors.teal.withValues(alpha: 0.05)
                : null,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFE6FFFA),
              child: Icon(
                Icons.supervisor_account_outlined,
                color: Colors.teal,
              ),
            ),
            title: const Text(
              'Quản lý bộ phận (Manager)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Theo dõi thống kê nhân sự, xem báo cáo, duyệt đơn cấp phòng ban.',
            ),
            trailing: e.role == 'manager'
                ? const Icon(Icons.check_circle, color: Colors.teal)
                : null,
            onTap: () => Navigator.pop(context, 'manager'),
          ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: e.role == 'admin'
                    ? Colors.deepPurple
                    : Colors.grey.shade300,
                width: e.role == 'admin' ? 2 : 1,
              ),
            ),
            tileColor: e.role == 'admin'
                ? Colors.deepPurple.withValues(alpha: 0.05)
                : null,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFEDE9FE),
              child: Icon(Icons.shield_outlined, color: Colors.deepPurple),
            ),
            title: const Text(
              'Quản trị viên (Admin)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Toàn quyền quản trị nhân sự, ca làm, duyệt đơn từ và cấu hình văn phòng.',
            ),
            trailing: e.role == 'admin'
                ? const Icon(Icons.check_circle, color: Colors.deepPurple)
                : null,
            onTap: () => Navigator.pop(context, 'admin'),
          ),
        ],
      ),
    );
    if (selected != null && selected != e.role) {
      final copy = Employee.fromJson(e.toJson())..role = selected;
      final roleTitle = selected == 'admin'
          ? 'Quản trị viên (Admin)'
          : selected == 'manager'
          ? 'Quản lý (Manager)'
          : 'Nhân viên (Employee)';
      await perform(
        () => c.saveEmployee(copy),
        'Đã cập nhật quyền thành: $roleTitle',
      );
    }
  }

  Future<void> editEmployee([Employee? e]) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _EmployeeFormDialog(
      controller: c,
      employee: e,
      onSaved: () {
        if (mounted) setState(() {});
      },
    ),
  );
  Future<void> assignShift(Employee e) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Phân ca • ${e.name}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Bỏ phân ca'),
          ),
          for (final s in c.data.shifts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s.id),
              child: Text(
                '${s.name} (${minuteText(s.startMinute)}–${minuteText(s.endMinute)})',
              ),
            ),
        ],
      ),
    );
    if (selected != null) {
      final copy = Employee.fromJson(e.toJson())
        ..shiftId = selected.isEmpty ? null : selected;
      await perform(() => c.saveEmployee(copy));
    }
  }

  Future<void> bulkAssignShiftDialog() async {
    final unassigned =
        c.data.employees.where((e) => e.shiftId == null).toList();
    if (unassigned.isEmpty) {
      message(context, 'Tất cả nhân sự đều đã có ca làm!');
      return;
    }
    if (c.data.shifts.isEmpty) {
      message(context, 'Chưa có ca làm nào. Vui lòng tạo ca làm trước.');
      return;
    }
    String? selectedShiftId = c.data.shifts.first.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Sắp ca nhanh cho ${unassigned.length} nhân sự'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hiện tại có ${unassigned.length} nhân sự chưa đăng ký / bình chọn ca làm. Chọn ca bên dưới để gán đồng loạt cho họ:',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedShiftId,
                decoration: const InputDecoration(
                  labelText: 'Ca làm gán đồng loạt',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in c.data.shifts)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${s.name} (${minuteText(s.startMinute)} – ${minuteText(s.endMinute)})',
                      ),
                    ),
                ],
                onChanged: (val) => setDialogState(() => selectedShiftId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.flash_on, size: 18),
              label: const Text('Gán ca ngay'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && selectedShiftId != null) {
      await perform(
        () => c.bulkAssignShift(selectedShiftId!, onlyUnassigned: true),
        'Đã gán ca thành công cho ${unassigned.length} nhân sự!',
      );
    }
  }

  Future<void> registerMyShiftDialog() async {
    if (c.data.shifts.isEmpty) {
      message(
        context,
        'Chưa có ca làm nào trên hệ thống. Vui lòng liên hệ Admin.',
      );
      return;
    }
    String? selected = c.user?.shiftId ?? c.data.shifts.first.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('Đăng ký / Bình chọn ca làm'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Chọn ca làm bạn mong muốn làm việc. Ca đã chọn sẽ trở thành ca làm chính thức của bạn để điểm danh:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: selected,
                onChanged: (val) => setDialogState(() => selected = val),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in c.data.shifts)
                      RadioListTile<String>(
                        value: s.id,
                        title: Text(
                          s.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${minuteText(s.startMinute)} – ${minuteText(s.endMinute)} • Trễ ${s.grace}p',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xác nhận đăng ký'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && selected != null) {
      await perform(
        () => c.registerMyShift(selected),
        'Đã bình chọn ca làm thành công!',
      );
    }
  }

  Future<void> showOfficeQr() async {
    if (!c.data.office.configured) {
      message(
        context,
        'Chưa ghim tọa độ văn phòng. Hãy cấu hình tên, GPS và bán kính trước.',
      );
      await editOffice();
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          OfficeQrDialog(controller: c, onEditOffice: editOffice),
    );
  }

  Future<void> editOffice([Position? position]) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _OfficeConfigDialog(
        controller: c,
        initialPosition: position,
      ),
    );
  }

  Widget _buildEmployeeTimesheetView() {
    final myRecords = records
        .where((a) => a.employeeId == c.user?.id)
        .toList();

    final monthRecords = myRecords.where((a) {
      return a.checkIn.year == _selectedTimesheetMonth.year &&
          a.checkIn.month == _selectedTimesheetMonth.month;
    }).toList();

    final totalDays = monthRecords.length;
    final onTimeDays = monthRecords.where((a) => a.lateMinutes <= 0).length;
    final lateDays = monthRecords.where((a) => a.lateMinutes > 0).length;
    final totalHours = monthRecords.fold<double>(0, (s, a) => s + a.hours);

    final daysInMonth = DateTime(
      _selectedTimesheetMonth.year,
      _selectedTimesheetMonth.month + 1,
      0,
    ).day;
    final firstWeekday = DateTime(
      _selectedTimesheetMonth.year,
      _selectedTimesheetMonth.month,
      1,
    ).weekday; // 1: Mon, 7: Sun

    final now = DateTime.now();

    return list([
      // Card bộ lọc chọn Tháng
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F7C8A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 28),
              onPressed: () {
                setState(() {
                  _selectedTimesheetMonth = DateTime(
                    _selectedTimesheetMonth.year,
                    _selectedTimesheetMonth.month - 1,
                    1,
                  );
                });
              },
            ),
            Row(
              children: [
                const Icon(Icons.calendar_month_rounded, color: Color(0xFF0F7C8A), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Tháng ${_selectedTimesheetMonth.month}/${_selectedTimesheetMonth.year}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 28),
              onPressed: () {
                setState(() {
                  _selectedTimesheetMonth = DateTime(
                    _selectedTimesheetMonth.year,
                    _selectedTimesheetMonth.month + 1,
                    1,
                  );
                });
              },
            ),
          ],
        ),
      ),

      // 4 metrics tháng
      LayoutBuilder(
        builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metric('Số ngày công', '$totalDays ngày', Icons.fact_check_rounded, const Color(0xFF0F7C8A), w),
              metric('Đúng giờ', '$onTimeDays ngày', Icons.check_circle_rounded, const Color(0xFF16A34A), w),
              metric('Đi muộn', '$lateDays ngày', Icons.warning_amber_rounded, const Color(0xFFEA580C), w),
              metric('Tổng giờ làm', '${totalHours.toStringAsFixed(1)}h', Icons.schedule_rounded, const Color(0xFF6366F1), w),
            ],
          );
        },
      ),

      const SizedBox(height: 16),

      // Mini Calendar trực quan
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_view_month_rounded, size: 18, color: Color(0xFF0F7C8A)),
                SizedBox(width: 8),
                Text(
                  'Lịch làm việc tháng',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _WeekdayHeader('T2'),
                _WeekdayHeader('T3'),
                _WeekdayHeader('T4'),
                _WeekdayHeader('T5'),
                _WeekdayHeader('T6'),
                _WeekdayHeader('T7', isWeekend: true),
                _WeekdayHeader('CN', isWeekend: true),
              ],
            ),
            const Divider(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (ctx, index) {
                final dayNumber = index - (firstWeekday - 1) + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }

                final targetDate = DateTime(
                  _selectedTimesheetMonth.year,
                  _selectedTimesheetMonth.month,
                  dayNumber,
                );

                final dayRecords = monthRecords.where((a) =>
                    a.checkIn.year == targetDate.year &&
                    a.checkIn.month == targetDate.month &&
                    a.checkIn.day == targetDate.day).toList();

                final isToday = now.year == targetDate.year &&
                    now.month == targetDate.month &&
                    now.day == targetDate.day;

                Color bg = const Color(0xFFF8FAFC);
                Color textCol = const Color(0xFF334155);
                Widget? indicator;

                if (dayRecords.isNotEmpty) {
                  final anyLate = dayRecords.any((a) => a.lateMinutes > 0);
                  if (anyLate) {
                    bg = const Color(0xFFFFF7ED);
                    textCol = const Color(0xFFC2410C);
                    indicator = Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFFEA580C),
                        shape: BoxShape.circle,
                      ),
                    );
                  } else {
                    bg = const Color(0xFFF0FDF4);
                    textCol = const Color(0xFF15803D);
                    indicator = Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                    );
                  }
                }

                return Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: isToday
                        ? Border.all(color: const Color(0xFF0F7C8A), width: 1.8)
                        : Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$dayNumber',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                          color: textCol,
                        ),
                      ),
                      if (indicator != null) ...[
                        const SizedBox(height: 2),
                        indicator,
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),

      // Danh sách chấm công chi tiết trong tháng
      Section(
        title: 'Bản ghi chấm công Tháng ${_selectedTimesheetMonth.month}/${_selectedTimesheetMonth.year}',
        child: monthRecords.isEmpty
            ? const EmptyState('Không có dữ liệu chấm công nào trong tháng này.')
            : Column(
                children: (monthRecords..sort((a, b) => b.checkIn.compareTo(a.checkIn)))
                    .map(attendanceTile)
                    .toList(),
              ),
      ),
    ]);
  }

  Widget history() {
    final filtered = records
        .where(
          (a) =>
              '${employeeName(a.employeeId)} ${a.shiftName} ${dateLabel(a.checkIn)}'
                  .toLowerCase()
                  .contains(search.toLowerCase()) &&
              (historyRange == null ||
                  (!a.checkIn.isBefore(historyRange!.start) &&
                      a.checkIn.isBefore(
                        historyRange!.end.add(const Duration(days: 1)),
                      ))),
        )
        .toList();

    final totalHours = filtered.fold<double>(0, (s, a) => s + a.hours);
    final totalLate = filtered.where((a) => a.lateMinutes > 0).length;

    return list([
      _pageHint(
        'Bảng công & Điểm danh',
        'Kiểm tra thời gian vào–ra và trạng thái làm việc. Chạm vào bất kỳ bản ghi nào để xem chi tiết GPS & bản đồ.',
        Icons.calendar_month_rounded,
      ),

      // Thanh tóm tắt số liệu bảng công
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B1F3A).withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${filtered.length}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F7C8A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('Lượt chấm', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
            Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${totalHours.toStringAsFixed(1)} h',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('Tổng giờ', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
            Container(height: 28, width: 1, color: const Color(0xFFE2E8F0)),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '$totalLate',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: totalLate > 0 ? const Color(0xFFEA580C) : const Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('Lần đi trễ', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
        ),
      ),

      Section(
        icon: Icons.access_time_filled_rounded,
        iconColor: const Color(0xFF0F7C8A),
        title: 'Bảng chấm công chi tiết',
        subtitle: '${filtered.length} bản ghi • Chạm vào dòng để xem bản đồ tọa độ',
        action: OutlinedButton.icon(
          onPressed: filtered.isEmpty
              ? null
              : () async {
                  String cell(Object? value) {
                    var s = '$value';
                    if (RegExp(r'^[=+@\-\t\r]').hasMatch(s)) s = "'$s";
                    return '"${s.replaceAll('"', '""')}"';
                  }

                  final rows = [
                    [
                      'Nhân viên',
                      'Ca',
                      'Giờ vào',
                      'Giờ ra',
                      'Trễ (phút)',
                      'Số giờ',
                    ],
                    ...filtered.map(
                      (a) => [
                        employeeName(a.employeeId),
                        a.shiftName,
                        a.checkIn.toIso8601String(),
                        a.checkOut?.toIso8601String() ?? '',
                        a.lateMinutes,
                        a.hours.toStringAsFixed(2),
                      ],
                    ),
                  ];
                  await Clipboard.setData(
                    ClipboardData(
                      text: rows
                          .map((r) => r.map(cell).join(','))
                          .join('\r\n'),
                    ),
                  );
                  if (mounted) {
                    message(
                      context,
                      'Đã sao chép CSV vào bộ nhớ tạm để dán vào Excel.',
                    );
                  }
                },
          icon: const Icon(Icons.download_rounded, size: 16),
          label: const Text('Xuất CSV'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên nhân viên, ca làm hoặc ngày...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Tất cả'),
                    selected: historyRange == null,
                    onSelected: (_) => setState(() => historyRange = null),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Hôm nay'),
                    selected: historyRange != null &&
                        dayKey(historyRange!.start) == dayKey(DateTime.now()) &&
                        dayKey(historyRange!.end) == dayKey(DateTime.now()),
                    onSelected: (_) {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      setState(() => historyRange = DateTimeRange(start: today, end: today));
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('7 ngày qua'),
                    selected: historyRange != null &&
                        DateTime.now().difference(historyRange!.start).inDays <= 7 &&
                        historyRange!.start != historyRange!.end,
                    onSelected: (_) {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      setState(() => historyRange = DateTimeRange(
                            start: today.subtract(const Duration(days: 6)),
                            end: today,
                          ));
                    },
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.date_range_rounded, size: 16),
                    label: Text(
                      historyRange == null
                          ? 'Chọn khoảng ngày'
                          : '${dateLabel(historyRange!.start)} – ${dateLabel(historyRange!.end)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDateRange: historyRange,
                      );
                      if (mounted && range != null) {
                        setState(() => historyRange = range);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (filtered.isEmpty)
              const EmptyState(
                'Không tìm thấy bản ghi chấm công nào phù hợp.',
                icon: Icons.calendar_today_outlined,
              ),
            ...filtered.map(attendanceTile),
          ],
        ),
      ),
    ]);
  }

  Widget requests() {
    final items =
        c.data.requests
            .where(
              (r) =>
                  (c.isStaff || r.employeeId == c.user!.id) &&
                  (requestFilter == 'all' || r.status == requestFilter),
            )
            .toList()
          ..sort((a, b) => b.from.compareTo(a.from));
    return list([
      _pageHint(
        c.isStaff ? 'Quản lý duyệt đơn' : 'Theo dõi đơn của bạn',
        c.isStaff
            ? 'Theo dõi và xét duyệt các đơn xin nghỉ phép, giải trình quên chấm công của nhân viên.'
            : 'Gửi đơn xin nghỉ phép hoặc giải trình chấm công. Chỉ đơn đang chờ duyệt mới có thể sửa hoặc xóa.',
        Icons.assignment_turned_in_rounded,
      ),
      Section(
        icon: Icons.fact_check_rounded,
        iconColor: const Color(0xFFEA580C),
        title: 'Danh sách đơn từ',
        subtitle: '${items.length} đơn • Đơn đã xử lý được lưu trữ để đối chiếu',
        action: c.isAdmin
            ? null
            : FilledButton.icon(
                onPressed: () => editRequest(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tạo đơn mới'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F7C8A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
        child: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in {
                    'all': 'Tất cả (${c.data.requests.where((r) => c.isStaff || r.employeeId == c.user!.id).length})',
                    'pending': 'Chờ duyệt (${c.data.requests.where((r) => r.status == 'pending' && (c.isStaff || r.employeeId == c.user!.id)).length})',
                    'approved': 'Đã duyệt',
                    'rejected': 'Từ chối',
                  }.entries) ...[
                    ChoiceChip(
                      label: Text(
                        item.value,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: requestFilter == item.key ? FontWeight.w700 : FontWeight.w600,
                          color: requestFilter == item.key ? const Color(0xFF0F766E) : const Color(0xFF334155),
                        ),
                      ),
                      selected: requestFilter == item.key,
                      selectedColor: const Color(0xFFCCFBF1),
                      backgroundColor: const Color(0xFFF1F5F9),
                      onSelected: (_) => setState(() => requestFilter = item.key),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const EmptyState(
                'Không có đơn từ nào trong mục này.',
                icon: Icons.assignment_outlined,
              ),
            for (final r in items) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0B1F3A).withValues(alpha: 0.02),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFFE0F2FE),
                            child: Text(
                              employeeName(r.employeeId).isNotEmpty
                                  ? employeeName(r.employeeId)[0].toUpperCase()
                                  : 'U',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0284C7),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  employeeName(r.employeeId),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                    color: Color(0xFF0B1F3A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  r.type,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF0F7C8A),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: r.status == 'approved'
                                  ? const Color(0xFFECFDF5)
                                  : r.status == 'rejected'
                                  ? const Color(0xFFFEF2F2)
                                  : const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: r.status == 'approved'
                                    ? const Color(0xFF6EE7B7)
                                    : r.status == 'rejected'
                                    ? const Color(0xFFFCA5A5)
                                    : const Color(0xFFFDBA74),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  r.status == 'approved'
                                      ? Icons.check_circle_rounded
                                      : r.status == 'rejected'
                                      ? Icons.cancel_rounded
                                      : Icons.timelapse_rounded,
                                  size: 13,
                                  color: r.status == 'approved'
                                      ? const Color(0xFF059669)
                                      : r.status == 'rejected'
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFFEA580C),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  {
                                    'pending': 'Chờ duyệt',
                                    'approved': 'Đã duyệt',
                                    'rejected': 'Từ chối',
                                  }[r.status]!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: r.status == 'approved'
                                        ? const Color(0xFF059669)
                                        : r.status == 'rejected'
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFFEA580C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.date_range_rounded, size: 15, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Text(
                            '${dateLabel(r.from)} → ${dateLabel(r.to)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Text(
                          r.reason.isEmpty ? 'Không có lý do chi tiết' : r.reason,
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.35),
                        ),
                      ),
                      if (r.reviewerNote.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Text(
                            'Phản hồi quản lý: ${r.reviewerNote}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                      if (r.status == 'pending') ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (r.employeeId == c.user!.id) ...[
                              OutlinedButton.icon(
                                onPressed: () => editRequest(r),
                                icon: const Icon(Icons.edit_outlined, size: 15),
                                label: const Text('Sửa'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () async {
                                  if (await confirm(context, 'Xác nhận xóa đơn này?')) {
                                    await perform(() => c.deleteRequest(r.id));
                                  }
                                },
                                icon: const Icon(Icons.delete_outline, size: 15, color: Colors.red),
                                label: const Text('Xóa', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                            if (c.isStaff && r.employeeId != c.user!.id) ...[
                              OutlinedButton.icon(
                                onPressed: () => review(r, false),
                                icon: const Icon(Icons.close_rounded, size: 15, color: Color(0xFFDC2626)),
                                label: const Text('Từ chối', style: TextStyle(color: Color(0xFFDC2626))),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () => review(r, true),
                                icon: const Icon(Icons.check_rounded, size: 15),
                                label: const Text('Phê duyệt'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F7C8A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  Future<void> editRequest([WorkRequest? r]) async {
    if (r == null) {
      final type = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Loại đơn'),
          children: [
            for (final t in ['Nghỉ phép', 'Giải trình chấm công'])
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, t),
                child: Text(t),
              ),
          ],
        ),
      );
      if (type == null || !mounted) return;
      r = WorkRequest(
        id: newId(),
        employeeId: c.user!.id,
        type: type,
        reason: '',
        from: DateTime.now(),
        to: DateTime.now(),
      );
    }
    final request = r;
    await editForm(
      context,
      title: request.type,
      fields: {
        'Từ ngày (yyyy-MM-dd)': dayKey(request.from),
        'Đến ngày (yyyy-MM-dd)': dayKey(request.to),
        'Lý do': request.reason,
      },
      save: (v) {
        DateTime parse(String input) {
          final d = DateTime.tryParse(input);
          if (d == null || dayKey(d) != input) {
            throw ArgumentError('Ngày phải theo yyyy-MM-dd và tồn tại.');
          }
          return d;
        }

        return c.saveRequest(
          WorkRequest(
            id: request.id,
            employeeId: request.employeeId,
            type: request.type,
            reason: v['Lý do']!,
            from: parse(v['Từ ngày (yyyy-MM-dd)']!),
            to: parse(v['Đến ngày (yyyy-MM-dd)']!),
          ),
        );
      },
    );
  }

  Future<void> review(WorkRequest r, bool approve) => editForm(
    context,
    title: approve ? 'Duyệt đơn' : 'Từ chối đơn',
    fields: {'Nhận xét': ''},
    save: (v) => c.reviewRequest(r.id, approve, v['Nhận xét']!),
  );
  Widget profile() {
    final roleColor = c.isAdmin
        ? Colors.amber.shade700
        : c.user?.role == 'manager'
        ? Colors.teal
        : const Color(0xFF0284C7);
    final roleBg = c.isAdmin
        ? Colors.amber.shade50
        : c.user?.role == 'manager'
        ? Colors.teal.shade50
        : const Color(0xFFE0F2FE);
    final roleBorder = c.isAdmin
        ? Colors.amber.shade300
        : c.user?.role == 'manager'
        ? Colors.teal.shade200
        : const Color(0xFFBAE6FD);
    final roleName = c.isAdmin
        ? 'Quản trị viên (Admin)'
        : c.user?.role == 'manager'
        ? 'Quản lý (Manager)'
        : 'Nhân viên (Employee)';

    return list([
      // Profile Header Card Hiện Đại
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: const Color(0xFF087F8C),
                        backgroundImage: _avatarBase64 != null
                            ? MemoryImage(base64Decode(_avatarBase64!))
                            : null,
                        child: _avatarBase64 == null
                            ? Text(
                                c.user!.name.isNotEmpty
                                    ? c.user!.name[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF087F8C),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.user!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: roleBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: roleBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              c.isAdmin
                                  ? Icons.shield_rounded
                                  : c.user?.role == 'manager'
                                  ? Icons.supervisor_account_rounded
                                  : Icons.badge_rounded,
                              size: 14,
                              color: roleColor,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                roleName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: roleColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 16),
            // Thông tin chi tiết
            _profileInfoRow(
              icon: Icons.account_circle_outlined,
              label: 'Tên đăng nhập',
              value: c.user!.username,
            ),
            const SizedBox(height: 12),
            _profileInfoRow(
              icon: Icons.email_outlined,
              label: 'Email nhận OTP',
              value: c.user!.email,
            ),
            const SizedBox(height: 12),
            _profileInfoRow(
              icon: Icons.corporate_fare_outlined,
              label: 'Phòng ban',
              value: c.user!.department.isEmpty
                  ? 'Chưa phân công'
                  : c.user!.department,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openEditProfileDialog,
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text(
                  'Chỉnh sửa hồ sơ cá nhân',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF087F8C),
                  side: const BorderSide(color: Color(0xFF087F8C)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 14),

      // Card Sinh trắc học
      FaceSettingsCard(controller: c),
      BiometricSettingsCard(controller: c),

      const SizedBox(height: 14),

      // Card Vị trí GPS hiện tại
      Section(
        icon: Icons.my_location_rounded,
        iconColor: const Color(0xFF087F8C),
        title: 'Vị trí hiện tại',
        subtitle: 'Xác định vị trí GPS chính xác — hiển thị địa chỉ thực tế.',
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: locating ? null : _showCurrentLocation,
                icon: const Icon(Icons.my_location_rounded),
                label: Text(
                  locating
                      ? 'Đang xác định vị trí…'
                      : 'Xác định vị trí hiện tại',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF087F8C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 16),

      // NÚT ĐĂNG XUẤT ĐẶT DƯỚI CÙNG TÁCH BIỆT RÕ RÀNG
      Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: OutlinedButton.icon(
          onPressed: () async {
            final ok = await confirm(
              context,
              'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản ${c.user!.name}?',
            );
            if (ok) {
              await SessionStorage.clearSession();
              c.logout();
            }
          },
          icon: const Icon(
            Icons.logout_rounded,
            color: Color(0xFFDC2626),
            size: 20,
          ),
          label: const Text(
            'Đăng xuất tài khoản',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFFDC2626),
            ),
          ),
          style: OutlinedButton.styleFrom(
            backgroundColor: const Color(0xFFFEF2F2),
            side: const BorderSide(color: Color(0xFFFECACA), width: 1.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Center(
        child: Text(
          'Chấm Công Thông Minh • Phiên bản 1.0.0\nNhóm 09 — Tống Nhật Bảo An',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.5),
        ),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _profileInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class OfficeQrDialog extends StatefulWidget {
  final AppController controller;
  final Future<void> Function([Position?])? onEditOffice;
  const OfficeQrDialog({
    super.key,
    required this.controller,
    this.onEditOffice,
  });
  @override
  State<OfficeQrDialog> createState() => _OfficeQrDialogState();
}

class _OfficeQrDialogState extends State<OfficeQrDialog> {
  Timer? timer;
  OfficeQrTicket? ticket;
  String? error;
  bool loading = true;
  bool rotating = false;
  bool fetching = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _fetch();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _fetch({bool rotate = false}) async {
    if (fetching && !rotate) return;
    fetching = true;
    setState(() {
      loading = ticket == null;
      error = null;
      rotating = rotate;
    });
    try {
      final next = await c.fetchServerQr(rotate: rotate);
      if (mounted) setState(() => ticket = next);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().replaceFirst(
            RegExp(r'^(Exception: |StateError: |Bad state: )'),
            '',
          ),
        );
      }
    } finally {
      fetching = false;
      if (mounted) {
        setState(() {
          loading = false;
          rotating = false;
        });
      }
    }
  }

  void _tick() {
    final current = ticket;
    if (current == null) return;
    final left = current.expiresAt.difference(DateTime.now().toUtc());
    if (left <= const Duration(seconds: 15) && !fetching) {
      _fetch();
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final office = c.data.office;
    final code = ticket?.code;
    final left = ticket == null
        ? Duration.zero
        : ticket!.expiresAt.difference(DateTime.now().toUtc());
    final seconds = left.isNegative ? 0 : left.inSeconds;
    return AlertDialog(
      title: Text(office.name),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                office.configured
                    ? 'Bán kính ${office.radius.round()} m • ${office.latitude?.toStringAsFixed(5)}, ${office.longitude?.toStringAsFixed(5)}'
                    : 'Chưa ghim tọa độ. Chấm công sẽ bị từ chối.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              if (loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                )
              else if (code != null && code.startsWith('BAOAN:'))
                QrImageView(data: code, size: 240, backgroundColor: Colors.white)
              else
                const Text(
                  'Chưa lấy được mã QR từ server.',
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),
              Text(
                code == null
                    ? 'Mã QR động do Admin cấu hình văn phòng rồi hiển thị tại đây. Nhân viên quét mã này khi chấm công.'
                    : 'Còn $seconds giây. Mã đổi theo phút; nhân viên cần quét mã còn hạn.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: code == null
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: code));
                            if (context.mounted) {
                              message(context, 'Đã sao chép mã QR server.');
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Sao chép mã'),
                  ),
                  TextButton.icon(
                    onPressed: loading ? null : () => _fetch(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Làm mới QR'),
                  ),
                ],
              ),
              if (widget.onEditOffice != null)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () async {
                        await widget.onEditOffice!();
                        if (mounted) setState(() {});
                      },
                      child: const Text('Sửa tên / bán kính'),
                    ),
                    TextButton(
                      onPressed: () async {
                        try {
                          final position = await acquirePosition();
                          if (!context.mounted) return;
                          await widget.onEditOffice!(position);
                          if (!context.mounted) return;
                          setState(() {});
                        } catch (e) {
                          if (context.mounted) message(context, e);
                        }
                      },
                      child: const Text('Ghim GPS tại đây'),
                    ),
                    TextButton(
                      onPressed: rotating
                          ? null
                          : () async {
                              if (!await confirm(
                                context,
                                'Tạo khóa QR mới? Mã đang hiện sẽ hết hiệu lực ngay, nhân viên phải quét mã mới.',
                              )) {
                                return;
                              }
                              await _fetch(rotate: true);
                            },
                      child: const Text('Đổi khóa QR'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class _EmployeeFormDialog extends StatefulWidget {
  final AppController controller;
  final Employee? employee;
  final VoidCallback onSaved;

  const _EmployeeFormDialog({
    required this.controller,
    this.employee,
    required this.onSaved,
  });

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  late final _nameCtrl = TextEditingController(
    text: widget.employee?.name ?? '',
  );
  late final _emailCtrl = TextEditingController(
    text: widget.employee?.email ?? '',
  );
  late final _usernameCtrl = TextEditingController(
    text: widget.employee?.username ?? '',
  );
  late String? _selectedDept = widget.employee?.department.isEmpty == true
      ? null
      : widget.employee?.department;
  late final _passwordCtrl = TextEditingController();

  late String _role = widget.employee?.role ?? 'employee';
  late bool _active = widget.employee?.active ?? true;
  late String? _shiftId = widget.employee?.shiftId;

  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final username = _usernameCtrl.text.trim();
    final dept = _selectedDept?.trim() ?? '';
    final password = _passwordCtrl.text;

    if (name.isEmpty || email.isEmpty || username.isEmpty) {
      setState(() => _error = 'Vui lòng điền họ tên, email và tên đăng nhập.');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Định dạng email không hợp lệ.');
      return;
    }
    if (widget.employee == null && password.length < 8) {
      setState(() => _error = 'Mật khẩu khởi tạo phải có tối thiểu 8 ký tự.');
      return;
    }
    if (password.isNotEmpty && password.length < 8) {
      setState(() => _error = 'Mật khẩu mới phải có tối thiểu 8 ký tự.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final emp = Employee(
        id: widget.employee?.id ?? newId(),
        name: name,
        email: email,
        username: username,
        department: dept,
        role: _role,
        active: _active,
        shiftId: _shiftId,
      );

      await widget.controller.saveEmployee(
        emp,
        password: password.isEmpty ? null : password,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
        message(
          context,
          widget.employee == null
              ? 'Đã thêm nhân viên thành công!'
              : 'Đã cập nhật thông tin nhân viên!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst(
            RegExp(r'^(Exception: |StateError: |Bad state: )'),
            '',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _minuteText(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final isNew = widget.employee == null;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isNew
                    ? const Color(0xFF087F8C).withValues(alpha: 0.1)
                    : Colors.deepPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isNew
                    ? Icons.person_add_alt_1_rounded
                    : Icons.manage_accounts_rounded,
                color: isNew ? const Color(0xFF087F8C) : Colors.deepPurple,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                isNew ? 'Thêm nhân viên mới' : 'Chỉnh sửa nhân viên',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: Color(0xFFDC2626),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFB91C1C),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // Họ và tên
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên nhân viên *',
                    hintText: 'Ví dụ: Nguyễn Văn An',
                    prefixIcon: Icon(Icons.badge_outlined),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                  ),
                ),
                const SizedBox(height: 14),

                // Email
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ Email *',
                    hintText: 'Ví dụ: an.nguyen@gmail.com',
                    prefixIcon: Icon(Icons.email_outlined),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                  ),
                ),
                const SizedBox(height: 14),

                // Tên đăng nhập
                TextField(
                  controller: _usernameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên đăng nhập *',
                    hintText: 'Ví dụ: an_nv25',
                    prefixIcon: Icon(Icons.account_circle_outlined),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                  ),
                ),
                const SizedBox(height: 14),

                // DROP LIST: PHÒNG BAN TRỰC THUỘC
                DropdownButtonFormField<String?>(
                  initialValue: _selectedDept,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Phòng ban trực thuộc',
                    prefixIcon: Icon(Icons.corporate_fare_outlined),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Chưa phân phòng ban',
                        style: TextStyle(color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final d in widget.controller.data.departments)
                      DropdownMenuItem<String?>(
                        value: d.name,
                        child: Text(
                          d.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (widget.employee?.department.isNotEmpty == true &&
                        !widget.controller.data.departments.any(
                          (d) =>
                              d.name.toLowerCase() ==
                              widget.employee!.department.toLowerCase(),
                        ))
                      DropdownMenuItem<String?>(
                        value: widget.employee!.department,
                        child: Text(
                          '${widget.employee!.department} (Hiện tại)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (val) => setState(() => _selectedDept = val),
                ),
                const SizedBox(height: 16),

                // DROP LIST 1: VAI TRÒ (ROLE)
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Vai trò tài khoản *',
                    prefixIcon: Icon(
                      _role == 'admin'
                          ? Icons.shield_outlined
                          : Icons.person_outline,
                      color: _role == 'admin'
                          ? Colors.deepPurple
                          : const Color(0xFF087F8C),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'employee',
                      child: Text(
                        'Nhân viên (Employee)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'manager',
                      child: Text(
                        'Quản lý (Manager)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.teal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text(
                        'Quản trị viên (Admin)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.deepPurple,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _role = val);
                  },
                ),
                const SizedBox(height: 14),

                // DROP LIST 2: TRẠNG THÁI (STATUS)
                DropdownButtonFormField<bool>(
                  initialValue: _active,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Trạng thái hoạt động *',
                    prefixIcon: Icon(
                      _active ? Icons.check_circle_outline : Icons.lock_outline,
                      color: _active
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: true,
                      child: Text(
                        'Đang hoạt động (Active)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF065F46),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: false,
                      child: Text(
                        'Đang bị khóa (Locked)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF991B1B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _active = val);
                  },
                ),
                const SizedBox(height: 14),

                // DROP LIST 3: PHÂN CA LÀM VIỆC (SHIFT)
                DropdownButtonFormField<String?>(
                  initialValue: _shiftId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ca làm việc phân công',
                    prefixIcon: Icon(Icons.schedule_outlined),
                    filled: true,
                    fillColor: Color(0xFFF8FAFC),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        'Chưa phân ca',
                        style: TextStyle(color: Color(0xFF64748B)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    for (final s in widget.controller.data.shifts)
                      DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(
                          '${s.name} (${_minuteText(s.startMinute)} – ${_minuteText(s.endMinute)})',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (val) => setState(() => _shiftId = val),
                ),
                const SizedBox(height: 14),

                // Mật khẩu
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: isNew
                        ? 'Mật khẩu khởi tạo * (tối thiểu 8 ký tự)'
                        : 'Mật khẩu mới (để trống nếu giữ nguyên)',
                    hintText: isNew
                        ? 'Nhập mật khẩu cho nhân viên'
                        : 'Chỉ nhập khi muốn đổi mật khẩu',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Hủy bỏ'),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _handleSave,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(isNew ? 'Thêm nhân viên' : 'Lưu thay đổi'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF087F8C),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<Position> acquirePosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw StateError('Hãy bật Location/GPS trên điện thoại.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.deniedForever) {
    throw StateError(
      'Quyền vị trí bị chặn. Vào Settings → Apps → Permissions để cấp lại.',
    );
  }
  if (permission == LocationPermission.denied) {
    throw StateError('Cần quyền vị trí để chấm công.');
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );
}


class _AttendanceDetailDialog extends StatefulWidget {
  final Attendance attendance;
  final String employeeName;
  const _AttendanceDetailDialog({
    required this.attendance,
    required this.employeeName,
  });

  @override
  State<_AttendanceDetailDialog> createState() => _AttendanceDetailDialogState();
}

class _AttendanceDetailDialogState extends State<_AttendanceDetailDialog> {
  String? _inAddress;
  String? _outAddress;
  bool _loadingIn = true;
  bool _loadingOut = false;
  static final Map<String, String> _addrCache = {};

  @override
  void initState() {
    super.initState();
    _fetchAddresses();
  }

  Future<void> _fetchAddresses() async {
    final a = widget.attendance;
    _resolve(a.latitude, a.longitude).then((addr) {
      if (mounted) {
        setState(() {
          _inAddress = addr;
          _loadingIn = false;
        });
      }
    });

    if (a.outLatitude != null && a.outLongitude != null) {
      setState(() => _loadingOut = true);
      _resolve(a.outLatitude!, a.outLongitude!).then((addr) {
        if (mounted) {
          setState(() {
            _outAddress = addr;
            _loadingOut = false;
          });
        }
      });
    }
  }

  Future<String> _resolve(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}';
    if (_addrCache.containsKey(key)) return _addrCache[key]!;
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
        ].whereType<String>().where((v) => v.trim().isNotEmpty).toSet().toList();
        if (parts.isNotEmpty) {
          final res = parts.join(', ');
          _addrCache[key] = res;
          return res;
        }
      }
    } catch (_) {}
    return '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attendance;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.assignment_outlined, color: Color(0xFF0F7C8A)),
          SizedBox(width: 10),
          Text('Chi tiết chấm công', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.employeeName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              a.shiftName,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0F7C8A), fontSize: 14),
            ),
            const Divider(height: 20),
            _infoRow('Vào:', '${dateLabel(a.checkIn)} ${clock(a.checkIn)}'),
            _infoRow(
              'Ra:',
              a.checkOut == null
                  ? 'Chưa ghi nhận'
                  : '${dateLabel(a.checkOut!)} ${clock(a.checkOut)}',
            ),
            const SizedBox(height: 8),
            _addressRow(
              label: 'Vị trí vào:',
              address: _inAddress,
              loading: _loadingIn,
            ),
            const SizedBox(height: 6),
            if (a.checkOut != null)
              _addressRow(
                label: 'Vị trí ra:',
                address: _outAddress,
                loading: _loadingOut,
              )
            else
              _infoRow('Vị trí ra:', 'Chưa ghi nhận'),
            if (a.explanation.isNotEmpty) ...[
              const Divider(height: 20),
              Text(
                a.explanation,
                style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F7C8A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addressRow({
    required String label,
    required String? address,
    required bool loading,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 85,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: loading
                ? const Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF0F7C8A)),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Đang tra cứu địa chỉ...',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  )
                : Text(
                    address ?? 'Không xác định được địa chỉ',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  final String label;
  final bool isWeekend;
  const _WeekdayHeader(this.label, {this.isWeekend = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isWeekend ? const Color(0xFFEA580C) : const Color(0xFF64748B),
        ),
      ),
    );
  }
}

class _OfficeConfigDialog extends StatefulWidget {
  final AppController controller;
  final Position? initialPosition;

  const _OfficeConfigDialog({
    required this.controller,
    this.initialPosition,
  });

  @override
  State<_OfficeConfigDialog> createState() => _OfficeConfigDialogState();
}

class _OfficeConfigDialogState extends State<_OfficeConfigDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  late final TextEditingController _radiusCtrl;
  final TextEditingController _addressSearchCtrl = TextEditingController();

  bool _searchingAddress = false;
  bool _locatingGps = false;
  bool _saving = false;
  String? _statusMessage;
  bool _isSuccess = true;

  @override
  void initState() {
    super.initState();
    final office = widget.controller.data.office;
    final name = office.name == 'Van phong chinh' ? 'Văn phòng chính' : office.name;
    _nameCtrl = TextEditingController(text: name);
    _latCtrl = TextEditingController(
      text: (widget.initialPosition?.latitude ?? office.latitude)?.toString() ?? '',
    );
    _lngCtrl = TextEditingController(
      text: (widget.initialPosition?.longitude ?? office.longitude)?.toString() ?? '',
    );
    _radiusCtrl = TextEditingController(
      text: office.radius > 0 ? '${office.radius.round()}' : '1000',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    _addressSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchByAddress() async {
    final query = _addressSearchCtrl.text.trim();
    if (query.isEmpty) {
      setState(() {
        _statusMessage = 'Vui lòng nhập địa chỉ cần tìm (VD: Quận 1, Võ Văn Ngân, TP.HCM...)';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _searchingAddress = true;
      _statusMessage = 'Đang tra cứu tọa độ từ địa chỉ...';
      _isSuccess = true;
    });

    try {
      final locations = await geo.Geocoding().locationFromAddress(query);
      if (locations.isEmpty) {
        throw Exception('Không tìm thấy tọa độ.');
      }
      final loc = locations.first;
      setState(() {
        _latCtrl.text = loc.latitude.toString();
        _lngCtrl.text = loc.longitude.toString();
        _statusMessage = 'Đã tìm thấy tọa độ theo địa chỉ thành công!';
        _isSuccess = true;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Không tìm thấy địa chỉ "$query". Hãy thử nhập thêm tên quận hoặc thành phố.';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _searchingAddress = false);
    }
  }

  Future<void> _pinCurrentLocation() async {
    setState(() {
      _locatingGps = true;
      _statusMessage = 'Đang lấy GPS chính xác từ thiết bị của bạn...';
      _isSuccess = true;
    });

    try {
      final pos = await acquirePosition();
      setState(() {
        _latCtrl.text = pos.latitude.toString();
        _lngCtrl.text = pos.longitude.toString();
        _statusMessage = 'Đã ghim vị trí máy bạn thành tọa độ văn phòng!';
        _isSuccess = true;
      });

      try {
        final placemarks = await geo.Geocoding().placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty && _addressSearchCtrl.text.isEmpty) {
          final p = placemarks.first;
          final parts = [p.street, p.subAdministrativeArea, p.administrativeArea]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(', ');
          if (parts.isNotEmpty) {
            _addressSearchCtrl.text = parts;
          }
        }
      } catch (_) {}
    } catch (e) {
      setState(() {
        _statusMessage = 'Lỗi lấy GPS: $e';
        _isSuccess = false;
      });
    } finally {
      if (mounted) setState(() => _locatingGps = false);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final lat = double.tryParse(_latCtrl.text.replaceAll(',', '.'));
    final lng = double.tryParse(_lngCtrl.text.replaceAll(',', '.'));
    final radius = double.tryParse(_radiusCtrl.text.replaceAll(',', '.'));

    if (name.isEmpty) {
      setState(() {
        _statusMessage = 'Vui lòng nhập tên văn phòng.';
        _isSuccess = false;
      });
      return;
    }
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      setState(() {
        _statusMessage = 'Tọa độ không hợp lệ. Vui lòng bấm tìm địa chỉ hoặc bấm Ghim GPS máy tôi.';
        _isSuccess = false;
      });
      return;
    }
    if (radius == null || radius < 10) {
      setState(() {
        _statusMessage = 'Bán kính tối thiểu là 10 mét.';
        _isSuccess = false;
      });
      return;
    }

    setState(() {
      _saving = true;
      _statusMessage = null;
    });

    try {
      final old = widget.controller.data.office;
      final newOffice = Office(
        name: name,
        latitude: lat,
        longitude: lng,
        radius: radius,
        qrSecret: old.qrSecret,
      );
      await widget.controller.saveOffice(newOffice);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã cập nhật vị trí văn phòng thành công! (Bán kính: ${radius.round()}m)'),
            backgroundColor: const Color(0xFF0F7C8A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Lỗi lưu: ${e.toString().replaceFirst(RegExp(r'^(Exception: |StateError: )'), '')}';
          _isSuccess = false;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _radiusChip(String label, double val) {
    final current = double.tryParse(_radiusCtrl.text.replaceAll(',', '.'));
    final selected = current != null && (current - val).abs() < 1;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _radiusCtrl.text = val.round().toString();
        });
      },
      selectedColor: const Color(0xFF0F7C8A).withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected ? const Color(0xFF0F7C8A) : const Color(0xFF475569),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.location_on_rounded, color: Color(0xFF0F7C8A), size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cấu hình vị trí văn phòng',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thông báo hướng dẫn ngắn gọn
              const Text(
                'Bạn có thể nhập địa chỉ bằng chữ hoặc bấm nút ghim GPS máy của bạn để làm vị trí văn phòng chấm công.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.4),
              ),
              const SizedBox(height: 16),

              // KHỐI 1: TÌM KIẾM THEO ĐỊA CHỈ THỰC TẾ
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.search_rounded, size: 16, color: Color(0xFF0F7C8A)),
                        SizedBox(width: 6),
                        Text(
                          'Tìm vị trí theo địa chỉ:',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _addressSearchCtrl,
                            decoration: const InputDecoration(
                              hintText: 'VD: Quận 1, Võ Văn Ngân, Hà Nội...',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _searchByAddress(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F7C8A).withValues(alpha: 0.12),
                            foregroundColor: const Color(0xFF0F7C8A),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          onPressed: _searchingAddress ? null : _searchByAddress,
                          child: _searchingAddress
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F7C8A)),
                                )
                              : const Text('Tìm'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // KHỐI 2: GHIM GPS MÁY TÔI HIỆN TẠI (NÚT 1 CHẠM)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0F7C8A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _locatingGps ? null : _pinCurrentLocation,
                icon: _locatingGps
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.my_location_rounded, size: 20),
                label: Text(
                  _locatingGps ? 'Đang đọc GPS máy...' : 'Ghim GPS vị trí máy tôi tại đây',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),

              if (_statusMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isSuccess ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _isSuccess ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Text(
                    _statusMessage!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _isSuccess ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Tên văn phòng
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên văn phòng',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.business_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 12),

              // Vĩ độ & Kinh độ
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Vĩ độ (Latitude)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lngCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Kinh độ (Longitude)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Bán kính cho phép
              TextField(
                controller: _radiusCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Bán kính cho phép chấm công (mét)',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixText: 'mét',
                ),
              ),
              const SizedBox(height: 8),

              // Chips bán kính nhanh cho test
              const Text(
                'Chọn nhanh bán kính (khuyến nghị 50km để test tự do):',
                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _radiusChip('100m', 100),
                  _radiusChip('500m', 500),
                  _radiusChip('2 km', 2000),
                  _radiusChip('50 km (Test)', 50000),
                  _radiusChip('500 km (Toàn quốc)', 500000),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F7C8A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Lưu cấu hình'),
        ),
      ],
    );
  }
}
