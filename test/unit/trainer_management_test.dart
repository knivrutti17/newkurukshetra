import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/batch.dart';
import 'package:kurukshetra/data/models/trainer.dart';
import 'package:kurukshetra/data/repositories/batch_repository.dart';
import 'package:kurukshetra/data/repositories/trainer_repository.dart';
import 'package:kurukshetra/data/services/trainer_seed_service.dart';
import 'package:kurukshetra/data/services/trainer_service.dart';

void main() {
  group('Trainer and TrainerAvailability models', () {
    test('Trainer model serialization and deserialization', () {
      final now = DateTime(2026, 3, 15, 10, 0);
      const availability = TrainerAvailability(
        weekdays: ['Monday', 'Wednesday', 'Friday'],
        preferredTimeRange: 'Morning (09:00 AM - 01:00 PM)',
        unavailableNotes: 'Unavailable evenings',
        generalNotes: 'Lead Flutter mentor',
      );

      final trainer = Trainer(
        id: 't-101',
        instituteId: 'demo-institute',
        fullName: 'Rohan Kulkarni',
        email: 'rohan@example.com',
        emailNormalized: 'rohan@example.com',
        phone: '+91 98201 12345',
        expertise: const ['Flutter', 'Dart', 'Node.js'],
        qualifications: 'M.Tech Software Systems',
        experienceYears: 8,
        availability: availability,
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );

      expect(trainer.isActive, isTrue);
      expect(trainer.isInactive, isFalse);

      final firestoreMap = trainer.toFirestore();
      expect(firestoreMap['fullName'], 'Rohan Kulkarni');
      expect(firestoreMap['emailNormalized'], 'rohan@example.com');
      expect(firestoreMap['experienceYears'], 8);
      expect(firestoreMap['availability']['weekdays'], ['Monday', 'Wednesday', 'Friday']);

      final updateMap = trainer.toUpdateMap();
      expect(updateMap.containsKey('createdAt'), isFalse);
      expect(updateMap.containsKey('updatedAt'), isTrue);

      final cloned = trainer.copyWith(
        status: 'inactive',
        experienceYears: 9,
      );
      expect(cloned.status, 'inactive');
      expect(cloned.isInactive, isTrue);
      expect(cloned.experienceYears, 9);
      expect(cloned.fullName, 'Rohan Kulkarni');
    });

    test('TrainerAvailability summary computation', () {
      const weekdaysAvail = TrainerAvailability(
        weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
        preferredTimeRange: '09:00 AM - 01:00 PM',
      );
      expect(weekdaysAvail.summary, 'Mon - Fri • 09:00 AM - 01:00 PM');

      const allDaysAvail = TrainerAvailability(
        weekdays: [
          'Monday',
          'Tuesday',
          'Wednesday',
          'Thursday',
          'Friday',
          'Saturday',
          'Sunday',
        ],
        preferredTimeRange: 'Flexible',
      );
      expect(allDaysAvail.summary, 'All 7 days • Flexible');

      const customDaysAvail = TrainerAvailability(
        weekdays: ['Saturday', 'Sunday'],
        preferredTimeRange: '10:00 AM - 01:00 PM',
      );
      expect(customDaysAvail.summary, 'Sat, Sun • 10:00 AM - 01:00 PM');

      const emptyAvail = TrainerAvailability(weekdays: []);
      expect(emptyAvail.summary, 'No weekdays configured');
    });
  });

  group('TrainerService CRUD and Validations', () {
    late _InMemoryTrainerRepository trainerRepo;
    late _InMemoryBatchRepository batchRepo;
    late TrainerService service;
    final owner = _user(AppRole.owner, 'demo-owner');
    final counselor = _user(AppRole.counselor, 'demo-counselor');
    final trainerUser = _user(AppRole.trainer, 't-rohan');

    setUp(() {
      trainerRepo = _InMemoryTrainerRepository();
      batchRepo = _InMemoryBatchRepository();
      service = TrainerService(
        repository: trainerRepo,
        batchRepository: batchRepo,
      );
    });

    test('Owner creates, updates, and deactivates a trainer', () async {
      final created = await service.createTrainer(
        owner,
        _testTrainer(
          id: 't-rohan',
          fullName: 'Rohan Kulkarni',
          email: 'rohan@example.com',
          experienceYears: 8,
        ),
      );

      expect(created.id, 't-rohan');
      expect(created.emailNormalized, 'rohan@example.com');
      expect(trainerRepo.trainers, hasLength(1));

      final updated = await service.updateTrainer(
        owner,
        created.copyWith(
          fullName: 'Rohan A. Kulkarni',
          experienceYears: 9,
        ),
      );
      expect(updated.fullName, 'Rohan A. Kulkarni');
      expect(updated.experienceYears, 9);
      expect(trainerRepo.trainers.single.fullName, 'Rohan A. Kulkarni');

      final deactivated = await service.deactivateTrainer(owner, 't-rohan');
      expect(deactivated.isInactive, isTrue);
      expect(trainerRepo.trainers.single.isInactive, isTrue);

      final reactivated = await service.activateTrainer(owner, 't-rohan');
      expect(reactivated.isActive, isTrue);
    });

    test('Validates required fields and email format', () async {
      // Empty name
      await expectLater(
        service.createTrainer(
          owner,
          _testTrainer(fullName: '   ', email: 'valid@example.com'),
        ),
        throwsA(isA<TrainerValidationException>()),
      );

      // Empty email
      await expectLater(
        service.createTrainer(
          owner,
          _testTrainer(fullName: 'Aditya Sen', email: '   '),
        ),
        throwsA(isA<TrainerValidationException>()),
      );

      // Invalid email format
      await expectLater(
        service.createTrainer(
          owner,
          _testTrainer(fullName: 'Aditya Sen', email: 'notanemail'),
        ),
        throwsA(isA<TrainerValidationException>()),
      );

      // Negative experience
      await expectLater(
        service.createTrainer(
          owner,
          _testTrainer(
            fullName: 'Aditya Sen',
            email: 'aditya@example.com',
            experienceYears: -2,
          ),
        ),
        throwsA(isA<TrainerValidationException>()),
      );
    });

    test('Prevents duplicate email registrations within the same institute', () async {
      await service.createTrainer(
        owner,
        _testTrainer(
          id: 't-1',
          fullName: 'Pooja Verma',
          email: 'Pooja.Verma@Example.com',
        ),
      );

      // Attempt creating second trainer with same email (different casing)
      await expectLater(
        service.createTrainer(
          owner,
          _testTrainer(
            id: 't-2',
            fullName: 'Pooja Duplicate',
            email: 'pooja.verma@example.com',
          ),
        ),
        throwsA(isA<TrainerValidationException>()),
      );

      // Updating t-1 with its own email is permitted
      final t1 = trainerRepo.trainers.first;
      final updated = await service.updateTrainer(
        owner,
        t1.copyWith(fullName: 'Pooja Verma Updated'),
      );
      expect(updated.fullName, 'Pooja Verma Updated');

      // Attempt updating t-2 (another trainer) with t-1's email is rejected
      final t2 = await service.createTrainer(
        owner,
        _testTrainer(
          id: 't-2',
          fullName: 'Unique Trainer',
          email: 'unique@example.com',
        ),
      );
      await expectLater(
        service.updateTrainer(
          owner,
          t2.copyWith(email: 'pooja.verma@example.com'),
        ),
        throwsA(isA<TrainerValidationException>()),
      );
    });

    test('Role permissions: non-owners cannot manage trainers', () async {
      expect(service.canManage(owner), isTrue);
      expect(service.canManage(counselor), isFalse);
      expect(service.canManage(trainerUser), isFalse);

      await expectLater(
        service.createTrainer(
          counselor,
          _testTrainer(fullName: 'Unauthorized', email: 'c@example.com'),
        ),
        throwsA(isA<TrainerValidationException>()),
      );

      await expectLater(
        service.createTrainer(
          trainerUser,
          _testTrainer(fullName: 'Unauthorized', email: 't@example.com'),
        ),
        throwsA(isA<TrainerValidationException>()),
      );

      await expectLater(
        service.deactivateTrainer(counselor, 't-1'),
        throwsA(isA<TrainerValidationException>()),
      );
    });

    test('Trainer role only sees their own profile in watchForUser', () async {
      await service.createTrainer(
        owner,
        _testTrainer(id: 't-rohan', fullName: 'Rohan Kulkarni', email: 'rohan@example.com'),
      );
      await service.createTrainer(
        owner,
        _testTrainer(id: 't-pooja', fullName: 'Pooja Verma', email: 'pooja@example.com'),
      );

      // Owner sees both
      final ownerTrainers = await service.getForUser(owner);
      expect(ownerTrainers, hasLength(2));

      // Trainer 't-rohan' sees only their own record
      final trainerScoped = await service.getForUser(trainerUser);
      expect(trainerScoped, hasLength(1));
      expect(trainerScoped.single.id, 't-rohan');
    });
  });

  group('Batch Assignment Integration', () {
    late _InMemoryTrainerRepository trainerRepo;
    late _InMemoryBatchRepository batchRepo;
    late TrainerService service;
    final owner = _user(AppRole.owner, 'demo-owner');

    setUp(() {
      trainerRepo = _InMemoryTrainerRepository();
      batchRepo = _InMemoryBatchRepository();
      service = TrainerService(
        repository: trainerRepo,
        batchRepository: batchRepo,
      );
    });

    test('Assigns active trainer to existing batch and preserves unrelated fields', () async {
      final trainer = await service.createTrainer(
        owner,
        _testTrainer(
          id: 'trainer-aditya',
          fullName: 'Aditya Sen',
          email: 'aditya@example.com',
        ),
      );

      final batch = Batch(
        id: 'batch-da-1',
        instituteId: 'demo-institute',
        name: 'DA May 2026',
        courseId: 'c-da',
        courseName: 'Data Analytics',
        trainerId: 'old-trainer',
        trainerName: 'Old Trainer',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 11, 1),
        capacity: 25,
        scheduleDescription: 'Mon-Wed-Fri, 10 AM',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await batchRepo.createBatch(batch);

      final updatedBatch = await service.assignTrainerToBatch(
        owner,
        batchId: 'batch-da-1',
        trainerId: trainer.id,
      );

      expect(updatedBatch.trainerId, 'trainer-aditya');
      expect(updatedBatch.trainerName, 'Aditya Sen');
      expect(updatedBatch.capacity, 25);
      expect(updatedBatch.courseName, 'Data Analytics');

      final persisted = batchRepo.batches.singleWhere((b) => b.id == 'batch-da-1');
      expect(persisted.trainerId, 'trainer-aditya');
      expect(persisted.trainerName, 'Aditya Sen');
    });

    test('Rejects assigning an inactive trainer to a batch', () async {
      final trainer = await service.createTrainer(
        owner,
        _testTrainer(
          id: 'trainer-inactive',
          fullName: 'Inactive Trainer',
          email: 'inactive@example.com',
          status: 'inactive',
        ),
      );

      final batch = Batch(
        id: 'batch-1',
        instituteId: 'demo-institute',
        name: 'Batch 1',
        courseId: 'c-1',
        courseName: 'Course 1',
        trainerId: '',
        trainerName: '',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 11, 1),
        capacity: 20,
        scheduleDescription: 'Daily',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await batchRepo.createBatch(batch);

      await expectLater(
        service.assignTrainerToBatch(
          owner,
          batchId: 'batch-1',
          trainerId: trainer.id,
        ),
        throwsA(isA<TrainerValidationException>()),
      );
    });

    test('Unassigns a trainer from a batch', () async {
      final batch = Batch(
        id: 'batch-2',
        instituteId: 'demo-institute',
        name: 'Batch 2',
        courseId: 'c-2',
        courseName: 'Course 2',
        trainerId: 't-1',
        trainerName: 'Some Trainer',
        startDate: DateTime(2026, 5, 1),
        endDate: DateTime(2026, 11, 1),
        capacity: 20,
        scheduleDescription: 'Daily',
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await batchRepo.createBatch(batch);

      final unassigned = await service.unassignTrainerFromBatch(
        owner,
        batchId: 'batch-2',
      );
      expect(unassigned.trainerId, '');
      expect(unassigned.trainerName, 'Unassigned');
    });
  });

  group('TrainerSeedService', () {
    test('Populates sample trainers and avoids duplicate overwrites on repeated runs', () async {
      final trainerRepo = _InMemoryTrainerRepository();
      final batchRepo = _InMemoryBatchRepository();
      final seedService = TrainerSeedService(
        trainerRepository: trainerRepo,
        batchRepository: batchRepo,
      );

      // First run: seeds all sample trainers
      final firstResult = await seedService.loadSampleData();
      expect(firstResult.trainersCreated, 5);
      expect(firstResult.trainersSkipped, 0);
      expect(firstResult.alreadyHadData, isFalse);
      expect(trainerRepo.trainers, hasLength(5));

      // Verifies deterministic IDs
      final ids = trainerRepo.trainers.map((t) => t.id).toList();
      expect(ids, containsAll([
        'demo-trainer',
        'trainer-pooja-verma',
        'trainer-aditya-sen',
        'trainer-ananya-joshi',
        'trainer-vikram-malhotra',
      ]));

      // Second run: repeat-safe
      final secondResult = await seedService.loadSampleData();
      expect(secondResult.trainersCreated, 0);
      expect(secondResult.trainersSkipped, 5);
      expect(secondResult.alreadyHadData, isTrue);
      expect(trainerRepo.trainers, hasLength(5));
    });
  });
}

// ---------------------------------------------------------------------------
// TEST HELPERS & IN-MEMORY REPOSITORIES
// ---------------------------------------------------------------------------

AppUser _user(AppRole role, String id) => AppUser(
      id: id,
      name: 'Test $id',
      email: '$id@demo.com',
      role: role,
    );

Trainer _testTrainer({
  String id = 'trainer-test',
  String fullName = 'Test Trainer',
  String email = 'trainer@example.com',
  int experienceYears = 5,
  String status = 'active',
}) =>
    Trainer(
      id: id,
      instituteId: 'demo-institute',
      fullName: fullName,
      email: email,
      emailNormalized: email.trim().toLowerCase(),
      phone: '+91 98200 00000',
      expertise: const ['Flutter', 'Node.js'],
      qualifications: 'B.Tech IT',
      experienceYears: experienceYears,
      availability: const TrainerAvailability(),
      status: status,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class _InMemoryTrainerRepository
    implements TrainerRepository, TrainerSeedRepository {
  final List<Trainer> trainers = <Trainer>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Trainer>> watchTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
    int limit = 200,
  }) async* {
    List<Trainer> visible() => trainers
        .where(
          (t) =>
              (scope.instituteId == null || t.instituteId == scope.instituteId) &&
              (scope.trainerId == null || t.id == scope.trainerId),
        )
        .take(limit)
        .toList();
    yield visible();
    yield* _changes.stream.map((_) => visible());
  }

  @override
  Future<List<Trainer>> getTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
  }) async =>
      trainers
          .where(
            (t) =>
                (scope.instituteId == null || t.instituteId == scope.instituteId) &&
                (scope.trainerId == null || t.id == scope.trainerId),
          )
          .toList();

  @override
  Future<Trainer?> getTrainerById(String id) async {
    final match = trainers.where((t) => t.id == id);
    return match.isEmpty ? null : match.first;
  }

  @override
  Future<Trainer> createTrainer(Trainer trainer) async {
    final id = trainer.id.isEmpty ? 'trainer-${trainers.length + 1}' : trainer.id;
    final saved = trainer.copyWith(id: id);
    trainers.add(saved);
    _changes.add(null);
    return saved;
  }

  @override
  Future<Trainer> updateTrainer(Trainer trainer) async {
    final index = trainers.indexWhere((t) => t.id == trainer.id);
    if (index >= 0) {
      trainers[index] = trainer;
      _changes.add(null);
    }
    return trainer;
  }

  @override
  Future<Trainer> setTrainerStatus(String id, String status) async {
    final index = trainers.indexWhere((t) => t.id == id);
    if (index >= 0) {
      trainers[index] = trainers[index].copyWith(status: status);
      _changes.add(null);
      return trainers[index];
    }
    throw StateError('Trainer $id not found');
  }

  @override
  Future<bool> isEmailTaken(
    String instituteId,
    String emailNormalized, {
    String? excludeTrainerId,
  }) async {
    return trainers.any(
      (t) =>
          t.instituteId == instituteId &&
          t.emailNormalized == emailNormalized &&
          t.id != excludeTrainerId,
    );
  }

  @override
  Future<bool> isTrainersCollectionEmpty() async => trainers.isEmpty;

  @override
  Future<int> countExistingSampleTrainers(List<Trainer> samples) async =>
      samples.where((s) => trainers.any((t) => t.id == s.id)).length;

  @override
  Future<void> createMissingSampleTrainers(List<Trainer> samples) async {
    for (final s in samples) {
      if (trainers.every((t) => t.id != s.id)) {
        trainers.add(s);
      }
    }
    _changes.add(null);
  }
}

class _InMemoryBatchRepository
    implements BatchRepository, BatchSeedRepository {
  final List<Batch> batches = <Batch>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

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
  }) async =>
      batches
          .where(
            (b) =>
                (scope.instituteId == null || b.instituteId == scope.instituteId) &&
                (scope.trainerId == null || b.trainerId == scope.trainerId),
          )
          .toList();

  @override
  Future<Batch> createBatch(Batch batch) async {
    batches.add(batch);
    _changes.add(null);
    return batch;
  }

  @override
  Future<Batch> updateBatch(Batch batch) async {
    final index = batches.indexWhere((b) => b.id == batch.id);
    if (index >= 0) {
      batches[index] = batch;
      _changes.add(null);
    }
    return batch;
  }

  @override
  Future<Batch> archiveBatch(Batch batch) =>
      updateBatch(batch.copyWith(status: 'archived'));

  @override
  Future<bool> isBatchesCollectionEmpty() async => batches.isEmpty;

  @override
  Future<int> countExistingSampleBatches(List<Batch> samples) async =>
      samples.where((s) => batches.any((b) => b.id == s.id)).length;

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

