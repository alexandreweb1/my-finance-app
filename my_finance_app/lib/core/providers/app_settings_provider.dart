import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Currency
// ─────────────────────────────────────────────────────────────────────────────

enum AppCurrency {
  brl(code: 'BRL', symbol: 'R\$', locale: 'pt_BR', label: 'Real (BRL)'),
  usd(code: 'USD', symbol: '\$', locale: 'en_US', label: 'Dollar (USD)'),
  eur(code: 'EUR', symbol: '€', locale: 'eu', label: 'Euro (EUR)'),
  gbp(code: 'GBP', symbol: '£', locale: 'en_GB', label: 'Pound (GBP)'),
  ars(code: 'ARS', symbol: '\$', locale: 'es_AR', label: 'Peso Arg. (ARS)'),
  mxn(code: 'MXN', symbol: '\$', locale: 'es_MX', label: 'Peso Mex. (MXN)');

  final String code;
  final String symbol;
  final String locale;
  final String label;

  const AppCurrency({
    required this.code,
    required this.symbol,
    required this.locale,
    required this.label,
  });

  static AppCurrency fromCode(String code) =>
      AppCurrency.values.firstWhere(
        (c) => c.code == code,
        orElse: () => AppCurrency.brl,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Language / Locale
// ─────────────────────────────────────────────────────────────────────────────

enum AppLanguage {
  portuguese(locale: Locale('pt', 'BR'), label: 'Português', nativeLabel: 'Português'),
  english(locale: Locale('en', 'US'), label: 'English', nativeLabel: 'English'),
  spanish(locale: Locale('es', 'ES'), label: 'Español', nativeLabel: 'Español');

  final Locale locale;
  final String label;
  final String nativeLabel;

  const AppLanguage({
    required this.locale,
    required this.label,
    required this.nativeLabel,
  });

  static AppLanguage fromCode(String code) =>
      AppLanguage.values.firstWhere(
        (l) => l.locale.languageCode == code,
        orElse: () => AppLanguage.portuguese,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme mode
// ─────────────────────────────────────────────────────────────────────────────

enum AppThemeMode {
  system,
  light,
  dark;

  ThemeMode get flutterThemeMode {
    switch (this) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }

  static AppThemeMode fromString(String value) =>
      AppThemeMode.values.firstWhere(
        (m) => m.name == value,
        orElse: () => AppThemeMode.system,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings state
// ─────────────────────────────────────────────────────────────────────────────

class AppSettings {
  final AppCurrency currency;
  final AppLanguage language;
  final AppThemeMode themeMode;

  const AppSettings({
    this.currency = AppCurrency.brl,
    this.language = AppLanguage.portuguese,
    this.themeMode = AppThemeMode.system,
  });

  AppSettings copyWith({
    AppCurrency? currency,
    AppLanguage? language,
    AppThemeMode? themeMode,
  }) =>
      AppSettings(
        currency: currency ?? this.currency,
        language: language ?? this.language,
        themeMode: themeMode ?? this.themeMode,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  static const _keyCurrency = 'app_currency';
  static const _keyLanguage = 'app_language';
  static const _keyThemeMode = 'app_theme_mode';

  AppSettingsNotifier(AppSettings initial) : super(initial);

  Future<void> setCurrency(AppCurrency currency) async {
    state = state.copyWith(currency: currency);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrency, currency.code);
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = state.copyWith(language: language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, language.locale.languageCode);
  }

  Future<void> setThemeMode(AppThemeMode themeMode) async {
    state = state.copyWith(themeMode: themeMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyThemeMode, themeMode.name);
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final currencyCode = prefs.getString(_keyCurrency) ?? 'BRL';
    final languageCode = prefs.getString(_keyLanguage) ?? 'pt';
    final themeModeStr = prefs.getString(_keyThemeMode) ?? 'system';
    return AppSettings(
      currency: AppCurrency.fromCode(currencyCode),
      language: AppLanguage.fromCode(languageCode),
      themeMode: AppThemeMode.fromString(themeModeStr),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

/// Loaded synchronously from SharedPreferences before the app starts.
/// Override this in main() with the persisted value.
final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>(
  (ref) => AppSettingsNotifier(const AppSettings()),
);
