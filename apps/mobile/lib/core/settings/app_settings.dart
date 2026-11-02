/// Uygulama ayarları: tema, dil, font boyutu.
///
/// `KeyStorage` ile kalıcı, `ChangeNotifier` ile reaktif.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../identity/key_storage.dart';

enum ThemeModeOption { system, light, dark }
enum LanguageOption { tr, en }
enum FontSizeOption { small, medium, large }

class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  final KeyStorage _storage = KeyStorage();

  ThemeModeOption _themeMode = ThemeModeOption.system;
  LanguageOption _language = LanguageOption.tr;
  FontSizeOption _fontSize = FontSizeOption.medium;
  bool _initialized = false;

  ThemeModeOption get themeMode => _themeMode;
  LanguageOption get language => _language;
  FontSizeOption get fontSize => _fontSize;
  bool get initialized => _initialized;

  /// Sistem temasını algılar.
  ThemeMode get effectiveThemeMode {
    switch (_themeMode) {
      case ThemeModeOption.light:
        return ThemeMode.light;
      case ThemeModeOption.dark:
        return ThemeMode.dark;
      case ThemeModeOption.system:
        final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
        return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
    }
  }

  Locale get locale => Locale(_language.name);

  double get fontScaleFactor {
    switch (_fontSize) {
      case FontSizeOption.small:
        return 0.85;
      case FontSizeOption.medium:
        return 1.0;
      case FontSizeOption.large:
        return 1.15;
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _themeMode = ThemeModeOption.values.byName(await _storage.loadThemeMode());
    _language = LanguageOption.values.byName(await _storage.loadLanguage());
    _fontSize = FontSizeOption.values.byName(await _storage.loadFontSize());
    _initialized = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeModeOption mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _storage.saveThemeMode(mode.name);
    notifyListeners();
  }

  Future<void> setLanguage(LanguageOption lang) async {
    if (_language == lang) return;
    _language = lang;
    await _storage.saveLanguage(lang.name);
    notifyListeners();
  }

  Future<void> setFontSize(FontSizeOption size) async {
    if (_fontSize == size) return;
    _fontSize = size;
    await _storage.saveFontSize(size.name);
    notifyListeners();
  }

  /// Tüm ayarları sıfırla.
  Future<void> reset() async {
    _themeMode = ThemeModeOption.system;
    _language = LanguageOption.tr;
    _fontSize = FontSizeOption.medium;
    await _storage.saveThemeMode('system');
    await _storage.saveLanguage('tr');
    await _storage.saveFontSize('medium');
    notifyListeners();
  }
}

/// `MaterialApp` için tema verisi sağlar.
class AppThemeData {
  static ThemeData light(BuildContext context, double fontScale) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: const Color(0xFFFF6B35),
        onPrimary: Colors.white,
        secondary: const Color(0xFF7C6BF5),
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: const Color(0xFF1A1A2E),
        surfaceContainerHighest: const Color(0xFFF5F5F5),
        onSurfaceVariant: const Color(0xFF6B6B6B),
        outline: const Color(0xFFE0E0E0),
        outlineVariant: const Color(0xFFE0E0E0),
        error: const Color(0xFFE0577F),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    return _applyFontScale(base, fontScale);
  }

  static ThemeData dark(BuildContext context, double fontScale) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFFFF6B35),
        onPrimary: Colors.white,
        secondary: const Color(0xFF7C6BF5),
        onSecondary: Colors.white,
        surface: const Color(0xFF1A1A2E),
        onSurface: const Color(0xFFEAEAEA),
        surfaceContainerHighest: const Color(0xFF25253E),
        onSurfaceVariant: const Color(0xFF9E9E9E),
        outline: const Color(0xFF3A3A5A),
        outlineVariant: const Color(0xFF3A3A5A),
        error: const Color(0xFFE0577F),
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFF141420),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    return _applyFontScale(base, fontScale);
  }

  static ThemeData _applyFontScale(ThemeData theme, double scale) {
    final textTheme = theme.textTheme.apply(fontSizeFactor: scale);
    return theme.copyWith(textTheme: textTheme);
  }
}