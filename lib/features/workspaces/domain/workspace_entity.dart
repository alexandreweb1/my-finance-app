import 'package:equatable/equatable.dart';

/// The kind of ledger space a workspace ("Carteira") represents.
enum WorkspaceType {
  personal, // Pessoa Física
  business, // Pessoa Jurídica / empresa
  holding; // Holding — patrimônio dividido entre sócios

  String get id => name;

  /// Unknown ids fall back to [personal] so a doc written by a NEWER app
  /// version still opens on an older build. Written as an exhaustive switch
  /// rather than a ternary: with a ternary, adding a type silently maps it to
  /// personal and the whole feature becomes dead code no test can catch.
  static WorkspaceType fromId(String? id) => switch (id) {
        'business' => WorkspaceType.business,
        'holding' => WorkspaceType.holding,
        _ => WorkspaceType.personal,
      };
}

/// How a Holding divides its patrimony between sócios.
enum HoldingQuotaMode {
  /// Quota = what the sócio contributed / everything contributed. Whoever puts
  /// in more owns more, automatically.
  proportional,

  /// The owner sets each sócio's percentage by hand; the app then reports how
  /// much each one SHOULD have contributed versus what they actually did.
  fixed;

  String get id => name;

  static HoldingQuotaMode fromId(String? id) =>
      id == 'fixed' ? HoldingQuotaMode.fixed : HoldingQuotaMode.proportional;
}

/// Role a member holds inside a workspace.
enum WorkspaceRole {
  editor, // full read/write
  viewer; // read-only

  String get id => name;

  static WorkspaceRole fromId(String? id) =>
      id == 'viewer' ? WorkspaceRole.viewer : WorkspaceRole.editor;
}

/// A "Carteira" — a self-contained ledger space (PF or PJ) owned by one user
/// and optionally shared with members (each with an editor/viewer role).
///
/// All ledger documents of a workspace carry `userId == ownerId` plus this
/// workspace's id in their `workspaceId` field.
class WorkspaceEntity extends Equatable {
  final String id;

  /// Uid of the owner. Ledger docs of this workspace are homed to this uid.
  final String ownerId;

  final String name;
  final WorkspaceType type;

  /// All member uids, ALWAYS including [ownerId] (uniform membership queries).
  final List<String> memberUids;

  /// Role per member uid. The owner is always an editor.
  final Map<String, WorkspaceRole> roles;

  final bool isDefault;
  final bool archived;
  final int order;
  final DateTime createdAt;

  /// Quota mode — meaningful only when [type] is [WorkspaceType.holding].
  /// Stored raw so an unknown future mode round-trips untouched instead of
  /// being silently rewritten to the default on the next save.
  final String? holdingQuotaMode;

  const WorkspaceEntity({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    required this.memberUids,
    required this.roles,
    this.isDefault = false,
    this.archived = false,
    this.order = 0,
    required this.createdAt,
    this.holdingQuotaMode,
  });

  bool get isBusiness => type == WorkspaceType.business;

  bool get isHolding => type == WorkspaceType.holding;

  /// The Holding's quota mode, defaulting to proportional. Meaningless (and
  /// unused) for non-Holding Carteiras.
  HoldingQuotaMode get quotaMode => HoldingQuotaMode.fromId(holdingQuotaMode);

  WorkspaceRole roleOf(String uid) => roles[uid] ?? WorkspaceRole.viewer;

  bool isEditor(String uid) => roleOf(uid) == WorkspaceRole.editor;

  @override
  List<Object?> get props => [
        id,
        ownerId,
        name,
        type,
        memberUids,
        roles,
        isDefault,
        archived,
        order,
        holdingQuotaMode,
      ];
}
