import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/student_alert.dart';
import '../services/risk_rule_engine.dart';

class AlertAccessScope {
  const AlertAccessScope({
    required this.instituteId,
    this.counselorId,
    this.trainerId,
    this.academicOnly = false,
    this.financialOnly = false,
  });

  final String instituteId;
  final String? counselorId;
  final String? trainerId;
  final bool academicOnly;
  final bool financialOnly;
}

class AlertScanWriteResult {
  const AlertScanWriteResult({
    required this.created,
    required this.updated,
    required this.preservedClosed,
  });

  final int created;
  final int updated;
  final int preservedClosed;
}

class AlertFollowUpUpdate {
  const AlertFollowUpUpdate({
    required this.actorId,
    required this.actorName,
    this.status,
    this.note,
    this.assignedTo,
    this.closureReason,
  });

  final String actorId;
  final String actorName;
  final StudentAlertStatus? status;
  final String? note;
  final String? assignedTo;
  final String? closureReason;
}

abstract interface class StudentAlertRepository {
  Stream<List<StudentAlert>> watchAlerts(AlertAccessScope scope);
  Future<List<StudentAlert>> getAlertsForScan(String instituteId);
  Future<AlertScanWriteResult> synchronizeScan({
    required String instituteId,
    required List<ProposedStudentAlert> candidates,
    required DateTime now,
  });
  Future<StudentAlert> updateFollowUp({
    required String alertId,
    required AlertFollowUpUpdate update,
    required DateTime now,
  });
  Future<DateTime?> getLastSuccessfulScan(String instituteId);
  Future<void> recordSuccessfulScan({
    required String instituteId,
    required DateTime completedAt,
    required String completedBy,
  });
}

class FirestoreStudentAlertRepository implements StudentAlertRepository {
  FirestoreStudentAlertRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _scanAlertLimit = 1000;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _alerts =>
      _firestore.collection('studentAlerts');

  CollectionReference<Map<String, dynamic>> get _metadata =>
      _firestore.collection('riskScanMetadata');

  @override
  Stream<List<StudentAlert>> watchAlerts(AlertAccessScope scope) {
    Query<Map<String, dynamic>> query = _alerts.where(
      'instituteId',
      isEqualTo: scope.instituteId,
    );
    if (scope.counselorId != null) {
      query = query.where('counselorId', isEqualTo: scope.counselorId);
    }
    if (scope.trainerId != null) {
      query = query.where('trainerId', isEqualTo: scope.trainerId);
    }
    if (scope.academicOnly) {
      query = query.where(
        'alertType',
        whereIn: const ['lowAttendance', 'repeatedAbsence'],
      );
    }
    if (scope.financialOnly) {
      query = query.where(
        'alertType',
        isEqualTo: StudentAlertType.overdueFees.value,
      );
    }
    return query.snapshots().map((snapshot) {
      var alerts = snapshot.docs.map(StudentAlert.fromFirestore).toList();
      alerts.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      return alerts;
    });
  }

  @override
  Future<List<StudentAlert>> getAlertsForScan(String instituteId) async {
    final snapshot = await _alerts
        .where('instituteId', isEqualTo: instituteId)
        .limit(_scanAlertLimit + 1)
        .get();
    if (snapshot.docs.length > _scanAlertLimit) {
      throw StateError(
        'Risk scan stopped before writing: more than $_scanAlertLimit existing alerts require review.',
      );
    }
    return snapshot.docs.map(StudentAlert.fromFirestore).toList();
  }

  @override
  Future<AlertScanWriteResult> synchronizeScan({
    required String instituteId,
    required List<ProposedStudentAlert> candidates,
    required DateTime now,
  }) async {
    final existing = await getAlertsForScan(instituteId);
    final existingById = <String, StudentAlert>{
      for (final alert in existing) alert.id: alert,
    };
    final writes = <StudentAlert>[];
    var created = 0;
    var updated = 0;
    var preservedClosed = 0;

    for (final candidate in candidates) {
      final current = existingById[candidate.id];
      if (current != null && current.status.isClosed) {
        // Resolved and dismissed outcomes are historical audit records; a scan
        // must not reopen them or replace their human decision.
        preservedClosed++;
        continue;
      }
      if (current == null) {
        created++;
        writes.add(_newAlert(candidate, now));
      } else {
        updated++;
        writes.add(
          StudentAlert(
            id: current.id,
            instituteId: current.instituteId,
            studentId: current.studentId,
            studentName: candidate.student.fullName,
            batchId: candidate.student.batchId,
            batchName: candidate.student.batchName,
            alertType: current.alertType,
            severity: candidate.severity,
            title: candidate.title,
            reason: candidate.reason,
            evidence: candidate.evidence,
            status: current.status,
            createdAt: current.createdAt,
            updatedAt: now,
            counselorId: candidate.student.counselorId,
            trainerId: candidate.student.trainerId,
            assignedTo: current.assignedTo,
            followUpNote: current.followUpNote,
            followUpHistory: current.followUpHistory,
            resolvedAt: current.resolvedAt,
            resolvedBy: current.resolvedBy,
            closureReason: current.closureReason,
          ),
        );
      }
    }

    for (var start = 0; start < writes.length; start += 450) {
      final end = (start + 450).clamp(0, writes.length);
      final batch = _firestore.batch();
      for (final alert in writes.sublist(start, end)) {
        batch.set(_alerts.doc(alert.id), alert.toFirestore());
      }
      await batch.commit();
    }
    return AlertScanWriteResult(
      created: created,
      updated: updated,
      preservedClosed: preservedClosed,
    );
  }

  @override
  Future<StudentAlert> updateFollowUp({
    required String alertId,
    required AlertFollowUpUpdate update,
    required DateTime now,
  }) => _firestore.runTransaction((transaction) async {
    final ref = _alerts.doc(alertId);
    final snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw StateError('This alert no longer exists. Refresh and try again.');
    }
    final current = StudentAlert.fromFirestore(snapshot);
    final nextStatus = update.status ?? current.status;
    final note = update.note?.trim();
    final assignmentChanged =
        update.assignedTo != null &&
        update.assignedTo!.trim() != (current.assignedTo ?? '');
    final statusChanged = nextStatus != current.status;
    final history = List<AlertFollowUpEntry>.from(current.followUpHistory);
    if ((note?.isNotEmpty ?? false) || statusChanged || assignmentChanged) {
      history.add(
        AlertFollowUpEntry(
          at: now,
          actorId: update.actorId,
          actorName: update.actorName,
          note: note?.isNotEmpty == true
              ? note!
              : statusChanged
              ? 'Status changed to ${nextStatus.label}.'
              : 'Follow-up owner updated.',
          status: nextStatus,
        ),
      );
    }
    final isClosing = nextStatus.isClosed && !current.status.isClosed;
    final isReopening = !nextStatus.isClosed && current.status.isClosed;
    final data = <String, dynamic>{
      'status': nextStatus.value,
      'updatedAt': Timestamp.fromDate(now),
      'followUpHistory': history.map((entry) => entry.toMap()).toList(),
      if (note?.isNotEmpty == true) 'followUpNote': note,
      if (update.assignedTo != null) 'assignedTo': update.assignedTo!.trim(),
    };
    if (isClosing) {
      data['resolvedAt'] = Timestamp.fromDate(now);
      data['resolvedBy'] = update.actorId;
      data['closureReason'] = update.closureReason?.trim().isNotEmpty == true
          ? update.closureReason!.trim()
          : note ?? 'Closed after review.';
    }
    if (isReopening) {
      data['resolvedAt'] = FieldValue.delete();
      data['resolvedBy'] = FieldValue.delete();
      data['closureReason'] = FieldValue.delete();
    }
    transaction.update(ref, data);
    return current.copyWith(
      status: nextStatus,
      updatedAt: now,
      assignedTo: update.assignedTo,
      followUpNote: note?.isNotEmpty == true ? note : null,
      followUpHistory: history,
      resolvedAt: isClosing ? now : current.resolvedAt,
      resolvedBy: isClosing ? update.actorId : current.resolvedBy,
      closureReason: isClosing
          ? data['closureReason'] as String
          : current.closureReason,
    );
  });

  @override
  Future<DateTime?> getLastSuccessfulScan(String instituteId) async {
    final document = await _metadata.doc(instituteId).get();
    final value = document.data()?['lastCompletedAt'];
    return value is Timestamp ? value.toDate() : null;
  }

  @override
  Future<void> recordSuccessfulScan({
    required String instituteId,
    required DateTime completedAt,
    required String completedBy,
  }) => _metadata.doc(instituteId).set(<String, dynamic>{
    'instituteId': instituteId,
    'lastCompletedAt': Timestamp.fromDate(completedAt),
    'lastCompletedBy': completedBy,
  }, SetOptions(merge: true));

  StudentAlert _newAlert(ProposedStudentAlert candidate, DateTime now) =>
      StudentAlert(
        id: candidate.id,
        instituteId: candidate.student.instituteId,
        studentId: candidate.student.id,
        studentName: candidate.student.fullName,
        batchId: candidate.student.batchId,
        batchName: candidate.student.batchName,
        alertType: candidate.type,
        severity: candidate.severity,
        title: candidate.title,
        reason: candidate.reason,
        evidence: candidate.evidence,
        status: StudentAlertStatus.newAlert,
        createdAt: now,
        updatedAt: now,
        counselorId: candidate.student.counselorId,
        trainerId: candidate.student.trainerId,
      );
}
