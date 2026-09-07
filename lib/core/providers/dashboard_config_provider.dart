import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Section enum ─────────────────────────────────────────────────────────────

enum DashboardSection {
  plan,
  insights,
  investments,
  safeToSpend,
  netWorth,
  incomeExpense,
  financialHealth,
  budgets,
  bills,
  wallets,
  recentTransactions,
  upcomingRecurring;

  String get id => name;

  String get label {
    switch (this) {
      case DashboardSection.plan:
        return 'Seu plano';
      case DashboardSection.insights:
        return 'Insights & Projeção';
      case DashboardSection.investments:
        return 'Investimentos';
      case DashboardSection.safeToSpend:
        return 'Pode Gastar';
      case DashboardSection.netWorth:
        return 'Patrimônio';
      case DashboardSection.bills:
        return 'Contas a pagar';
      case DashboardSection.incomeExpense:
        return 'Receitas & Despesas';
      case DashboardSection.financialHealth:
        return 'Saúde Financeira';
      case DashboardSection.budgets:
        return 'Resumo de Orçamentos';
      case DashboardSection.wallets:
        return 'Saldo por Conta';
      case DashboardSection.recentTransactions:
        return 'Últimas Transações';
      case DashboardSection.upcomingRecurring:
        return 'Próximas Recorrências';
    }
  }

  String get description {
    switch (this) {
      case DashboardSection.plan:
        return 'Seu perfil e o plano 50/30/20 do onboarding';
      case DashboardSection.insights:
        return 'Alertas de orçamento e projeção de fim de mês';
      case DashboardSection.investments:
        return 'Ganho/perda dos seus investimentos';
      case DashboardSection.safeToSpend:
        return 'Quanto você pode gastar com segurança';
      case DashboardSection.netWorth:
        return 'Seu patrimônio e a evolução nos últimos meses';
      case DashboardSection.bills:
        return 'Próximas contas a pagar e receber';
      case DashboardSection.incomeExpense:
        return 'Cards de receita e despesa do mês';
      case DashboardSection.financialHealth:
        return 'Score de 0 a 100 com seu nível atual';
      case DashboardSection.budgets:
        return 'Barra de progresso dos orçamentos';
      case DashboardSection.wallets:
        return 'Saldo individual por conta';
      case DashboardSection.recentTransactions:
        return 'Últimas 5 transações realizadas';
      case DashboardSection.upcomingRecurring:
        return 'Próximos lançamentos automáticos';
    }
  }

  static DashboardSection? fromId(String id) {
    for (final s in DashboardSection.values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

// ─── Config model ──────────────────────────────────────────────────────────────

class DashboardConfig {
  /// Ordered list of all sections; hidden ones are excluded from the view.
  final List<DashboardSection> order;

  /// Sections that are hidden (not rendered).
  final Set<DashboardSection> hidden;

  const DashboardConfig({
    required this.order,
    required this.hidden,
  });

  /// Seções ligadas de fábrica. TODAS as 12 continuam disponíveis (a ordem
  /// abaixo lista o conjunto inteiro) — o que muda é quantas aparecem sem o
  /// usuário pedir: a Home abria com tudo ligado e virava uma rolagem longa
  /// logo no primeiro acesso. Ficam ligadas as que respondem "como estou este
  /// mês?"; o resto entra por um toque em Personalizar.
  ///
  /// Três das visíveis já se escondem sozinhas quando não têm o que mostrar
  /// (plano do onboarding, insights e orçamentos), então na prática a Home
  /// nova abre com 2 a 5 blocos em vez de 9 a 12.
  static const Set<DashboardSection> defaultHidden = {
    DashboardSection.investments,
    DashboardSection.safeToSpend,
    DashboardSection.netWorth,
    DashboardSection.financialHealth,
    DashboardSection.bills,
    DashboardSection.wallets,
    DashboardSection.upcomingRecurring,
  };

  /// Default section order (padrão para todos os usuários). Mirrors the layout
  /// approved in the Personalizar Dashboard screen.
  static const DashboardConfig defaultConfig = DashboardConfig(
    order: [
      DashboardSection.plan, // Seu plano (recap do onboarding)
      DashboardSection.incomeExpense, // Receitas & Despesas
      DashboardSection.financialHealth, // Saúde Financeira
      DashboardSection.budgets, // Resumo de Orçamentos
      DashboardSection.insights, // Insights & Projeção
      DashboardSection.investments, // Investimentos
      DashboardSection.safeToSpend, // Pode Gastar
      DashboardSection.netWorth, // Patrimônio
      DashboardSection.bills, // Contas a pagar
      DashboardSection.wallets, // Saldo por Conta
      DashboardSection.recentTransactions, // Últimas Transações
      DashboardSection.upcomingRecurring, // Próximas Recorrências
    ],
    hidden: defaultHidden,
  );

  bool isVisible(DashboardSection s) => !hidden.contains(s);

  List<DashboardSection> get visibleSections =>
      order.where(isVisible).toList();

  /// Seções desligadas, na ordem em que apareceriam — o que o botão
  /// "Mostrar mais seções" da Home oferece.
  List<DashboardSection> get hiddenSections =>
      order.where((s) => !isVisible(s)).toList();

  DashboardConfig copyWith({
    List<DashboardSection>? order,
    Set<DashboardSection>? hidden,
  }) {
    return DashboardConfig(
      order: order ?? this.order,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, dynamic> toJson() => {
        'order': order.map((s) => s.id).toList(),
        'hidden': hidden.map((s) => s.id).toList(),
      };

  factory DashboardConfig.fromJson(Map<String, dynamic> json) {
    final orderIds = (json['order'] as List<dynamic>?)?.cast<String>() ?? [];
    final hiddenIds = (json['hidden'] as List<dynamic>?)?.cast<String>() ?? [];

    // Build order from stored IDs, appending any new sections not yet persisted.
    final orderedSections = <DashboardSection>[];
    for (final id in orderIds) {
      final s = DashboardSection.fromId(id);
      if (s != null) orderedSections.add(s);
    }
    for (final s in DashboardSection.values) {
      if (!orderedSections.contains(s)) orderedSections.add(s);
    }

    final hiddenSections = hiddenIds
        .map(DashboardSection.fromId)
        .whereType<DashboardSection>()
        .toSet();

    return DashboardConfig(order: orderedSections, hidden: hiddenSections);
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

// v2: rolled out the new default section order to every user (a saved v1 config
// is ignored, so everyone starts from the new default and can re-customize).
//
// A chave segue em v2 de propósito depois da simplificação do padrão: `_save()`
// só roda quando o usuário mexe em algo, então quem nunca personalizou não tem
// nada gravado e cai no novo padrão sozinho — e quem personalizou mantém o
// layout que escolheu em vez de ser resetado pelas nossas costas.
const _kPrefKey = 'dashboard_config_v2';

class DashboardConfigNotifier extends Notifier<DashboardConfig> {
  @override
  DashboardConfig build() {
    _load();
    return DashboardConfig.defaultConfig;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefKey);
    if (raw != null) {
      try {
        final config = DashboardConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        state = config;
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, jsonEncode(state.toJson()));
  }

  void reorder(int oldIndex, int newIndex) {
    final list = [...state.order];
    if (newIndex > oldIndex) newIndex--;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = state.copyWith(order: list);
    _save();
  }

  void toggle(DashboardSection section) {
    final hidden = {...state.hidden};
    if (hidden.contains(section)) {
      hidden.remove(section);
    } else {
      hidden.add(section);
    }
    state = state.copyWith(hidden: hidden);
    _save();
  }

  void reset() {
    state = DashboardConfig.defaultConfig;
    _save();
  }
}

final dashboardConfigProvider =
    NotifierProvider<DashboardConfigNotifier, DashboardConfig>(
        DashboardConfigNotifier.new);
