/// Pure equity math for a Holding Carteira — quotas, patrimony, rateio and
/// settlement. No Flutter, no Firestore, so every number here is unit-testable
/// in isolation.
///
/// Sign conventions, fixed once and used everywhere:
///   * contributed   — what a sócio put IN (aportes). Positive.
///   * owed          — the sócio's accumulated share of Holding expenses.
///   * paidOnBehalf  — expense money this sócio fronted for the group.
///   * saldo         — contributed + paidOnBehalf - owed.
///                     Positive means the group owes them; negative means they
///                     owe the group.
library;

import '../../../core/utils/cents.dart';

// ─── Split snapshot ──────────────────────────────────────────────────────────

/// One sócio's slice of one expense.
class SplitShare {
  final String participantId;
  final Cents cents;
  const SplitShare(this.participantId, this.cents);

  @override
  String toString() => '$participantId:$cents';
}

/// The frozen rateio of a single expense.
///
/// It is a SNAPSHOT on purpose: it records who was participating when the
/// expense happened, so adding a sócio later never rewrites the past.
class SplitSnapshot {
  final Cents totalCents;
  final List<SplitShare> shares;

  /// Which sócio actually paid, when known. Null means the Holding itself paid
  /// from a shared Conta, so nobody fronted the money personally.
  final String? paidByParticipantId;

  const SplitSnapshot({
    required this.totalCents,
    required this.shares,
    this.paidByParticipantId,
  });

  /// False when the stored shares no longer add up to the expense total —
  /// e.g. the amount was edited after the split was frozen. The UI surfaces
  /// this as a "recalcular" prompt instead of silently trusting stale numbers.
  bool get isConsistent =>
      shares.fold<int>(0, (a, s) => a + s.cents) == totalCents;

  Cents shareOf(String participantId) {
    for (final s in shares) {
      if (s.participantId == participantId) return s.cents;
    }
    return 0;
  }

  /// The exact inverse of this split, for an estorno.
  SplitSnapshot reversed() => SplitSnapshot(
        totalCents: -totalCents,
        shares:
            shares.map((s) => SplitShare(s.participantId, -s.cents)).toList(),
        paidByParticipantId: paidByParticipantId,
      );
}

/// Deterministic rotation offset derived from [seed], used to decide who
/// absorbs the leftover centavo of an odd split.
///
/// Hand-rolled rather than `String.hashCode`: Dart's string hash is not
/// guaranteed stable across runs or platforms, so the same expense could rotate
/// differently on the web build and on iOS, and the numbers would disagree
/// between two people looking at the same Holding.
int stableRotation(String seed, int n) {
  if (n <= 1) return 0;
  var h = 0;
  for (var i = 0; i < seed.length; i++) {
    h = (h * 31 + seed.codeUnitAt(i)) & 0x1fffffff;
  }
  return h % n;
}

/// Splits [totalCents] equally between [participantIds], to the centavo.
///
/// Participants are sorted, then rotated by [seed] (use the transaction id), so
/// the odd centavo lands on a different sócio for each expense instead of
/// always taxing whoever sorts first.
SplitSnapshot buildEqualSplit({
  required Cents totalCents,
  required List<String> participantIds,
  required String seed,
  String? paidByParticipantId,
}) {
  final ids = List<String>.from(participantIds)..sort();
  if (ids.isEmpty) {
    return SplitSnapshot(
      totalCents: totalCents,
      shares: const [],
      paidByParticipantId: paidByParticipantId,
    );
  }
  final n = ids.length;
  final r = stableRotation(seed, n);
  final rotated = [...ids.sublist(r), ...ids.sublist(0, r)];
  final parts = splitEqually(totalCents, n);
  return SplitSnapshot(
    totalCents: totalCents,
    shares: [for (var i = 0; i < n; i++) SplitShare(rotated[i], parts[i])],
    paidByParticipantId: paidByParticipantId,
  );
}

// ─── Quotas ──────────────────────────────────────────────────────────────────

enum QuotaStatus {
  ok,

  /// Nobody has contributed yet, so proportional shares are undefined — NOT
  /// zero, and not an equal split. The UI must say "sem aportes ainda".
  noContributions,

  /// Data corruption: a negative contribution total.
  negativeContribution,

  /// Fixed percentages that do not add up to exactly 100%.
  invalidFixed,
}

/// One sócio's ownership share, kept as an exact fraction (never a rounded
/// percentage) so downstream money math stays exact.
class Quota {
  /// Numerator: contributed centavos, or basis points for fixed mode.
  final int weight;

  /// Denominator: everything contributed, or 10000 for fixed mode.
  final int totalWeight;

  const Quota(this.weight, this.totalWeight);

  static const undefined = Quota(0, 0);

  bool get isUndefined => totalWeight <= 0;

  double? get fraction => isUndefined ? null : weight / totalWeight;

  double? get percent => isUndefined ? null : weight * 100 / totalWeight;

  int? get bps => isUndefined ? null : (weight * 10000 / totalWeight).round();
}

class QuotaTable {
  final Map<String, Quota> quotas;
  final QuotaStatus status;

  /// Raw weights per participant, in the caller's order — the input to the
  /// exact patrimony allocation.
  final Map<String, int> weights;

  const QuotaTable(this.quotas, this.status, this.weights);

  bool get isUsable => status == QuotaStatus.ok;

  Quota quotaOf(String id) => quotas[id] ?? Quota.undefined;
}

/// Quota = this sócio's contributions / everything contributed.
QuotaTable proportionalQuotas(
  List<String> ids,
  Map<String, Cents> contributions,
) {
  final w = <String, int>{for (final id in ids) id: contributions[id] ?? 0};
  if (w.values.any((v) => v < 0)) {
    return QuotaTable(
      {for (final id in ids) id: Quota.undefined},
      QuotaStatus.negativeContribution,
      w,
    );
  }
  final total = w.values.fold<int>(0, (a, b) => a + b);
  if (total <= 0) {
    return QuotaTable(
      {for (final id in ids) id: Quota.undefined},
      QuotaStatus.noContributions,
      w,
    );
  }
  return QuotaTable(
    {for (final id in ids) id: Quota(w[id]!, total)},
    QuotaStatus.ok,
    w,
  );
}

class FixedQuotaValidation {
  final int sumBps;
  final bool hasOutOfRange;
  const FixedQuotaValidation(this.sumBps, this.hasOutOfRange);

  bool get isValid => sumBps == 10000 && !hasOutOfRange;

  /// How far from 100% the percentages are, in basis points.
  int get deltaBps => sumBps - 10000;
}

/// Validates hand-set percentages.
///
/// Percentages are basis points (`5000` = 50,00%), never doubles: seven sócios
/// at `100/7` each sum to `100.00000000000001` as doubles, so a `== 100` check
/// would reject a perfectly legal split.
FixedQuotaValidation validateFixedQuotas(Map<String, int> bpsById) {
  var sum = 0;
  var bad = false;
  for (final v in bpsById.values) {
    if (v < 0 || v > 10000) bad = true;
    sum += v;
  }
  return FixedQuotaValidation(sum, bad);
}

QuotaTable fixedQuotas(List<String> ids, Map<String, int> bpsById) {
  final w = <String, int>{for (final id in ids) id: bpsById[id] ?? 0};
  final v = validateFixedQuotas(w);
  if (!v.isValid) {
    return QuotaTable(
      {for (final id in ids) id: Quota.undefined},
      QuotaStatus.invalidFixed,
      w,
    );
  }
  return QuotaTable(
    {for (final id in ids) id: Quota(w[id]!, 10000)},
    QuotaStatus.ok,
    w,
  );
}

/// Distributes [netWorthCents] between sócios according to [table].
///
/// Returns null when quotas are undefined (no contributions yet, or invalid
/// fixed percentages) — the caller must show "indisponível", never zero, which
/// would read as "you own nothing".
///
/// Works for a NEGATIVE net worth (a Holding whose debts exceed its assets):
/// each sócio then carries their share of the hole.
Map<String, Cents>? patrimonyByParticipant(
  List<String> ids,
  QuotaTable table,
  Cents netWorthCents,
) {
  if (!table.isUsable) return null;
  if (ids.isEmpty) return const {};
  final weights = [for (final id in ids) table.weights[id] ?? 0];
  final parts = allocateProportional(netWorthCents, weights);
  return {for (var i = 0; i < ids.length; i++) ids[i]: parts[i]};
}

// ─── Expected versus actual (fixed-quota mode) ───────────────────────────────

class ContributionGap {
  final Cents expected;
  final Cents actual;
  const ContributionGap(this.expected, this.actual);

  /// Positive: contributed more than the quota required. Negative: owes.
  Cents get delta => actual - expected;

  @override
  String toString() => 'exp=$expected act=$actual delta=$delta';
}

/// For fixed quotas: how much each sócio SHOULD have put in versus what they
/// actually did. [targetTotalCents] defaults to what the group has contributed
/// so far, which is what makes the answer "who is behind right now".
Map<String, ContributionGap> contributionGaps({
  required List<String> ids,
  required Map<String, int> bpsById,
  required Map<String, Cents> contributions,
  Cents? targetTotalCents,
}) {
  final actualTotal = ids.fold<int>(0, (a, id) => a + (contributions[id] ?? 0));
  final base = targetTotalCents ?? actualTotal;
  final weights = [for (final id in ids) bpsById[id] ?? 0];
  final totalW = weights.fold<int>(0, (a, b) => a + b);
  final expected = totalW <= 0
      ? List<Cents>.filled(ids.length, 0)
      : allocateProportional(base, weights);
  return {
    for (var i = 0; i < ids.length; i++)
      ids[i]: ContributionGap(expected[i], contributions[ids[i]] ?? 0),
  };
}

// ─── Rateio balances ─────────────────────────────────────────────────────────

class ParticipantBalance {
  final Cents contributed;
  final Cents owed;
  final Cents paidOnBehalf;
  const ParticipantBalance(this.contributed, this.owed, this.paidOnBehalf);

  /// Positive: the group owes this sócio. Negative: this sócio owes the group.
  Cents get saldo => contributed + paidOnBehalf - owed;

  @override
  String toString() =>
      'contr=$contributed owed=$owed paid=$paidOnBehalf saldo=$saldo';
}

/// Folds every frozen expense split plus every aporte into a per-sócio balance.
///
/// Shares belonging to someone no longer in [ids] are ignored here but remain
/// in the stored snapshots, so history is never rewritten.
Map<String, ParticipantBalance> rateioBalances({
  required List<String> ids,
  required Map<String, Cents> contributions,
  required List<SplitSnapshot> splits,
}) {
  final owed = <String, int>{for (final id in ids) id: 0};
  final paid = <String, int>{for (final id in ids) id: 0};
  for (final s in splits) {
    for (final sh in s.shares) {
      if (owed.containsKey(sh.participantId)) {
        owed[sh.participantId] = owed[sh.participantId]! + sh.cents;
      }
    }
    final p = s.paidByParticipantId;
    if (p != null && paid.containsKey(p)) {
      paid[p] = paid[p]! + s.totalCents;
    }
  }
  return {
    for (final id in ids)
      id: ParticipantBalance(contributions[id] ?? 0, owed[id]!, paid[id]!),
  };
}

// ─── Settlement ──────────────────────────────────────────────────────────────

class SettlementTransfer {
  final String fromId;
  final String toId;
  final Cents cents;
  const SettlementTransfer(this.fromId, this.toId, this.cents);

  @override
  String toString() => '$fromId -> $toId : $cents';
}

/// Resolves who pays whom, greedily matching the largest debtor to the largest
/// creditor. Produces at most (participants - 1) transfers.
///
/// Ordering is fully deterministic (amount desc, then id) so two people looking
/// at the same Holding see the same instructions.
List<SettlementTransfer> settle(Map<String, Cents> saldos) {
  final debtors = <MapEntry<String, int>>[];
  final creditors = <MapEntry<String, int>>[];
  final keys = saldos.keys.toList()..sort();
  for (final k in keys) {
    final v = saldos[k]!;
    if (v < 0) debtors.add(MapEntry(k, -v));
    if (v > 0) creditors.add(MapEntry(k, v));
  }
  int byAmountThenId(MapEntry<String, int> a, MapEntry<String, int> b) =>
      b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key);
  debtors.sort(byAmountThenId);
  creditors.sort(byAmountThenId);

  final out = <SettlementTransfer>[];
  var i = 0;
  var j = 0;
  var d = debtors.isEmpty ? 0 : debtors[0].value;
  var c = creditors.isEmpty ? 0 : creditors[0].value;
  while (i < debtors.length && j < creditors.length) {
    final amt = d < c ? d : c;
    if (amt > 0) {
      out.add(SettlementTransfer(debtors[i].key, creditors[j].key, amt));
    }
    d -= amt;
    c -= amt;
    if (d == 0) {
      i++;
      if (i < debtors.length) d = debtors[i].value;
    }
    if (c == 0) {
      j++;
      if (j < creditors.length) c = creditors[j].value;
    }
  }
  return out;
}
