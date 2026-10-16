import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/attendance_record.dart';

class AttendanceAccessScope {
  const AttendanceAccessScope({
    this.instituteId = 'demo-institute',
    this.counselorId,
    this.trainerId,
  });

  final String? instituteId;
  final String? counselorId;
  final String? trainerId;
}

abstract interface class AttendanceRepository {
  Future<List<AttendanceRecord>> getSessionRecords({
    required AttendanceAccessScope scope,
    required String batchId,
    required DateTime classDate,
    required List<String> studentIds,
  });

  Stream<List<AttendanceRecord>> watchAttendanceHistory({
    required AttendanceAccessScope scope,
    int limit = 500,
  });

  Future<void> upsertAttendanceRecords(List<AttendanceRecord> records);
}

class FirestoreAttendanceRepository implements AttendanceRepository {
  FirestoreAttendanceRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _attendance =>
      _firestore.collection('attendance');

  @override
  Future<List<AttendanceRecord>> getSessionRecords({
    required AttendanceAccessScope scope,
    required String batchId,
    required DateTime classDate,
    required List<String> studentIds,
  }) async {
    if (studentIds.isEmpty || scope.instituteId == null) {
      return const <AttendanceRecord>[];
    }
    final documents = await Future.wait(
      studentIds.map(
        (studentId) => _attendance
            .doc(
              AttendanceRecord.documentId(
                instituteId: scope.instituteId!,
                batchId: batchId,
                classDate: classDate,
                studentId: studentId,
              ),
            )
            .get(),
      ),
    );
    return documents
        .where((document) => document.exists)
        .map(AttendanceRecord.fromFirestore)
        .where((record) => _isInScope(record, scope))
        .toList();
  }

  @override
  Stream<List<AttendanceRecord>> watchAttendanceHistory({
    required AttendanceAccessScope scope,
    int limit = 500,
  }) {
    Query<Map<String, dynamic>> query = _attendance.limit(limit);
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.counselorId != null) {
      query = query.where('counselorId', isEqualTo: scope.counselorId);
    }
    if (scope.trainerId != null) {
      query = query.where('trainerId', isEqualTo: scope.trainerId);
    }
    return query.snapshots().map(
      (snapshot) {
        final records = snapshot.docs
            .map(AttendanceRecord.fromFirestore)
            .toList()
          ..sort((left, right) => right.classDate.compareTo(left.classDate));
        return records;
      },
    );
  }

  @override
  Future<void> upsertAttendanceRecords(List<AttendanceRecord> records) async {
    const batchLimit = 450;
    for (var start = 0; start < records.length; start += batchLimit) {
      final end = (start + batchLimit).clamp(0, records.length);
      final write = _firestore.batch();
      for (final record in records.sublist(start, end)) {
        write.set(_attendance.doc(record.id), record.toFirestore());
      }
      await write.commit();
    }
  }

  bool _isInScope(AttendanceRecord record, AttendanceAccessScope scope) =>
      (scope.instituteId == null || record.instituteId == scope.instituteId) &&
      (scope.counselorId == null || record.counselorId == scope.counselorId) &&
      (scope.trainerId == null || record.trainerId == scope.trainerId);
}
