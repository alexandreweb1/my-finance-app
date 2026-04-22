import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../domain/financial_score.dart';
import '../providers/financial_health_provider.dart';

class FinancialHealthScreen extends ConsumerWidget {
  const FinancialHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final score = ref.watch(financialScoreProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.financialHealthTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScoreHero(score: score),
              const SizedBox(height: 20),
              Text(l10n.financialHealthFactors,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...score.factors.map((f) => _FactorTile(factor: f)),
              if (score.recommendations.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(l10n.financialHealthRecommendations,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _RecommendationsCard(items: score.recommendations),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card with the circular gauge
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreHero extends StatelessWidget {
  final FinancialScore score;
  const _ScoreHero({required this.score});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _colorFor(score.level);
    final label = _labelFor(score.level, l10n);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(
              width: 160,
              height: 160,
              child: CustomPaint(
                painter: _GaugePainter(
                  progress: (score.score / 100).clamp(0.0, 1.0),
                  color: color,
                  trackColor:
                      Theme.of(context).dividerColor.withValues(alpha: 0.3),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(score.scoreRounded.toString(),
                          style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.bold,
                              color: color)),
                      Text('/ 100',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(l10n.financialHealthSubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _GaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) / 2) - stroke / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Sweep from 135° (lower-left) clockwise to 45° (lower-right) → 270° arc.
    const startAngle = 0.75 * math.pi * 2 - math.pi; // = 135°
    const sweepAll = 1.5 * math.pi; // 270°
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAll, false, track);
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle, sweepAll * progress, false, fill);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.progress != progress || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Factor breakdown
// ─────────────────────────────────────────────────────────────────────────────

class _FactorTile extends StatelessWidget {
  final ScoreFactor factor;
  const _FactorTile({required this.factor});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = factor.measured
        ? _factorColor(factor.value)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = _iconFor(factor.kind);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(_titleFor(factor.kind, l10n),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(
                  factor.measured
                      ? '${factor.value.round()} / 20'
                      : '—',
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: factor.measured
                    ? (factor.value / ScoreFactor.maxValue).clamp(0.0, 1.0)
                    : 0,
                backgroundColor:
                    Theme.of(context).dividerColor.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(factor.headline,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _RecommendationsCard extends StatelessWidget {
  final List<String> items;
  const _RecommendationsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items.map((tip) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.tips_and_updates_outlined,
                        size: 18, color: Color(0xFFFFA726)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(tip,
                            style: const TextStyle(fontSize: 13))),
                  ],
                ),
              )).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Color _colorFor(HealthLevel level) {
  switch (level) {
    case HealthLevel.excellent:
      return const Color(0xFF2E7D32);
    case HealthLevel.good:
      return const Color(0xFF66BB6A);
    case HealthLevel.fair:
      return const Color(0xFFFFA726);
    case HealthLevel.attention:
      return const Color(0xFFEF6C00);
    case HealthLevel.critical:
      return const Color(0xFFC62828);
  }
}

String _labelFor(HealthLevel level, AppLocalizations l10n) {
  switch (level) {
    case HealthLevel.excellent:
      return l10n.financialHealthLevelExcellent;
    case HealthLevel.good:
      return l10n.financialHealthLevelGood;
    case HealthLevel.fair:
      return l10n.financialHealthLevelFair;
    case HealthLevel.attention:
      return l10n.financialHealthLevelAttention;
    case HealthLevel.critical:
      return l10n.financialHealthLevelCritical;
  }
}

Color _factorColor(double value) {
  if (value >= 16) return const Color(0xFF2E7D32);
  if (value >= 12) return const Color(0xFF66BB6A);
  if (value >= 8) return const Color(0xFFFFA726);
  if (value >= 4) return const Color(0xFFEF6C00);
  return const Color(0xFFC62828);
}

IconData _iconFor(ScoreFactorKind kind) {
  switch (kind) {
    case ScoreFactorKind.savingsRate:
      return Icons.savings_outlined;
    case ScoreFactorKind.emergencyReserve:
      return Icons.shield_outlined;
    case ScoreFactorKind.budgetAdherence:
      return Icons.track_changes_outlined;
    case ScoreFactorKind.goalMomentum:
      return Icons.flag_outlined;
    case ScoreFactorKind.spendingConcentration:
      return Icons.donut_large_outlined;
    case ScoreFactorKind.investments:
      return Icons.trending_up_rounded;
  }
}

String _titleFor(ScoreFactorKind kind, AppLocalizations l10n) {
  switch (kind) {
    case ScoreFactorKind.savingsRate:
      return l10n.financialFactorSavingsRate;
    case ScoreFactorKind.emergencyReserve:
      return l10n.financialFactorEmergencyReserve;
    case ScoreFactorKind.budgetAdherence:
      return l10n.financialFactorBudgetAdherence;
    case ScoreFactorKind.goalMomentum:
      return l10n.financialFactorGoalMomentum;
    case ScoreFactorKind.spendingConcentration:
      return l10n.financialFactorSpendingConcentration;
    case ScoreFactorKind.investments:
      return 'Investimentos';
  }
}
