import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/class_session.dart';

class TimetableAccessScope {
  const TimetableAccessScope({
    this.instituteId = 'demo-institute',
    this.trainerId,
    this.batchId,
    this.startDate,
    this.endDate,
  });

  final String? instituteId;
  final String? trainerId;
  final String? batchId;
  final DateTime? startDate;
  final DateTime? endDate;
}

abstract interface class TimetableRepository {
  Stream<List<ClassSession>> watchSessions({
    TimetableAccessScope scope = const TimetableAccessScope(),
    int limit = 300,
  });

  Future<List<ClassSession>> getSessions({
    TimetableAccessScope scope = const TimetableAccessScope(),
  });

  Future<ClassSession?> getSessionById(String id);

  Future<ClassSession> createSession(ClassSession session);

  Future<ClassSession> updateSession(ClassSession session);

  Future<ClassSession> cancelSession(String id);

  Future<bool> isSessionsCollectionEmpty();
}

abstract interface class TimetableSeedRepository {
  Future<bool> isSessionsCollectionEmpty();
  Future<int> countExistingSampleSessions(List<ClassSession> sessions);
  Future<void> createMissingSampleSessions(List<ClassSession> sessions);
}

class FirestoreTimetableRepository
    implements TimetableRepository, TimetableSeedRepository {
  FirestoreTimetableRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _classSessions =>
      _firestore.collection('classSessions');

  @override
  Stream<List<ClassSession>> watchSessions({
    TimetableAccessScope scope = const TimetableAccessScope(),
    int limit = 300,
  }) {
    Query<Map<String, dynamic>> query = _classSessions.limit(limit);

    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.trainerId != null) {
      query = query.where('trainerId', isEqualTo: scope.trainerId);
    }
    if (scope.batchId != null) {
      query = query.where('batchId', isEqualTo: scope.batchId);
    }

    return query.snapshots().map((snapshot) {
      var sessions = snapshot.docs.map(ClassSession.fromFirestore).toList();

      if (scope.startDate != null) {
        sessions = sessions
            .where((s) => !s.endAt.isBefore(scope.startDate!))
            .toList();
      }
      if (scope.endDate != null) {
        sessions = sessions
            .where((s) => !s.startAt.isAfter(scope.endDate!))
            .toList();
      }

      sessions.sort((a, b) => a.startAt.compareTo(b.startAt));
      return sessions;
    });
  }

  @override
  Future<List<ClassSession>> getSessions({
    TimetableAccessScope scope = const TimetableAccessScope(),
  }) async {
    Query<Map<String, dynamic>> query = _classSessions;

    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.trainerId != null) {
      query = query.where('trainerId', isEqualTo: scope.trainerId);
    }
    if (scope.batchId != null) {
      query = query.where('batchId', isEqualTo: scope.batchId);
    }

    final snapshot = await query.get();
    var sessions = snapshot.docs.map(ClassSession.fromFirestore).toList();

    if (scope.startDate != null) {
      sessions = sessions
          .where((s) => !s.endAt.isBefore(scope.startDate!))
          .toList();
    }
    if (scope.endDate != null) {
      sessions = sessions
          .where((s) => !s.startAt.isAfter(scope.endDate!))
          .toList();
    }

    sessions.sort((a, b) => a.startAt.compareTo(b.startAt));
    return sessions;
  }

  @override
  Future<ClassSession?> getSessionById(String id) async {
    final doc = await _classSessions.doc(id).get();
    if (!doc.exists) return null;
    return ClassSession.fromFirestore(doc);
  }

  @override
  Future<ClassSession> createSession(ClassSession session) async {
    if (session.id.isEmpty) {
      final docRef = _classSessions.doc();
      final created = session.copyWith(id: docRef.id);
      await docRef.set(created.toFirestore());
      return created;
    }

    await _classSessions.doc(session.id).set(session.toFirestore());
    return session;
  }

  @override
  Future<ClassSession> updateSession(ClassSession session) async {
    final updated = session.copyWith(updatedAt: DateTime.now());
    await _classSessions.doc(session.id).update(updated.toUpdateMap());
    return updated;
  }

  @override
  Future<ClassSession> cancelSession(String id) async {
    final existing = await getSessionById(id);
    if (existing == null) {
      throw StateError('Cannot cancel non-existent class session: $id');
    }

    final updated = existing.copyWith(
      status: 'cancelled',
      updatedAt: DateTime.now(),
    );
    await _classSessions.doc(id).update(updated.toUpdateMap());
    return updated;
  }

  @override
  Future<bool> isSessionsCollectionEmpty() async {
    final snapshot = await _classSessions.limit(1).get();
    return snapshot.docs.isEmpty;
  }

  @override
  Future<int> countExistingSampleSessions(List<ClassSession> sessions) async {
    var count = 0;
    for (final session in sessions) {
      final doc = await _classSessions.doc(session.id).get();
      if (doc.exists) count++;
    }
    return count;
  }

  @override
  Future<void> createMissingSampleSessions(List<ClassSession> sessions) async {
    for (final session in sessions) {
      final doc = await _classSessions.doc(session.id).get();
      if (!doc.exists) {
        await _classSessions.doc(session.id).set(session.toFirestore());
      }
    }
  }
}

