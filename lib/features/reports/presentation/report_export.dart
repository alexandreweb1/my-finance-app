import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'dart:io' show File;

// ─────────────────────────────────────────────────────────────────────────────
// Exportar relatórios como imagem ou PDF.
//
// Os gráficos são widgets Flutter (CustomPainter), então não dá para
// "redesenhá-los" no PDF: o caminho é capturar o pixel do próprio widget via
// RepaintBoundary e embutir o PNG. Por isso a exportação passa por uma tela de
// pré-visualização — é ela que monta e PINTA as seções escolhidas (inclusive as
// que não estavam abertas), que é o que a captura precisa.
// ─────────────────────────────────────────────────────────────────────────────

enum ReportExportScope {
  /// Só o gráfico aberto na tela, com os filtros e o período atuais.
  current,

  /// Todos os relatórios (Categorias, Evolução, Comparar e Fluxo), cada um no
  /// sub-filtro/período em que o usuário deixou.
  all,
}

enum ReportExportFormat { image, pdf }

class ReportExportChoice {
  final ReportExportScope scope;
  final ReportExportFormat format;

  const ReportExportChoice(this.scope, this.format);
}

/// Um relatório pronto para virar imagem: cabeçalho + gráfico já construído.
class ReportExportSection {
  final String title;
  final String period;
  final Widget content;

  /// Âncora da captura — cada seção vira uma imagem (ou uma página do PDF).
  final GlobalKey boundaryKey = GlobalKey();

  ReportExportSection({
    required this.title,
    required this.period,
    required this.content,
  });
}

/// Tema claro fixo para a exportação (espelha o seed do `_lightTheme` do
/// main.dart). O que sai daqui é compartilhado e impresso: um print de tela
/// escura fica ilegível no papel e pesado no chat de quem recebe.
/// Tema em que a exportação é renderizada. Quem monta as seções deve usar
/// ESTE ColorScheme nos gráficos — senão um usuário em tema escuro exporta
/// texto cinza-claro sobre fundo branco.
ThemeData get reportExportTheme => _kExportTheme;

final ThemeData _kExportTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
  useMaterial3: true,
);

// ─────────────────────────────────────────────────────────────────────────────
// Escolha do que exportar
// ─────────────────────────────────────────────────────────────────────────────

Future<ReportExportChoice?> showReportExportOptions(
  BuildContext context, {
  required String currentReportLabel,
}) {
  return showModalBottomSheet<ReportExportChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        _ReportExportOptionsSheet(currentReportLabel: currentReportLabel),
  );
}

class _ReportExportOptionsSheet extends StatefulWidget {
  final String currentReportLabel;

  const _ReportExportOptionsSheet({required this.currentReportLabel});

  @override
  State<_ReportExportOptionsSheet> createState() =>
      _ReportExportOptionsSheetState();
}

class _ReportExportOptionsSheetState extends State<_ReportExportOptionsSheet> {
  ReportExportScope _scope = ReportExportScope.current;
  ReportExportFormat _format = ReportExportFormat.image;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Exportar relatório',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _SheetLabel('O que exportar', cs: cs),
            _ChoiceTile(
              icon: Icons.insert_chart_outlined_rounded,
              title: 'Só este gráfico',
              subtitle: widget.currentReportLabel,
              selected: _scope == ReportExportScope.current,
              onTap: () => setState(() => _scope = ReportExportScope.current),
            ),
            _ChoiceTile(
              icon: Icons.dashboard_customize_outlined,
              title: 'Todos os relatórios',
              subtitle: 'Categorias, Evolução, Comparar e Fluxo',
              selected: _scope == ReportExportScope.all,
              onTap: () => setState(() => _scope = ReportExportScope.all),
            ),
            const SizedBox(height: 16),
            _SheetLabel('Formato', cs: cs),
            _ChoiceTile(
              icon: Icons.image_outlined,
              title: 'Imagem (PNG)',
              subtitle: 'Boa para WhatsApp e redes sociais',
              selected: _format == ReportExportFormat.image,
              onTap: () => setState(() => _format = ReportExportFormat.image),
            ),
            _ChoiceTile(
              icon: Icons.picture_as_pdf_outlined,
              title: 'PDF',
              subtitle: _scope == ReportExportScope.all
                  ? 'Um arquivo, uma página por relatório'
                  : 'Bom para imprimir ou anexar em e-mail',
              selected: _format == ReportExportFormat.pdf,
              onTap: () => setState(() => _format = ReportExportFormat.pdf),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .pop(ReportExportChoice(_scope, _format)),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Ver e compartilhar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  final String text;
  final ColorScheme cs;

  const _SheetLabel(this.text, {required this.cs});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: cs.onSurfaceVariant,
          ),
        ),
      );
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected ? cs.primaryContainer.withValues(alpha: 0.4) : null,
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, size: 20, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pré-visualização + compartilhamento
// ─────────────────────────────────────────────────────────────────────────────

class ReportExportPreviewScreen extends StatefulWidget {
  final List<ReportExportSection> sections;
  final ReportExportFormat initialFormat;

  /// Nome da Carteira ativa, impresso no cabeçalho de cada relatório.
  final String? walletLabel;

  const ReportExportPreviewScreen({
    super.key,
    required this.sections,
    required this.initialFormat,
    this.walletLabel,
  });

  @override
  State<ReportExportPreviewScreen> createState() =>
      _ReportExportPreviewScreenState();
}

class _ReportExportPreviewScreenState extends State<ReportExportPreviewScreen> {
  late ReportExportFormat _format = widget.initialFormat;
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      // Garante que tudo o que está na árvore já foi pintado — capturar um
      // boundary ainda sujo devolve imagem em branco.
      await WidgetsBinding.instance.endOfFrame;

      // 3x deixa o gráfico nítido em tela cheia; com vários relatórios, 2x
      // corta o arquivo pela metade sem diferença visível numa página A4 (e um
      // PDF de 20 MB não passa em anexo de e-mail).
      final ratio = widget.sections.length == 1 ? 3.0 : 2.0;
      final pngs = <Uint8List>[];
      for (final section in widget.sections) {
        pngs.add(await _capturePng(section.boundaryKey, pixelRatio: ratio));
      }

      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      if (_format == ReportExportFormat.pdf) {
        final bytes = await buildReportPdf(pngs);
        await Printing.sharePdf(
            bytes: bytes, filename: 'fintab_relatorio_$stamp.pdf');
      } else {
        await _shareImages(pngs, stamp);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Não consegui gerar o arquivo: $e'),
        backgroundColor: Colors.red.shade700,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImages(List<Uint8List> pngs, String stamp) async {
    String nameFor(int i) => pngs.length == 1
        ? 'fintab_relatorio_$stamp.png'
        : 'fintab_relatorio_${i + 1}_$stamp.png';

    if (kIsWeb) {
      await Share.shareXFiles([
        for (var i = 0; i < pngs.length; i++)
          XFile.fromData(pngs[i], name: nameFor(i), mimeType: 'image/png'),
      ]);
      return;
    }

    final dir = await getTemporaryDirectory();
    final files = <XFile>[];
    for (var i = 0; i < pngs.length; i++) {
      final file = File('${dir.path}/${nameFor(i)}');
      await file.writeAsBytes(pngs[i], flush: true);
      files.add(XFile(file.path, mimeType: 'image/png'));
    }
    await Share.shareXFiles(files, subject: 'Relatório Fintab');
  }

  @override
  Widget build(BuildContext context) {
    final isPdf = _format == ReportExportFormat.pdf;
    return Theme(
      data: _kExportTheme,
      child: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: cs.surfaceContainerLow,
          appBar: AppBar(
            title: Text(widget.sections.length == 1
                ? 'Exportar relatório'
                : 'Exportar ${widget.sections.length} relatórios'),
            backgroundColor: cs.surface,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            child: Column(
              children: [
                for (final section in widget.sections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ExportCard(
                      section: section,
                      walletLabel: widget.walletLabel,
                    ),
                  ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<ReportExportFormat>(
                    style: const ButtonStyle(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                          value: ReportExportFormat.image,
                          icon: Icon(Icons.image_outlined, size: 16),
                          label: Text('Imagem')),
                      ButtonSegment(
                          value: ReportExportFormat.pdf,
                          icon: Icon(Icons.picture_as_pdf_outlined, size: 16),
                          label: Text('PDF')),
                    ],
                    selected: {_format},
                    onSelectionChanged: _busy
                        ? null
                        : (v) => setState(() => _format = v.first),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _share,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.ios_share, size: 18),
                      label: Text(_busy
                          ? 'Gerando…'
                          : isPdf
                              ? 'Compartilhar PDF'
                              : widget.sections.length == 1
                                  ? 'Compartilhar imagem'
                                  : 'Compartilhar ${widget.sections.length} imagens'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// O bloco que de fato vira a imagem — o que está aqui dentro é o que sai.
class _ExportCard extends StatelessWidget {
  final ReportExportSection section;
  final String? walletLabel;

  const _ExportCard({required this.section, this.walletLabel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      key: section.boundaryKey,
      child: Container(
        color: cs.surface,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: 22,
                    height: 22,
                    filterQuality: FilterQuality.medium,
                    // Um asset que não carrega não pode derrubar a exportação
                    // inteira — o relatório vale sem o selo.
                    errorBuilder: (_, __, ___) => const SizedBox(width: 22),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Fintab',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const Spacer(),
                if (walletLabel != null && walletLabel!.isNotEmpty)
                  Flexible(
                    child: Text(
                      walletLabel!,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style:
                          TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(section.title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 2),
            Text(section.period,
                style: TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 0.4,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            section.content,
            const SizedBox(height: 14),
            Divider(height: 1, color: cs.outlineVariant),
            const SizedBox(height: 8),
            Text(
              'Gerado em ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} · Fintab',
              style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Captura / PDF
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List> _capturePng(GlobalKey key, {double pixelRatio = 3}) async {
  final object = key.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary) {
    throw StateError('relatório não está montado na tela');
  }
  final image = await object.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('imagem vazia');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Uma página A4 por relatório, com a imagem inteira dentro da margem.
Future<Uint8List> buildReportPdf(List<Uint8List> pngs) async {
  final doc = pw.Document();
  for (final png in pngs) {
    final image = pw.MemoryImage(png);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => pw.Center(
        child: pw.Image(image, fit: pw.BoxFit.contain),
      ),
    ));
  }
  return doc.save();
}
