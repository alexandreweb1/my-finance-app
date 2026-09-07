import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_finance_app/core/providers/effective_user_provider.dart';
import 'package:my_finance_app/core/providers/workspace_provider.dart';
import 'package:my_finance_app/features/auth/domain/entities/user_entity.dart';
import 'package:my_finance_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:my_finance_app/features/recurring/presentation/providers/recurring_provider.dart';
import 'package:my_finance_app/features/reports/presentation/report_export.dart';
import 'package:my_finance_app/features/reports/presentation/screens/reports_screen.dart';
import 'package:my_finance_app/features/subscription/presentation/providers/subscription_provider.dart';
import 'package:my_finance_app/features/transactions/domain/entities/transaction_entity.dart';
import 'package:my_finance_app/features/transactions/presentation/providers/transactions_provider.dart';
import 'package:my_finance_app/features/wallets/presentation/providers/wallets_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Exportação de relatórios: escolher escopo (gráfico aberto × todos) e formato
// (imagem × PDF), e a captura do widget virar PNG de verdade.
// ─────────────────────────────────────────────────────────────────────────────

TransactionEntity _tx({
  required String id,
  required double amount,
  required bool income,
  required DateTime date,
  String category = 'Mercado',
}) =>
    TransactionEntity(
      id: id,
      userId: 'owner1',
      title: 'tx $id',
      amount: amount,
      date: date,
      category: category,
      type: income ? TransactionType.income : TransactionType.expense,
      walletId: 'w1',
    );

Future<void> _pumpReports(WidgetTester tester, {bool isPro = true}) async {
  final now = DateTime.now();
  final txs = [
    _tx(id: '1', amount: 250, income: false, date: DateTime(now.year, now.month, 3)),
    _tx(id: '2', amount: 90, income: false, date: DateTime(now.year, now.month, 9), category: 'Transporte'),
    _tx(id: '3', amount: 4200, income: true, date: DateTime(now.year, now.month, 5), category: 'Salário'),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) =>
            Stream.value(const UserEntity(id: 'owner1', email: 'o@t.co'))),
        userProfileStreamProvider.overrideWith((ref) => Stream.value(const {})),
        ownWorkspacesStreamProvider.overrideWith((ref) => Stream.value(const [])),
        sharedWorkspacesStreamProvider
            .overrideWith((ref) => Stream.value(const [])),
        visibleTransactionsProvider.overrideWithValue(txs),
        walletsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        activeRecurrencesProvider.overrideWithValue(const []),
        isProProvider.overrideWithValue(isPro),
        isSubscriptionLoadingProvider.overrideWithValue(false),
      ],
      child: const MaterialApp(home: ReportsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    // A tela usa DateFormat com locale explícito; fora do app o main.dart não
    // rodou para inicializar os símbolos.
    await initializeDateFormatting('pt_BR');
  });

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Pro: exporta só o gráfico aberto', (tester) async {
    await _pumpReports(tester);

    await tester.tap(find.byTooltip('Exportar relatório'));
    await tester.pumpAndSettle();

    // A folha oferece os dois escopos e os dois formatos.
    expect(find.text('Só este gráfico'), findsOneWidget);
    expect(find.text('Todos os relatórios'), findsOneWidget);
    expect(find.text('Imagem (PNG)'), findsOneWidget);
    expect(find.text('PDF'), findsOneWidget);
    // O escopo "só este" mostra QUAL relatório está aberto.
    expect(find.text('Despesas por categoria'), findsWidgets);

    await tester.tap(find.text('Ver e compartilhar'));
    await tester.pumpAndSettle();

    expect(find.byType(ReportExportPreviewScreen), findsOneWidget);
    expect(find.text('Exportar relatório'), findsWidgets);
    expect(find.text('Compartilhar imagem'), findsOneWidget);
  });

  testWidgets('Pro: "todos os relatórios" gera as 4 seções em PDF',
      (tester) async {
    await _pumpReports(tester);

    await tester.tap(find.byTooltip('Exportar relatório'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todos os relatórios'));
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver e compartilhar'));
    await tester.pumpAndSettle();

    expect(find.text('Exportar 4 relatórios'), findsOneWidget);
    expect(find.text('Compartilhar PDF'), findsOneWidget);
    // Um título por relatório, com o sub-filtro atual de cada aba.
    expect(find.text('Despesas por categoria'), findsOneWidget);
    expect(find.text('Despesas do mês'), findsOneWidget);
    expect(find.text('Balanço mensal'), findsOneWidget);
    expect(find.text('Fluxo de caixa'), findsOneWidget);
  });

  testWidgets('grátis: exportar cai no paywall, não na folha de opções',
      (tester) async {
    await _pumpReports(tester, isPro: false);

    await tester.tap(find.byTooltip('Exportar relatório'));
    await tester.pumpAndSettle();

    expect(find.text('Só este gráfico'), findsNothing);
    expect(find.textContaining('Exportar relatórios'), findsWidgets);
  });

  testWidgets('seção fora da dobra também é capturada pintada', (tester) async {
    // O risco real do modo "todos os relatórios": as seções de baixo estão
    // fora da viewport. Se o boundary delas não estivesse pintado, o PNG sairia
    // em branco e o usuário compartilharia uma folha vazia sem perceber.
    const marker = Color(0xFF7C4DFF);
    final sections = [
      for (var i = 0; i < 4; i++)
        ReportExportSection(
          title: 'Relatório $i',
          period: 'SETEMBRO 2026',
          content: Container(
              height: 500, color: i == 3 ? marker : Colors.grey.shade300),
        ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: ReportExportPreviewScreen(
        sections: sections,
        initialFormat: ReportExportFormat.pdf,
      ),
    ));
    await tester.pumpAndSettle();

    final last = sections.last;
    expect(last.boundaryKey.currentContext, isNotNull,
        reason: 'a seção precisa estar montada mesmo fora da viewport');

    final pixels = await tester.runAsync(() async {
      final boundary = last.boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    });

    // A cor do bloco tem que estar nos pixels: prova que pintou, e que pintou
    // a seção certa.
    var found = false;
    for (var i = 0; i + 3 < pixels!.length; i += 4) {
      if (pixels[i] == marker.r * 255 &&
          pixels[i + 1] == marker.g * 255 &&
          pixels[i + 2] == marker.b * 255 &&
          pixels[i + 3] == 255) {
        found = true;
        break;
      }
    }
    expect(found, isTrue, reason: 'captura saiu em branco');
  });

  testWidgets('a seção da pré-visualização vira PNG de verdade',
      (tester) async {
    final section = ReportExportSection(
      title: 'Despesas por categoria',
      period: 'SETEMBRO 2026',
      content: Container(width: 260, height: 140, color: Colors.indigo),
    );

    await tester.pumpWidget(MaterialApp(
      home: ReportExportPreviewScreen(
        sections: [section],
        initialFormat: ReportExportFormat.image,
        walletLabel: 'Pessoal',
      ),
    ));
    await tester.pumpAndSettle();

    expect(section.boundaryKey.currentContext, isNotNull);
    expect(find.text('Pessoal'), findsOneWidget);

    final bytes = await tester.runAsync(() async {
      final boundary = section.boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });

    // PNG real, não um frame em branco de 1x1.
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(2000));
    expect(bytes.sublist(1, 4), equals('PNG'.codeUnits));

    // E o mesmo PNG vira um PDF válido (caminho do formato "PDF").
    final pdf = await tester.runAsync(() => buildReportPdf([bytes, bytes]));
    expect(pdf!.sublist(0, 4), equals('%PDF'.codeUnits));
    expect(pdf.length, greaterThan(bytes.length));
  });
}
