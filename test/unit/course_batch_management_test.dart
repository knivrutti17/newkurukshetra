import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/batch.dart';
import 'package:kurukshetra/data/models/course.dart';
import 'package:kurukshetra/data/repositories/batch_repository.dart';
import 'package:kurukshetra/data/repositories/course_repository.dart';
import 'package:kurukshetra/data/services/batch_service.dart';
import 'package:kurukshetra/data/services/course_batch_seed_service.dart';
import 'package:kurukshetra/data/services/course_service.dart';

void main() {
  group('CourseService', () {
    test('owner creates, updates, and archives a course', () async {
      final repository = _InMemoryCourseRepository();
      final service = CourseService(repository: repository);
      final owner = _user(AppRole.owner, 'demo-owner');

      final created = await service.createForUser(
        owner,
        _course(name: 'Data Analytics', fee: 45000),
      );
      expect(created.id, isNotEmpty);
      expect(repository.courses, hasLength(1));
      expect(repository.courses.single.name, 'Data Analytics');

      final updated = await service.updateForUser(
        owner,
        created.copyWith(feeAmount: 50000, duration: '7 Months'),
      );
      expect(updated.feeAmount, 50000);
      expect(updated.duration, '7 Months');
      expect(repository.courses.single.feeAmount, 50000);

      final archived = await service.archiveForUser(owner, updated);
      expect(archived.isArchived, isTrue);
      expect(repository.courses.single.status, 'archived');
    });

    test('validates required fields and rejects negative fee amounts', () async {
      final service = CourseService(repository: _InMemoryCourseRepository());
      final owner = _user(AppRole.owner, 'demo-owner');

      // Empty name
      await expectLater(
        service.createForUser(owner, _course(name: '   ', fee: 1000)),
        throwsA(isA<CourseValidationException>()),
      );

      // Empty duration
      await expectLater(
        service.createForUser(owner, _course(name: 'Flutter', duration: '  ', fee: 1000)),
        throwsA(isA<CourseValidationException>()),
      );

      // Negative fee
      await expectLater(
        service.createForUser(owner, _course(name: 'Flutter', fee: -500)),
        throwsA(isA<CourseValidationException>()),
      );
    });

    test('non-owner roles cannot manage courses', () async {
      final service = CourseService(repository: _InMemoryCourseRepository());
      final counselor = _user(AppRole.counselor, 'demo-counselor');
      final trainer = _user(AppRole.trainer, 'demo-trainer');
      final accounts = _user(AppRole.accounts, 'demo-accounts');

      expect(service.canManage(counselor), isFalse);
      expect(service.canManage(trainer), isFalse);
      expect(service.canManage(accounts), isFalse);

      await expectLater(
        service.createForUser(counselor, _course(name: 'Python')),
        throwsA(isA<CourseValidationException>()),
      );
      await expectLater(
        service.createForUser(trainer, _course(name: 'Python')),
        throwsA(isA<CourseValidationException>()),
      );
      await expectLater(
        service.createForUser(accounts, _course(name: 'Python')),
        throwsA(isA<CourseValidationException>()),
      );
    });
  });

  group('BatchService', () {
    test('owner creates, updates, and archives a batch', () async {
      final repository = _InMemoryBatchRepository();
      final service = BatchService(repository: repository);
      final owner = _user(AppRole.owner, 'demo-owner');

      final created = await service.createForUser(
        owner,
        _batch(name: 'DA Jan 2026 A', capacity: 25),
      );
      expect(created.id, isNotEmpty);
      expect(repository.batches, hasLength(1));
      expect(repository.batches.single.name, 'DA Jan 2026 A');

      final updated = await service.updateForUser(
        owner,
        created.copyWith(capacity: 30, scheduleDescription: 'Mon-Fri, 10 AM'),
      );
      expect(updated.capacity, 30);
      expect(repository.batches.single.capacity, 30);

      final archived = await service.archiveForUser(owner, updated);
      expect(archived.isArchived, isTrue);
      expect(repository.batches.single.status, 'archived');
    });

    test('validates capacity, date ordering, and course status', () async {
      final service = BatchService(repository: _InMemoryBatchRepository());
      final owner = _user(AppRole.owner, 'demo-owner');

      // Zero or negative capacity
      await expectLater(
        service.createForUser(owner, _batch(capacity: 0)),
        throwsA(isA<BatchValidationException>()),
      );
      await expectLater(
        service.createForUser(owner, _batch(capacity: -10)),
        throwsA(isA<BatchValidationException>()),
      );

      // End date before start date
      await expectLater(
        service.createForUser(
          owner,
          _batch(
            startDate: DateTime(2026, 6, 1),
            endDate: DateTime(2026, 5, 1),
          ),
        ),
        throwsA(isA<BatchValidationException>()),
      );

      // Cannot create batch for archived course
      final archivedCourse = _course(name: 'Old Course').copyWith(status: 'archived');
      await expectLater(
        service.createForUser(
          owner,
          _batch(name: 'New Batch'),
          course: archivedCourse,
        ),
        throwsA(isA<BatchValidationException>()),
      );
    });

    test('trainer watches only their assigned batches', () async {
      final repository = _InMemoryBatchRepository()
        ..batches.addAll([
          _batch(id: 'b1', name: 'Trainer 1 Batch', trainerId: 'demo-trainer'),
          _batch(id: 'b2', name: 'Trainer 2 Batch', trainerId: 'other-trainer'),
        ]);
      final service = BatchService(repository: repository);
      final trainer = _user(AppRole.trainer, 'demo-trainer');

      final visible = await service.watchForUser(trainer).first;
      expect(visible.map((b) => b.id), ['b1']);
    });

    test('counselor and accounts roles have view-only access', () async {
      final service = BatchService(repository: _InMemoryBatchRepository());
      final counselor = _user(AppRole.counselor, 'demo-counselor');
      final accounts = _user(AppRole.accounts, 'demo-accounts');

      expect(service.canManage(counselor), isFalse);
      expect(service.canManage(accounts), isFalse);

      await expectLater(
        service.createForUser(counselor, _batch()),
        throwsA(isA<BatchValidationException>()),
      );
      await expectLater(
        service.createForUser(accounts, _batch()),
        throwsA(isA<BatchValidationException>()),
      );
    });
  });

  group('CourseBatchSeedService', () {
    test('sample initialization is a repeat-safe operation with deterministic IDs', () async {
      final courseRepo = _InMemoryCourseRepository();
      final batchRepo = _InMemoryBatchRepository();
      final seedService = CourseBatchSeedService(
        courseRepository: courseRepo,
        batchRepository: batchRepo,
      );

      final firstLoad = await seedService.loadSampleData();
      expect(firstLoad.coursesCreated, 5);
      expect(firstLoad.batchesCreated, 6);
      expect(firstLoad.alreadyHadData, isFalse);
      expect(courseRepo.courses, hasLength(5));
      expect(batchRepo.batches, hasLength(6));

      // Check deterministic document IDs match student sample references
      expect(courseRepo.courses.map((c) => c.id), containsAll(['data-analytics', 'full-stack-development']));
      expect(batchRepo.batches.map((b) => b.id), containsAll(['da-jan-2026-a', 'fsd-feb-2026-b']));

      // Repeat execution
      final secondLoad = await seedService.loadSampleData();
      expect(secondLoad.coursesCreated, 0);
      expect(secondLoad.batchesCreated, 0);
      expect(secondLoad.alreadyHadData, isTrue);
      expect(courseRepo.courses, hasLength(5));
      expect(batchRepo.batches, hasLength(6));
    });
  });
}

class _InMemoryCourseRepository
    implements CourseRepository, CourseSeedRepository {
  final List<Course> courses = <Course>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  @override
  Stream<List<Course>> watchCourses({
    CourseAccessScope scope = const CourseAccessScope(),
    int limit = 200,
  }) async* {
    List<Course> visible() => courses
        .where((c) => scope.instituteId == null || c.instituteId == scope.instituteId)
        .take(limit)
        .toList();
    yield visible();
    yield* _changes.stream.map((_) => visible());
  }

  @override
  Future<List<Course>> getCourses({
    CourseAccessScope scope = const CourseAccessScope(),
  }) async => courses
      .where((c) => scope.instituteId == null || c.instituteId == scope.instituteId)
      .toList();

  @override
  Future<Course> createCourse(Course course) async {
    final id = course.id.isEmpty ? 'course-${_nextId++}' : course.id;
    final saved = course.copyWith(id: id);
    courses.add(saved);
    _changes.add(null);
    return saved;
  }

  @override
  Future<Course> updateCourse(Course course) async {
    final index = courses.indexWhere((c) => c.id == course.id);
    courses[index] = course;
    _changes.add(null);
    return course;
  }

  @override
  Future<Course> archiveCourse(Course course) =>
      updateCourse(course.copyWith(status: 'archived'));

  @override
  Future<bool> isCoursesCollectionEmpty() async => courses.isEmpty;

  @override
  Future<int> countExistingSampleCourses(List<Course> samples) async => samples
      .where((s) => courses.any((c) => c.id == s.id))
      .length;

  @override
  Future<void> createMissingSampleCourses(List<Course> samples) async {
    for (final s in samples) {
      if (courses.every((c) => c.id != s.id)) {
        courses.add(s);
      }
    }
    _changes.add(null);
  }
}

class _InMemoryBatchRepository
    implements BatchRepository, BatchSeedRepository {
  final List<Batch> batches = <Batch>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 1;

  @override
  Stream<List<Batch>> watchBatches({
    BatchAccessScope scope = const BatchAccessScope(),
    int limit = 200,
  }) async* {
    List<Batch> visible() => batches
        .where(
          (b) =>
              (scope.instituteId == null || b.instituteId == scope.instituteId) &&
              (scope.trainerId == null || b.trainerId == scope.trainerId),
        )
        .take(limit)
        .toList();
    yield visible();
    yield* _changes.stream.map((_) => visible());
  }

  @override
  Future<List<Batch>> getBatches({
    BatchAccessScope scope = const BatchAccessScope(),
  }) async => batches
      .where(
        (b) =>
            (scope.instituteId == null || b.instituteId == scope.instituteId) &&
            (scope.trainerId == null || b.trainerId == scope.trainerId),
      )
      .toList();

  @override
  Future<Batch> createBatch(Batch batch) async {
    final id = batch.id.isEmpty ? 'batch-${_nextId++}' : batch.id;
    final saved = batch.copyWith(id: id);
    batches.add(saved);
    _changes.add(null);
    return saved;
  }

  @override
  Future<Batch> updateBatch(Batch batch) async {
    final index = batches.indexWhere((b) => b.id == batch.id);
    batches[index] = batch;
    _changes.add(null);
    return batch;
  }

  @override
  Future<Batch> archiveBatch(Batch batch) =>
      updateBatch(batch.copyWith(status: 'archived'));

  @override
  Future<bool> isBatchesCollectionEmpty() async => batches.isEmpty;

  @override
  Future<int> countExistingSampleBatches(List<Batch> samples) async => samples
      .where((s) => batches.any((b) => b.id == s.id))
      .length;

  @override
  Future<void> createMissingSampleBatches(List<Batch> samples) async {
    for (final s in samples) {
      if (batches.every((b) => b.id != s.id)) {
        batches.add(s);
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

Course _course({
  String id = '',
  String name = 'Test Course',
  String duration = '6 Months',
  double fee = 30000,
}) => Course(
  id: id,
  instituteId: 'demo-institute',
  name: name,
  description: 'Test description',
  duration: duration,
  feeAmount: fee,
  status: 'active',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Batch _batch({
  String id = '',
  String name = 'Test Batch',
  String courseId = 'data-analytics',
  String courseName = 'Data Analytics',
  String trainerId = 'demo-trainer',
  String trainerName = 'Rohan Kulkarni',
  DateTime? startDate,
  DateTime? endDate,
  int capacity = 25,
}) => Batch(
  id: id,
  instituteId: 'demo-institute',
  name: name,
  courseId: courseId,
  courseName: courseName,
  trainerId: trainerId,
  trainerName: trainerName,
  startDate: startDate ?? DateTime(2026, 1, 1),
  endDate: endDate ?? DateTime(2026, 7, 1),
  capacity: capacity,
  scheduleDescription: 'Mon-Wed-Fri, 10 AM',
  status: 'active',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

