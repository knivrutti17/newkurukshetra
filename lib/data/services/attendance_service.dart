import '../../data/models/app_user.dart';
import '../models/attendance_record.dart';
import '../models/student.dart';
import '../repositories/attendance_repository.dart';

class AttendanceAccessException implements Exception {
  const AttendanceAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AttendanceCounts {
  const AttendanceCounts({
    required this.present,
    required this.absent,
    required this.late,
  });

  final int present;
  final int absent;
  final int late;

  int get total => present + absent + late;
}

class StudentAttendancePercentage {
  const StudentAttendancePercentage({
    required this.studentId,
    required this.presentSessions,
    required this.recordedSessions,
  });

  final String studentId;
  final int presentSessions;
  final int recordedSessions;

  double get value =>
      recordedSessions == 0 ? 0 : (presentSessions / recordedSessions) * 100;
}

/// Coordinates attendance reads/writes with the current demo role.
///
/// These local checks only drive the demo UI. They are not a replacement for
/// Firebase Authentication and Firestore Security Rules in production.
class AttendanceService {
  AttendanceService({AttendanceRepository? repository})
    : _repository = repository ?? FirestoreAttendanceRepository();

  final AttendanceRepository _repository;

  bool canManage(AppUser user) =>
      user.role == AppRole.owner || user.role == AppRole.trainer;

  Stream<List<AttendanceRecord>> watchHistoryForUser(AppUser user) =>
      _repository.watchAttendanceHistory(scope: _scopeFor(user));

  Future<List<AttendanceRecord>> loadSessionForUser({
    required AppUser user,
    required String batchId,
    required DateTime classDate,
    required List<Student> students,
  }) => _repository.getSessionRecords(
    scope: _scopeFor(user),
    batchId: batchId,
    classDate: classDate,
    studentIds: students.map((student) => student.id).toList(),
  );

  Future<int> saveSessionForUser({
    required AppUser user,
    required String batchId,
    required DateTime classDate,
    required List<Student> students,
    required Map<String, AttendanceStatus> statuses,
    required Map<String, AttendanceRecord> existingRecords,
  }) async {
    _ensureCanManage(user);
    final activeStudents = students
        .where((student) => student.status == 'active')
        .toList();
    if (activeStudents.isEmpty) {
      throw const AttendanceAccessException(
        'There are no active enrolled students in this batch.',
      );
    }
    if (activeStudents.any((student) => student.batchId != batchId)) {
      throw const AttendanceAccessException(
        'Attendance can only be saved for the selected batch.',
      );
    }
    if (user.role == AppRole.trainer &&
        activeStudents.any((student) => student.trainerId != user.id)) {
      throw const AttendanceAccessException(
        'You can only save attendance for students assigned to your batches.',
      );
    }

    final now = DateTime.now();
    final records = activeStudents.map((student) {
      final previous = existingRecords[student.id];
      return AttendanceRecord(
        id: AttendanceRecord.documentId(
          instituteId: student.instituteId,
          batchId: batchId,
          classDate: classDate,
          studentId: student.id,
        ),
        instituteId: student.instituteId,
        studentId: student.id,
        batchId: batchId,
        classDate: AttendanceRecord.normalizeClassDate(classDate),
        status: statuses[student.id] ?? AttendanceStatus.present,
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
        recordedBy: user.id,
        counselorId: student.counselorId,
        trainerId: student.trainerId,
      );
    }).toList();
    await _repository.upsertAttendanceRecords(records);
    return records.length;
  }

  AttendanceCounts countsFor(Iterable<AttendanceStatus> statuses) {
    var present = 0;
    var absent = 0;
    var late = 0;
    for (final status in statuses) {
      switch (status) {
        case AttendanceStatus.present:
          present++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.late:
          late++;
      }
    }
    return AttendanceCounts(present: present, absent: absent, late: late);
  }

  List<StudentAttendancePercentage> percentagesFor(
    Iterable<AttendanceRecord> records,
  ) {
    final totals = <String, List<AttendanceRecord>>{};
    for (final record in records) {
      totals.putIfAbsent(record.studentId, () => <AttendanceRecord>[]).add(record);
    }
    return totals.entries
        .map(
          (entry) => StudentAttendancePercentage(
            studentId: entry.key,
            presentSessions: entry.value
                .where((record) => record.status == AttendanceStatus.present)
                .length,
            recordedSessions: entry.value.length,
          ),
        )
        .toList()
      ..sort((left, right) => left.studentId.compareTo(right.studentId));
  }

  AttendanceAccessScope _scopeFor(AppUser user) => switch (user.role) {
    AppRole.owner || AppRole.accounts => const AttendanceAccessScope(),
    AppRole.counselor => AttendanceAccessScope(counselorId: user.id),
    AppRole.trainer => AttendanceAccessScope(trainerId: user.id),
  };

  void _ensureCanManage(AppUser user) {
    if (!canManage(user)) {
      throw const AttendanceAccessException(
        'Your demo role has view-only attendance access.',
      );
    }
  }
}
