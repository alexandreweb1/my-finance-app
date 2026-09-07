import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_finance_app/core/providers/dashboard_config_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// A Home abre com menos blocos — mas sem PERDER nenhum: os 12 continuam na
// lista de Personalizar, só que a maioria começa desligada.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nenhuma seção sumiu: o padrão lista as 12', () {
    expect(DashboardConfig.defaultConfig.order.toSet(),
        equals(DashboardSection.values.toSet()));
    expect(DashboardConfig.defaultConfig.order.length,
        DashboardSection.values.length);
  });

  test('o padrão abre só com o essencial do mês', () {
    expect(
      DashboardConfig.defaultConfig.visibleSections,
      equals(const [
        DashboardSection.plan,
        DashboardSection.incomeExpense,
        DashboardSection.budgets,
        DashboardSection.insights,
        DashboardSection.recentTransactions,
      ]),
    );
    // O resto continua acessível, listado na ordem em que voltaria.
    expect(DashboardConfig.defaultConfig.hiddenSections, hasLength(7));
  });

  test('uma seção desligada volta com um toque', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(dashboardConfigProvider.notifier);

    expect(
        container
            .read(dashboardConfigProvider)
            .isVisible(DashboardSection.netWorth),
        isFalse);
    notifier.toggle(DashboardSection.netWorth);
    expect(
        container
            .read(dashboardConfigProvider)
            .isVisible(DashboardSection.netWorth),
        isTrue);
  });

  test('quem já personalizou não é resetado pelo novo padrão', () {
    // Config gravada por um usuário que ligou tudo e escondeu só o plano.
    final saved = DashboardConfig.fromJson({
      'order': DashboardSection.values.map((s) => s.id).toList(),
      'hidden': [DashboardSection.plan.id],
    });

    expect(saved.hidden, equals({DashboardSection.plan}));
    expect(saved.isVisible(DashboardSection.netWorth), isTrue,
        reason: 'a escolha do usuário manda, não o padrão novo');
    expect(saved.visibleSections, hasLength(11));
  });

  test('resetar leva de volta ao padrão enxuto', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(dashboardConfigProvider.notifier);

    notifier.toggle(DashboardSection.netWorth);
    notifier.toggle(DashboardSection.wallets);
    notifier.reset();

    expect(container.read(dashboardConfigProvider).hidden,
        equals(DashboardConfig.defaultHidden));
  });
}
