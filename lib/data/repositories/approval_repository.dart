import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/approval_action.dart';

class ApprovalAccessScope {
  const ApprovalAccessScope({
    this.instituteId = 'demo-institute',
    this.status,
    this.type,
    this.startDate,
    this.endDate,
  });

  final String? instituteId;
  final String? status;
  final String? type;
  final DateTime? startDate;
  final DateTime? endDate;
}

abstract interface class ApprovalRepository {
  Stream<List<ApprovalAction>> watchActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
    int limit = 300,
  });

  Future<List<ApprovalAction>> getActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
  });

  Future<ApprovalAction?> getActionById(String id);

  Future<ApprovalAction> createAction(ApprovalAction action);

  Future<ApprovalAction> updateDecision(
    String id, {
    required String status,
    String? reviewer,
    String? rejectionReason,
    required DateTime decisionAt,
  });

  Future<bool> isActionsCollectionEmpty();
}

abstract interface class ApprovalSeedRepository {
  Future<bool> isActionsCollectionEmpty();
  Future<int> countExistingSampleActions(List<ApprovalAction> actions);
  Future<void> createMissingSampleActions(List<ApprovalAction> actions);
}

class FirestoreApprovalRepository
    implements ApprovalRepository, ApprovalSeedRepository {
  FirestoreApprovalRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _pendingActions =>
      _firestore.collection('pendingActions');

  @override
  Stream<List<ApprovalAction>> watchActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
    int limit = 300,
  }) {
    Query<Map<String, dynamic>> query = _pendingActions.limit(limit);

    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.status != null && scope.status != 'all') {
      query = query.where('status', isEqualTo: scope.status);
    }
    if (scope.type != null && scope.type != 'all') {
      query = query.where('type', isEqualTo: scope.type);
    }

    return query.snapshots().map((snapshot) {
      var actions = snapshot.docs.map(ApprovalAction.fromFirestore).toList();

      if (scope.startDate != null) {
        actions = actions
            .where((a) => !a.requestedAt.isBefore(scope.startDate!))
            .toList();
      }
      if (scope.endDate != null) {
        actions = actions
            .where((a) => !a.requestedAt.isAfter(scope.endDate!))
            .toList();
      }

      actions.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
      return actions;
    });
  }

  @override
  Future<List<ApprovalAction>> getActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
  }) async {
    Query<Map<String, dynamic>> query = _pendingActions;

    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.status != null && scope.status != 'all') {
      query = query.where('status', isEqualTo: scope.status);
    }
    if (scope.type != null && scope.type != 'all') {
      query = query.where('type', isEqualTo: scope.type);
    }

    final snapshot = await query.get();
    var actions = snapshot.docs.map(ApprovalAction.fromFirestore).toList();

    if (scope.startDate != null) {
      actions = actions
          .where((a) => !a.requestedAt.isBefore(scope.startDate!))
          .toList();
    }
    if (scope.endDate != null) {
      actions = actions
          .where((a) => !a.requestedAt.isAfter(scope.endDate!))
          .toList();
    }

    actions.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return actions;
  }

  @override
  Future<ApprovalAction?> getActionById(String id) async {
    final doc = await _pendingActions.doc(id).get();
    if (!doc.exists) return null;
    return ApprovalAction.fromFirestore(doc);
  }

  @override
  Future<ApprovalAction> createAction(ApprovalAction action) async {
    if (action.id.isEmpty) {
      final docRef = _pendingActions.doc();
      final created = action.copyWith(id: docRef.id);
      await docRef.set(created.toFirestore());
      return created;
    }
    await _pendingActions.doc(action.id).set(action.toFirestore());
    return action;
  }

  @override
  Future<ApprovalAction> updateDecision(
    String id, {
    required String status,
    String? reviewer,
    String? rejectionReason,
    required DateTime decisionAt,
  }) async {
    final docRef = _pendingActions.doc(id);
    return _firestore.runTransaction<ApprovalAction>((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        throw StateError('Approval action not found: $id');
      }

      final existing = ApprovalAction.fromFirestore(snapshot);
      if (!existing.isPending) {
        throw StateError(
          'Action "$id" has already been decided as "${existing.statusLabel}".',
        );
      }

      final isApproval = status == 'approved' || status == 'awaiting_execution';
      final updateData = <String, dynamic>{
        'status': status,
        if (isApproval) 'approvedBy': reviewer,
        if (isApproval) 'approvedAt': Timestamp.fromDate(decisionAt),
        if (!isApproval) 'rejectedBy': reviewer,
        if (!isApproval) 'rejectedAt': Timestamp.fromDate(decisionAt),
        if (!isApproval && rejectionReason != null)
          'rejectionReason': rejectionReason,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      transaction.update(docRef, updateData);

      return existing.copyWith(
        status: status,
        approvedBy: isApproval ? reviewer : existing.approvedBy,
        approvedAt: isApproval ? decisionAt : existing.approvedAt,
        rejectedBy: !isApproval ? reviewer : existing.rejectedBy,
        rejectedAt: !isApproval ? decisionAt : existing.rejectedAt,
        rejectionReason:
            !isApproval ? rejectionReason : existing.rejectionReason,
        updatedAt: DateTime.now(),
      );
    });
  }

  @override
  Future<bool> isActionsCollectionEmpty() async {
    final snapshot = await _pendingActions.limit(1).get();
    return snapshot.docs.isEmpty;
  }

  @override
  Future<int> countExistingSampleActions(List<ApprovalAction> actions) async {
    var count = 0;
    for (final action in actions) {
      final doc = await _pendingActions.doc(action.id).get();
      if (doc.exists) count++;
    }
    return count;
  }

  @override
  Future<void> createMissingSampleActions(List<ApprovalAction> actions) async {
    for (final action in actions) {
      final doc = await _pendingActions.doc(action.id).get();
      if (!doc.exists) {
        await _pendingActions.doc(action.id).set(action.toFirestore());
      }
    }
  }
}

