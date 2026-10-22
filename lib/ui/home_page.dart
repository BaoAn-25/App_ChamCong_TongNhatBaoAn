import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'common.dart';
import 'punch_page.dart';
import 'stats_page.dart';
import 'biometric_page.dart';

class HomePage extends StatefulWidget {
  final AppController controller;
  const HomePage({super.key, required this.controller});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int page = 0;
  bool performing = false;
  String search = '', requestFilter = 'all', roleFilter = 'all';
  String? deptFilter;
  String? _avatarBase64;
  DateTimeRange? historyRange;

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
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF087F8C)),
              title: const Text('Chụp ảnh từ máy ảnh'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF087F8C)),
              title: const Text('Chọn ảnh từ thư viện'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (_avatarBase64 != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                title: const Text('Xóa ảnh đại diện', style: TextStyle(color: Colors.red)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải ảnh: $e')),
        );
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
                Text('Chỉnh sửa hồ sơ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
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
                        icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setDialogState(() => obscurePass = !obscurePass),
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
                    setDialogState(() => error = 'Họ tên và tên đăng nhập không được để trống.');
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
                        const SnackBar(content: Text('Cập nhật hồ sơ thành công!')),
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

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Tổng quan',
      c.isStaff ? 'Quản lý' : 'Chấm công',
      'Bảng công',
      'Thống kê',
      'Đơn từ',
      'Tài khoản',
    ];
    final icons = [
      Icons.space_dashboard_outlined,
      c.isStaff ? Icons.manage_accounts_outlined : Icons.fingerprint,
      Icons.calendar_month_outlined,
      Icons.bar_chart_rounded,
      Icons.assignment_outlined,
      Icons.person_outline,
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = switch (page) {
      0 => dashboard(),
      1 => c.isStaff ? management() : PunchPage(controller: c),
      2 => history(),
      3 => StatsPage(controller: c),
      4 => requests(),
      _ => profile(),
    };
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              labels[page],
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const Text(
              'Chấm công • Nhóm 09',
              style: TextStyle(fontSize: 10, letterSpacing: 1),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(
                c.isAdmin
                    ? Icons.shield_outlined
                    : c.user?.role == 'manager'
                    ? Icons.supervisor_account_outlined
                    : Icons.badge_outlined,
                size: 17,
              ),
              label: Text(
                c.isAdmin
                    ? 'Admin'
                    : c.user?.role == 'manager'
                    ? 'Quản lý'
                    : 'Nhân viên',
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (performing || c.isSyncing)
            const LinearProgressIndicator(minHeight: 2),
          Material(
            color: c.syncError == null
                ? const Color(0xFFEDF6F5)
                : const Color(0xFFFFF3E5),
            child: ListTile(
              dense: true,
              leading: Icon(
                c.syncError != null
                    ? Icons.cloud_off_outlined
                    : c.isSyncing
                    ? Icons.sync
                    : Icons.cloud_done_outlined,
                color: c.syncError == null
                    ? const Color(0xFF087F8C)
                    : const Color(0xFF9A5700),
              ),
              title: Text(
                c.isSyncing
                    ? 'Đang cập nhật dữ liệu…'
                    : c.syncError ??
                          (c.lastSyncedAt == null
                              ? 'Chưa đồng bộ dữ liệu'
                              : 'Đã cập nhật lúc ${TimeOfDay.fromDateTime(c.lastSyncedAt!).format(context)}'),
              ),
              subtitle: c.syncError == null
                  ? null
                  : const Text('Đang hiển thị dữ liệu lần tải trước.'),
              trailing: IconButton(
                tooltip: 'Tải lại dữ liệu',
                onPressed: c.isSyncing ? null : c.syncAll,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (wide)
                  NavigationRail(
                    selectedIndex: page,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: (v) => setState(() {
                      page = v;
                      search = '';
                    }),
                    destinations: List.generate(
                      labels.length,
                      (i) => NavigationRailDestination(
                        icon: Icon(icons[i]),
                        label: Text(labels[i]),
                      ),
                    ),
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
          : NavigationBar(
              selectedIndex: page < 3 ? page : 3,
              onDestinationSelected: (v) async {
                if (v < 3) {
                  setState(() {
                    page = v;
                    search = '';
                  });
                  return;
                }
                final chosen = await showModalBottomSheet<int>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final i in [3, 4, 5])
                          ListTile(
                            leading: Icon(icons[i]),
                            title: Text(labels[i]),
                            selected: page == i,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(context, i),
                          ),
                      ],
                    ),
                  ),
                );
                if (chosen != null && mounted) {
                  setState(() {
                    page = chosen;
                    search = '';
                  });
                }
              },
              destinations: [
                for (var i = 0; i < 3; i++)
                  NavigationDestination(icon: Icon(icons[i]), label: labels[i]),
                NavigationDestination(
                  icon: const Icon(Icons.grid_view_rounded),
                  label: page >= 3 ? labels[page] : 'Tiện ích',
                ),
              ],
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF1E293B),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4F4),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF087F8C)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(description),
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

      // Lối tắt tác vụ nhanh (Quick Actions)
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: c.isAdmin
                ? [
                    _quickActionItem(
                      label: 'Thêm nhân viên',
                      icon: Icons.person_add_alt_1_rounded,
                      color: const Color(0xFF0284C7),
                      onTap: () => editEmployee(),
                    ),
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'Tạo ca làm',
                      icon: Icons.more_time_rounded,
                      color: const Color(0xFF0D9488),
                      onTap: () => editShift(),
                    ),
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'QR Văn phòng',
                      icon: Icons.qr_code_2_rounded,
                      color: const Color(0xFF7C3AED),
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => OfficeQrDialog(controller: c),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'Duyệt đơn ($pending)',
                      icon: Icons.fact_check_outlined,
                      color: pending > 0
                          ? const Color(0xFFEA580C)
                          : const Color(0xFF64748B),
                      onTap: () => setState(() => page = 4),
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
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'Thống kê',
                      icon: Icons.bar_chart_rounded,
                      color: const Color(0xFF7C3AED),
                      onTap: () => setState(() => page = 3),
                    ),
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'Bảng công',
                      icon: Icons.calendar_month_rounded,
                      color: const Color(0xFF0284C7),
                      onTap: () => setState(() => page = 2),
                    ),
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'Nhân sự',
                      icon: Icons.groups_outlined,
                      color: const Color(0xFF0D9488),
                      onTap: () => setState(() => page = 1),
                    ),
                  ]
                : [
                    _quickActionItem(
                      label: 'Điểm danh ngay',
                      icon: Icons.fingerprint_rounded,
                      color: const Color(0xFF087F8C),
                      onTap: () => setState(() => page = 1),
                    ),
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'Gửi đơn xin phép',
                      icon: Icons.post_add_rounded,
                      color: const Color(0xFFEA580C),
                      onTap: () => setState(() => page = 4),
                    ),
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'Thống kê',
                      icon: Icons.bar_chart_rounded,
                      color: const Color(0xFF7C3AED),
                      onTap: () => setState(() => page = 3),
                    ),
                    const SizedBox(width: 10),
                    _quickActionItem(
                      label: 'Bảng công tháng',
                      icon: Icons.calendar_month_rounded,
                      color: const Color(0xFF0284C7),
                      onTap: () => setState(() => page = 2),
                    ),
                  ],
          ),
        ),
      ),

      // Thẻ Thống Kê Chỉ Số Đẹp Mắt
      LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            metric(
              c.isStaff ? 'Nhân viên hoạt động' : 'Ca tháng này',
              c.isStaff
                  ? '${c.data.employees.where((e) => e.active && !e.isStaff).length}'
                  : '${month.length}',
              Icons.groups_outlined,
              const Color(0xFF6366F1),
              box.maxWidth,
            ),
            metric(
              'Chấm công hôm nay',
              '${today.length}',
              Icons.verified_outlined,
              const Color(0xFF10B981),
              box.maxWidth,
            ),
            metric(
              'Giờ hoàn tất / tháng',
              month
                  .fold<double>(0, (sum, a) => sum + a.hours)
                  .toStringAsFixed(1),
              Icons.access_time_rounded,
              const Color(0xFF0284C7),
              box.maxWidth,
            ),
            metric(
              'Đơn chờ duyệt',
              '$pending',
              Icons.pending_actions_rounded,
              pending > 0 ? const Color(0xFFEA580C) : const Color(0xFF64748B),
              box.maxWidth,
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
                      Text(
                        myShift?.name ?? 'Chưa được phân ca',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        myShift != null
                            ? '${minuteText(myShift.startMinute)} – ${minuteText(myShift.endMinute)} (Cho phép trễ ${myShift.grace}p)'
                            : 'Vui lòng liên hệ Admin để được phân ca làm việc',
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
        child: records.isEmpty
            ? const EmptyState('Chưa có dữ liệu chấm công để phân tích.')
            : Column(
                children: records
                    .take(4)
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
              ),
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
    double width,
  ) => SizedBox(
    width: width >= 700 ? (width - 36) / 4 : (width - 12) / 2,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 26,
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
  );
  Widget attendanceTile(Attendance a) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: const Color(0xFFE3F5F2),
      child: Text(
        '${a.checkIn.day}',
        style: const TextStyle(color: Color(0xFF087F8C)),
      ),
    ),
    title: Text(c.isStaff ? employeeName(a.employeeId) : a.shiftName),
    subtitle: Text(
      '${dateLabel(a.checkIn)} • ${clock(a.checkIn)} → ${clock(a.checkOut)}\n${a.explanation}',
    ),
    isThreeLine: true,
    trailing: Text(
      a.checkOut == null
          ? (DateTime.now().isAfter(a.scheduledEnd)
                ? 'Thiếu giờ ra'
                : 'Trong ca')
          : '${a.hours.toStringAsFixed(1)} h',
      style: const TextStyle(fontWeight: FontWeight.bold),
    ),
    onTap: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chi tiết chấm công'),
        content: SingleChildScrollView(
          child: SelectableText(
            '${employeeName(a.employeeId)}\n${a.shiftName}\nVào: ${dateLabel(a.checkIn)} ${clock(a.checkIn)}\nRa: ${a.checkOut == null ? 'Chưa ghi nhận' : '${dateLabel(a.checkOut!)} ${clock(a.checkOut)}'}\nGPS vào: ${a.latitude}, ${a.longitude}\nSai số GPS vào: ±${a.accuracy.round()} m\nGPS ra: ${a.outLatitude ?? '—'}, ${a.outLongitude ?? '—'}\n\n${a.explanation}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    ),
  );
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
          title: 'Văn phòng & mã QR',
          subtitle: c.data.office.configured
              ? '${c.data.office.name} • Bán kính ${c.data.office.radius.round()} m'
              : 'Chưa cấu hình vị trí chấm công',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: () => editOffice(),
                icon: const Icon(Icons.location_on_outlined),
                label: const Text('Cấu hình văn phòng'),
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
                label: const Text('Lấy GPS để thiết lập'),
              ),
              OutlinedButton.icon(
                onPressed: c.data.office.configured
                    ? () => showDialog<void>(
                        context: context,
                        builder: (_) => OfficeQrDialog(controller: c),
                      )
                    : null,
                icon: const Icon(Icons.qr_code),
                label: const Text('Hiển thị QR động'),
              ),
            ],
          ),
        ),
      Section(
        title: 'Nhân sự & Người dùng',
        subtitle: c.isAdmin
            ? '${c.data.employees.length} tài khoản trên hệ thống'
            : '${c.data.employees.length} tài khoản • Quản lý chỉ được xem',
        action: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                    c.data.employees.where((e) => !e.isAdmin && !e.isManager).length,
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
                      label: const Text('Tất cả', style: TextStyle(fontSize: 11)),
                      selected: deptFilter == null,
                      onSelected: (_) => setState(() => deptFilter = null),
                    ),
                    for (final d in c.data.departments) ...[
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: Text(d.name, style: const TextStyle(fontSize: 11)),
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
            for (final e in employees)
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
                  subtitle: Text(
                    '${e.username} • ${e.department.isEmpty ? 'Chưa có phòng ban' : e.department}\n${c.data.shifts.where((s) => s.id == e.shiftId).firstOrNull?.name ?? 'Chưa phân ca'}',
                  ),
                  trailing: !c.isAdmin
                      ? null
                      : PopupMenuButton<String>(
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
                                  SizedBox(width: 8),
                                  Text('Sửa thông tin'),
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
                                  SizedBox(width: 8),
                                  Text('Phân quyền (Admin / Quản lý / NV)'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'shift',
                              child: Row(
                                children: [
                                  Icon(Icons.access_time, size: 18),
                                  SizedBox(width: 8),
                                  Text('Phân ca làm việc'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle_lock',
                              child: Row(
                                children: [
                                  Icon(
                                    e.active
                                        ? Icons.lock_outline
                                        : Icons.lock_open,
                                    size: 18,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    e.active
                                        ? 'Khóa tài khoản'
                                        : 'Mở khóa tài khoản',
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Xóa tài khoản',
                                    style: TextStyle(color: Colors.red),
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
      Section(
        title: 'Ca làm việc',
        subtitle: 'Chạm vào ca để xem danh sách nhân sự đang phân ca',
        action: c.isAdmin
            ? IconButton(
                tooltip: 'Thêm ca',
                onPressed: () => editShift(),
                icon: const Icon(Icons.add),
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
                                child: Text('Sửa'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Xóa'),
                              ),
                            ],
                          ),
                  );
                }).toList(),
              ),
      ),
      Section(
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
                children: c.data.departments
                    .map(
                      (d) {
                        final count = c.data.employees
                            .where((e) => e.department.toLowerCase() == d.name.toLowerCase())
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
                                      child: Text('Sửa'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Xóa'),
                                    ),
                                  ],
                                ),
                        );
                      },
                    )
                    .toList(),
              ),
      ),
    ]);
  }

  Future<void> editDepartment([Department? d]) => editForm(
    context,
    title: d == null ? 'Thêm phòng ban mới' : 'Sửa phòng ban',
    fields: {
      'Tên phòng ban': d?.name ?? '',
      'Mô tả': d?.description ?? '',
    },
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
                desc: '• Quản trị nhân sự: Thêm, sửa, xóa, phân quyền, khóa tài khoản\n'
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
                desc: '• Xem danh sách nhân sự & ca làm việc (chỉ xem, không xóa/sửa)\n'
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
                desc: '• Chấm công vào / ra bằng GPS + QR văn phòng + Vân tay\n'
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Cho phép trễ tối đa: ${s.grace} phút',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.people_outline, size: 18, color: Color(0xFF087F8C)),
                  const SizedBox(width: 6),
                  Text(
                    'Nhân viên đang phân ca (${assignedEmps.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (assignedEmps.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Chưa có nhân viên nào được phân vào ca này.',
                    style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                )
              else
                for (final e in assignedEmps)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                  final names = assignedEmps.map((e) => '• ${e.name}').join('\n');
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

  Future<void> editOffice([Position? position]) async {
    final office = c.data.office;
    await editForm(
      context,
      title: 'Cấu hình văn phòng (GPS thập phân)',
      fields: {
        'Tên văn phòng': office.name,
        'Vĩ độ': (position?.latitude ?? office.latitude)?.toString() ?? '',
        'Kinh độ': (position?.longitude ?? office.longitude)?.toString() ?? '',
        'Bán kính (m)': '${office.radius.round()}',
      },
      save: (v) => c.saveOffice(
        Office(
          name: v['Tên văn phòng']!,
          latitude: double.tryParse(v['Vĩ độ']!),
          longitude: double.tryParse(v['Kinh độ']!),
          radius: double.tryParse(v['Bán kính (m)']!) ?? 0,
          qrSecret: office.qrSecret,
        ),
      ),
    );
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
    return list([
      _pageHint(
        'Kiểm tra bảng công',
        'Tìm theo nhân viên hoặc chọn khoảng ngày. Chạm vào bản ghi để xem giờ vào, giờ ra và vị trí.',
        Icons.fact_check_outlined,
      ),
      Section(
        title: 'Bảng công',
        subtitle:
            '${filtered.length} bản ghi • Giờ công là thời gian vào–ra, chưa trừ giờ nghỉ',
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm nhân viên, ca hoặc ngày',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    historyRange == null
                        ? 'Lọc ngày'
                        : '${dateLabel(historyRange!.start)} – ${dateLabel(historyRange!.end)}',
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
                if (historyRange != null)
                  TextButton(
                    onPressed: () => setState(() => historyRange = null),
                    child: const Text('Bỏ lọc'),
                  ),
                OutlinedButton.icon(
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
                              'Đã sao chép CSV. Dán vào file .csv UTF-8 để mở bằng Excel.',
                            );
                          }
                        },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Sao chép CSV'),
                ),
              ],
            ),
            const Divider(height: 28),
            if (filtered.isEmpty)
              const EmptyState('Chưa có bản ghi trong khoảng đã chọn.'),
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
        'Theo dõi đơn của bạn',
        'Chỉ đơn đang chờ mới được sửa hoặc xóa. Người quản lý không được tự duyệt đơn của mình.',
        Icons.assignment_outlined,
      ),
      Section(
        title: 'Đơn nghỉ & giải trình',
        subtitle: 'Đơn đã xử lý được giữ nguyên để đối chiếu',
        action: IconButton(
          tooltip: 'Tạo đơn',
          onPressed: () => editRequest(),
          icon: const Icon(Icons.add),
        ),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final item in {
                  'all': 'Tất cả',
                  'pending': 'Chờ duyệt',
                  'approved': 'Đã duyệt',
                  'rejected': 'Từ chối',
                }.entries)
                  ChoiceChip(
                    label: Text(item.value),
                    selected: requestFilter == item.key,
                    onSelected: (_) => setState(() => requestFilter = item.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty) const EmptyState('Chưa có đơn trong nhóm này.'),
            for (final r in items)
              Card(
                color: const Color(0xFFF3F6FA),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.type} • ${employeeName(r.employeeId)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text('${dateLabel(r.from)} → ${dateLabel(r.to)}'),
                      Text(r.reason),
                      const SizedBox(height: 8),
                      Text(
                        {
                          'pending': 'Chờ duyệt',
                          'approved': 'Đã duyệt',
                          'rejected': 'Từ chối',
                        }[r.status]!,
                        style: TextStyle(
                          color: r.status == 'approved'
                              ? Colors.teal
                              : r.status == 'rejected'
                              ? Colors.red.shade700
                              : Colors.brown,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (r.reviewerNote.isNotEmpty)
                        Text('Phản hồi: ${r.reviewerNote}'),
                      if (r.status == 'pending')
                        Wrap(
                          spacing: 8,
                          children: [
                            if (r.employeeId == c.user!.id) ...[
                              TextButton(
                                onPressed: () => editRequest(r),
                                child: const Text('Sửa'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  if (await confirm(context, 'Xóa đơn này?')) {
                                    await perform(() => c.deleteRequest(r.id));
                                  }
                                },
                                child: const Text('Xóa'),
                              ),
                            ],
                            if (c.isStaff && r.employeeId != c.user!.id) ...[
                              TextButton(
                                onPressed: () => review(r, true),
                                child: const Text('Duyệt'),
                              ),
                              TextButton(
                                onPressed: () => review(r, false),
                                child: const Text('Từ chối'),
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
              ),
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
      _pageHint(
        'Tài khoản & bảo mật',
        'Kiểm tra email nhận OTP và quản lý đăng nhập sinh trắc học trên thiết bị này.',
        Icons.shield_outlined,
      ),
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
                            Text(
                              roleName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: roleColor,
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
      BiometricSettingsCard(controller: c),

      const SizedBox(height: 14),

      // Card Vị trí GPS hiện tại
      Section(
        title: 'Vị trí hiện tại',
        subtitle: 'Chỉ thu thập khi bạn bấm nút để test GPS hoặc chấm công.',
        child: Column(
          children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                try {
                  final p = await acquirePosition();
                  if (!mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Tọa độ của bạn'),
                      content: SelectableText(
                        '${p.latitude}, ${p.longitude}\nSai số ±${p.accuracy.round()} m\nCó thể dùng tọa độ này để cấu hình văn phòng khi demo.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Đóng'),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  if (mounted) message(context, e);
                }
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Lấy tọa độ GPS thiết bị'),
            ),
          ],
        ),
      ),

      const SizedBox(height: 14),

      // Thông tin phiên bản & hệ thống
      Section(
        title: 'Hệ thống & Phiên bản',
        subtitle: 'Nhóm 09 • Tống Nhật Bảo An',
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '• Backend: ASP.NET Core 10 (Render Cloud + Neon PostgreSQL)\n• Xác thực: Mật khẩu + OTP Brevo HTTPS API + Biometric Secure Storage\n• Chấm công: GPS Geofencing + QR Code động mã hóa\n• Thống kê: Báo cáo AI Insights + Biểu đồ fl_chart',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),

      const SizedBox(height: 20),

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
      const SizedBox(height: 30),
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
        Column(
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class OfficeQrDialog extends StatefulWidget {
  final AppController controller;
  const OfficeQrDialog({super.key, required this.controller});
  @override
  State<OfficeQrDialog> createState() => _OfficeQrDialogState();
}

class _OfficeQrDialogState extends State<OfficeQrDialog> {
  Timer? timer;
  String? serverQr;
  @override
  void initState() {
    super.initState();
    _fetch();
    timer = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
  }

  Future<void> _fetch() async {
    try {
      final code = await widget.controller.fetchServerQr();
      if (mounted) setState(() => serverQr = code);
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now(),
        code = serverQr ?? widget.controller.officeQr(now);
    return AlertDialog(
      title: Text(widget.controller.data.office.name),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(data: code, size: 240, backgroundColor: Colors.white),
              const SizedBox(height: 8),
              const Text(
                'Mã QR động được ký số trực tiếp từ Server API. Hết hạn sau mỗi 1-2 phút.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    message(context, 'Đã sao chép mã QR server.');
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Sao chép mã QR này'),
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
