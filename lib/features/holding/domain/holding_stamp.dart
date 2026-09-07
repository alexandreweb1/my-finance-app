/// The write-path half of the Holding rateio: turns "an expense is being
/// created right now" into the frozen `holdingSplit` map that gets persisted
/// on the transaction doc.
///
/// WHY THIS IS A VALUE OBJECT AND NOT A PROVIDER CALL. Splitting happens deep
/// inside [TransactionsNotifier], which is constructed once per scope change
/// and has no `Ref`. Handing it an immutable snapshot of "which Holding is
/// active and who its sócios are" keeps the write path synchronous and makes
/// the whole rule unit-testable without Firestore or Riverpod.
library;

import 'package:equatable/equatable.dart';

import '../../../core/utils/cents.dart';
import '../../transactions/domain/entities/transaction_entity.dart';
import 'holding_entities.dart';
import 'holding_math.dart';

/// An immutable snapshot of the Holding a write may be stamped with.
///
/// Equatable on purpose: the notifier that holds it is rebuilt whenever this
/// value changes, and a Firestore stream re-emits on metadata changes alone.
/// Value equality keeps an unchanged roster from tearing down the notifier
/// (and the error state a failed save just put there) for nothing.
class HoldingStamp extends Equatable {
  /// The Holding Carteira this stamp — and ONLY this stamp — is valid for.
  final String workspaceId;

  /// Every sócio of that Holding, including ones who already left; the roster
  /// for a given expense is derived per-date by [rosterAsOf], never by
  /// pre-filtering here.
  final List<HoldingMemberEntity> members;

  const HoldingStamp({required this.workspaceId, required this.members});

  @override
  List<Object?> get props => [workspaceId, members];

  /// The frozen rateio for one expense, or null when this stamp does not apply.
  ///
  /// [targetWorkspaceId] is the Carteira the doc is ACTUALLY being written to,
  /// which is not always the active one. `addAndReturnId` accepts a
  /// `workspaceIdOverride` and the bank-notification capture passes
  /// `captureWorkspaceIdProvider` — the DEFAULT Carteira. Without the first
  /// guard below, a bank notification arriving while a Holding happens to be on
  /// screen would write Holding shares into the PF ledger, where nothing would
  /// ever read them back and the numbers would just be wrong. NEVER remove it.
  ///
  /// Returns null (rather than an empty map) for every non-applicable case so
  /// the model omits the field entirely and PF/PJ docs stay byte-identical to
  /// what they are today.
  Map<String, int>? splitFor({
    required String? targetWorkspaceId,
    required TransactionType type,
    required double amount,
    required DateTime date,
    required String seed,
    String? paidByParticipantId,
  }) {
    if (targetWorkspaceId != workspaceId) return null;
    // Only expenses are rateados. An aporte is income into the Holding and
    // belongs to ONE sócio (it is tracked as a contribution, not a shared
    // cost); a transfer just moves money between Contas of the same Holding.
    // Splitting either would double-count it in `rateioBalances`.
    if (type != TransactionType.expense) return null;
    final roster = rosterAsOf(members, date);
    if (roster.isEmpty) return null;
    // Non-throwing on purpose: a corrupt amount must not take down the whole
    // save, it just means "no rateio for this one".
    final totalCents = toCentsOr(amount, fallback: 0);
    if (totalCents == 0) return null;
    return splitCentsAmong(
      participantIds: [for (final m in roster) m.id],
      totalCents: totalCents,
      seed: seed,
      paidByParticipantId: paidByParticipantId,
    );
  }
}

/// Folds [buildEqualSplit] into the flat `participantId → centavos` map the
/// transaction doc stores. The single place the split math is called from, so
/// creating and re-freezing an expense can never drift apart.
Map<String, int> splitCentsAmong({
  required List<String> participantIds,
  required Cents totalCents,
  required String seed,
  String? paidByParticipantId,
}) {
  final snapshot = buildEqualSplit(
    totalCents: totalCents,
    participantIds: participantIds,
    seed: seed,
    paidByParticipantId: paidByParticipantId,
  );
  return {for (final s in snapshot.shares) s.participantId: s.cents};
}

/// Re-freezes an ALREADY STORED split at a new [amount], keeping exactly the
/// participants the stored split names.
///
/// WHY NOT today's roster: editing the value of an old expense must not
/// silently pull in a sócio who joined afterwards, nor drop one who has since
/// left — that would rewrite history through the back door, which is the exact
/// thing the frozen snapshot exists to prevent. Only the numbers move.
///
/// Returns null when there is nothing to re-freeze — no stored split, or the
/// total did not actually move — so the caller carries the stored split
/// through untouched and an edit that only fixes a typo in the title never
/// rewrites the numbers.
Map<String, int>? resplitStored({
  required Map<String, int>? storedSplit,
  required double amount,
  required String seed,
}) {
  if (storedSplit == null || storedSplit.isEmpty) return null;
  final totalCents = toCentsOr(amount, fallback: 0);
  if (totalCents == 0) return null;
  if (storedSplit.values.fold<int>(0, (a, b) => a + b) == totalCents) {
    return null;
  }
  return splitCentsAmong(
    participantIds: storedSplit.keys.toList(),
    totalCents: totalCents,
    seed: seed,
  );
}
