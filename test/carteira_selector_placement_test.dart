import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_finance_app/core/providers/effective_user_provider.dart';
import 'package:my_finance_app/core/providers/workspace_provider.dart';
import 'package:my_finance_app/features/auth/domain/entities/user_entity.dart';
import 'package:my_finance_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:my_finance_app/features/subscription/presentation/providers/subscription_provider.dart';
import 'package:my_finance_app/features/workspaces/domain/workspace_entity.dart';
import 'package:my_finance_app/features/workspaces/presentation/workspace_switcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layout regression coverage for CarteiraHeaderSelector.
//
// The pill used to live in exactly three roomy places (the navy dashboard
// header, the Planejamento AppBar title, the Ajustes SliverAppBar actions). It
// is now also placed in CROWDED toolbars — next to a back button, a screen
// title and other actions — on Extrato, Relatórios, Contas a pagar,
// Assinaturas, Investimentos, Saúde financeira, Regras de categorização,
// Importar and Exportar.
//
// That is only safe because the Carteira name is wrapped in a Flexible, so it
// ellipsizes under pressure instead of painting overflow stripes. These tests
// pin that down on the worst realistic surface: a 320dp phone, a long Carteira
// name, and a 1.3x text scale. A RenderFlex overflow reports a FlutterError,
// which tester.takeException() surfaces — so `takeException() == null` is the
// assertion that matters in every case below.
// ─────────────────────────────────────────────────────────────────────────────

const _kLongName = 'Consultoria e Holding Patrimonial Ltda';

WorkspaceEntity _ws(
  String id, {
  required String name,
  bool isDefault = false,
  int order = 0,
  WorkspaceType type = WorkspaceType.personal,
}) =>
    WorkspaceEntity(
      id: id,
      ownerId: 'owner1',
      name: name,
      type: type,
      memberUids: const ['owner1'],
      roles: const {'owner1': WorkspaceRole.editor},
      isDefault: isDefault,
      order: order,
      createdAt: DateTime(2020, 1, 1),
    );

/// Pumps [child] inside a ProviderScope where the active Carteira is a
/// business one named [name], at [size] logical pixels and [textScale].
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String name = _kLongName,
  Size size = const Size(320, 640),
  double textScale = 1.3,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final own = [
    _ws('pessoal', name: 'Pessoal', isDefault: true, order: 0),
    _ws('empresa', name: name, order: 1, type: WorkspaceType.business),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) =>
            Stream.value(const UserEntity(id: 'owner1', email: 't@t.co'))),
        userProfileStreamProvider.overrideWith(
            (ref) => Stream.value({'defaultWorkspaceId': 'pessoal'})),
        ownWorkspacesStreamProvider.overrideWith((ref) => Stream.value(own)),
        sharedWorkspacesStreamProvider
            .overrideWith((ref) => Stream.value(const [])),
        canUseWorkspacesProvider.overrideWithValue(true),
        isSubscriptionLoadingProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        // Mirrors lib/main.dart:359 — the global centered-title theme is part
        // of what the pill has to share the toolbar with.
        theme: ThemeData(appBarTheme: const AppBarTheme(centerTitle: true)),
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: w!,
        ),
        home: child,
      ),
    ),
  );
  // Let the workspace streams deliver so the pill renders the long name.
  await tester.pumpAndSettle();
}

/// Selects the non-default (business) Carteira so the pill shows the long name
/// plus the "PJ" badge — the widest state it can reach.
Future<void> _selectLongCarteira(WidgetTester tester) async {
  final element = tester.element(find.byType(CarteiraHeaderSelector));
  final container = ProviderScope.containerOf(element);
  await container.read(activeWorkspaceIdProvider.notifier).select('empresa');
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('CarteiraHeaderSelector fits its toolbar', () {
    testWidgets('title slot with two actions and a TabBar (Extrato)',
        (tester) async {
      await _pump(
        tester,
        DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 12,
              title: const Align(
                alignment: Alignment.centerLeft,
                child: CarteiraHeaderSelector(onDark: false),
              ),
              actions: [
                IconButton(icon: const Icon(Icons.search), onPressed: () {}),
                IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
              ],
              bottom: const TabBar(tabs: [
                Tab(text: 'Extrato'),
                Tab(text: 'Cartões'),
                Tab(text: 'Investimentos'),
              ]),
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      await _selectLongCarteira(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(CarteiraHeaderSelector), findsOneWidget);
    });

    testWidgets(
        'actions slot behind a back button and a long title '
        '(Regras de categorização)', (tester) async {
      await _pump(
        tester,
        Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const Text('Regras de categorização'),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: Center(child: CarteiraHeaderSelector(onDark: false)),
              ),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
      );
      await _selectLongCarteira(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('pinned SliverAppBar actions slot (Relatórios / Ajustes)',
        (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                centerTitle: false,
                title: Text('Relatórios',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                actions: [
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Center(child: CarteiraHeaderSelector(onDark: false)),
                  ),
                ],
              ),
              SliverToBoxAdapter(child: SizedBox(height: 800)),
            ],
          ),
        ),
      );
      await _selectLongCarteira(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navy dashboard header column (onDark) is unregressed',
        (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 40),
                CarteiraHeaderSelector(),
              ],
            ),
          ),
        ),
      );
      await _selectLongCarteira(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a 280dp viewport at 2.0x text scale', (tester) async {
      await _pump(
        tester,
        Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const Text('Importar extrato'),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: Center(child: CarteiraHeaderSelector(onDark: false)),
              ),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
        size: const Size(280, 640),
        textScale: 2.0,
      );
      await _selectLongCarteira(tester);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the pill announces itself as a Carteira switcher',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const Scaffold(
        body: Center(child: CarteiraHeaderSelector(onDark: false)),
      ),
    );
    await _selectLongCarteira(tester);
    expect(
      find.bySemanticsLabel('Trocar de Carteira: $_kLongName'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
