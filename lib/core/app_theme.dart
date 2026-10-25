import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bảng màu chuẩn dùng chung toàn bộ ứng dụng
class AppColors {
  // Màu thương hiệu & nền
  static const Color navy = Color(0xFF0B1F3A);
  static const Color teal = Color(0xFF0F7C8A);
  static const Color tealLight = Color(0xFF19A7B5);
  static const Color tealPill = Color(0xFFE3F3F5); // Viên thuốc chỉ báo thanh điều hướng
  static const Color background = Color(0xFFF4F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color input = Color(0xFFEEF3F7);
  static const Color border = Color(0xFFDDE5EC);
  static const Color gridLine = Color(0xFFE4EAF0); // Đường lưới nét đứt biểu đồ fl_chart

  // Màu chữ
  static const Color textPrimary = Color(0xFF0B1F3A);
  static const Color textSecondary = Color(0xFF5B6B7C);

  // Màu trạng thái & nền tint
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

/// Hệ thống Theme Material 3 dùng chung chuẩn hóa nhận diện thị giác
class AppTheme {
  // Khoảng cách theo chuẩn giao diện
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space28 = 28.0;
  static const double space32 = 32.0;

  // Bo góc chuẩn
  static final BorderRadius radiusCard = BorderRadius.circular(24);
  static final BorderRadius radiusButton = BorderRadius.circular(16);
  static final BorderRadius radiusInput = BorderRadius.circular(16);
  static final BorderRadius radiusChip = BorderRadius.circular(999);
  static const BorderRadius radiusSheet = BorderRadius.vertical(top: Radius.circular(28));
  static final BorderRadius radiusDialog = BorderRadius.circular(28);

  // Bóng đổ hai lớp của AppCard (blur 24 offset 8 opacity 6% và blur 4 offset 1 opacity 4%)
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: AppColors.navy.withValues(alpha: 0.06),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: AppColors.navy.withValues(alpha: 0.04),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  // Bóng đổ phía trên của thanh điều hướng (NavigationBar)
  static final List<BoxShadow> navBarShadow = [
    BoxShadow(
      color: AppColors.navy.withValues(alpha: 0.05),
      blurRadius: 16,
      offset: const Offset(0, -3),
    ),
  ];

  // ============================================================================
  // TYPOGRAPHY: Font Be Vietnam Pro hỗ trợ tiếng Việt toàn diện
  // ============================================================================
  static TextStyle get statNumber => GoogleFonts.beVietnamPro(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: AppColors.navy,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static TextStyle get screenTitle => GoogleFonts.beVietnamPro(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: -0.3,
      );

  static TextStyle get sectionTitle => GoogleFonts.beVietnamPro(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyRegular => GoogleFonts.beVietnamPro(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
        height: 1.4,
      );

  static TextStyle get captionSecondary => GoogleFonts.beVietnamPro(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  static TextStyle get navLabel => GoogleFonts.beVietnamPro(
        fontSize: 11,
        fontWeight: FontWeight.w600,
      );

  // ============================================================================
  // CẤU HÌNH THEME TOÀN ỨNG DỤNG
  // ============================================================================
  static ThemeData get theme {
    // Khởi tạo TextTheme cơ sở từ GoogleFonts.beVietnamProTextTheme
    final baseTextTheme = GoogleFonts.beVietnamProTextTheme();

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

      // Áp dụng font Be Vietnam Pro với thang chữ chuẩn
      textTheme: baseTextTheme.copyWith(
        displayLarge: statNumber,
        headlineSmall: screenTitle,
        titleMedium: sectionTitle,
        bodyMedium: bodyRegular,
        bodySmall: captionSecondary,
        labelSmall: navLabel,
      ),

      // Thẻ Card: nền trắng, không viền, bo 24
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusCard,
          side: BorderSide.none,
        ),
      ),

      // Ô nhập liệu: filled #EEF3F7, bo 16, không viền, viền teal 1.5 khi focus
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.input,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: GoogleFonts.beVietnamPro(
          fontSize: 14,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: GoogleFonts.beVietnamPro(
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

      // Thanh điều hướng: cao 68, viên thuốc teal nhạt #E3F3F5, nhãn 11/600
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.tealPill,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.beVietnamPro(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.teal,
            );
          }
          return GoogleFonts.beVietnamPro(
            fontSize: 11,
            fontWeight: FontWeight.w600,
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

      // Bottom Sheet: Bo đỉnh 28, nền trắng, scrim 40%
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: radiusSheet),
        modalBarrierColor: Colors.black.withValues(alpha: 0.40),
        dragHandleColor: AppColors.border,
        dragHandleSize: const Size(44, 4),
      ),

      // Dialog: Bo 28, nền trắng, scrim 40%
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radiusDialog),
        barrierColor: Colors.black.withValues(alpha: 0.40),
        titleTextStyle: GoogleFonts.beVietnamPro(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.beVietnamPro(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
          height: 1.4,
        ),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.beVietnamPro(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),

      // Chip bo tròn 999 với màu sắc và độ tương phản cao, không bao giờ bị trùng màu
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: radiusChip,
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        backgroundColor: const Color(0xFFF1F5F9),
        selectedColor: const Color(0xFFCCFBF1),
        disabledColor: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        labelStyle: GoogleFonts.beVietnamPro(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF334155), // Màu chữ unselected tương phản cao
        ),
        secondaryLabelStyle: GoogleFonts.beVietnamPro(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F766E), // Màu chữ selected Teal đậm nét
        ),
      ),
    );
  }
}
