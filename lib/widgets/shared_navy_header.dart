import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_theme.dart';
import '../domain/app_controller.dart';
import '../domain/models.dart';

/// Hàm thuần tính lời chào theo giờ địa phương (local time)
/// 05:00 - 10:59: "Chào buổi sáng"
/// 11:00 - 12:59: "Chào buổi trưa"
/// 13:00 - 17:59: "Chào buổi chiều"
/// 18:00 - 04:59: "Chào buổi tối"
String getGreeting([DateTime? time]) {
  final now = (time ?? DateTime.now()).toLocal();
  final hour = now.hour;
  final minute = now.minute;
  final totalMinutes = hour * 60 + minute;

  if (totalMinutes >= 5 * 60 && totalMinutes <= 10 * 60 + 59) {
    return 'Chào buổi sáng';
  }
  if (totalMinutes >= 11 * 60 && totalMinutes <= 12 * 60 + 59) {
    return 'Chào buổi trưa';
  }
  if (totalMinutes >= 13 * 60 && totalMinutes <= 17 * 60 + 59) {
    return 'Chào buổi chiều';
  }
  return 'Chào buổi tối';
}

/// Widget hiển thị lời chào tự động cập nhật mỗi 1 phút và khi app quay lại từ nền
class GreetingText extends StatefulWidget {
  final TextStyle? style;
  const GreetingText({super.key, this.style});

  @override
  State<GreetingText> createState() => _GreetingTextState();
}

class _GreetingTextState extends State<GreetingText> with WidgetsBindingObserver {
  late String _greeting;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _greeting = getGreeting();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final current = getGreeting();
      if (current != _greeting && mounted) {
        setState(() => _greeting = current);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final current = getGreeting();
      if (current != _greeting && mounted) {
        setState(() => _greeting = current);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _greeting,
      style: widget.style ??
          const TextStyle(
            fontSize: 13,
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w500,
          ),
    );
  }
}

/// Widget Header xanh Navy đồng bộ dùng chung cho 4 màn hình của Nhân viên
class SharedNavyHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final AppController? controller;
  final Widget? customTrailing;
  final Widget? bottomContent;
  final double bottomPadding;

  const SharedNavyHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showSubtitle = true,
    this.controller,
    this.customTrailing,
    this.bottomContent,
    this.bottomPadding = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top + 16.0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          top: topPadding,
          left: 20,
          right: 20,
          bottom: bottomPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (showSubtitle) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle ??
                              (controller?.lastSyncedAt == null
                                  ? 'Chấm công thông minh • Nhóm 09'
                                  : 'Cập nhật ${clock(controller?.lastSyncedAt)} • Kéo để làm mới'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (customTrailing != null)
                  customTrailing!
                else ...[
                  if (controller != null)
                    IconButton(
                      tooltip: 'Làm mới dữ liệu',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: controller!.isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(
                              Icons.refresh_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                      onPressed: controller!.isSyncing
                          ? null
                          : () => controller!.syncAll(),
                    ),
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.badge_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Nhân viên',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            if (bottomContent != null) ...[
              const SizedBox(height: 16),
              bottomContent!,
            ],
          ],
        ),
      ),
    );
  }
}
