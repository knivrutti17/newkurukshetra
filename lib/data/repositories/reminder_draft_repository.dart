import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reminder_draft.dart';

class ReminderDraftRepository {
  ReminderDraftRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _drafts =>
      _firestore.collection('reminderDrafts');

  Stream<List<ReminderDraft>> watchDrafts({
    String instituteId = 'demo-institute',
  }) {
    return _drafts
        .where('instituteId', isEqualTo: instituteId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(ReminderDraft.fromFirestore).toList(),
        );
  }

  Future<List<ReminderDraft>> getDrafts({
    String instituteId = 'demo-institute',
  }) async {
    final snapshot = await _drafts
        .where('instituteId', isEqualTo: instituteId)
        .orderBy('updatedAt', descending: true)
        .get();
    return snapshot.docs.map(ReminderDraft.fromFirestore).toList();
  }

  Future<ReminderDraft?> getDraftForInstallment({
    required String instituteId,
    required String feeInstallmentId,
  }) async {
    final id = ReminderDraft.documentId(
      instituteId: instituteId,
      feeInstallmentId: feeInstallmentId,
    );
    final doc = await _drafts.doc(id).get();
    if (!doc.exists) {
      return null;
    }
    return ReminderDraft.fromFirestore(doc);
  }

  Future<ReminderDraft> saveDraft(ReminderDraft draft) async {
    final docId = draft.id.isEmpty
        ? ReminderDraft.documentId(
            instituteId: draft.instituteId,
            feeInstallmentId: draft.feeInstallmentId,
          )
        : draft.id;
    final createdAt = draft.createdAt;
    final updatedAt = DateTime.now();
    final record = draft.copyWith(
      id: docId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      status: draft.status,
    );
    await _drafts.doc(docId).set(record.toFirestore(), SetOptions(merge: true));
    return record;
  }

  Future<ReminderDraft> updateDraft(ReminderDraft draft) async {
    final updated = draft.copyWith(updatedAt: DateTime.now());
    await _drafts.doc(updated.id).update(updated.toFirestore());
    return updated;
  }

  Future<ReminderDraft> approveDraft(
    ReminderDraft draft,
    String approvedBy,
  ) async {
    final now = DateTime.now();
    final updated = draft.copyWith(
      status: ReminderDraftStatus.approved,
      approvedBy: approvedBy,
      approvedAt: now,
      cancelledBy: null,
      cancelledAt: null,
      updatedAt: now,
    );
    await _drafts
        .doc(updated.id)
        .set(updated.toFirestore(), SetOptions(merge: true));
    return updated;
  }

  Future<ReminderDraft> cancelDraft(
    ReminderDraft draft,
    String cancelledBy,
  ) async {
    final now = DateTime.now();
    final updated = draft.copyWith(
      status: ReminderDraftStatus.cancelled,
      cancelledBy: cancelledBy,
      cancelledAt: now,
      updatedAt: now,
    );
    await _drafts
        .doc(updated.id)
        .set(updated.toFirestore(), SetOptions(merge: true));
    return updated;
  }
}
