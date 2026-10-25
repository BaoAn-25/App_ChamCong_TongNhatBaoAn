import 'package:flutter/material.dart';

/// Bảng màu chuẩn dùng chung toàn bộ ứng dụng
class AppColors {
  // Màu thương hiệu & nền
  static const Color navy = Color(0xFF0B1F3A);
  static const Color teal = Color(0xFF0F7C8A);
  static const Color tealLight = Color(0xFF19A7B5);
  static const Color background = Color(0xFFF4F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color input = Color(0xFFEEF3F7);
  static const Color border = Color(0xFFDDE5EC);

  // Màu chữ
  static const Color textPrimary = Color(0xFF0B1F3A);
  static const Color textSecondary = Color(0xFF5B6B7C);

  // Màu trạng thái
  static const Color success = Color(0xFF2E9E6B);
  static const Color successBg = Color(0xFFE6F5EE);

  static const Color warning = Color(0xFFE0A100);
  static const Color warningBg = Color(0xFFFFF6DB);

  static const Color error = Color(0xFFD64545);
  static const Color errorBg = Color(0xFFFDECEC);

  static const Color info = Color(0xFF2F7FD0);
  static const Color infoBg = Color(0xFFEAF2FB);

  // Màu bổ sung cho Ra sớm (cam)
  static const Color orange = Color(0xFFE67E22);
  static const Color orangeBg = Color(0xFFFDF2E9);
}

/// Hệ thống Theme Material 3 dùng chung
class AppTheme {
  // Khoảng cách theo bội số 8
  static const double space8 = 8.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;

  // Bo góc chuẩn
  static final BorderRadius radiusCard = BorderRadius.circular(20);
  static final BorderRadius radiusButton = BorderRadius.circular(16);
  static final BorderRadius radiusInput = BorderRadius.circular(16);
  static final BorderRadius radiusChip = BorderRadius.circular(999);

  // Bóng đổ thẻ (blur 20, opacity 6%)
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: AppColors.navy.withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        primary: AppColors.teal,
        onPrimary: Colors.white,
        secondary: AppColors.tealLight,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),

      // Kiểu chữ chuẩn toàn app
      textTheme: const TextTheme(
        // Tiêu đề màn hình: 22/700
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        // Tiêu đề mục / section: 18/600
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        // Nội dung chính: 14
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textPrimary,
          height: 1.4,
        ),
        // Ghi chú / phụ đề: 12
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      ),

      // Cấu hình thẻ Card
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusCard,
          side: const BorderSide(color: AppColors.border, width: 0.8),
        ),
      ),

      // Ô nhập liệu: filled, không viền, viền teal 1.5 khi focus, đỏ khi lỗi
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
        border: OutlineInputBorder(
          borderRadius: radiusInput,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radiusInput,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radiusInput,
          borderSide: const BorderSide(color: AppColors.teal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radiusInput,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radiusInput,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),

      // Thanh điều hướng NavigationBar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.teal.withValues(alpha: 0.12),
        elevation: 3,
        shadowColor: AppColors.navy.withValues(alpha: 0.08),
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.teal,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.teal, size: 24);
          }
          return const IconThemeData(color: AppColors.textSecondary, size: 24);
        }),
      ),

      // AppBar
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),

      // Chip bo góc 999
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: radiusChip),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
    );
  }
}
