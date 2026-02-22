import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/error/exceptions.dart';
import '../models/transaction_model.dart';

abstract class TransactionRemoteDataSource {
  Stream<List<TransactionModel>> watchTransactions(String userId);
  Future<TransactionModel> addTransaction(TransactionModel transaction);
  Future<void> updateTransaction(TransactionModel transaction);
  Future<void> deleteTransaction(String transactionId);
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
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
  }

  @override
  Future<TransactionModel> addTransaction(TransactionModel transaction) async {
    try {
      final docRef = await _collection.add(transaction.toFirestore());
      final doc = await docRef.get();
      return TransactionModel.fromFirestore(doc);
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> updateTransaction(TransactionModel transaction) async {
    try {
      await _collection.doc(transaction.id).update(transaction.toFirestore());
    } catch (e) {
      throw ServerException(e.toString());
    }
  }

  @override
  Future<void> deleteTransaction(String transactionId) async {
    try {
      await _collection.doc(transactionId).delete();
    } catch (e) {
      throw ServerException(e.toString());
    }
  }
}
