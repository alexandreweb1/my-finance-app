import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_backlog_item_model.dart';

abstract class NotificationBacklogDatasource {
  Stream<List<NotificationBacklogItemModel>> watchItems(String userId);
  Future<void> addItem(NotificationBacklogItemModel item);
  Future<void> markImported(String itemId);
  Future<void> deleteItem(String itemId);
  Future<void> deleteAllPending(String userId);
}

class NotificationBacklogFirestoreDatasource
    implements NotificationBacklogDatasource {
  final FirebaseFirestore _firestore;

  NotificationBacklogFirestoreDatasource(this._firestore);

  CollectionReference get _col =>
      _firestore.collection('notification_backlog');

  @override
  Stream<List<NotificationBacklogItemModel>> watchItems(String userId) {
    // No composite index needed: single-field filter + client-side sort.
    return _col.where('userId', isEqualTo: userId).snapshots().map((snap) {
      final items = snap.docs
          .map(NotificationBacklogItemModel.fromFirestore)
          .toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
      // Cap at 200 most recent to avoid large lists.
      return items.length > 200 ? items.sublist(0, 200) : items;
    });
  }

  @override
  Future<void> addItem(NotificationBacklogItemModel item) async {
    // Use Firestore auto-ID; item.id is ignored on insert.
    await _col.add(item.toFirestore());
  }

  @override
  Future<void> markImported(String itemId) async {
    await _col.doc(itemId).update({'imported': true});
  }

  @override
  Future<void> deleteItem(String itemId) async {
    await _col.doc(itemId).delete();
  }

  @override
  Future<void> deleteAllPending(String userId) async {
    final snap = await _col
        .where('userId', isEqualTo: userId)
        .where('imported', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
