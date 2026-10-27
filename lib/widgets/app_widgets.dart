import 'package:flutter/material.dart';
import '../core/app_theme.dart';

// ============================================================================
// 1. BOUNCING WIDGET (Hiệu ứng scale 0.97 khi nhấn)
// ============================================================================
class BouncingWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const BouncingWidget({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
  });

  @override
  State<BouncingWidget> createState() => _BouncingWidgetState();
}

class _BouncingWidgetState extends State<BouncingWidget> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return widget.child;
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}

// ============================================================================
// 2. APP CARD (Nền trắng, không viền, bo 24, bóng 2 lớp, padding 20, scale 0.97)
// ============================================================================
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.space20),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    Widget cardContent = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: AppTheme.radiusCard,
        boxShadow: AppTheme.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: AppTheme.radiusCard,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      return BouncingWidget(
        onTap: onTap,
        borderRadius: AppTheme.radiusCard,
        child: cardContent,
      );
    }
    return cardContent;
  }
}

// ============================================================================
// 3. SECTION HEADER (Tiêu đề 17/600 + Hành động bên phải)
// ============================================================================
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final VoidCallback? onAction;
  final String? actionText;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
    this.actionText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTheme.sectionTitle,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: AppTheme.captionSecondary,
                  ),
                ],
              ],
            ),
          ),
          if (action != null)
            action!
          else if (actionText != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.teal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionText!,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// 4. STATUS CHIP (Nền tint 12%, chữ đậm màu trạng thái, chấm tròn 6px, bo 999, cao 24)
// ============================================================================
class StatusChip extends StatelessWidget {
  final String status;
  final IconData? icon;

  const StatusChip(this.status, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final lower = status.trim().toLowerCase();

    Color textColor;
    Color bgColor;

    if (lower.contains('đúng giờ') || lower.contains('đã duyệt') || lower.contains('hoàn tất') || lower.contains('trong bán kính') || lower.contains('đã bật') || lower.contains('đã đăng ký')) {
      textColor = AppColors.success;
      bgColor = AppColors.successBg;
    } else if (lower.contains('đi trễ') || lower.contains('chờ duyệt') || lower.contains('chờ') || lower.contains('chưa kích hoạt')) {
      textColor = AppColors.warning;
      bgColor = AppColors.warningBg;
    } else if (lower.contains('ra sớm')) {
      textColor = AppColors.orange;
      bgColor = AppColors.orangeBg;
    } else if (lower.contains('thiếu giờ ra') || lower.contains('từ chối') || lower.contains('hủy') || lower.contains('ngoài bán kính') || lower.contains('thiết bị chưa hỗ trợ')) {
      textColor = AppColors.error;
      bgColor = AppColors.errorBg;
    } else {
      textColor = AppColors.info;
      bgColor = AppColors.infoBg;
    }

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppTheme.radiusChip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Chấm tròn 6px phía trước chữ
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: textColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            status,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. STAT CARD (Icon trong ô bo 12 kích thước 40, tint 12%, số 28/700 đếm lên 600ms, mũi tên khi bấm được)
// ============================================================================
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  final String? subtitle;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.iconColor = AppColors.teal,
    this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    // Trích xuất số từ chuỗi value nếu có để hỗ trợ hiệu ứng đếm lên 600ms
    final numMatch = RegExp(r'^(\d+(?:\.\d+)?)').firstMatch(value);
    final targetNum = numMatch != null ? double.tryParse(numMatch.group(1)!) : null;
    final suffix = numMatch != null ? value.substring(numMatch.end) : '';

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon trong ô bo 12 kích thước 40x40, nền tint 10-12%
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              if (onTap != null)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),

          // Số liệu lớn 28/700 với hiệu ứng đếm lên 600ms
          targetNum != null
              ? TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: targetNum),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, val, child) {
                    final isInt = targetNum % 1 == 0;
                    final formatted = isInt ? val.toInt().toString() : val.toStringAsFixed(1);
                    return Text(
                      '$formatted$suffix',
                      style: AppTheme.statNumber,
                    );
                  },
                )
              : Text(
                  value,
                  style: AppTheme.statNumber,
                ),

          const SizedBox(height: 4),

          // Nhãn 12 màu chữ phụ
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.captionSecondary,
          ),

          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// 6. EMPTY STATE (Icon lớn trong vòng tròn tint 72px + tiêu đề + mô tả + nút)
// ============================================================================
class EmptyState extends StatelessWidget {
  final String title;
  final String? description;
  final IconData icon;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  const EmptyState({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: AppTheme.space16, horizontal: AppTheme.space16),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Vòng tròn tint 72px với opacity 10%
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: AppColors.teal),
              ),
              const SizedBox(height: AppTheme.space12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTheme.sectionTitle,
              ),
              if (description != null) ...[
                const SizedBox(height: 6),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: AppTheme.captionSecondary.copyWith(height: 1.4),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: AppTheme.space20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 7. ERROR STATE (Vòng tròn tint 72px màu lỗi + nút Thử lại)
// ============================================================================
class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space32, horizontal: AppTheme.space24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Vòng tròn tint 72px đỏ
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, size: 34, color: AppColors.error),
            ),
            const SizedBox(height: AppTheme.space16),
            Text(
              'Đã xảy ra sự cố',
              style: AppTheme.sectionTitle.copyWith(color: AppColors.error),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.captionSecondary.copyWith(height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppTheme.space20),
              SecondaryButton(
                title: 'Thử lại',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 8. SKELETON LOADER (Shimmer / Pulse chuyển sắc mượt)
// ============================================================================
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const SkeletonLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(
              AppColors.input,
              AppColors.border,
              _anim.value,
            ),
            borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 9. PRIMARY BUTTON (Gradient Teal, Scale 0.97 khi nhấn, bo 16)
// ============================================================================
class PrimaryButton extends StatefulWidget {
  final String title;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double? width;
  final double height;

  const PrimaryButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width = double.infinity,
    this.height = 50.0,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [AppColors.teal, AppColors.tealLight],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: enabled ? null : AppColors.border,
          borderRadius: AppTheme.radiusButton,
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: AppColors.teal.withValues(alpha: 0.25),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? widget.onPressed : null,
            onHighlightChanged: (val) {
              if (enabled) setState(() => _pressed = val);
            },
            borderRadius: AppTheme.radiusButton,
            child: Center(
              child: widget.isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, color: Colors.white, size: 18),
                          const SizedBox(width: AppTheme.space8),
                        ],
                        Flexible(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 10. SECONDARY BUTTON (Nền trắng viền xám nhẹ, bo 16, Scale 0.97 khi nhấn)
// ============================================================================
class SecondaryButton extends StatelessWidget {
  final String title;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double? width;
  final double height;

  const SecondaryButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.icon,
    this.width,
    this.height = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    return BouncingWidget(
      onTap: onPressed,
      child: SizedBox(
        width: width,
        height: height,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.border, width: 1.2),
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusButton),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.teal),
                const SizedBox(width: AppTheme.space8),
              ],
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 11. APP HEADER MỚI (Gradient navy -> teal, đáy bo 28, cao 150, 2 vòng tròn trang trí)
// ============================================================================
class AppHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String roleName;
  final IconData roleIcon;
  final DateTime? lastUpdated;
  final VoidCallback? onRefresh;

  const AppHeader({
    super.key,
    required this.title,
    this.subtitle = 'Chấm công • Nhóm 09',
    this.roleName = 'Admin',
    this.roleIcon = Icons.shield_outlined,
    this.lastUpdated,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = lastUpdated == null
        ? 'Chưa cập nhật'
        : 'Cập nhật ${TimeOfDay.fromDateTime(lastUpdated!).format(context)}';

    return Container(
      width: double.infinity,
      height: 152,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.navy, AppColors.teal],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        child: Stack(
          children: [
            // Vòng tròn trang trí 1 ở góc phải (opacity 8%)
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            // Vòng tròn trang trí 2 ở góc phải (opacity 6%)
            Positioned(
              right: 60,
              top: 30,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),

            // Nội dung chính của Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.85),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Huy hiệu vai trò: nền trắng 16% opacity, viền mờ
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: AppTheme.radiusChip,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(roleIcon, size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              roleName.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Thời gian cập nhật 12px chữ trắng
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF6EE7B7),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.82),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      if (onRefresh != null) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: onRefresh,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.refresh_rounded,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 12. ANIMATED LIST ITEM (Fade + trượt lên 12px, trễ 40ms/mục, tối đa 8 mục)
// ============================================================================
class AnimatedListItem extends StatelessWidget {
  final int index;
  final Widget child;

  const AnimatedListItem({
    super.key,
    required this.index,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Giới hạn trễ tối đa 8 mục (8 * 40ms = 320ms)
    final effectiveIndex = index > 8 ? 8 : index;
    final delayMs = effectiveIndex * 40;

    return FutureBuilder(
      future: Future.delayed(Duration(milliseconds: delayMs)),
      builder: (context, snapshot) {
        final ready = snapshot.connectionState == ConnectionState.done;
        return AnimatedOpacity(
          opacity: ready ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: AnimatedSlide(
            offset: ready ? Offset.zero : const Offset(0, 0.08), // trượt lên ~12px
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: child,
          ),
        );
      },
    );
  }
}
