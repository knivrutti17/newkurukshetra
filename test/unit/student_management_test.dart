import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/student.dart';
import 'package:kurukshetra/data/repositories/student_repository.dart';
import 'package:kurukshetra/data/services/student_seed_service.dart';
import 'package:kurukshetra/data/services/student_service.dart';

void main() {
  group('StudentService', () {
    test('owner creates, updates, and archives a persisted student', () async {
      final repository = _InMemoryStudentRepository();
      final service = StudentService(repository: repository);
      final owner = _user(AppRole.owner, 'demo-owner');

      final created = await service.createForUser(owner, _student());
      expect(created.id, isNotEmpty);
      expect(repository.students, hasLength(1));

      final edited = await service.updateForUser(
        owner,
        created.copyWith(fullName: 'Aarohi Sharma'),
      );
      expect(edited.fullName, 'Aarohi Sharma');
      expect(repository.students.single.fullName, 'Aarohi Sharma');

      final archived = await service.archiveForUser(owner, edited);
      expect(archived.status, 'archived');
      expect(repository.students.single.status, 'archived');
    });

    test('counselor sees and manages only their assigned student records', () async {
      final repository = _InMemoryStudentRepository()
        ..students.addAll([
          _student(id: 'assigned', counselorId: 'demo-counselor'),
          _student(id: 'other', counselorId: 'another-counselor'),
        ]);
      final service = StudentService(repository: repository);
      final counselor = _user(AppRole.counselor, 'demo-counselor');

      final visible = await service.watchForUser(counselor).first;
      expect(visible.map((student) => student.id), ['assigned']);

      await expectLater(
        service.updateForUser(counselor, repository.students.last),
        throwsA(isA<Object>()),
      );
    });
  });

  test('sample initialization is a repeat-safe batch operation', () async {
    final repository = _InMemoryStudentRepository();
    final seedService = StudentSeedService(repository: repository);

    final firstLoad = await seedService.loadSampleStudents();
    final secondLoad = await seedService.loadSampleStudents();

    expect(firstLoad.createdCount, 10);
    expect(firstLoad.skippedCount, 0);
    expect(repository.students, hasLength(10));
    expect(secondLoad.createdCount, 0);
    expect(secondLoad.skippedCount, 10);
    expect(secondLoad.collectionAlreadyHadData, isTrue);
    expect(repository.students, hasLength(10));
  });
}

class _InMemoryStudentRepository
    implements StudentRepository, StudentSeedRepository {
  final List<Student> students = <Student>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  @override
  Stream<List<Student>> watchStudents({
    StudentAccessScope scope = const StudentAccessScope(),
    int limit = 200,
  }) async* {
    List<Student> visible() => students
        .where(
          (student) =>
              (scope.instituteId == null ||
                  student.instituteId == scope.instituteId) &&
              (scope.counselorId == null ||
                  student.counselorId == scope.counselorId) &&
              (scope.trainerId == null || student.trainerId == scope.trainerId),
        )
        .take(limit)
        .toList();

    yield visible();
    yield* _changes.stream.map((_) => visible());
  }

  @override
  Future<Student> createStudent(Student student) async {
    final saved = student.copyWith(id: 'student-${_nextId++}');
    students.add(saved);
    _changes.add(null);
    return saved;
  }

  @override
  Future<Student> updateStudent(Student student) async {
    final index = students.indexWhere((item) => item.id == student.id);
    students[index] = student;
    _changes.add(null);
    return student;
  }

  @override
  Future<Student> archiveStudent(Student student) =>
      updateStudent(student.copyWith(status: 'archived'));

  @override
  Future<bool> isStudentsCollectionEmpty() async => students.isEmpty;

  @override
  Future<int> countExistingSampleStudents(List<Student> samples) async => samples
      .where((sample) => students.any((student) => student.id == sample.id))
      .length;

  @override
  Future<void> createMissingSampleStudents(List<Student> samples) async {
    for (final sample in samples) {
      if (students.every((student) => student.id != sample.id)) {
        students.add(sample);
      }
    }
    _changes.add(null);
  }
}

AppUser _user(AppRole role, String id) => AppUser(
  id: id,
  name: 'Demo user',
  email: 'demo@example.test',
  role: role,
);

Student _student({String id = '', String? counselorId}) {
  final date = DateTime(2026, 1, 1);
  return Student(
    id: id,
    instituteId: 'demo-institute',
    fullName: 'Aarohi Shah',
    email: 'aarohi.shah@example.test',
    phone: '+91 90000 20001',
    courseId: 'data-analytics',
    courseName: 'Data Analytics',
    batchId: 'da-2026-a',
    batchName: 'DA 2026 A',
    enrollmentDate: date,
    status: 'active',
    createdAt: date,
    updatedAt: date,
    counselorId: counselorId,
  );
}
