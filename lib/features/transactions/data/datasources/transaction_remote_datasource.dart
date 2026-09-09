import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/error/exceptions.dart';
import '../models/transaction_model.dart';

abstract class TransactionRemoteDataSource {
  Stream<List<TransactionModel>> watchTransactions(String userId);
  Future<TransactionModel> addTransaction(TransactionModel transaction);
  Future<void> updateTransaction(TransactionModel transaction);
  Future<void> deleteTransaction(String transactionId);

  /// Re-homes [ids] to another Carteira by stamping [workspaceId] on each
  /// (batched). `userId` and wallet refs are preserved so the move is
  /// non-destructive and reversible. A frozen Holding rateio
  /// (`holdingSplit`/`holdingPaidBy`) is DROPPED: it names the sócios of the
  /// Carteira it was created in and means nothing anywhere else.
  Future<void> moveToWorkspace(List<String> ids, String workspaceId);
}

class TransactionRemoteDataSourceImpl implements TransactionRemoteDataSource {
  final FirebaseFirestore _firestore;

  TransactionRemoteDataSourceImpl(this._firestore);

  CollectionReference get _collection =>
      _firestore.collection('transactions');

  @override
  Stream<List<TransactionModel>> watchTransactions(String userId) {
    return _collection
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => TransactionModel.fromFirestore(doc))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          return list;
        });
  }

  static const _kTimeout = Duration(seconds: 12);

  @override
  Future<TransactionModel> addTransaction(TransactionModel transaction) async {
    const timeoutMsg = ServerException(
        'Tempo limite excedido. Verifique se o Firestore está habilitado '
        'no Firebase Console.');
    try {
      // When the caller provides a client-generated id, write it deterministically
      // with .doc(id).set(): re-running the same write (recurrence generation,
      // retry) overwrites the same doc instead of creating a duplicate, and the
      // caller gets back the real doc id immediately (no phantom id from .add()).
      if (transaction.id.isNotEmpty) {
        await _collection
            .doc(transaction.id)
            .set(transaction.toFirestore())
            .timeout(_kTimeout, onTimeout: () => throw timeoutMsg);
        return transaction;
      }
      final docRef = await _collection
          .add(transaction.toFirestore())
          .timeout(_kTimeout, onTimeout: () => throw timeoutMsg);
      final doc = await docRef.get().timeout(_kTimeout);
      return TransactionModel.fromFirestore(doc);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> updateTransaction(TransactionModel transaction) async {
    try {
      await _collection
          .doc(transaction.id)
          .update(transaction.toFirestore())
          .timeout(_kTimeout);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    try {
      final docRef = _collection.doc(transactionId);
      // The Extrato half of a Holding aporte is removed ONLY together with its
      // contribution (HoldingNotifier.deleteContribution, one batch). Every UI
      // path already hides delete for it; this read is the last line so no
      // future caller can orphan the cap table. One extra read per delete.
      final snap = await docRef.get().timeout(_kTimeout);
      final data = snap.data() as Map<String, dynamic>?;
      final mirrorOf = data?['holdingContributionId'];
      if (mirrorOf is String && mirrorOf.isNotEmpty) {
        throw const ServerException(
            'Este lançamento espelha um aporte. Desfaça-o na tela Holding.');
      }
      await docRef.delete().timeout(_kTimeout);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> moveToWorkspace(List<String> ids, String workspaceId) async {
    if (ids.isEmpty) return;
    try {
      const chunk = 400; // Firestore batch limit is 500.
      for (var i = 0; i < ids.length; i += chunk) {
        final batch = _firestore.batch();
        for (final id in ids.skip(i).take(chunk)) {
          batch.update(_collection.doc(id), {
            'workspaceId': workspaceId,
            // A frozen rateio describes the sócios of the Holding it was
            // created in. Outside it the map is meaningless, and the rules
            // deny a holdingSplit inside a PF/PJ Carteira — which failed the
            // WHOLE batch, plain docs included (auditoria 2026-09-08 #3).
            // Dropped on every move; a no-op on docs that never had one, and
            // inside a Holding the dynamic projection still covers the expense.
            'holdingSplit': FieldValue.delete(),
            'holdingPaidBy': FieldValue.delete(),
          });
        }
        await batch.commit().timeout(_kTimeout);
      }
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
