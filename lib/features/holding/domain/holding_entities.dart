import 'package:equatable/equatable.dart';

import '../../../core/utils/cents.dart';

/// A sócio of a Holding Carteira.
///
/// Two kinds live in the same collection:
///   * LINKED — [memberUid] points at an app user who is a member of the
///     Carteira, so they see their own position on their own phone.
///   * STANDALONE — [memberUid] is null and the sócio exists only as a name the
///     owner typed in. Someone who does not use Fintab still gets counted.
///
/// Both participate identically in every calculation.
class HoldingMemberEntity extends Equatable {
  final String id;

  /// Uid of the Carteira OWNER — every ledger doc is homed to the owner.
  final String userId;

  /// The Holding this sócio belongs to.
  final String workspaceId;

  final String name;

  /// App user behind this sócio, when there is one.
  final String? memberUid;

  /// Fixed-quota percentage in basis points (5000 = 50,00%). Ignored in
  /// proportional mode. Basis points, never a double: seven sócios at 100/7
  /// each sum to 100.00000000000001 as doubles and would fail a == 100 check.
  final int quotaBps;

  /// When this sócio started participating. Expenses dated BEFORE this are not
  /// theirs. Defaults to the Carteira's creation date, never "now", so adding
  /// the founding sócios later does not accidentally exclude them from the
  /// history they were actually part of.
  final DateTime joinedAt;

  /// When they stopped participating, if they did. Their past shares stay
  /// exactly as they were.
  final DateTime? leftAt;

  final DateTime createdAt;

  const HoldingMemberEntity({
    required this.id,
    required this.userId,
    required this.workspaceId,
    required this.name,
    this.memberUid,
    this.quotaBps = 0,
    required this.joinedAt,
    this.leftAt,
    required this.createdAt,
  });

  bool get isLinked => memberUid != null && memberUid!.isNotEmpty;

  /// Whether this sócio was participating on [date] — the rule that makes the
  /// roster a pure function of an expense's date.
  bool participatesOn(DateTime date) {
    if (date.isBefore(joinedAt)) return false;
    final out = leftAt;
    if (out != null && !date.isBefore(out)) return false;
    return true;
  }

  bool get isActive => leftAt == null;

  HoldingMemberEntity copyWith({
    String? name,
    int? quotaBps,
    DateTime? joinedAt,
    DateTime? leftAt,
    bool clearLeftAt = false,
  }) =>
      HoldingMemberEntity(
        id: id,
        userId: userId,
        workspaceId: workspaceId,
        name: name ?? this.name,
        memberUid: memberUid,
        quotaBps: quotaBps ?? this.quotaBps,
        joinedAt: joinedAt ?? this.joinedAt,
        leftAt: clearLeftAt ? null : (leftAt ?? this.leftAt),
        createdAt: createdAt,
      );

  @override
  List<Object?> get props =>
      [id, userId, workspaceId, name, memberUid, quotaBps, joinedAt, leftAt];
}

/// One aporte (or retirada) by a sócio — the money trail behind "sei que
/// coloquei cada centavo".
///
/// Append-only by design: entries are never silently edited. Only [note] can
/// change; a wrong amount is corrected with an opposing entry, so the history
/// still shows what happened.
class HoldingContributionEntity extends Equatable {
  final String id;

  /// Uid of the Carteira owner (ledger homing).
  final String userId;

  final String workspaceId;

  /// The sócio this belongs to — a [HoldingMemberEntity] id.
  final String memberId;

  /// Centavos. Positive = aporte, negative = retirada. Stored as an int so the
  /// value is exact and the Firestore rules can actually validate it.
  final Cents amountCents;

  final DateTime date;

  final String? note;

  /// Transaction created alongside this aporte, so the money also shows up in
  /// the Extrato and in the Holding's net worth. Written in the same batch.
  final String? linkedTransactionId;

  final String createdBy;
  final DateTime createdAt;

  const HoldingContributionEntity({
    required this.id,
    required this.userId,
    required this.workspaceId,
    required this.memberId,
    required this.amountCents,
    required this.date,
    this.note,
    this.linkedTransactionId,
    required this.createdBy,
    required this.createdAt,
  });

  bool get isWithdrawal => amountCents < 0;

  double get amountReais => toReais(amountCents);

  @override
  List<Object?> get props => [
        id,
        userId,
        workspaceId,
        memberId,
        amountCents,
        date,
        note,
        linkedTransactionId,
      ];
}

/// The sócios participating on [date] — the roster a rateio must use.
///
/// Sorted by id so the result is deterministic regardless of stream order.
List<HoldingMemberEntity> rosterAsOf(
  List<HoldingMemberEntity> members,
  DateTime date,
) {
  final out = members.where((m) => m.participatesOn(date)).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  return out;
}
