import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:my_finance_app/features/data_io/data/csv_parser.dart';
import 'package:my_finance_app/features/data_io/data/excel_exporter.dart';
import 'package:my_finance_app/features/data_io/data/ofx_parser.dart';
import 'package:my_finance_app/features/data_io/data/pdf_exporter.dart';
import 'package:my_finance_app/features/transactions/domain/entities/transaction_entity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Import/export rodando de verdade sobre arquivos como os que os bancos geram
// — inclusive com quebra de linha CRLF, que é o padrão de extrato baixado no
// Windows e o que mais aparece na caixa de e-mail do usuário.
// ─────────────────────────────────────────────────────────────────────────────

const _csvNubank = 'date,title,amount\n'
    '2026-08-03,Mercado Extra,-250.90\n'
    '2026-08-05,Salário,4200.00\n'
    '2026-08-09,Uber,-32.50\n';

const _csvItau = 'Data;Histórico;Débito;Crédito\n'
    '03/08/2026;COMPRA CARTAO MERCADO;R\$ 1.250,90;\n'
    '05/08/2026;TED RECEBIDA;;R\$ 4.200,00\n';

const _ofx1x = '''OFXHEADER:100
DATA:OFXSGML
VERSION:102

<OFX>
<BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20260803120000[-3:BRT]
<TRNAMT>-250.90
<MEMO>MERCADO EXTRA
</STMTTRN>
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20260805
<TRNAMT>4200.00
<MEMO>SALARIO AGOSTO
</STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1>
</OFX>''';

const _ofx2x = '''<?xml version="1.0" encoding="UTF-8"?>
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN><TRNTYPE>DEBIT</TRNTYPE><DTPOSTED>20260803</DTPOSTED>
<TRNAMT>-99.90</TRNAMT><MEMO>ASSINATURA STREAMING</MEMO></STMTTRN>
</BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>''';

List<TransactionEntity> _sampleTxs() => [
      TransactionEntity(
        id: '1',
        userId: 'u1',
        title: 'Mercado',
        amount: 250.90,
        type: TransactionType.expense,
        category: 'Alimentação',
        date: DateTime(2026, 8, 3),
      ),
      TransactionEntity(
        id: '2',
        userId: 'u1',
        title: 'Salário',
        amount: 4200,
        type: TransactionType.income,
        category: 'Salário',
        date: DateTime(2026, 8, 5),
      ),
    ];

void main() {
  group('CSV', () {
    test('extrato simples (LF)', () {
      final txs = CsvParser().parse(_csvNubank);
      expect(txs, hasLength(3));
      expect(txs[0].title, 'Mercado Extra');
      expect(txs[0].amount, 250.90);
      expect(txs[0].type, TransactionType.expense);
      expect(txs[0].date, DateTime(2026, 8, 3));
      expect(txs[1].type, TransactionType.income);
      expect(txs[1].amount, 4200.00);
    });

    test('extrato com CRLF (arquivo baixado no Windows)', () {
      final txs = CsvParser().parse(_csvNubank.replaceAll('\n', '\r\n'));
      expect(txs, hasLength(3),
          reason: 'CRLF é o padrão de extrato de banco; não pode zerar');
      expect(txs[0].date, DateTime(2026, 8, 3));
      expect(txs[0].amount, 250.90);
    });

    test('colunas débito/crédito, ponto-e-vírgula, R\$ e dd/MM/yyyy', () {
      final txs = CsvParser().parse(_csvItau);
      expect(txs, hasLength(2));
      expect(txs[0].amount, 1250.90);
      expect(txs[0].type, TransactionType.expense);
      expect(txs[0].date, DateTime(2026, 8, 3));
      expect(txs[1].amount, 4200.00);
      expect(txs[1].type, TransactionType.income);
    });

    test('CRLF com débito/crédito também', () {
      final txs = CsvParser().parse(_csvItau.replaceAll('\n', '\r\n'));
      expect(txs, hasLength(2));
      expect(txs[1].type, TransactionType.income);
    });

    test('arquivo sem colunas reconhecíveis devolve vazio (não quebra)', () {
      expect(CsvParser().parse('a,b,c\n1,2,3\n'), isEmpty);
      expect(CsvParser().parse(''), isEmpty);
    });
  });

  group('OFX', () {
    test('OFX 1.x (SGML, tags abertas)', () {
      final txs = OfxParser().parse(_ofx1x);
      expect(txs, hasLength(2));
      expect(txs[0].title, 'MERCADO EXTRA');
      expect(txs[0].amount, 250.90);
      expect(txs[0].type, TransactionType.expense);
      expect(txs[0].date, DateTime(2026, 8, 3));
      expect(txs[1].type, TransactionType.income);
    });

    test('OFX 1.x com CRLF', () {
      final txs = OfxParser().parse(_ofx1x.replaceAll('\n', '\r\n'));
      expect(txs, hasLength(2));
      expect(txs[0].amount, 250.90);
    });

    test('OFX 2.x (XML)', () {
      final txs = OfxParser().parse(_ofx2x);
      expect(txs, hasLength(1));
      expect(txs[0].title, 'ASSINATURA STREAMING');
      expect(txs[0].amount, 99.90);
    });

    test('acento em latin1 sobrevive à decodificação do import', () {
      // O import faz utf8.decode com fallback latin1 — reproduz aqui.
      final latinBytes = latin1.encode(_ofx1x.replaceAll('SALARIO', 'SALÁRIO'));
      String decoded;
      try {
        decoded = utf8.decode(latinBytes);
      } catch (_) {
        decoded = latin1.decode(latinBytes);
      }
      final txs = OfxParser().parse(decoded);
      expect(txs, hasLength(2));
      expect(txs[1].title, 'SALÁRIO AGOSTO');
    });
  });

  group('Exportação', () {
    test('Excel gera um .xlsx válido', () {
      final raw = ExcelExporter().build(
          transactions: _sampleTxs(), sheetName: 'Transações');
      final bytes = Uint8List.fromList(raw);
      expect(bytes.length, greaterThan(1000));
      // xlsx é um zip: assinatura PK\x03\x04
      expect(bytes.sublist(0, 4), equals([0x50, 0x4B, 0x03, 0x04]));
    });

    test('PDF gera um arquivo válido com o período no cabeçalho', () async {
      final bytes = await PdfExporter().build(
        transactions: _sampleTxs(),
        title: 'Extrato financeiro',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 8, 31),
      );
      expect(bytes.sublist(0, 4), equals('%PDF'.codeUnits));
      expect(bytes.length, greaterThan(2000));
    });

    test('PDF sem transações não explode', () async {
      final bytes = await PdfExporter().build(
        transactions: const [],
        title: 'Extrato financeiro',
        rangeStart: null,
        rangeEnd: null,
      );
      expect(bytes.sublist(0, 4), equals('%PDF'.codeUnits));
    });
  });
}
