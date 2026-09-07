import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/holding_entities.dart';

class HoldingMemberModel extends HoldingMemberEntity {
  const HoldingMemberModel({
    required super.id,
    required super.userId,
    required super.workspaceId,
    required super.name,
    super.memberUid,
    super.quotaBps,
    required super.joinedAt,
    super.leftAt,
    required super.createdAt,
  });

  factory HoldingMemberModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    final created = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2020);
    return HoldingMemberModel(
      id: doc.id,
      userId: (d['userId'] as String?) ?? '',
      workspaceId: (d['workspaceId'] as String?) ?? '',
      name: (d['name'] as String?) ?? '',
      memberUid: d['memberUid'] as String?,
      quotaBps: (d['quotaBps'] as num?)?.round() ?? 0,
      // Falls back to createdAt, never DateTime.now(): a missing joinedAt must
      // not silently exclude a sócio from expenses they took part in.
      joinedAt: (d['joinedAt'] as Timestamp?)?.toDate() ?? created,
      leftAt: (d['leftAt'] as Timestamp?)?.toDate(),
      createdAt: created,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'workspaceId': workspaceId,
        'name': name,
        if (memberUid != null) 'memberUid': memberUid,
        'quotaBps': quotaBps,
        'joinedAt': Timestamp.fromDate(joinedAt),
        if (leftAt != null) 'leftAt': Timestamp.fromDate(leftAt!),
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory HoldingMemberModel.fromEntity(HoldingMemberEntity e) =>
      HoldingMemberModel(
        id: e.id,
        userId: e.userId,
        workspaceId: e.workspaceId,
        name: e.name,
        memberUid: e.memberUid,
        quotaBps: e.quotaBps,
        joinedAt: e.joinedAt,
        leftAt: e.leftAt,
        createdAt: e.createdAt,
      );
}

class HoldingContributionModel extends HoldingContributionEntity {
  const HoldingContributionModel({
    required super.id,
    required super.userId,
    required super.workspaceId,
    required super.memberId,
    required super.amountCents,
    required super.date,
    super.note,
    super.linkedTransactionId,
    required super.createdBy,
    required super.createdAt,
  });

  factory HoldingContributionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? const {};
    final raw = d['amountCents'];
    return HoldingContributionModel(
      id: doc.id,
      userId: (d['userId'] as String?) ?? '',
      workspaceId: (d['workspaceId'] as String?) ?? '',
      memberId: (d['memberId'] as String?) ?? '',
      // Firestore hands integers back as num; round rather than cast so a
      // malformed doc degrades to the nearest centavo instead of throwing.
      amountCents: (raw is num && raw.isFinite) ? raw.round() : 0,
      date: (d['date'] as Timestamp?)?.toDate() ?? DateTime(2020),
      note: d['note'] as String?,
      linkedTransactionId: d['linkedTransactionId'] as String?,
      createdBy: (d['createdBy'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime(2020),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'workspaceId': workspaceId,
        'memberId': memberId,
        'amountCents': amountCents,
        'date': Timestamp.fromDate(date),
        if (note != null) 'note': note,
        if (linkedTransactionId != null)
          'linkedTransactionId': linkedTransactionId,
        'createdBy': createdBy,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory HoldingContributionModel.fromEntity(HoldingContributionEntity e) =>
      HoldingContributionModel(
        id: e.id,
        userId: e.userId,
        workspaceId: e.workspaceId,
        memberId: e.memberId,
        amountCents: e.amountCents,
        date: e.date,
        note: e.note,
        linkedTransactionId: e.linkedTransactionId,
        createdBy: e.createdBy,
        createdAt: e.createdAt,
      );
}
