import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_finance_app/core/error/failures.dart';
import 'package:my_finance_app/core/providers/effective_user_provider.dart';
import 'package:my_finance_app/core/providers/workspace_provider.dart';
import 'package:my_finance_app/features/auth/domain/entities/user_entity.dart';
import 'package:my_finance_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:my_finance_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:my_finance_app/features/sharing/domain/entities/invitation_entity.dart';
import 'package:my_finance_app/features/sharing/domain/repositories/sharing_repository.dart';
import 'package:my_finance_app/features/sharing/presentation/providers/sharing_provider.dart';
import 'package:my_finance_app/features/subscription/presentation/providers/subscription_provider.dart';
import 'package:my_finance_app/features/workspaces/domain/workspace_entity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Compartilhamento é POR CARTEIRA: a tela precisa deixar escolher qual Carteira
// está sendo compartilhada — e essa escolha manda tanto no convite que sai
// quanto na lista de quem já tem acesso (era uma lista única, sem recorte).
// ─────────────────────────────────────────────────────────────────────────────

class _FakeSharingRepository implements SharingRepository {
  _FakeSharingRepository({
    this.collaborators = const [],
    this.sentPending = const [],
  });

  final List<InvitationEntity> collaborators;
  final List<InvitationEntity> sentPending;

  final sent = <Map<String, String?>>[];
  final canceled = <String>[];
  final removed = <String>[];

  @override
  Future<Either<Failure, void>> sendInvitation({
    required String masterUserId,
    required String masterEmail,
    required String masterName,
    required String inviteeEmail,
    String? workspaceId,
    String? workspaceName,
    String role = 'editor',
  }) async {
    sent.add({
      'email': inviteeEmail,
      'workspaceId': workspaceId,
      'workspaceName': workspaceName,
      'role': role,
    });
    return const Right(null);
  }

  @override
  Stream<Either<Failure, List<InvitationEntity>>>
      watchPendingInvitationsForEmail(String email) =>
          Stream.value(const Right([]));

  @override
  Stream<Either<Failure, List<InvitationEntity>>> watchCollaborators(
          String masterUserId) =>
      Stream.value(Right(collaborators));

  @override
  Stream<Either<Failure, List<InvitationEntity>>> watchSentPendingInvitations(
          String masterUserId) =>
      Stream.value(Right(sentPending));

  @override
  Future<Either<Failure, void>> acceptInvitation({
    required String invitationId,
    required String inviteeUserId,
    required String masterUserId,
    String? workspaceId,
  }) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> declineInvitation(String invitationId) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> cancelInvitation(String invitationId) async {
    canceled.add(invitationId);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> removeCollaborator({
    required String invitationId,
    required String collaboratorUserId,
    String? workspaceId,
  }) async {
    removed.add(invitationId);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> leaveSharedAccount(String userId) async =>
      const Right(null);

  @override
  Future<Either<Failure, void>> leaveWorkspace(String workspaceId) async =>
      const Right(null);
}

WorkspaceEntity _ws(String id, String name,
        {bool isDefault = false, int order = 0}) =>
    WorkspaceEntity(
      id: id,
      ownerId: 'owner1',
      name: name,
      type: isDefault ? WorkspaceType.personal : WorkspaceType.business,
      memberUids: const ['owner1'],
      roles: const {'owner1': WorkspaceRole.editor},
      isDefault: isDefault,
      order: order,
      createdAt: DateTime(2020, 1, 1),
    );

InvitationEntity _inv(
  String id, {
  required String email,
  required String status,
  String? workspaceId,
  String? workspaceName,
  String role = 'editor',
  String? collaboratorUserId,
}) =>
    InvitationEntity(
      id: id,
      masterUserId: 'owner1',
      masterEmail: 'owner@t.co',
      masterName: 'Dono',
      inviteeEmail: email,
      status: status,
      createdAt: DateTime(2026, 1, 1),
      collaboratorUserId: collaboratorUserId,
      workspaceId: workspaceId,
      workspaceName: workspaceName,
      role: role,
    );

Future<void> _pump(
  WidgetTester tester,
  _FakeSharingRepository repo, {
  required List<WorkspaceEntity> own,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) =>
            Stream.value(const UserEntity(id: 'owner1', email: 'owner@t.co'))),
        userProfileStreamProvider
            .overrideWith((ref) => Stream.value({'defaultWorkspaceId': 'pessoal'})),
        ownWorkspacesStreamProvider.overrideWith((ref) => Stream.value(own)),
        sharedWorkspacesStreamProvider
            .overrideWith((ref) => Stream.value(const [])),
        isProProvider.overrideWithValue(true),
        sharingRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: SharingSettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final pessoal = _ws('pessoal', 'Pessoal', isDefault: true);
  final empresa = _ws('empresa', 'Empresa', order: 1);

  testWidgets('o seletor de Carteira aparece mesmo com uma única Carteira',
      (tester) async {
    // Antes o dropdown só existia com 2+ Carteiras, então o usuário nunca via
    // QUAL Carteira o convite ia liberar.
    await _pump(tester, _FakeSharingRepository(), own: [pessoal]);

    expect(find.text('Carteira a compartilhar'), findsOneWidget);
    expect(find.text('Pessoal'), findsWidgets);
  });

  testWidgets('a lista de acessos segue a Carteira selecionada',
      (tester) async {
    final repo = _FakeSharingRepository(collaborators: [
      _inv('i1',
          email: 'ana@t.co',
          status: 'accepted',
          workspaceId: 'pessoal',
          workspaceName: 'Pessoal',
          collaboratorUserId: 'u-ana'),
      _inv('i2',
          email: 'bruno@t.co',
          status: 'accepted',
          workspaceId: 'empresa',
          workspaceName: 'Empresa',
          role: 'viewer',
          collaboratorUserId: 'u-bruno'),
    ]);
    await _pump(tester, repo, own: [pessoal, empresa]);

    expect(find.text('Quem tem acesso a "Pessoal"'), findsOneWidget);
    expect(find.text('ana@t.co'), findsOneWidget);
    expect(find.text('bruno@t.co'), findsNothing);

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empresa').last);
    await tester.pumpAndSettle();

    expect(find.text('Quem tem acesso a "Empresa"'), findsOneWidget);
    expect(find.text('bruno@t.co'), findsOneWidget);
    expect(find.text('ana@t.co'), findsNothing);
  });

  testWidgets('o convite sai para a Carteira escolhida, não para a padrão',
      (tester) async {
    final repo = _FakeSharingRepository();
    await _pump(tester, repo, own: [pessoal, empresa]);

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empresa').last);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'novo@t.co');
    await tester.tap(find.text('Só ver'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Convidar'));
    await tester.pumpAndSettle();

    expect(repo.sent, hasLength(1));
    expect(repo.sent.single['workspaceId'], 'empresa');
    expect(repo.sent.single['workspaceName'], 'Empresa');
    expect(repo.sent.single['role'], 'viewer');
  });

  testWidgets('convite pendente enviado aparece e pode ser cancelado',
      (tester) async {
    final repo = _FakeSharingRepository(sentPending: [
      _inv('i-pend',
          email: 'carla@t.co',
          status: 'pending',
          workspaceId: 'pessoal',
          workspaceName: 'Pessoal'),
    ]);
    await _pump(tester, repo, own: [pessoal, empresa]);

    expect(find.text('carla@t.co'), findsOneWidget);
    expect(find.textContaining('Aguardando aceite'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Cancelar convite'));
    await tester.tap(find.byTooltip('Cancelar convite'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancelar convite'));
    await tester.pumpAndSettle();

    expect(repo.canceled, ['i-pend']);
  });

  testWidgets('acessos fora do seletor (modelo antigo) continuam visíveis',
      (tester) async {
    final repo = _FakeSharingRepository(collaborators: [
      _inv('i-legacy',
          email: 'legado@t.co',
          status: 'accepted',
          collaboratorUserId: 'u-legado'),
    ]);
    await _pump(tester, repo, own: [pessoal]);

    expect(find.text('Outros acessos'), findsOneWidget);
    expect(find.text('legado@t.co'), findsOneWidget);
  });
}
