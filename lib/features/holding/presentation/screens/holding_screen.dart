import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/providers/consolidated_balance_provider.dart';
import '../../../../core/utils/cents.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../workspaces/domain/workspace_entity.dart';
import '../../../workspaces/presentation/workspace_switcher.dart';
import '../../domain/holding_entities.dart';
import '../../domain/holding_math.dart';
import '../providers/holding_provider.dart';
import '../widgets/holding_dialogs.dart';

/// Money coming TO a sócio (saldo a receber, an aporte). Same green the
/// investment and reserve surfaces already use, so "positive" reads the same
/// everywhere in the app.
const _kGreen = Color(0xFF00A86B);

/// The Holding's main surface: who the sócios are, what each of them put in,
/// how much of the patrimônio is theirs, and who owes whom.
///
/// Read-only for everyone except the Carteira's owner. A collaborator with
/// editor rights can still add ordinary transactions to the Holding, but the
/// equity itself — who is a sócio, what their quota is, what they contributed —
/// is the owner's to declare; letting a guest rewrite it would silently change
/// how much every other sócio owns.
class HoldingScreen extends ConsumerWidget {
  const HoldingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final holding = ref.watch(activeHoldingProvider);
    final membersAsync = ref.watch(holdingMembersStreamProvider);
    final members = ref.watch(holdingActiveMembersProvider);
    final uid = ref.watch(authStateProvider).value?.id;
    final isOwner = holding != null && uid != null && holding.ownerId == uid;

    // The stream resolves to an empty list (never an error) when no Holding is
    // active, so "loading" is only meaningful while a value has never arrived.
    final loading =
        holding != null && membersAsync.isLoading && membersAsync.value == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.holdingTitle),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(child: CarteiraHeaderSelector(onDark: false)),
          ),
        ],
      ),
      // No sócios means there is nothing to attribute an aporte to; the empty
      // state offers "Adicionar sócio" instead.
      floatingActionButton: (isOwner && members.isNotEmpty)
          ? FloatingActionButton.extended(
              heroTag: 'holding_add_contribution',
              onPressed: () => _startContribution(context, ref, members),
              icon: const Icon(Icons.add),
              label: Text(l10n.holdingAddContribution),
            )
          : null,
      body: holding == null
          ? _NotAHolding(l10n: l10n)
          : loading
              ? const Center(child: CircularProgressIndicator())
              : members.isEmpty
                  ? _EmptyPartners(l10n: l10n, isOwner: isOwner)
                  : _HoldingBody(isOwner: isOwner),
    );
  }

  /// Asks WHO the aporte belongs to before opening the dialog.
  ///
  /// With a single sócio the question has one answer, so it is skipped — an
  /// extra tap that can only produce one outcome is friction, not safety.
  Future<void> _startContribution(
    BuildContext context,
    WidgetRef ref,
    List<HoldingMemberEntity> members,
  ) async {
    if (members.length == 1) {
      showAddContributionDialog(context, ref, memberId: members.first.id);
      return;
    }
    final l10n = AppLocalizations.of(context);
    final sorted = _byName(members);
    final memberId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                l10n.holdingAddContribution,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            ...sorted.map((m) => ListTile(
                  leading: _Avatar(name: m.name, seed: m.id),
                  title: Text(m.name),
                  onTap: () => Navigator.of(ctx).pop(m.id),
                )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (memberId == null || !context.mounted) return;
    showAddContributionDialog(context, ref, memberId: memberId);
  }
}

/// Display order: alphabetical, id as tiebreaker.
///
/// Deliberately a COPY sorted by name for the eye only —
/// [holdingActiveMembersProvider] is ordered by id because the largest-
/// remainder allocation depends on that order, and reordering it here would
/// move centavos every time somebody was renamed.
List<HoldingMemberEntity> _byName(List<HoldingMemberEntity> members) {
  final out = [...members];
  out.sort((a, b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return out;
}

class _HoldingBody extends ConsumerWidget {
  final bool isOwner;
  const _HoldingBody({required this.isOwner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      children: [
        const _HeaderCard(),
        const SizedBox(height: 12),
        const _StaleSplitsWarning(),
        if (isOwner) ...[
          const _QuotaModeCard(),
          const SizedBox(height: 12),
        ] else ...[
          _ReadOnlyNote(l10n: l10n),
          const SizedBox(height: 12),
        ],
        _PartnersSection(isOwner: isOwner),
        const SizedBox(height: 16),
        const _BalancesSection(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header — patrimônio × total aportado
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCard extends ConsumerWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final fmt = ref.watch(currencyFormatterProvider);
    final netWorth = ref.watch(holdingNetWorthCentsProvider);
    final totals = ref.watch(holdingContributionTotalsProvider);
    final contributed = totals.values.fold<Cents>(0, (a, b) => a + b);
    // A consolidated total across currencies is an FX product: it moves every
    // time rates refresh. Saying so is the difference between a number the
    // user can act on and one they will think is wrong tomorrow.
    final approximate = ref.watch(hasMultipleCurrenciesProvider);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.primaryContainer.withValues(alpha: 0.30),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HeaderMetric(
                  label: l10n.holdingNetWorth,
                  value: fmt(toReais(netWorth)),
                  emphasis: true,
                  footnote: approximate ? l10n.holdingApproxFx : null,
                  footnoteTooltip:
                      approximate ? l10n.holdingApproxFxHint : null,
                ),
              ),
              VerticalDivider(
                width: 24,
                thickness: 1,
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
              Expanded(
                child: _HeaderMetric(
                  label: l10n.holdingTotalContributed,
                  value: fmt(toReais(contributed)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasis;
  final String? footnote;
  final String? footnoteTooltip;

  const _HeaderMetric({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.footnote,
    this.footnoteTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final note = footnote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: emphasis ? 22 : 19,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 3),
          Tooltip(
            message: footnoteTooltip ?? note,
            triggerMode: TooltipTriggerMode.tap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 12, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    note,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stale rateios
// ─────────────────────────────────────────────────────────────────────────────

class _StaleSplitsWarning extends ConsumerWidget {
  const _StaleSplitsWarning();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(holdingStaleSplitCountProvider);
    if (n == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, size: 18, color: cs.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.holdingStaleSplits(n),
                style: TextStyle(fontSize: 12, color: cs.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quota mode (owner only)
// ─────────────────────────────────────────────────────────────────────────────

class _QuotaModeCard extends ConsumerWidget {
  const _QuotaModeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final holding = ref.watch(activeHoldingProvider);
    if (holding == null) return const SizedBox.shrink();
    final mode = holding.quotaMode;
    final busy = ref.watch(holdingNotifierProvider).isLoading;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.holdingQuotaMode,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<HoldingQuotaMode>(
                segments: [
                  ButtonSegment(
                    value: HoldingQuotaMode.proportional,
                    icon: const Icon(Icons.pie_chart_outline_rounded, size: 16),
                    label: Text(l10n.holdingQuotaProportional),
                  ),
                  ButtonSegment(
                    value: HoldingQuotaMode.fixed,
                    icon: const Icon(Icons.percent_rounded, size: 16),
                    label: Text(l10n.holdingQuotaFixed),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                onSelectionChanged: busy
                    ? null
                    : (s) => ref
                        .read(holdingNotifierProvider.notifier)
                        .setQuotaMode(s.first),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mode == HoldingQuotaMode.fixed
                  ? l10n.holdingQuotaFixedHint
                  : l10n.holdingQuotaProportionalHint,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyNote extends StatelessWidget {
  final AppLocalizations l10n;
  const _ReadOnlyNote({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.holdingReadOnly,
            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sócios
// ─────────────────────────────────────────────────────────────────────────────

class _PartnersSection extends ConsumerWidget {
  final bool isOwner;
  const _PartnersSection({required this.isOwner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final members = _byName(ref.watch(holdingActiveMembersProvider));
    final totals = ref.watch(holdingContributionTotalsProvider);
    final table = ref.watch(holdingQuotaTableProvider);
    final patrimony = ref.watch(holdingPatrimonyProvider);
    final gaps = ref.watch(holdingContributionGapsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(
          l10n.holdingPartners,
          trailing: isOwner
              ? TextButton.icon(
                  onPressed: () => showAddSocioDialog(context, ref),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                  label: Text(l10n.holdingAddPartner),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                )
              : null,
        ),
        ...members.map((m) => _PartnerTile(
              member: m,
              contributed: totals[m.id] ?? 0,
              quota: table.quotaOf(m.id),
              patrimony: patrimony?[m.id],
              gap: gaps[m.id],
              onTap: isOwner
                  ? () =>
                      showAddContributionDialog(context, ref, memberId: m.id)
                  : null,
            )),
        // Explained ONCE, under the table: repeating the reason on every row
        // would drown the numbers, and the cause is always the Holding's, not
        // any single sócio's.
        if (patrimony == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              _unavailableReason(l10n, table.status),
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

/// Why a patrimony cannot be attributed right now — never "R$ 0,00", which a
/// sócio reads as "I own nothing".
String _unavailableReason(AppLocalizations l10n, QuotaStatus status) =>
    switch (status) {
      QuotaStatus.invalidFixed => l10n.holdingInvalidFixedQuotas,
      QuotaStatus.negativeContribution => l10n.holdingNegativeContributions,
      QuotaStatus.noContributions ||
      QuotaStatus.ok =>
        l10n.holdingNoContributionsYet,
    };

class _PartnerTile extends ConsumerWidget {
  final HoldingMemberEntity member;
  final Cents contributed;
  final Quota quota;
  final Cents? patrimony;
  final ContributionGap? gap;
  final VoidCallback? onTap;

  const _PartnerTile({
    required this.member,
    required this.contributed,
    required this.quota,
    required this.patrimony,
    required this.gap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final fmt = ref.watch(currencyFormatterProvider);
    final locale = ref.watch(dateLocaleProvider);
    final share = patrimony;
    final g = gap;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Avatar(name: member.name, seed: member.id),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${l10n.holdingContributedVerb} '
                          '${fmt(toReais(contributed))}',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _percentLabel(quota, locale),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        share == null
                            ? l10n.holdingUnavailable
                            : fmt(toReais(share)),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              share == null ? FontWeight.w400 : FontWeight.w600,
                          fontStyle: share == null
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: share == null
                              ? cs.onSurfaceVariant
                              : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Fixed mode only — in proportional mode the quota IS the
              // contribution, so the gap is zero by construction and the
              // provider returns nothing to render.
              if (g != null) ...[
                const SizedBox(height: 10),
                _GapRow(gap: g),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Deveria ter aportado X · faltam Y" — the whole point of fixed quotas.
class _GapRow extends ConsumerWidget {
  final ContributionGap gap;
  const _GapRow({required this.gap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final fmt = ref.watch(currencyFormatterProvider);
    final delta = gap.delta;
    final (String status, Color color) = delta == 0
        ? (l10n.holdingOnTrack, cs.onSurfaceVariant)
        : delta < 0
            ? (l10n.holdingShortBy(fmt(toReais(-delta))), cs.error)
            : (l10n.holdingAheadBy(fmt(toReais(delta))), _kGreen);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${l10n.holdingExpectedContribution}: '
              '${fmt(toReais(gap.expected))}',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Saldos + acerto
// ─────────────────────────────────────────────────────────────────────────────

class _BalancesSection extends ConsumerWidget {
  const _BalancesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final fmt = ref.watch(currencyFormatterProvider);
    final members = _byName(ref.watch(holdingActiveMembersProvider));
    final balances = ref.watch(holdingBalancesProvider);
    final settlement = ref.watch(holdingSettlementProvider);
    final names = {for (final m in members) m.id: m.name};

    final open = members
        .where((m) => (balances[m.id]?.saldo ?? 0) != 0)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(l10n.holdingBalances),
        if (open.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: _kGreen.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: _kGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.holdingAllSettled,
                    style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                  ),
                ),
              ],
            ),
          )
        else ...[
          ...open.map((m) {
            final saldo = balances[m.id]!.saldo;
            final positive = saldo > 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      m.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    fmt(toReais(saldo.abs())),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: positive ? _kGreen : cs.error,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    positive ? l10n.holdingToReceive : l10n.holdingToPay,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }),
          if (settlement.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.holdingHowToSettle,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            ...settlement.map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.arrow_forward_rounded,
                          size: 14, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.holdingSettlementLine(
                            names[t.fromId] ?? t.fromId,
                            fmt(toReais(t.cents)),
                            names[t.toId] ?? t.toId,
                          ),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / wrong-Carteira states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyPartners extends ConsumerWidget {
  final AppLocalizations l10n;
  final bool isOwner;
  const _EmptyPartners({required this.l10n, required this.isOwner});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.groups_2_rounded,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              l10n.holdingEmptyTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.holdingEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (isOwner)
              FilledButton.icon(
                onPressed: () => showAddSocioDialog(context, ref),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text(l10n.holdingAddPartner),
              )
            else
              Text(
                l10n.holdingReadOnly,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the active Carteira is not a Holding (including the combined
/// "Todas juntas" view, where an aporte would land in the wrong Carteira). The
/// AppBar keeps the selector, so the fix is one tap away.
class _NotAHolding extends StatelessWidget {
  final AppLocalizations l10n;
  const _NotAHolding({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_rounded,
                size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              l10n.holdingNotAHolding,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared pieces
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const _SectionLabel(this.text, {this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Initial-based avatar. Colored from the sócio's ID, not their name, so
/// renaming somebody does not change the face the eye already learned.
class _Avatar extends StatelessWidget {
  final String name;
  final String seed;
  const _Avatar({required this.name, required this.seed});

  static const _palette = <Color>[
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF6C00),
    Color(0xFF7B1FA2),
    Color(0xFF0288D1),
    Color(0xFFC2185B),
  ];

  @override
  Widget build(BuildContext context) {
    // Sum of code units instead of hashCode: hashCode is not guaranteed stable
    // across runs, and a face that changes color on every launch is noise.
    var acc = 0;
    for (final u in seed.codeUnits) {
      acc = (acc + u) % _palette.length;
    }
    final color = _palette[acc];
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

/// Percentage with two decimals in the user's locale ("33,33%"), or an em dash
/// when the quota is undefined — the same "we don't know" the patrimony column
/// shows, never a misleading 0%.
String _percentLabel(Quota quota, String locale) {
  final fraction = quota.fraction;
  if (fraction == null) return '—';
  return NumberFormat.decimalPercentPattern(locale: locale, decimalDigits: 2)
      .format(fraction);
}
