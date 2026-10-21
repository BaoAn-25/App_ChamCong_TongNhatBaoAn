import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';
import 'common.dart';
import 'punch_page.dart';

class HomePage extends StatefulWidget {
  final AppController controller;
  const HomePage({super.key, required this.controller});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int page = 0;
  String search = '', requestFilter = 'all';
  DateTimeRange? historyRange;
  AppController get c => widget.controller;
  List<Attendance> get records =>
      c.data.attendance
          .where((a) => c.isAdmin || a.employeeId == c.user!.id)
          .toList()
        ..sort((a, b) => b.checkIn.compareTo(a.checkIn));
  String employeeName(String id) =>
      c.data.employees.where((e) => e.id == id).firstOrNull?.name ??
      'Nhân viên đã xóa';
  Future<void> perform(
    Future<void> Function() work, [
    String success = 'Đã lưu thay đổi.',
  ]) async {
    try {
      await work();
      if (mounted) message(context, success);
    } catch (e) {
      if (mounted) message(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = [
      'Tổng quan',
      c.isAdmin ? 'Quản lý' : 'Chấm công',
      'Bảng công',
      'Đơn từ',
      'Tài khoản',
    ];
    final icons = [
      Icons.space_dashboard_outlined,
      c.isAdmin ? Icons.manage_accounts_outlined : Icons.fingerprint,
      Icons.calendar_month_outlined,
      Icons.assignment_outlined,
      Icons.person_outline,
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final content = switch (page) {
      0 => dashboard(),
      1 => c.isAdmin ? management() : PunchPage(controller: c),
      2 => history(),
      3 => requests(),
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
              'TỐNG NHẬT BẢO AN  /  NHÓM 09',
              style: TextStyle(fontSize: 10, letterSpacing: 1),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(
                c.isAdmin ? Icons.shield_outlined : Icons.badge_outlined,
                size: 17,
              ),
              label: Text(c.isAdmin ? 'Admin' : 'Nhân viên'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: const Color(0xFFE8F5E9),
            child: Row(
              children: [
                const Icon(Icons.cloud_done, size: 16, color: Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'MÁY CHỦ • ĐÃ KẾT NỐI API (${c.client.baseUrl}) • DỮ LIỆU THẬT',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2E7D32),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => c.syncAll(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.refresh, size: 18, color: Color(0xFF2E7D32)),
                  ),
                ),
              ],
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
              selectedIndex: page,
              onDestinationSelected: (v) => setState(() {
                page = v;
                search = '';
              }),
              destinations: List.generate(
                labels.length,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: labels[i],
                ),
              ),
            ),
    );
  }

  Widget list(List<Widget> children) =>
      ListView(padding: const EdgeInsets.all(20), children: children);
  Widget dashboard() {
    final today = records
        .where((a) => dayKey(a.checkIn) == dayKey(DateTime.now()))
        .toList();
    final pending = c.data.requests
        .where(
          (r) =>
              r.status == 'pending' &&
              (c.isAdmin || r.employeeId == c.user!.id),
        )
        .length;
    final month = records
        .where(
          (a) =>
              a.checkIn.year == DateTime.now().year &&
              a.checkIn.month == DateTime.now().month,
        )
        .toList();
    return list([
      Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF075B68), Color(0xFF119C9B)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateLabel(DateTime.now()),
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Text(
              'Xin chào, ${c.user!.name}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              c.isAdmin
                  ? 'Quản lý ca làm, đồng hành cùng đội ngũ.'
                  : 'Ghi nhận thời gian. Chủ động ngày làm việc.',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => setState(() => page = 1),
              icon: Icon(c.isAdmin ? Icons.tune : Icons.fingerprint),
              label: Text(
                c.isAdmin ? 'Quản lý nhân sự & văn phòng' : 'Chấm công ngay',
              ),
            ),
          ],
        ),
      ),
      LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            metric(
              c.isAdmin ? 'Nhân viên hoạt động' : 'Ca tháng này',
              c.isAdmin
                  ? '${c.data.employees.where((e) => e.active && !e.isAdmin).length}'
                  : '${month.length}',
              Icons.groups_outlined,
              box.maxWidth,
            ),
            metric(
              'Chấm công hôm nay',
              '${today.length}',
              Icons.today_outlined,
              box.maxWidth,
            ),
            metric(
              'Giờ đã hoàn tất / tháng',
              month
                  .fold<double>(0, (sum, a) => sum + a.hours)
                  .toStringAsFixed(1),
              Icons.schedule,
              box.maxWidth,
            ),
            metric(
              'Đơn chờ duyệt',
              '$pending',
              Icons.assignment_outlined,
              box.maxWidth,
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
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
                          '${c.isAdmin ? '${employeeName(a.employeeId)} • ' : ''}${dateLabel(a.checkIn)}',
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
  Widget metric(String title, String value, IconData icon, double width) =>
      SizedBox(
        width: width >= 700 ? (width - 36) / 4 : (width - 12) / 2,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: const Color(0xFF087F8C)),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
              ],
            ),
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
    title: Text(c.isAdmin ? employeeName(a.employeeId) : a.shiftName),
    subtitle: Text(
      '${dateLabel(a.checkIn)} • ${clock(a.checkIn)} → ${clock(a.checkOut)}\n${a.explanation}',
    ),
    isThreeLine: true,
    trailing: Text(
      a.checkOut == null ? 'Trong ca' : '${a.hours.toStringAsFixed(1)} h',
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
    final employees = c.data.employees
        .where(
          (e) => '${e.name} ${e.username} ${e.department}'
              .toLowerCase()
              .contains(search.toLowerCase()),
        )
        .toList();
    return list([
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
        title: 'Nhân viên',
        subtitle: '${c.data.employees.length} tài khoản trên thiết bị',
        action: IconButton(
          tooltip: 'Thêm nhân viên',
          onPressed: () => editEmployee(),
          icon: const Icon(Icons.person_add_alt),
        ),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm tên, tài khoản, phòng ban',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            const SizedBox(height: 12),
            if (employees.isEmpty)
              const EmptyState('Không có nhân viên phù hợp.'),
            for (final e in employees)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Icon(
                    e.isAdmin ? Icons.shield_outlined : Icons.person_outline,
                  ),
                ),
                title: Text(e.name),
                subtitle: Text(
                  '${e.username} • ${e.department.isEmpty ? 'Chưa có phòng ban' : e.department}\n${c.data.shifts.where((s) => s.id == e.shiftId).firstOrNull?.name ?? 'Chưa phân ca'}${e.active ? '' : ' • Đã khóa'}',
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'edit') {
                      editEmployee(e);
                    }
                    if (v == 'shift') {
                      assignShift(e);
                    }
                    if (v == 'delete' &&
                        await confirm(
                          context,
                          'Xóa tài khoản ${e.name}? Tài khoản đã có lịch sử chỉ có thể khóa.',
                        )) {
                      await perform(() => c.deleteEmployee(e.id));
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Sửa / khóa tài khoản'),
                    ),
                    PopupMenuItem(value: 'shift', child: Text('Phân ca')),
                    PopupMenuItem(value: 'delete', child: Text('Xóa')),
                  ],
                ),
              ),
          ],
        ),
      ),
      Section(
        title: 'Ca làm việc',
        subtitle: 'Hỗ trợ ca trong ngày và ca qua đêm',
        action: IconButton(
          tooltip: 'Thêm ca',
          onPressed: () => editShift(),
          icon: const Icon(Icons.add),
        ),
        child: c.data.shifts.isEmpty
            ? const EmptyState('Tạo ca rồi phân công cho nhân viên.')
            : Column(
                children: c.data.shifts
                    .map(
                      (s) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule),
                        title: Text(s.name),
                        subtitle: Text(
                          '${minuteText(s.startMinute)} – ${minuteText(s.endMinute)} • Cho phép trễ ${s.grace} phút${s.endMinute < s.startMinute ? ' • Qua đêm' : ''}',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              editShift(s);
                            } else if (await confirm(
                              context,
                              'Xóa ca ${s.name}?',
                            )) {
                              await perform(() => c.deleteShift(s.id));
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Sửa')),
                            PopupMenuItem(value: 'delete', child: Text('Xóa')),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    ]);
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
  Future<void> editEmployee([Employee? e]) => editForm(
    context,
    title: e == null ? 'Thêm nhân viên' : 'Sửa nhân viên',
    fields: {
      'Họ tên': e?.name ?? '',
      'Email': e?.email ?? '',
      'Tên đăng nhập': e?.username ?? '',
      'Phòng ban': e?.department ?? '',
      'Mật khẩu mới (để trống nếu giữ)': '',
      'Trạng thái (active / locked)': e?.active == false ? 'locked' : 'active',
    },
    passwords: {'Mật khẩu mới (để trống nếu giữ)'},
    save: (v) async {
      final active = v['Trạng thái (active / locked)'];
      if (active != 'active' && active != 'locked') {
        throw ArgumentError('Trạng thái phải là active hoặc locked.');
      }
      await c.saveEmployee(
        Employee(
          id: e?.id ?? newId(),
          name: v['Họ tên']!,
          email: v['Email']!,
          username: v['Tên đăng nhập']!,
          department: v['Phòng ban']!,
          role: e?.role ?? 'employee',
          active: active == 'active',
          shiftId: e?.shiftId,
        ),
        password: v['Mật khẩu mới (để trống nếu giữ)'],
      );
    },
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
                  (c.isAdmin || r.employeeId == c.user!.id) &&
                  (requestFilter == 'all' || r.status == requestFilter),
            )
            .toList()
          ..sort((a, b) => b.from.compareTo(a.from));
    return list([
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
                            if (c.isAdmin && r.employeeId != c.user!.id) ...[
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
  Widget profile() => list([
    Section(
      title: c.user!.name,
      subtitle: c.user!.isAdmin ? 'Quản trị viên' : 'Nhân viên',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tài khoản: ${c.user!.username}'),
          Text('Email: ${c.user!.email}'),
          Text(
            'Phòng ban: ${c.user!.department.isEmpty ? 'Chưa phân công' : c.user!.department}',
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              if (await confirm(context, 'Đăng xuất khỏi tài khoản này?')) {
                c.logout();
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    ),
    Section(
      title: 'Vị trí hiện tại',
      subtitle: 'Chỉ lấy vị trí khi bạn bấm nút. Không theo dõi nền.',
      child: FilledButton.tonalIcon(
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
        label: const Text('Lấy tọa độ GPS'),
      ),
    ),
    const Section(
      title: 'Về phiên bản này',
      child: Text(
        'Flutter / Dart • Nhóm 09\nAppChamCong_TongNhatBaoAn\n\nĐang chạy local, không đồng bộ giữa 4 máy. Email và OTP chỉ mô phỏng. QR đổi mỗi phút, chấp nhận thêm mã của phút trước. GPS và camera QR dùng phần cứng thật. Đăng nhập bằng khuôn mặt chưa được triển khai.\n\nChuyển sang Web API cần xác thực, kiểm tra quyền, thời gian server và kiểm tra QR tại backend. Dữ liệu lưu local chưa phù hợp cho chấm công thực tế.',
      ),
    ),
  ]);
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
