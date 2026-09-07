import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:my_finance_app/core/providers/effective_user_provider.dart';
import 'package:my_finance_app/core/providers/workspace_provider.dart';
import 'package:my_finance_app/features/auth/domain/entities/user_entity.dart';
import 'package:my_finance_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:my_finance_app/features/holding/domain/holding_entities.dart';
import 'package:my_finance_app/features/holding/presentation/providers/holding_provider.dart';
import 'package:my_finance_app/features/subscription/presentation/providers/subscription_provider.dart';
import 'package:my_finance_app/features/transactions/domain/entities/transaction_entity.dart';
import 'package:my_finance_app/features/workspaces/domain/workspace_entity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The promise the user made the feature on: "essa opção só deve aparecer na
// carteira Holding, na carteira PF isso não aparece."
//
// These tests hold the line at the provider level, which is where every UI
// surface and every write path asks the question. If activeHoldingProvider
// answers wrongly, the Holding tool appears in a personal Carteira and — worse
// — a rateio could be stamped onto a PF expense.
// ─────────────────────────────────────────────────────────────────────────────

WorkspaceEntity _ws(
  String id, {
  required WorkspaceType type,
  bool isDefault = false,
  int order = 0,
  String owner = 'owner1',
  String? quotaMode,
}) =>
    WorkspaceEntity(
      id: id,
      ownerId: owner,
      name: id,
      type: type,
      memberUids: [owner],
      roles: {owner: WorkspaceRole.editor},
      isDefault: isDefault,
      order: order,
      createdAt: DateTime(2024, 1, 1),
      holdingQuotaMode: quotaMode,
    );

ProviderContainer _make({
  required List<WorkspaceEntity> own,
  List<WorkspaceEntity> shared = const [],
  Map<String, dynamic>? profile,
  bool pro = true,
  String user = 'owner1',
  List<HoldingMemberEntity>? members,
}) =>
    ProviderContainer(overrides: [
      // Only overridden when a test needs the roster: the sócios stream talks
      // to Firestore, and leaving it live is itself the assertion that the
      // guards short-circuit BEFORE any query fires.
      if (members != null)
        holdingMembersStreamProvider
            .overrideWith((ref) => Stream.value(members)),
      authStateProvider.overrideWith(
          (ref) => Stream.value(UserEntity(id: user, email: 't@t.co'))),
      userProfileStreamProvider.overrideWith((ref) => Stream.value(profile)),
      ownWorkspacesStreamProvider.overrideWith((ref) => Stream.value(own)),
      sharedWorkspacesStreamProvider
          .overrideWith((ref) => Stream.value(shared)),
      canUseWorkspacesProvider.overrideWithValue(pro),
      isSubscriptionLoadingProvider.overrideWithValue(false),
    ]);

Future<void> _settle(ProviderContainer c) async {
  await c.read(authStateProvider.future);
  await c.read(userProfileStreamProvider.future);
  await c.read(ownWorkspacesStreamProvider.future);
  await c.read(sharedWorkspacesStreamProvider.future);
}

final _pessoal = _ws('pessoal', type: WorkspaceType.personal, isDefault: true);
final _empresa = _ws('empresa', type: WorkspaceType.business, order: 1);
final _holding = _ws('holding', type: WorkspaceType.holding, order: 2);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('the Holding surfaces appear ONLY in a Holding Carteira', () {
    test('a personal (PF) Carteira exposes nothing', () async {
      final c = _make(own: [_pessoal, _empresa, _holding]);
      addTearDown(c.dispose);
      await _settle(c);

      // Default selection = the PF Carteira.
      expect(c.read(activeHoldingProvider), isNull);
      expect(c.read(isHoldingActiveProvider), isFalse);
      expect(c.read(activeHoldingStampProvider), isNull);
    });

    test('a business (PJ) Carteira exposes nothing either', () async {
      final c = _make(own: [_pessoal, _empresa, _holding]);
      addTearDown(c.dispose);
      await _settle(c);
      await c.read(activeWorkspaceIdProvider.notifier).select('empresa');

      expect(c.read(activeHoldingProvider), isNull);
      expect(c.read(isHoldingActiveProvider), isFalse);
      expect(c.read(activeHoldingStampProvider), isNull);
    });

    test('a Holding Carteira does expose them', () async {
      final c = _make(own: [_pessoal, _empresa, _holding]);
      addTearDown(c.dispose);
      await _settle(c);
      await c.read(activeWorkspaceIdProvider.notifier).select('holding');

      expect(c.read(activeHoldingProvider)?.id, 'holding');
      expect(c.read(isHoldingActiveProvider), isTrue);
    });

    test('switching away from the Holding closes the surfaces again', () async {
      final c = _make(own: [_pessoal, _empresa, _holding]);
      addTearDown(c.dispose);
      await _settle(c);

      await c.read(activeWorkspaceIdProvider.notifier).select('holding');
      expect(c.read(isHoldingActiveProvider), isTrue);

      await c.read(activeWorkspaceIdProvider.notifier).select('pessoal');
      expect(c.read(isHoldingActiveProvider), isFalse);
      expect(c.read(activeHoldingStampProvider), isNull);
    });

    test('"Todas juntas" exposes nothing, even with a Holding selected before',
        () async {
      // In the combined view the write stamp resolves to the DEFAULT Carteira,
      // so a sócio or an aporte homed off the "active" Holding would land in
      // the wrong Carteira and be invisible from both.
      final c = _make(own: [_pessoal, _empresa, _holding]);
      addTearDown(c.dispose);
      await _settle(c);

      await c.read(activeWorkspaceIdProvider.notifier).select('holding');
      expect(c.read(isHoldingActiveProvider), isTrue);

      await c.read(activeWorkspaceIdProvider.notifier).select(kAllWorkspaces);
      expect(c.read(isCombinedViewProvider), isTrue);
      expect(c.read(activeHoldingProvider), isNull);
      expect(c.read(isHoldingActiveProvider), isFalse);
      expect(c.read(activeHoldingStampProvider), isNull);
    });

    test('a user with no Holding at all never sees the surfaces', () async {
      final c = _make(own: [_pessoal, _empresa]);
      addTearDown(c.dispose);
      await _settle(c);
      expect(c.read(isHoldingActiveProvider), isFalse);
    });

    test(
        'a free user pinned to the default PF Carteira sees nothing, '
        'even owning a Holding', () async {
      final c = _make(own: [_pessoal, _holding], pro: false);
      addTearDown(c.dispose);
      await _settle(c);

      // Free users cannot switch Carteira; the scope snaps back to default.
      await c.read(activeWorkspaceIdProvider.notifier).select('holding');
      expect(c.read(isHoldingActiveProvider), isFalse);
    });
  });

  group('the write stamp is bound to one Carteira', () {
    test('the stamp names the Holding, so a doc bound elsewhere is refused',
        () async {
      final c = _make(
        own: [_pessoal, _holding],
        members: [
          HoldingMemberEntity(
            id: 'p_alex',
            userId: 'owner1',
            workspaceId: 'holding',
            name: 'Alexandre',
            joinedAt: DateTime(2024, 1, 1),
            createdAt: DateTime(2024, 1, 1),
          ),
          HoldingMemberEntity(
            id: 'p_marina',
            userId: 'owner1',
            workspaceId: 'holding',
            name: 'Marina',
            joinedAt: DateTime(2024, 1, 1),
            createdAt: DateTime(2024, 1, 1),
          ),
        ],
      );
      addTearDown(c.dispose);
      await _settle(c);
      await c.read(activeWorkspaceIdProvider.notifier).select('holding');
      // Let the sócios stream deliver before reading the stamp.
      await c.read(holdingMembersStreamProvider.future);

      final stamp = c.read(activeHoldingStampProvider);
      expect(stamp, isNotNull);
      expect(stamp!.workspaceId, 'holding');

      // A bank-notification capture is homed to the DEFAULT Carteira even
      // while the Holding is on screen. The stamp must refuse it.
      expect(
        stamp.splitFor(
          targetWorkspaceId: 'pessoal',
          type: TransactionType.expense,
          amount: 90.0,
          date: DateTime(2025, 6, 1),
          seed: 'tx',
        ),
        isNull,
      );

      // ...but the SAME expense bound to the Holding itself is split.
      final split = stamp.splitFor(
        targetWorkspaceId: 'holding',
        type: TransactionType.expense,
        amount: 90.0,
        date: DateTime(2025, 6, 1),
        seed: 'tx',
      );
      expect(split, isNotNull);
      expect(split!.values.fold<int>(0, (a, b) => a + b), 9000);
      expect(split.keys.toSet(), {'p_alex', 'p_marina'});
    });
  });

  group('quota mode round-trips per Holding', () {
    test('defaults to proportional and reads back fixed when set', () async {
      final c = _make(own: [
        _pessoal,
        _ws('h1', type: WorkspaceType.holding, order: 2),
        _ws('h2', type: WorkspaceType.holding, order: 3, quotaMode: 'fixed'),
      ]);
      addTearDown(c.dispose);
      await _settle(c);

      await c.read(activeWorkspaceIdProvider.notifier).select('h1');
      expect(c.read(activeHoldingProvider)!.quotaMode,
          HoldingQuotaMode.proportional);

      await c.read(activeWorkspaceIdProvider.notifier).select('h2');
      expect(c.read(activeHoldingProvider)!.quotaMode, HoldingQuotaMode.fixed);
    });

    test('an unknown mode written by a newer app falls back safely', () {
      expect(HoldingQuotaMode.fromId('something_new'),
          HoldingQuotaMode.proportional);
      expect(HoldingQuotaMode.fromId(null), HoldingQuotaMode.proportional);
    });
  });

  group('an older app build reading a Holding doc', () {
    test('an unknown Carteira type degrades to personal, never crashes', () {
      // This is what a 1.1.8 client does with a type it has never heard of.
      expect(WorkspaceType.fromId('holding'), WorkspaceType.holding);
      expect(WorkspaceType.fromId('galactic'), WorkspaceType.personal);
      expect(WorkspaceType.fromId(null), WorkspaceType.personal);
      expect(WorkspaceType.fromId('business'), WorkspaceType.business);
    });

    test('the three types stay distinguishable', () {
      expect(_holding.isHolding, isTrue);
      expect(_holding.isBusiness, isFalse);
      expect(_empresa.isBusiness, isTrue);
      expect(_empresa.isHolding, isFalse);
      expect(_pessoal.isHolding, isFalse);
      expect(_pessoal.isBusiness, isFalse);
    });
  });
}
