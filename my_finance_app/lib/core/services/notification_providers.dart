import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_suggestion.dart';

const _kPrefKey = 'notification_detection_enabled';
const _kAutoSaveKey = 'notification_auto_save_enabled';
const _kAllowedBanksKey = 'notification_allowed_banks';

// ── Known Brazilian bank apps ────────────────────────────────────────────────

class BankApp {
  final String packageName;
  final String displayName;

  const BankApp(this.packageName, this.displayName);
}

/// Comprehensive list of popular Brazilian bank apps.
const kKnownBanks = <BankApp>[
  BankApp('com.itau', 'Itaú'),
  BankApp('com.bradesco', 'Bradesco'),
  BankApp('br.com.bb.android', 'Banco do Brasil'),
  BankApp('br.com.gabba.Caixa', 'Caixa Econômica'),
  BankApp('com.nu.production', 'Nubank'),
  BankApp('br.com.intermedium', 'Inter'),
  BankApp('com.c6bank.app', 'C6 Bank'),
  BankApp('br.com.original.bank', 'Banco Original'),
  BankApp('com.picpay', 'PicPay'),
  BankApp('br.com.mercadopago.wallet', 'Mercado Pago'),
  BankApp('br.com.sicoob.app', 'Sicoob'),
  BankApp('br.com.santander.way', 'Santander'),
  BankApp('com.btgpactual.banking', 'BTG Pactual'),
  BankApp('br.com.pag.bank', 'PagBank / PagSeguro'),
  BankApp('br.com.next', 'Next'),
  BankApp('br.com.neon', 'Neon'),
  BankApp('com.will.app', 'Will Bank'),
  BankApp('com.modalmais', 'Modalmais'),
  BankApp('br.com.xpi.investor', 'XP Investimentos'),
  BankApp('com.stone.conta', 'Stone / Ton'),
  BankApp('br.com.safra.SafraWallet', 'Safra'),
  BankApp('br.com.daycoval.daymove', 'Daycoval'),
  BankApp('com.bancodigimais.app', 'Digio'),
  BankApp('br.com.ame', 'Ame Digital'),
  BankApp('com.samsung.android.spay', 'Samsung Wallet / Samsung Pay'),
  BankApp('com.google.android.apps.walletnfcrel', 'Google Wallet'),
];

// ── Detection toggle ─────────────────────────────────────────────────────────

/// Whether the notification-to-transaction detection is enabled by the user.
/// Persisted in SharedPreferences, defaults to true.
final notificationDetectionEnabledProvider =
    StateNotifierProvider<_NotificationDetectionNotifier, bool>(
  (ref) => _NotificationDetectionNotifier(),
);

class _NotificationDetectionNotifier extends StateNotifier<bool> {
  _NotificationDetectionNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kPrefKey) ?? true;
  }

  Future<void> toggle() async {
    final prefs = await SharedPreferences.getInstance();
    state = !state;
    await prefs.setBool(_kPrefKey, state);
  }

  Future<void> setValue(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    state = value;
    await prefs.setBool(_kPrefKey, value);
  }
}

// ── Auto-save toggle (pre-launch pending transactions) ──────────────────────

/// When enabled, detected notifications are saved automatically as pending
/// transactions instead of just showing a notification suggestion.
final notificationAutoSaveProvider =
    StateNotifierProvider<_AutoSaveNotifier, bool>(
  (ref) => _AutoSaveNotifier(),
);

class _AutoSaveNotifier extends StateNotifier<bool> {
  _AutoSaveNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kAutoSaveKey) ?? false;
  }

  Future<void> setValue(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    state = value;
    await prefs.setBool(_kAutoSaveKey, value);
  }
}

// ── Allowed banks selection ─────────────────────────────────────────────────

/// Set of package names the user has enabled for notification detection.
/// Defaults to all known banks enabled.
final allowedBanksProvider =
    StateNotifierProvider<_AllowedBanksNotifier, Set<String>>(
  (ref) => _AllowedBanksNotifier(),
);

class _AllowedBanksNotifier extends StateNotifier<Set<String>> {
  _AllowedBanksNotifier()
      : super(kKnownBanks.map((b) => b.packageName).toSet()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_kAllowedBanksKey);
    if (json != null) {
      final list = (jsonDecode(json) as List).cast<String>();
      state = list.toSet();
    }
  }

  Future<void> toggle(String packageName) async {
    final updated = {...state};
    if (updated.contains(packageName)) {
      updated.remove(packageName);
    } else {
      updated.add(packageName);
    }
    state = updated;
    await _save();
  }

  Future<void> setAll(bool enabled) async {
    if (enabled) {
      state = kKnownBanks.map((b) => b.packageName).toSet();
    } else {
      state = {};
    }
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAllowedBanksKey, jsonEncode(state.toList()));
  }
}

// ── Pending suggestion ──────────────────────────────────────────────────────

/// Holds the suggestion that came from tapping a local notification.
/// When non-null, the UI should open AddTransactionDialog pre-filled.
final pendingSuggestionProvider =
    StateProvider<NotificationSuggestion?>((ref) => null);
