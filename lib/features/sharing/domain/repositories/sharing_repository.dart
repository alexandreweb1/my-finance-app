import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/invitation_entity.dart';

abstract class SharingRepository {
  Future<Either<Failure, void>> sendInvitation({
    required String masterUserId,
    required String masterEmail,
    required String masterName,
    required String inviteeEmail,
    String? workspaceId,
    String? workspaceName,
    String role = 'editor',
  });

  Stream<Either<Failure, List<InvitationEntity>>> watchPendingInvitationsForEmail(
      String email);

  Stream<Either<Failure, List<InvitationEntity>>> watchCollaborators(
      String masterUserId);

  /// Convites enviados pelo master que ainda aguardam resposta.
  Stream<Either<Failure, List<InvitationEntity>>> watchSentPendingInvitations(
      String masterUserId);

  Future<Either<Failure, void>> acceptInvitation({
    required String invitationId,
    required String inviteeUserId,
    required String masterUserId,
    String? workspaceId,
  });

  Future<Either<Failure, void>> declineInvitation(String invitationId);

  /// Master cancela um convite pendente que ele mesmo enviou.
  Future<Either<Failure, void>> cancelInvitation(String invitationId);

  Future<Either<Failure, void>> removeCollaborator({
    required String invitationId,
    required String collaboratorUserId,
    String? workspaceId,
  });

  Future<Either<Failure, void>> leaveSharedAccount(String userId);

  Future<Either<Failure, void>> leaveWorkspace(String workspaceId);
}
