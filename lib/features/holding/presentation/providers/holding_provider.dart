import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/providers/workspace_provider.dart';
import '../../../../core/utils/cents.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../home/presentation/providers/money_metrics_provider.dart';
import '../../../transactions/data/models/transaction_model.dart';
import '../../../transactions/domain/entities/transaction_entity.dart';
import '../../../transactions/presentation/providers/transactions_provider.dart';
import '../../../wallets/domain/entities/wallet_entity.dart';
import '../../../wallets/presentation/providers/wallets_provider.dart';
import '../../../workspaces/domain/workspace_entity.dart';
import '../../data/holding_models.dart';
import '../../domain/holding_entities.dart';
import '../../domain/holding_math.dart';
import '../../domain/holding_stamp.dart';

/// Riverpod layer for the Holding Carteira.
///
/// Everything here is a thin, side-effect-free wiring of three things that
/// already exist and are already tested: the scoping engine
/// (`workspace_provider.dart`), the pure equity math (`holding_math.dart`) and
/// the ledger streams. No money arithmetic is invented in this file — it only
/// converts at the boundary with [toCentsOr] / [toReais] and delegates.
///
/// Nothing here runs for personal/business Carteiras: every provider bails out
/// to a neutral value as soon as [activeHoldingProvider] is null.

/// Firestore collection names, in one place so the notifier and the streams
/// can never drift apart.
const String _kMembersCollection = 'holding_members';
const String _kContributionsCollection = 'holding_contributions';

// ─────────────────────────────────────────────────────────────────────────────
// Is a Holding active?
// ─────────────────────────────────────────────────────────────────────────────

/// The active Carteira, but ONLY when it is a Holding. Null otherwise.
///
/// Returns null in the combined "Todas juntas" view even if the user's last
/// selection was a Holding. In that view [workspaceStampProvider] resolves to
/// the DEFAULT Carteira, so anything homed off the "active" Holding — a sócio,
/// an aporte, the transaction that mirrors it — would be written into the
/// wrong Carteira and then be invisible from both. Reads are equally wrong
/// there: "Todas juntas" mixes every Carteira's expenses, and rateio-ing a PF
/// grocery bill between sócios is nonsense. The UI is expected to ask the user
/// to pick the Holding first.
final activeHoldingProvider = Provider<WorkspaceEntity?>((ref) {
  if (ref.watch(isCombinedViewProvider)) return null;
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws == null || !ws.isHolding) return null;
  return ws;
});

/// Convenience flag for widgets that only need to know whether to render the
/// Holding surfaces at all.
final isHoldingActiveProvider =
    Provider<bool>((ref) => ref.watch(activeHoldingProvider) != null);

// ─────────────────────────────────────────────────────────────────────────────
// Streams
// ─────────────────────────────────────────────────────────────────────────────

/// The Holding's sócios.
///
/// Same two-branch shape as every other ledger stream (see
/// `goals_provider.dart`): a new-style shared member queries by `workspaceId`
/// server-side, everyone else queries by uid and filters client-side.
///
/// On top of [applyWorkspaceScope] there is a second, non-negotiable filter on
/// `workspaceId == holding.id`. These docs only ever exist for Holdings, so
/// they ALWAYS carry a workspaceId — but [applyWorkspaceScope] deliberately
/// treats a doc with a NULL workspaceId as belonging to the default Carteira,
/// and a corrupt/legacy doc without the field would then leak into whatever
/// Holding happens to be default. Sócios are the identity of the Holding; one
/// leaked name silently changes everybody's quota.
final holdingMembersStreamProvider =
    StreamProvider<List<HoldingMemberEntity>>((ref) {
  final holding = ref.watch(activeHoldingProvider);
  // No Holding active → no sócios. NEVER fall through to an unfiltered query:
  // that would show another Carteira's sócios.
  if (holding == null) return Stream.value(const []);

  final scope = ref.watch(activeLedgerScopeProvider);

  if (scope is MemberScope) {
    return workspaceCollectionQuery(ref.watch(firestoreProvider),
            _kMembersCollection, scope.workspaceId)
        .snapshots()
        .map((snap) => _sortedMembers(
              snap.docs
                  .map(HoldingMemberModel.fromFirestore)
                  .cast<HoldingMemberEntity>()
                  .where((m) => m.workspaceId == holding.id)
                  .toList(),
            ));
  }

  final userId = ref.watch(ledgerQueryUserIdProvider);
  // Empty while the profile (and therefore masterUserId) is still loading —
  // firing the query anyway would read the wrong account.
  if (userId.isEmpty) return Stream.value(const []);

  // BOTH clauses on purpose. A list query is granted only when the rules can
  // be proven from the query's own filters: `userId` proves the owner /
  // legacy-collaborator path, `workspaceId` proves the membership path. With
  // `userId` alone the whole query was denied for the owner (auditoria
  // 2026-09-08 #1) and the Holding looked permanently empty. Two equality
  // filters need no composite index.
  return ref
      .watch(firestoreProvider)
      .collection(_kMembersCollection)
      .where('userId', isEqualTo: userId)
      .where('workspaceId', isEqualTo: holding.id)
      .snapshots()
      .map((snap) {
    final all = snap.docs
        .map(HoldingMemberModel.fromFirestore)
        .cast<HoldingMemberEntity>()
        .toList();
    return _sortedMembers(
      applyWorkspaceScope(all, (m) => m.workspaceId, scope)
          .where((m) => m.workspaceId == holding.id)
          .toList(),
    );
  });
});

/// Alphabetical by name, then by id.
///
/// The id tiebreaker is not cosmetic: two sócios can legitimately share a name
/// ("Maria"), and an unstable order would make the list jump on every snapshot
/// and reorder the rows the user is tapping.
List<HoldingMemberEntity> _sortedMembers(List<HoldingMemberEntity> list) {
  list.sort((a, b) {
    final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return list;
}

/// The Holding's aportes/retiradas. Same shape and same double filter as
/// [holdingMembersStreamProvider].
final holdingContributionsStreamProvider =
    StreamProvider<List<HoldingContributionEntity>>((ref) {
  final holding = ref.watch(activeHoldingProvider);
  if (holding == null) return Stream.value(const []);

  final scope = ref.watch(activeLedgerScopeProvider);

  if (scope is MemberScope) {
    return workspaceCollectionQuery(ref.watch(firestoreProvider),
            _kContributionsCollection, scope.workspaceId)
        .snapshots()
        .map((snap) => _sortedContributions(
              snap.docs
                  .map(HoldingContributionModel.fromFirestore)
                  .cast<HoldingContributionEntity>()
                  .where((c) => c.workspaceId == holding.id)
                  .toList(),
            ));
  }

  final userId = ref.watch(ledgerQueryUserIdProvider);
  if (userId.isEmpty) return Stream.value(const []);

  // Same two clauses as holdingMembersStreamProvider, same reason.
  return ref
      .watch(firestoreProvider)
      .collection(_kContributionsCollection)
      .where('userId', isEqualTo: userId)
      .where('workspaceId', isEqualTo: holding.id)
      .snapshots()
      .map((snap) {
    final all = snap.docs
        .map(HoldingContributionModel.fromFirestore)
        .cast<HoldingContributionEntity>()
        .toList();
    return _sortedContributions(
      applyWorkspaceScope(all, (c) => c.workspaceId, scope)
          .where((c) => c.workspaceId == holding.id)
          .toList(),
    );
  });
});

/// Newest first (that is how a money trail is read), id as the tiebreaker so
/// same-day aportes keep a stable order between snapshots.
List<HoldingContributionEntity> _sortedContributions(
    List<HoldingContributionEntity> list) {
  list.sort((a, b) {
    final c = b.date.compareTo(a.date);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return list;
}

// ─────────────────────────────────────────────────────────────────────────────
// Derived
// ─────────────────────────────────────────────────────────────────────────────

/// memberId → everything they put in, in centavos.
///
/// Retiradas are negative rows, so summing (rather than taking absolutes) is
/// what makes the total mean "net capital in".
final holdingContributionTotalsProvider = Provider<Map<String, Cents>>((ref) {
  final contributions =
      ref.watch(holdingContributionsStreamProvider).value ?? const [];
  final out = <String, Cents>{};
  for (final c in contributions) {
    out[c.memberId] = (out[c.memberId] ?? 0) + c.amountCents;
  }
  return out;
});

/// EVERY aporte/retirada the current scope can see, regardless of which
/// Carteira is active.
///
/// [holdingContributionsStreamProvider] is empty outside a Holding by design,
/// but a mirror transaction shows up in "Todas juntas" and — after a move — in
/// any Carteira's Extrato, and it must stay locked there too. Same dual query
/// as the Holding streams: `where userId` for the owner / legacy collaborator
/// (granted by the legacyAccess() read path), `where workspaceId` for a
/// Carteira member. Almost every account has zero docs here, so the listener
/// costs one empty query.
final allVisibleContributionsStreamProvider =
    StreamProvider<List<HoldingContributionEntity>>((ref) {
  final scope = ref.watch(activeLedgerScopeProvider);
  final fs = ref.watch(firestoreProvider);
  List<HoldingContributionEntity> parse(QuerySnapshot<Map<String, dynamic>> s) =>
      s.docs
          .map(HoldingContributionModel.fromFirestore)
          .cast<HoldingContributionEntity>()
          .toList();

  if (scope is MemberScope) {
    return workspaceCollectionQuery(
            fs, _kContributionsCollection, scope.workspaceId)
        .snapshots()
        .map(parse);
  }
  final userId = ref.watch(ledgerQueryUserIdProvider);
  if (userId.isEmpty) return Stream.value(const []);
  return fs
      .collection(_kContributionsCollection)
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map(parse);
});

/// Ids of the transactions that mirror an aporte/retirada — the Extrato half
/// of each `holding_contributions` doc the current scope can see.
///
/// Complements [TransactionEntity.holdingContributionId]: mirrors written
/// before that field existed (build 171) are still recognised through the
/// contribution's own `linkedTransactionId`, so no data migration is needed.
final holdingMirrorTransactionIdsProvider = Provider<Set<String>>((ref) {
  final contributions =
      ref.watch(allVisibleContributionsStreamProvider).value ?? const [];
  return {
    for (final c in contributions)
      if (c.linkedTransactionId != null && c.linkedTransactionId!.isNotEmpty)
        c.linkedTransactionId!,
  };
});

/// True when [t] is the Extrato half of an aporte/retirada.
///
/// Such a transaction is locked in the Extrato (no swipe-to-delete, no edit
/// dialog): the contribution trail is append-only, so the only correct way to
/// change it is to undo the contribution on the Holding screen, which removes
/// both halves in one batch. Editing the mirror alone would leave the cap
/// table describing money the ledger no longer has (auditoria 2026-09-08 #4).
bool isContributionMirror(TransactionEntity t, Set<String> mirrorIds) {
  final id = t.holdingContributionId;
  return (id != null && id.isNotEmpty) || mirrorIds.contains(t.id);
}

/// Sócios who have not left, sorted by id.
///
/// Sorted by ID, not by name: this list is the participant order fed to
/// `allocateProportional`, and the largest-remainder tiebreak is
/// order-sensitive. Anchoring it to the (immutable) id means renaming a sócio
/// can never move a centavo; anchoring it to the name would.
final holdingActiveMembersProvider = Provider<List<HoldingMemberEntity>>((ref) {
  final members = ref.watch(holdingMembersStreamProvider).value ?? const [];
  final out = members.where((m) => m.isActive).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return out;
});

/// The quota table for the Holding's configured mode.
///
/// Proportional: quota follows the money actually contributed. Fixed: quota is
/// whatever the owner typed, and the app reports the gap separately (see
/// [holdingContributionGapsProvider]) instead of quietly "fixing" the numbers.
final holdingQuotaTableProvider = Provider<QuotaTable>((ref) {
  final holding = ref.watch(activeHoldingProvider);
  final members = ref.watch(holdingActiveMembersProvider);
  final ids = [for (final m in members) m.id];
  if (holding == null || ids.isEmpty) {
    // An empty roster has no usable quotas — NOT zeroed ones, which would read
    // as "everyone owns nothing".
    return const QuotaTable({}, QuotaStatus.noContributions, {});
  }
  if (holding.quotaMode == HoldingQuotaMode.fixed) {
    return fixedQuotas(ids, {for (final m in members) m.id: m.quotaBps});
  }
  return proportionalQuotas(ids, ref.watch(holdingContributionTotalsProvider));
});

/// The Holding's net worth in centavos.
///
/// Reuses the dashboard's own multi-currency-aware number so the Holding and
/// the Home screen can never disagree, and converts once, here, at the
/// boundary.
final holdingNetWorthCentsProvider =
    Provider<Cents>((ref) => toCentsOr(ref.watch(netWorthProvider)));

/// memberId → their slice of the net worth, or NULL when quotas are undefined
/// (nobody has contributed yet, or the fixed percentages do not add to 100%).
///
/// Null and zero mean very different things to a sócio, so this deliberately
/// propagates `null` instead of a map of zeros; the UI must render
/// "indisponível".
final holdingPatrimonyProvider = Provider<Map<String, Cents>?>((ref) {
  final members = ref.watch(holdingActiveMembersProvider);
  if (members.isEmpty) return null;
  return patrimonyByParticipant(
    [for (final m in members) m.id],
    ref.watch(holdingQuotaTableProvider),
    ref.watch(holdingNetWorthCentsProvider),
  );
});

/// Every expense of the Holding as a rateio snapshot.
///
/// Two sources, in this order:
///
///  1. `tx.holdingSplit` — the split frozen when the expense was created. It
///     ALWAYS wins. It records who was participating at that moment, which is
///     exactly what keeps a sócio added later from rewriting the past.
///  2. A PROJECTION, computed on the fly with [buildEqualSplit] over
///     `rosterAsOf(members, tx.date)`, for any expense that has no stored
///     split: entries imported from OFX/CSV, entries created before the
///     Carteira became a Holding, entries moved in from another Carteira, or
///     entries written by an older build.
///
/// The projection is the important half. Backfilling those expenses with a
/// write would need editor rights (viewers would see nothing), would fail
/// offline, and would race two devices into duplicate/conflicting splits. A
/// pure function of data everyone already has is correct for every viewer,
/// instantly, with ZERO writes — and it converges to the stored value the
/// moment someone edits the expense, because [buildEqualSplit] is
/// deterministic (seeded by the transaction id).
///
/// Skips transfers and income: an aporte is capital, not a shared cost, and
/// double-counting it as "owed" would put every sócio permanently in the red.
/// Skips expenses whose roster is empty (dated before the first sócio joined):
/// there is nobody to charge, and an empty split would silently swallow the
/// amount.
final holdingSplitsProvider = Provider<List<SplitSnapshot>>((ref) {
  if (ref.watch(activeHoldingProvider) == null) return const [];
  final members = ref.watch(holdingMembersStreamProvider).value ?? const [];
  if (members.isEmpty) return const [];

  // Already scoped to the active Carteira (and honours hidden Contas).
  final txs = ref.watch(visibleTransactionsProvider);
  final out = <SplitSnapshot>[];
  for (final t in txs) {
    if (!t.isExpense) continue;
    final total = toCentsOr(t.amount);
    final stored = t.holdingSplit;
    if (stored != null && stored.isNotEmpty) {
      // Sorted by participant id so the snapshot is identical on every device
      // regardless of Firestore's map ordering.
      final keys = stored.keys.toList()..sort();
      out.add(SplitSnapshot(
        totalCents: total,
        shares: [for (final k in keys) SplitShare(k, stored[k]!)],
        paidByParticipantId: t.holdingPaidBy,
      ));
      continue;
    }
    final roster = rosterAsOf(members, t.date);
    if (roster.isEmpty) continue;
    out.add(buildEqualSplit(
      totalCents: total,
      participantIds: [for (final m in roster) m.id],
      seed: t.id,
      paidByParticipantId: t.holdingPaidBy,
    ));
  }
  return out;
});

/// memberId → contributed / owed / paid-on-behalf / saldo.
///
/// Keyed by EVERY sócio the Holding has ever had — including the ones who have
/// left. Leaving a Holding does not settle a debt, and [rateioBalances]
/// silently ignores shares belonging to an id it was not handed: keying this
/// by the ACTIVE roster made a departing sócio's saldo, and their half of
/// "quem paga quem", disappear the instant [HoldingNotifier.setMemberLeft] was
/// written. Concretely — A and B, one R$ 100,00 expense fronted by A, B leaves:
/// the app would say A is owed R$ 50,00 and name nobody to pay it.
///
/// Someone who left with a clean slate lands on saldo 0 and is filtered out by
/// the UI anyway; someone who left owing money stays visible until an
/// aporte/retirada zeroes them. Ids sorted so the map (and the settlement
/// derived from it) is byte-identical on every device.
final holdingBalancesProvider =
    Provider<Map<String, ParticipantBalance>>((ref) {
  final members = ref.watch(holdingMembersStreamProvider).value ?? const [];
  if (members.isEmpty) return const {};
  final ids = [for (final m in members) m.id]..sort();
  return rateioBalances(
    ids: ids,
    contributions: ref.watch(holdingContributionTotalsProvider),
    splits: ref.watch(holdingSplitsProvider),
  );
});

/// "Quem paga quem" — the minimal set of transfers that zeroes every saldo.
final holdingSettlementProvider = Provider<List<SettlementTransfer>>((ref) {
  final balances = ref.watch(holdingBalancesProvider);
  if (balances.isEmpty) return const [];
  return settle({for (final e in balances.entries) e.key: e.value.saldo});
});

/// Fixed mode only: how much each sócio SHOULD have contributed for their
/// declared percentage versus what they actually did.
///
/// Empty in proportional mode by construction — there the quota IS the
/// contribution, so the gap is always zero and showing it would be noise.
final holdingContributionGapsProvider =
    Provider<Map<String, ContributionGap>>((ref) {
  final holding = ref.watch(activeHoldingProvider);
  if (holding == null || holding.quotaMode != HoldingQuotaMode.fixed) {
    return const {};
  }
  final members = ref.watch(holdingActiveMembersProvider);
  if (members.isEmpty) return const {};
  return contributionGaps(
    ids: [for (final m in members) m.id],
    bpsById: {for (final m in members) m.id: m.quotaBps},
    contributions: ref.watch(holdingContributionTotalsProvider),
  );
});

/// How many STORED splits no longer add up to their expense's amount.
///
/// Only stored splits can go stale: someone edited the value of an expense
/// after its rateio was frozen. Projections are recomputed from the current
/// amount every time, so they are consistent by construction and are excluded
/// here. A non-zero count is the UI's cue to offer "recalcular" rather than to
/// silently present numbers that do not add up.
final holdingStaleSplitCountProvider = Provider<int>((ref) {
  if (ref.watch(activeHoldingProvider) == null) return 0;
  var n = 0;
  for (final t in ref.watch(visibleTransactionsProvider)) {
    if (!t.isExpense) continue;
    final stored = t.holdingSplit;
    if (stored == null || stored.isEmpty) continue;
    final sum = stored.values.fold<int>(0, (a, b) => a + b);
    if (sum != toCentsOr(t.amount)) n++;
  }
  return n;
});

// ─────────────────────────────────────────────────────────────────────────────
// Writes
// ─────────────────────────────────────────────────────────────────────────────

/// Mutations for the Holding.
///
/// Reads its context with `ref.read` at call time rather than capturing it in
/// the constructor: the active Carteira, the owner uid and the loaded streams
/// all change while this notifier is alive, and a stale capture would write
/// into the wrong Carteira.
///
/// Every method is a no-op (false/null) when no Holding is active. That is the
/// single guard that keeps this feature from touching a PF/PJ Carteira.
class HoldingNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  HoldingNotifier(this._ref) : super(const AsyncValue.data(null));

  FirebaseFirestore get _fs => _ref.read(firestoreProvider);

  WorkspaceEntity? get _holding => _ref.read(activeHoldingProvider);

  /// The uid every ledger doc of this Carteira is homed to — the OWNER's, even
  /// when a shared collaborator is the one writing.
  String get _ownerId => _ref.read(ledgerOwnerIdProvider);

  /// Who physically performed the write (audit trail), which is not
  /// necessarily [_ownerId].
  String get _actorId => _ref.read(authStateProvider).value?.id ?? _ownerId;

  /// True only when we can PROVE [memberId] is not a sócio of the ACTIVE
  /// Holding.
  ///
  /// The member-id arguments below all come from a list the user is looking
  /// at, but nothing in the type system says so, and one stale id would edit
  /// (or delete) a sócio of a DIFFERENT Holding the same owner happens to
  /// have: the rules only check that the caller owns the doc's Carteira, not
  /// that it is the one on screen. Deliberately returns false while the roster
  /// has not loaded — an unproven suspicion must never turn a legitimate save
  /// into a silent no-op.
  bool _isForeignMember(String memberId) {
    final known = _ref.read(holdingMembersStreamProvider).value;
    if (known == null) return false;
    return !known.any((m) => m.id == memberId);
  }

  // ── Sócios ────────────────────────────────────────────────────────────────

  /// Adds a sócio and returns its id (null on failure).
  ///
  /// [joinedAt] defaults to the CARTEIRA's creation date, never
  /// `DateTime.now()`: sócios are typically registered days after the Holding
  /// itself, and "now" would silently exclude them from every expense already
  /// recorded — the founding partner would show up owing nothing and owning
  /// nothing. The Carteira's birthday is the earliest date any of its expenses
  /// can carry, so it is the only safe default.
  Future<String?> addMember({
    required String name,
    String? memberUid,
    int quotaBps = 0,
    DateTime? joinedAt,
  }) async {
    final holding = _holding;
    final ownerId = _ownerId;
    if (holding == null || ownerId.isEmpty) return null;
    state = const AsyncValue.loading();
    try {
      final id = const Uuid().v4();
      final model = HoldingMemberModel(
        id: id,
        userId: ownerId,
        workspaceId: holding.id,
        name: name.trim(),
        memberUid: memberUid,
        quotaBps: quotaBps,
        joinedAt: joinedAt ?? holding.createdAt,
        createdAt: DateTime.now(),
      );
      await _fs
          .collection(_kMembersCollection)
          .doc(id)
          .set(model.toFirestore());
      state = const AsyncValue.data(null);
      return id;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Overwrites a sócio's doc from [member].
  ///
  /// A full `set` rather than a partial `update` on purpose: it is the only
  /// way `leftAt` can be REMOVED (the model omits null fields), so
  /// `copyWith(clearLeftAt: true)` actually reinstates a sócio instead of
  /// leaving a stale timestamp behind.
  Future<bool> updateMember(HoldingMemberEntity member) async {
    final holding = _holding;
    if (holding == null) return false;
    // The doc carries its own workspaceId and this is a full `set`: writing a
    // foreign sócio's entity here would rewrite a different Holding's cap
    // table.
    if (member.workspaceId != holding.id) return false;
    if (_isForeignMember(member.id)) return false;
    state = const AsyncValue.loading();
    try {
      await _fs
          .collection(_kMembersCollection)
          .doc(member.id)
          .set(HoldingMemberModel.fromEntity(member).toFirestore());
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Sets (or clears, with null) the date a sócio stopped participating.
  ///
  /// This — not deletion — is how someone leaves a Holding: their past shares
  /// stay exactly as they were frozen, and only expenses dated on/after
  /// [leftAt] stop being theirs.
  ///
  /// Written as a targeted field update so it cannot clobber a concurrent
  /// rename, and with `FieldValue.delete()` for the null case so the absent
  /// field means "still in" everywhere (entity, model and rules agree).
  Future<bool> setMemberLeft(String memberId, DateTime? leftAt) async {
    if (_holding == null) return false;
    if (_isForeignMember(memberId)) return false;
    state = const AsyncValue.loading();
    try {
      await _fs.collection(_kMembersCollection).doc(memberId).update({
        'leftAt':
            leftAt == null ? FieldValue.delete() : Timestamp.fromDate(leftAt),
      });
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Hard-deletes a sócio — allowed ONLY while they have no money trail.
  ///
  /// Returns false, without writing anything, when the sócio has any
  /// contribution. Deleting them would orphan those aportes: the docs would
  /// survive, keep counting toward the Holding's totals, and point at a
  /// memberId nothing resolves — quotas would silently stop adding up to 100%
  /// and no screen could explain why. Someone who has actually put money in is
  /// removed with [setMemberLeft], which preserves the history.
  ///
  /// Also refuses while the contributions stream has no value yet: at that
  /// point we cannot PROVE the sócio is clean, and guessing wrong is
  /// irreversible.
  Future<bool> deleteMember(String memberId) async {
    if (_holding == null) return false;
    final loaded = _ref.read(holdingContributionsStreamProvider).value;
    if (loaded == null) return false;
    if (loaded.any((c) => c.memberId == memberId)) return false;
    state = const AsyncValue.loading();
    try {
      await _fs.collection(_kMembersCollection).doc(memberId).delete();
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  // ── Quotas ────────────────────────────────────────────────────────────────

  /// Switches the Holding between proportional and fixed quotas.
  ///
  /// Only this one field is touched — the workspace doc also carries
  /// membership, roles and ordering that this feature has no business
  /// rewriting.
  Future<bool> setQuotaMode(HoldingQuotaMode mode) async {
    final holding = _holding;
    if (holding == null) return false;
    state = const AsyncValue.loading();
    try {
      await _fs
          .collection('workspaces')
          .doc(holding.id)
          .update({'holdingQuotaMode': mode.id});
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Writes hand-set percentages (basis points) for the given sócios.
  ///
  /// Validated BEFORE any write and rejected as a whole: percentages that do
  /// not total exactly 100% would make [fixedQuotas] return
  /// [QuotaStatus.invalidFixed], and the patrimony of every sócio — not just
  /// the edited ones — would read "indisponível". A half-applied batch is the
  /// worst possible state, so it is all or nothing.
  ///
  /// One [WriteBatch] for the same reason.
  Future<bool> setFixedQuotas(Map<String, int> bpsById) async {
    if (_holding == null) return false;
    if (!validateFixedQuotas(bpsById).isValid) return false;
    state = const AsyncValue.loading();
    try {
      final batch = _fs.batch();
      bpsById.forEach((memberId, bps) {
        batch.update(
          _fs.collection(_kMembersCollection).doc(memberId),
          {'quotaBps': bps},
        );
      });
      await batch.commit();
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  // ── Aportes ───────────────────────────────────────────────────────────────

  /// The Conta an aporte lands in: the Holding's default Conta, else its first
  /// regular Conta (by id, so the choice is stable), else `''` = "Geral".
  ///
  /// Reserve/investment/credit-card Contas are excluded: capital entering the
  /// Holding is cash, and dropping it into a credit card would corrupt that
  /// card's fatura. `''` is a legitimate answer — the app already treats it as
  /// the "Geral" bucket everywhere.
  String _defaultWalletId() {
    final wallets = _ref.read(walletsStreamProvider).value ?? const [];
    final regular = wallets.where((w) => w.type == WalletType.regular).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final w in regular) {
      if (w.isDefault) return w.id;
    }
    return regular.isEmpty ? '' : regular.first.id;
  }

  /// Records an aporte (or, with a negative [amountCents], a retirada) and
  /// returns the contribution id.
  ///
  /// The contribution doc AND a mirroring transaction are written in ONE
  /// [WriteBatch], atomically. Two separate writes could leave an aporte that
  /// exists in the Holding's equity math but nowhere in the Extrato or in net
  /// worth (or the reverse) — the Holding would then report a patrimony the
  /// dashboard disagrees with, and there is no way for a user to tell which
  /// number is lying. The transaction id is stored in `linkedTransactionId` so
  /// deletion can undo both halves.
  ///
  /// The transaction is a TRANSFER with `sourceWalletId == null`: the money
  /// arrives from OUTSIDE the app (the sócio's own pocket), so no Conta loses
  /// it. Modelling it as income would inflate the Holding's "receita do mês"
  /// with capital that is not revenue, and modelling it as a wallet-to-wallet
  /// transfer would invent an outflow that never happened.
  ///
  /// A retirada is the SAME shape with a negative amount, which the app's own
  /// balance folds already handle correctly (a transfer adds `amount` to the
  /// destination and to the total, so a negative one subtracts). Its title and
  /// category say "Resgate", matching the wording the Reservas screen already
  /// uses for the identical operation, so the Extrato reads consistently.
  Future<String?> addContribution({
    required String memberId,
    required Cents amountCents,
    required DateTime date,
    String? note,
  }) async {
    final holding = _holding;
    final ownerId = _ownerId;
    if (holding == null || ownerId.isEmpty) return null;
    if (amountCents == 0) return null; // nothing to record
    state = const AsyncValue.loading();
    try {
      final id = const Uuid().v4();
      final txId = const Uuid().v4();
      final isWithdrawal = amountCents < 0;

      // Falls back to a generic label rather than failing the write: the name
      // is cosmetic (the contribution doc carries the authoritative memberId),
      // and refusing to record money because a stream had not loaded yet would
      // be a far worse outcome.
      final members = _ref.read(holdingMembersStreamProvider).value ?? const [];
      var name = 'sócio';
      for (final m in members) {
        if (m.id == memberId) name = m.name;
      }

      final contribution = HoldingContributionModel(
        id: id,
        userId: ownerId,
        workspaceId: holding.id,
        memberId: memberId,
        amountCents: amountCents,
        date: date,
        note: note,
        linkedTransactionId: txId,
        createdBy: _actorId,
        createdAt: DateTime.now(),
      );

      final tx = TransactionModel(
        id: txId,
        userId: ownerId,
        workspaceId: holding.id,
        title: isWithdrawal ? 'Resgate — $name' : 'Aporte — $name',
        // The single conversion back to the app's double-based ledger. Exact
        // for every value the cents engine accepts.
        amount: toReais(amountCents),
        type: TransactionType.transfer,
        category: isWithdrawal ? 'Resgate' : 'Aporte',
        date: date,
        description: note,
        walletId: _defaultWalletId(),
        sourceWalletId: null,
        // Back-reference that locks this row in the Extrato: it can only be
        // undone through deleteContribution, which removes both halves.
        holdingContributionId: id,
      );

      final batch = _fs.batch();
      batch.set(
        _fs.collection(_kContributionsCollection).doc(id),
        contribution.toFirestore(),
      );
      batch.set(
        _fs.collection('transactions').doc(txId),
        tx.toFirestore(),
      );
      await batch.commit();

      state = const AsyncValue.data(null);
      return id;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return null;
    }
  }

  /// Deletes an aporte and the transaction that mirrors it, in one batch — the
  /// exact inverse of [addContribution], so the two halves can never drift
  /// apart.
  ///
  /// The contribution is re-read from Firestore instead of from the stream:
  /// `linkedTransactionId` is what makes the undo complete, and reading it from
  /// the authoritative doc means a stale/partially-loaded stream can never
  /// leave an orphaned transaction sitting in the Extrato.
  Future<bool> deleteContribution(String contributionId) async {
    if (_holding == null) return false;
    state = const AsyncValue.loading();
    try {
      // Named docRef, not `ref`: inside this class `ref` would read as the
      // Riverpod one.
      final docRef =
          _fs.collection(_kContributionsCollection).doc(contributionId);
      final snap = await docRef.get();
      if (!snap.exists) {
        // Already gone — nothing to undo, and reporting failure would only
        // make the UI show an error for a state the user already wanted.
        state = const AsyncValue.data(null);
        return true;
      }
      final contribution = HoldingContributionModel.fromFirestore(snap);
      final batch = _fs.batch();
      batch.delete(docRef);
      final txId = contribution.linkedTransactionId;
      if (txId != null && txId.isNotEmpty) {
        // Deleting a doc that no longer exists makes the rules dereference
        // `resource.data` on null → PERMISSION_DENIED for the WHOLE batch, and
        // an aporte whose mirror was already swiped away (builds ≤ 171) could
        // never be undone. One read decides whether the mirror is still there.
        final txRef = _fs.collection('transactions').doc(txId);
        if ((await txRef.get()).exists) batch.delete(txRef);
      }
      await batch.commit();
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

final holdingNotifierProvider =
    StateNotifierProvider<HoldingNotifier, AsyncValue<void>>(
  HoldingNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Write-path glue
// ─────────────────────────────────────────────────────────────────────────────

/// The [HoldingStamp] the transaction write path must freeze new expenses with,
/// or null when no Holding is active.
///
/// [TransactionsNotifier] is built once per scope change and has no `Ref`, so
/// it cannot look the roster up itself — it takes this immutable snapshot
/// instead. Exposed from here (rather than from the transactions layer) because
/// this is the only place that already knows both "is a Holding active" and
/// "who its sócios are", and both answers must come from the SAME rebuild or a
/// stamp could carry one Carteira's id and another's roster.
///
/// Wire it in `transactionsNotifierProvider` as
/// `holdingStamp: ref.watch(activeHoldingStampProvider)`.
final activeHoldingStampProvider = Provider<HoldingStamp?>((ref) {
  final holding = ref.watch(activeHoldingProvider);
  if (holding == null) return null;
  final members = ref.watch(holdingMembersStreamProvider).value ?? const [];
  // No sócios yet → nothing to rateio. Returning a stamp with an empty roster
  // would be harmless (`splitFor` bails on an empty roster) but returning null
  // makes the intent explicit at the call site.
  if (members.isEmpty) return null;
  return HoldingStamp(workspaceId: holding.id, members: members);
});
