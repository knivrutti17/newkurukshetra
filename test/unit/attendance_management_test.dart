import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/attendance_record.dart';
import 'package:kurukshetra/data/models/student.dart';
import 'package:kurukshetra/data/repositories/attendance_repository.dart';
import 'package:kurukshetra/data/services/attendance_service.dart';

void main() {
  group('AttendanceService', () {
    test('saves several student records and edits their existing documents', () async {
      final repository = _InMemoryAttendanceRepository();
      final service = AttendanceService(repository: repository);
      final owner = _user(AppRole.owner, 'demo-owner');
      final students = <Student>[
        _student(id: 'student-a'),
        _student(id: 'student-b'),
        _student(id: 'student-c'),
      ];
      final date = DateTime(2026, 7, 10);

      final savedCount = await service.saveSessionForUser(
        user: owner,
        batchId: 'da-2026-a',
        classDate: date,
        students: students,
        statuses: const {
          'student-a': AttendanceStatus.present,
          'student-b': AttendanceStatus.absent,
          'student-c': AttendanceStatus.late,
        },
        existingRecords: const {},
      );
      expect(savedCount, 3);
      expect(repository.records, hasLength(3));

      final existing = await service.loadSessionForUser(
        user: owner,
        batchId: 'da-2026-a',
        classDate: date,
        students: students,
      );
      final existingByStudent = {
        for (final record in existing) record.studentId: record,
      };
      await service.saveSessionForUser(
        user: owner,
        batchId: 'da-2026-a',
        classDate: date,
        students: students,
        statuses: const {
          'student-a': AttendanceStatus.absent,
          'student-b': AttendanceStatus.present,
          'student-c': AttendanceStatus.late,
        },
        existingRecords: existingByStudent,
      );

      expect(repository.records, hasLength(3));
      expect(
        repository.records.values
            .firstWhere((record) => record.studentId == 'student-a')
            .status,
        AttendanceStatus.absent,
      );
    });

    test('percentage uses only recorded statuses and counts late as non-present', () {
      final service = AttendanceService(
        repository: _InMemoryAttendanceRepository(),
      );
      final records = [
        _record(studentId: 'student-a', status: AttendanceStatus.present),
        _record(
          studentId: 'student-a',
          classDate: DateTime(2026, 7, 11),
          status: AttendanceStatus.absent,
        ),
        _record(
          studentId: 'student-a',
          classDate: DateTime(2026, 7, 12),
          status: AttendanceStatus.late,
        ),
      ];

      final percentage = service.percentagesFor(records).single;
      final counts = service.countsFor(records.map((record) => record.status));

      expect(percentage.presentSessions, 1);
      expect(percentage.recordedSessions, 3);
      expect(percentage.value, closeTo(33.333, .001));
      expect(counts.present, 1);
      expect(counts.absent, 1);
      expect(counts.late, 1);
    });

    test('trainer cannot save attendance for an unassigned student', () async {
      final service = AttendanceService(
        repository: _InMemoryAttendanceRepository(),
      );
      final trainer = _user(AppRole.trainer, 'demo-trainer');

      await expectLater(
        service.saveSessionForUser(
          user: trainer,
          batchId: 'da-2026-a',
          classDate: DateTime(2026, 7, 10),
          students: [_student(id: 'student-a', trainerId: 'another-trainer')],
          statuses: const {'student-a': AttendanceStatus.present},
          existingRecords: const {},
        ),
        throwsA(isA<AttendanceAccessException>()),
      );
    });

    test('counselor and accounts roles have view-only access and cannot save attendance', () async {
      final service = AttendanceService(repository: _InMemoryAttendanceRepository());
      final counselor = _user(AppRole.counselor, 'demo-counselor');
      final accounts = _user(AppRole.accounts, 'demo-accounts');
      final students = [_student(id: 'student-a')];

      expect(service.canManage(counselor), isFalse);
      expect(service.canManage(accounts), isFalse);

      await expectLater(
        service.saveSessionForUser(
          user: counselor,
          batchId: 'da-2026-a',
          classDate: DateTime(2026, 7, 10),
          students: students,
          statuses: const {'student-a': AttendanceStatus.present},
          existingRecords: const {},
        ),
        throwsA(isA<AttendanceAccessException>()),
      );

      await expectLater(
        service.saveSessionForUser(
          user: accounts,
          batchId: 'da-2026-a',
          classDate: DateTime(2026, 7, 10),
          students: students,
          statuses: const {'student-a': AttendanceStatus.present},
          existingRecords: const {},
        ),
        throwsA(isA<AttendanceAccessException>()),
      );
    });

    test('deterministic documentId prevents duplicates across different times on the same date', () {
      final morning = DateTime(2026, 7, 10, 9, 30);
      final evening = DateTime(2026, 7, 10, 18, 45);

      final idMorning = AttendanceRecord.documentId(
        instituteId: 'demo-institute',
        batchId: 'da-2026-a',
        classDate: morning,
        studentId: 'student-a',
      );
      final idEvening = AttendanceRecord.documentId(
        instituteId: 'demo-institute',
        batchId: 'da-2026-a',
        classDate: evening,
        studentId: 'student-a',
      );

      expect(idMorning, idEvening);
      expect(idMorning, 'demo-institute--da-2026-a--20260710--student-a');
    });

    test('saveSessionForUser rejects empty active students or batch mismatch', () async {
      final service = AttendanceService(repository: _InMemoryAttendanceRepository());
      final owner = _user(AppRole.owner, 'demo-owner');

      await expectLater(
        service.saveSessionForUser(
          user: owner,
          batchId: 'da-2026-a',
          classDate: DateTime(2026, 7, 10),
          students: [_student(id: 'student-a').copyWith(status: 'archived')],
          statuses: const {'student-a': AttendanceStatus.present},
          existingRecords: const {},
        ),
        throwsA(isA<AttendanceAccessException>()),
      );

      await expectLater(
        service.saveSessionForUser(
          user: owner,
          batchId: 'da-2026-a',
          classDate: DateTime(2026, 7, 10),
          students: [_student(id: 'student-a').copyWith(batchId: 'other-batch')],
          statuses: const {'student-a': AttendanceStatus.present},
          existingRecords: const {},
        ),
        throwsA(isA<AttendanceAccessException>()),
      );
    });

    test('watchHistoryForUser scopes records correctly by role', () async {
      final repository = _InMemoryAttendanceRepository();
      final service = AttendanceService(repository: repository);
      final counselor = _user(AppRole.counselor, 'counselor-1');
      final trainer = _user(AppRole.trainer, 'trainer-1');
      final owner = _user(AppRole.owner, 'owner-1');

      final r1 = AttendanceRecord(
        id: 'r1',
        instituteId: 'demo-institute',
        studentId: 's1',
        batchId: 'b1',
        classDate: DateTime(2026, 7, 10),
        status: AttendanceStatus.present,
        createdAt: DateTime(2026, 7, 10),
        updatedAt: DateTime(2026, 7, 10),
        recordedBy: 'owner-1',
        counselorId: 'counselor-1',
        trainerId: 'trainer-1',
      );
      final r2 = AttendanceRecord(
        id: 'r2',
        instituteId: 'demo-institute',
        studentId: 's2',
        batchId: 'b1',
        classDate: DateTime(2026, 7, 10),
        status: AttendanceStatus.absent,
        createdAt: DateTime(2026, 7, 10),
        updatedAt: DateTime(2026, 7, 10),
        recordedBy: 'owner-1',
        counselorId: 'counselor-2',
        trainerId: 'trainer-2',
      );
      await repository.upsertAttendanceRecords([r1, r2]);

      final counselorRecords = await service.watchHistoryForUser(counselor).first;
      expect(counselorRecords.map((r) => r.id), ['r1']);

      final trainerRecords = await service.watchHistoryForUser(trainer).first;
      expect(trainerRecords.map((r) => r.id), ['r1']);

      final ownerRecords = await service.watchHistoryForUser(owner).first;
      expect(ownerRecords.map((r) => r.id), containsAll(['r1', 'r2']));
    });
  });
}

class _InMemoryAttendanceRepository implements AttendanceRepository {
  final Map<String, AttendanceRecord> records = <String, AttendanceRecord>{};

  @override
  Future<List<AttendanceRecord>> getSessionRecords({
    required AttendanceAccessScope scope,
    required String batchId,
    required DateTime classDate,
    required List<String> studentIds,
  }) async => records.values
      .where(
        (record) =>
            record.batchId == batchId &&
            _sameDate(record.classDate, classDate) &&
            studentIds.contains(record.studentId) &&
            _inScope(record, scope),
      )
      .toList();

  @override
  Stream<List<AttendanceRecord>> watchAttendanceHistory({
    required AttendanceAccessScope scope,
    int limit = 500,
  }) => Stream.value(
    records.values.where((record) => _inScope(record, scope)).take(limit).toList(),
  );

  @override
  Future<void> upsertAttendanceRecords(List<AttendanceRecord> items) async {
    for (final record in items) {
      records[record.id] = record;
    }
  }

  bool _inScope(AttendanceRecord record, AttendanceAccessScope scope) =>
      (scope.instituteId == null || record.instituteId == scope.instituteId) &&
      (scope.counselorId == null || record.counselorId == scope.counselorId) &&
      (scope.trainerId == null || record.trainerId == scope.trainerId);
}

AppUser _user(AppRole role, String id) => AppUser(
  id: id,
  name: 'Demo user',
  email: 'demo@example.test',
  role: role,
);

Student _student({required String id, String? trainerId}) {
  final date = DateTime(2026, 1, 1);
  return Student(
    id: id,
    instituteId: 'demo-institute',
    fullName: 'Student $id',
    email: '$id@example.test',
    phone: '+91 90000 30001',
    courseId: 'data-analytics',
    courseName: 'Data Analytics',
    batchId: 'da-2026-a',
    batchName: 'DA 2026 A',
    enrollmentDate: date,
    status: 'active',
    createdAt: date,
    updatedAt: date,
    counselorId: 'demo-counselor',
    trainerId: trainerId ?? 'demo-trainer',
  );
}

AttendanceRecord _record({
  required String studentId,
  required AttendanceStatus status,
  DateTime? classDate,
}) {
  final date = classDate ?? DateTime(2026, 7, 10);
  return AttendanceRecord(
    id: AttendanceRecord.documentId(
      instituteId: 'demo-institute',
      batchId: 'da-2026-a',
      classDate: date,
      studentId: studentId,
    ),
    instituteId: 'demo-institute',
    studentId: studentId,
    batchId: 'da-2026-a',
    classDate: date,
    status: status,
    createdAt: date,
    updatedAt: date,
    recordedBy: 'demo-owner',
    counselorId: 'demo-counselor',
    trainerId: 'demo-trainer',
  );
}

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
