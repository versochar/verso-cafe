import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tasarım tokenları.
///
/// Renk ve tipografi tek yerden yönetilir; ekranlar ham `Color(...)`
/// kullanmaz. Palet bilinçli olarak nötr (siyaha yakın) ve tek vurgulu.
class AppColors {
  const AppColors._();

  static const background = Color(0xFF0A0A0B);
  static const surface = Color(0xFF121214);
  static const surfaceAlt = Color(0xFF18181B);
  static const line = Color(0xFF232327);
  static const lineStrong = Color(0xFF313136);

  static const text = Color(0xFFF4F4F5);
  static const textMuted = Color(0xFF8D8D95);
  static const textFaint = Color(0xFF5F5F67);

  /// Tek vurgu rengi. Butonlar, seçili durumlar ve bağlantı noktası.
  static const accent = Color(0xFFFF6B35);
  static const accentInk = Color(0xFF1A0B04);
  static const accentWash = Color(0x1FFF6B35);

  static const online = Color(0xFF4ADE80);
  static const warning = Color(0xFFFBBF24);
  static const offline = Color(0xFFEF4444);
}

/// 4pt tabanlı boşluk ölçeği.
class Insets {
  const Insets._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const huge = 48.0;

  static const page = EdgeInsets.symmetric(horizontal: 20);
}

class Radii {
  const Radii._();

  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;

  static const card = BorderRadius.all(Radius.circular(md));
  static const sheet = BorderRadius.vertical(top: Radius.circular(xl));
  static const pill = BorderRadius.all(Radius.circular(999));
}

class AppTheme {
  const AppTheme._();

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.accentInk,
      secondary: AppColors.accent,
      onSecondary: AppColors.accentInk,
      surface: AppColors.background,
      onSurface: AppColors.text,
      surfaceContainerHighest: AppColors.surfaceAlt,
      onSurfaceVariant: AppColors.textMuted,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
      error: AppColors.offline,
      onError: AppColors.text,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        toolbarHeight: 56,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: AppColors.background,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        iconTheme: IconThemeData(color: AppColors.text, size: 22),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.line,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textMuted, size: 20),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 15),
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: AppColors.textMuted),
        border: _border(AppColors.line),
        enabledBorder: _border(AppColors.line),
        focusedBorder: _border(AppColors.lineStrong, width: 1.4),
        errorBorder: _border(AppColors.offline),
        focusedErrorBorder: _border(AppColors.offline, width: 1.4),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.accentInk,
          disabledBackgroundColor: AppColors.surfaceAlt,
          disabledForegroundColor: AppColors.textFaint,
          elevation: 0,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          shape: const RoundedRectangleBorder(borderRadius: Radii.card),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.text,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.lineStrong),
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          shape: const RoundedRectangleBorder(borderRadius: Radii.card),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: BorderSide(color: AppColors.line),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: Radii.sheet),
        showDragHandle: false,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.card),
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        contentTextStyle: TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
          height: 1.45,
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.accent),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textMuted,
        textColor: AppColors.text,
        contentPadding: EdgeInsets.symmetric(horizontal: 0),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: Radii.card,
        borderSide: BorderSide(color: color, width: width),
      );

  static TextTheme _textTheme(TextTheme base) {
    return base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
            height: 1.15,
            color: AppColors.text,
          ),
          headlineSmall: base.headlineSmall?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            color: AppColors.text,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: AppColors.text,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
            color: AppColors.text,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: AppColors.text,
          ),
          bodyLarge: base.bodyLarge?.copyWith(
            fontSize: 15,
            height: 1.5,
            letterSpacing: -0.1,
            color: AppColors.text,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            fontSize: 14,
            height: 1.45,
            color: AppColors.text,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.4,
            color: AppColors.textMuted,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: AppColors.text,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
            color: AppColors.textFaint,
          ),
        )
        .apply(fontFamily: 'Roboto');
  }
}
