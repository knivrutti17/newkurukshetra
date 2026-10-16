import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/batch.dart';
import 'package:kurukshetra/data/models/trainer.dart';
import 'package:kurukshetra/data/repositories/batch_repository.dart';
import 'package:kurukshetra/data/repositories/trainer_repository.dart';
import 'package:kurukshetra/data/services/batch_service.dart';
import 'package:kurukshetra/data/services/trainer_service.dart';
import 'package:kurukshetra/features/trainers/screens/trainers_screen.dart';

void main() {
  final now = DateTime(2026, 3, 1, 10, 0);

  group('TrainersScreen Widget Tests', () {
    testWidgets(
      'Owner sees header, action buttons, summary cards, and trainer table rows',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final trainerRepo = _WidgetMemoryTrainerRepository();
        final batchRepo = _WidgetMemoryBatchRepository();

        final t1 = _makeTrainer(
          id: 'demo-trainer',
          fullName: 'Rohan Kulkarni',
          email: 'trainer@demo.com',
          expertise: ['Flutter', 'Node.js'],
          status: 'active',
          createdAt: now,
        );
        final t2 = _makeTrainer(
          id: 'trainer-2',
          fullName: 'Pooja Verma',
          email: 'pooja@demo.com',
          expertise: ['UI/UX Design', 'Figma'],
          status: 'active',
          createdAt: now,
        );
        trainerRepo.trainers[t1.id] = t1;
        trainerRepo.trainers[t2.id] = t2;

        final batch = _makeBatch(
          id: 'b-1',
          name: 'FSD Feb 2026',
          trainerId: 'demo-trainer',
          trainerName: 'Rohan Kulkarni',
        );
        batchRepo.batches[batch.id] = batch;

        final trainerService = TrainerService(
          repository: trainerRepo,
          batchRepository: batchRepo,
        );
        final batchService = BatchService(repository: batchRepo);

        final owner = const AppUser(
          id: 'demo-owner',
          name: 'Aarav Mehta',
          email: 'owner@demo.com',
          role: AppRole.owner,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrainersScreen(
                user: owner,
                trainerService: trainerService,
                batchService: batchService,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Header and actions
        expect(find.text('Trainer Management'), findsOneWidget);
        expect(find.text('Load Sample Trainers'), findsOneWidget);
        expect(find.text('Add Trainer'), findsWidgets);

        // Overview metrics
        expect(find.text('Active Trainers'), findsOneWidget);
        expect(find.text('Assigned to Batches'), findsOneWidget);
        expect(find.text('No Batch Assignments'), findsOneWidget);
        expect(find.text('Active Batch Allocations'), findsOneWidget);

        // Metric values: 2 active, 1 assigned, 1 unassigned, 1 allocation
        expect(find.text('2'), findsOneWidget);
        expect(find.text('1'), findsNWidgets(3));

        // Table Rows
        expect(find.text('Rohan Kulkarni'), findsOneWidget);
        expect(find.text('Pooja Verma'), findsOneWidget);
        expect(find.text('trainer@demo.com'), findsOneWidget);
        expect(find.text('pooja@demo.com'), findsOneWidget);
        expect(find.text('Flutter'), findsOneWidget);
        expect(find.text('UI/UX Design'), findsOneWidget);
      },
    );

    testWidgets('Owner opens Add Trainer dialog and creates a new trainer', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final trainerRepo = _WidgetMemoryTrainerRepository();
      final batchRepo = _WidgetMemoryBatchRepository();

      final trainerService = TrainerService(
        repository: trainerRepo,
        batchRepository: batchRepo,
      );
      final batchService = BatchService(repository: batchRepo);

      final owner = const AppUser(
        id: 'demo-owner',
        name: 'Aarav Mehta',
        email: 'owner@demo.com',
        role: AppRole.owner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainersScreen(
              user: owner,
              trainerService: trainerService,
              batchService: batchService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "Add Trainer" button
      await tester.tap(find.widgetWithText(FilledButton, 'Add Trainer').first);
      await tester.pumpAndSettle();

      expect(find.text('Add Trainer'), findsWidgets);
      expect(find.text('Full Name *'), findsOneWidget);
      expect(find.text('Email Address *'), findsOneWidget);

      // Enter details
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full Name *'),
        'Aditya Sen',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email Address *'),
        'aditya.sen@demo.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone Number'),
        '+91 98203 34567',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Areas of Expertise / Subjects',
        ),
        'Data Analytics, Python, SQL',
      );

      // Submit
      await tester.tap(find.widgetWithText(FilledButton, 'Create Trainer'));
      await tester.pumpAndSettle();

      // Verifies created in repository and visible in table
      expect(trainerRepo.trainers.values, hasLength(1));
      expect(find.text('Aditya Sen'), findsOneWidget);
      expect(find.text('aditya.sen@demo.com'), findsOneWidget);
    });

    testWidgets(
      'Owner views trainer details dialog and assigned batches',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final trainerRepo = _WidgetMemoryTrainerRepository();
        final batchRepo = _WidgetMemoryBatchRepository();

        final t1 = _makeTrainer(
          id: 'demo-trainer',
          fullName: 'Rohan Kulkarni',
          email: 'trainer@demo.com',
          expertise: ['Flutter', 'Node.js'],
          qualifications: 'M.Tech Software Systems',
          experienceYears: 8,
          status: 'active',
          createdAt: now,
        );
        trainerRepo.trainers[t1.id] = t1;

        final batch = _makeBatch(
          id: 'b-fsd',
          name: 'FSD Feb 2026',
          courseName: 'Full Stack Development',
          trainerId: 'demo-trainer',
          trainerName: 'Rohan Kulkarni',
        );
        batchRepo.batches[batch.id] = batch;

        final trainerService = TrainerService(
          repository: trainerRepo,
          batchRepository: batchRepo,
        );
        final batchService = BatchService(repository: batchRepo);

        final owner = const AppUser(
          id: 'demo-owner',
          name: 'Aarav Mehta',
          email: 'owner@demo.com',
          role: AppRole.owner,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrainersScreen(
                user: owner,
                trainerService: trainerService,
                batchService: batchService,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Tap view profile button
        final viewButton = find.byTooltip('View Profile & Batches').first;
        await tester.tap(viewButton);
        await tester.pumpAndSettle();

        // Detail dialog inspection
        expect(find.text('Rohan Kulkarni'), findsWidgets);
        expect(find.text('ID: demo-trainer'), findsOneWidget);
        expect(find.text('M.Tech Software Systems'), findsOneWidget);
        expect(find.text('8 Years'), findsOneWidget);
        expect(find.text('Assigned Batches (1)'), findsOneWidget);
        expect(find.text('FSD Feb 2026'), findsOneWidget);
        expect(find.text('Full Stack Development • Mon-Wed-Fri, 10 AM'), findsOneWidget);

        // Close dialog
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Owner sees active batch warning and acknowledgement checkbox when deactivating assigned trainer',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final trainerRepo = _WidgetMemoryTrainerRepository();
        final batchRepo = _WidgetMemoryBatchRepository();

        final t1 = _makeTrainer(
          id: 'demo-trainer',
          fullName: 'Rohan Kulkarni',
          email: 'trainer@demo.com',
          status: 'active',
          createdAt: now,
        );
        trainerRepo.trainers[t1.id] = t1;

        final batch = _makeBatch(
          id: 'b-da',
          name: 'DA Jan 2026 A',
          courseName: 'Data Analytics',
          trainerId: 'demo-trainer',
          trainerName: 'Rohan Kulkarni',
        );
        batchRepo.batches[batch.id] = batch;

        final trainerService = TrainerService(
          repository: trainerRepo,
          batchRepository: batchRepo,
        );
        final batchService = BatchService(repository: batchRepo);

        final owner = const AppUser(
          id: 'demo-owner',
          name: 'Aarav Mehta',
          email: 'owner@demo.com',
          role: AppRole.owner,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrainersScreen(
                user: owner,
                trainerService: trainerService,
                batchService: batchService,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Tap Deactivate
        await tester.tap(find.byTooltip('Deactivate Trainer').first);
        await tester.pumpAndSettle();

        // Warning banner and batch name shown
        expect(find.text('Active Batch Assignment Warning'), findsOneWidget);
        expect(find.text('• DA Jan 2026 A (Data Analytics)'), findsOneWidget);

        final deactivateButtonFinder =
            find.widgetWithText(FilledButton, 'Deactivate Trainer');
        expect(deactivateButtonFinder, findsOneWidget);

        // Confirm button is disabled because checkbox is not checked
        final FilledButton buttonBefore =
            tester.widget<FilledButton>(deactivateButtonFinder);
        expect(buttonBefore.onPressed, isNull);

        // Check the acknowledgement checkbox
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();

        final FilledButton buttonAfter =
            tester.widget<FilledButton>(deactivateButtonFinder);
        expect(buttonAfter.onPressed, isNotNull);

        // Click Deactivate Trainer
        await tester.tap(deactivateButtonFinder);
        await tester.pumpAndSettle();

        // Verifies trainer is now inactive
        expect(trainerRepo.trainers['demo-trainer']?.isInactive, isTrue);
      },
    );

    testWidgets(
      'Counselor role has view-only access without add or seed buttons',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final trainerRepo = _WidgetMemoryTrainerRepository();
        final batchRepo = _WidgetMemoryBatchRepository();

        final t1 = _makeTrainer(
          id: 'demo-trainer',
          fullName: 'Rohan Kulkarni',
          email: 'trainer@demo.com',
          status: 'active',
          createdAt: now,
        );
        trainerRepo.trainers[t1.id] = t1;

        final trainerService = TrainerService(
          repository: trainerRepo,
          batchRepository: batchRepo,
        );
        final batchService = BatchService(repository: batchRepo);

        final counselor = const AppUser(
          id: 'demo-counselor',
          name: 'Priya Shah',
          email: 'counselor@demo.com',
          role: AppRole.counselor,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TrainersScreen(
                user: counselor,
                trainerService: trainerService,
                batchService: batchService,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Trainer Management'), findsOneWidget);
        expect(find.text('Load Sample Trainers'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Add Trainer'), findsNothing);
        expect(find.byTooltip('Edit Trainer'), findsNothing);
        expect(find.byTooltip('Deactivate Trainer'), findsNothing);

        // View profile is still accessible for reading
        expect(find.byTooltip('View Profile & Batches'), findsOneWidget);
      },
    );

    testWidgets('Empty state is shown when no trainers exist', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final trainerRepo = _WidgetMemoryTrainerRepository();
      final batchRepo = _WidgetMemoryBatchRepository();

      final trainerService = TrainerService(
        repository: trainerRepo,
        batchRepository: batchRepo,
      );
      final batchService = BatchService(repository: batchRepo);

      final owner = const AppUser(
        id: 'demo-owner',
        name: 'Aarav Mehta',
        email: 'owner@demo.com',
        role: AppRole.owner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrainersScreen(
              user: owner,
              trainerService: trainerService,
              batchService: batchService,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No trainers registered yet.'), findsOneWidget);
      expect(
        find.text('Click "Add Trainer" or "Load Sample Trainers" to begin.'),
        findsOneWidget,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// TEST HELPERS & REPOSITORIES
// ---------------------------------------------------------------------------

Trainer _makeTrainer({
  required String id,
  required String fullName,
  required String email,
  List<String> expertise = const [],
  String qualifications = '',
  int experienceYears = 3,
  String status = 'active',
  required DateTime createdAt,
}) =>
    Trainer(
      id: id,
      instituteId: 'demo-institute',
      fullName: fullName,
      email: email,
      emailNormalized: email.trim().toLowerCase(),
      phone: '+91 98200 00000',
      expertise: expertise,
      qualifications: qualifications,
      experienceYears: experienceYears,
      availability: const TrainerAvailability(),
      status: status,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

Batch _makeBatch({
  required String id,
  required String name,
  String courseName = 'Full Stack Development',
  required String trainerId,
  required String trainerName,
}) =>
    Batch(
      id: id,
      instituteId: 'demo-institute',
      name: name,
      courseId: 'course-1',
      courseName: courseName,
      trainerId: trainerId,
      trainerName: trainerName,
      startDate: DateTime(2026, 2, 1),
      endDate: DateTime(2026, 8, 1),
      capacity: 25,
      scheduleDescription: 'Mon-Wed-Fri, 10 AM',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class _WidgetMemoryTrainerRepository
    implements TrainerRepository, TrainerSeedRepository {
  final Map<String, Trainer> trainers = <String, Trainer>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Trainer>> watchTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
    int limit = 200,
  }) async* {
    List<Trainer> visible() => trainers.values
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
      trainers.values
          .where(
            (t) =>
                (scope.instituteId == null || t.instituteId == scope.instituteId) &&
                (scope.trainerId == null || t.id == scope.trainerId),
          )
          .toList();

  @override
  Future<Trainer?> getTrainerById(String id) async => trainers[id];

  @override
  Future<Trainer> createTrainer(Trainer trainer) async {
    final id = trainer.id.isEmpty ? 'trainer-${trainers.length + 1}' : trainer.id;
    final saved = trainer.copyWith(id: id);
    trainers[saved.id] = saved;
    _changes.add(null);
    return saved;
  }

  @override
  Future<Trainer> updateTrainer(Trainer trainer) async {
    trainers[trainer.id] = trainer;
    _changes.add(null);
    return trainer;
  }

  @override
  Future<Trainer> setTrainerStatus(String id, String status) async {
    final existing = trainers[id];
    if (existing != null) {
      final updated = existing.copyWith(status: status);
      trainers[id] = updated;
      _changes.add(null);
      return updated;
    }
    throw StateError('Trainer not found');
  }

  @override
  Future<bool> isEmailTaken(
    String instituteId,
    String emailNormalized, {
    String? excludeTrainerId,
  }) async =>
      trainers.values.any(
        (t) =>
            t.instituteId == instituteId &&
            t.emailNormalized == emailNormalized &&
            t.id != excludeTrainerId,
      );

  @override
  Future<bool> isTrainersCollectionEmpty() async => trainers.isEmpty;

  @override
  Future<int> countExistingSampleTrainers(List<Trainer> samples) async =>
      samples.where((s) => trainers.containsKey(s.id)).length;

  @override
  Future<void> createMissingSampleTrainers(List<Trainer> samples) async {
    for (final s in samples) {
      if (!trainers.containsKey(s.id)) {
        trainers[s.id] = s;
      }
    }
    _changes.add(null);
  }
}

class _WidgetMemoryBatchRepository
    implements BatchRepository, BatchSeedRepository {
  final Map<String, Batch> batches = <String, Batch>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Batch>> watchBatches({
    BatchAccessScope scope = const BatchAccessScope(),
    int limit = 200,
  }) async* {
    List<Batch> visible() => batches.values
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
      batches.values
          .where(
            (b) =>
                (scope.instituteId == null || b.instituteId == scope.instituteId) &&
                (scope.trainerId == null || b.trainerId == scope.trainerId),
          )
          .toList();

  @override
  Future<Batch> createBatch(Batch batch) async {
    batches[batch.id] = batch;
    _changes.add(null);
    return batch;
  }

  @override
  Future<Batch> updateBatch(Batch batch) async {
    batches[batch.id] = batch;
    _changes.add(null);
    return batch;
  }

  @override
  Future<Batch> archiveBatch(Batch batch) =>
      updateBatch(batch.copyWith(status: 'archived'));

  @override
  Future<bool> isBatchesCollectionEmpty() async => batches.isEmpty;

  @override
  Future<int> countExistingSampleBatches(List<Batch> samples) async =>
      samples.where((s) => batches.containsKey(s.id)).length;

  @override
  Future<void> createMissingSampleBatches(List<Batch> samples) async {
    for (final s in samples) {
      if (!batches.containsKey(s.id)) {
        batches[s.id] = s;
      }
    }
    _changes.add(null);
  }
}
