import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/batch.dart';
import 'package:kurukshetra/data/models/class_session.dart';
import 'package:kurukshetra/data/models/trainer.dart';
import 'package:kurukshetra/data/repositories/batch_repository.dart';
import 'package:kurukshetra/data/repositories/timetable_repository.dart';
import 'package:kurukshetra/data/repositories/trainer_repository.dart';
import 'package:kurukshetra/data/services/batch_service.dart';
import 'package:kurukshetra/data/services/timetable_seed_service.dart';
import 'package:kurukshetra/data/services/timetable_service.dart';
import 'package:kurukshetra/data/services/trainer_service.dart';
import 'package:kurukshetra/features/timetable/screens/timetable_screen.dart';

void main() {
  final now = DateTime.now();
  final mondayThisWeek = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: now.weekday - DateTime.monday));

  group('TimetableScreen Widget Tests', () {
    testWidgets(
      'Owner sees header, action buttons, summary cards, and weekly calendar view',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final timetableRepo = _WidgetMemoryTimetableRepository();
        final batchRepo = _WidgetMemoryBatchRepository();
        final trainerRepo = _WidgetMemoryTrainerRepository();

        final batch = _makeBatch(
          id: 'da-jan-2026-a',
          name: 'DA Jan 2026 A',
          courseName: 'Data Analytics',
          trainerId: 'demo-trainer',
          trainerName: 'Rohan Kulkarni',
        );
        batchRepo.batches[batch.id] = batch;

        final trainer = _makeTrainer(
          id: 'demo-trainer',
          fullName: 'Rohan Kulkarni',
          email: 'trainer@demo.com',
        );
        trainerRepo.trainers[trainer.id] = trainer;

        final session = ClassSession(
          id: 's-1',
          instituteId: 'demo-institute',
          batchId: 'da-jan-2026-a',
          batchName: 'DA Jan 2026 A',
          courseId: 'c-da',
          courseName: 'Data Analytics',
          trainerId: 'demo-trainer',
          trainerName: 'Rohan Kulkarni',
          startAt: mondayThisWeek.add(const Duration(hours: 9)),
          endAt: mondayThisWeek.add(const Duration(hours: 11)),
          deliveryMode: 'in_person',
          roomId: 'room-101',
          roomName: 'Lab 101',
          meetingLink: '',
          status: 'scheduled',
          createdAt: now,
          updatedAt: now,
        );
        timetableRepo.sessions[session.id] = session;

        final timetableService = TimetableService(
          timetableRepository: timetableRepo,
          batchRepository: batchRepo,
          trainerRepository: trainerRepo,
        );
        final batchService = BatchService(repository: batchRepo);
        final trainerService = TrainerService(
          repository: trainerRepo,
          batchRepository: batchRepo,
        );
        final seedService = TimetableSeedService(
          timetableRepository: timetableRepo,
        );

        final owner = const AppUser(
          id: 'demo-owner',
          name: 'Aarav Mehta',
          email: 'owner@demo.com',
          role: AppRole.owner,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TimetableScreen(
                user: owner,
                timetableService: timetableService,
                batchService: batchService,
                trainerService: trainerService,
                seedService: seedService,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Timetable Management'), findsOneWidget);
        expect(find.text('Add Class'), findsOneWidget);
        expect(find.text('Load Sample Schedule'), findsOneWidget);
        expect(find.textContaining('Full Schedule Administration'), findsOneWidget);

        // Overview metrics
        expect(find.text("Today's Classes"), findsOneWidget);
        expect(find.text('Weekly Classes'), findsOneWidget);
        expect(find.text('Clash Status'), findsOneWidget);
        expect(find.text('Delivery Modes'), findsOneWidget);

        // Week control bar & filters
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Weekly Grid'), findsOneWidget);
        expect(find.text('Daily List'), findsOneWidget);
        expect(find.text('All Batches'), findsOneWidget);
        expect(find.text('All Trainers'), findsOneWidget);
        expect(find.text('All Modes'), findsOneWidget);

        // Session card in calendar
        expect(find.text('DA Jan 2026 A'), findsWidgets);
        expect(find.text('Lab 101'), findsOneWidget);
      },
    );

    testWidgets('Empty state appears when no sessions scheduled', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final timetableRepo = _WidgetMemoryTimetableRepository();
      final batchRepo = _WidgetMemoryBatchRepository();
      final trainerRepo = _WidgetMemoryTrainerRepository();

      final timetableService = TimetableService(
        timetableRepository: timetableRepo,
        batchRepository: batchRepo,
        trainerRepository: trainerRepo,
      );

      final owner = const AppUser(
        id: 'demo-owner',
        name: 'Aarav Mehta',
        email: 'owner@demo.com',
        role: AppRole.owner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableScreen(
              user: owner,
              timetableService: timetableService,
              batchService: BatchService(repository: batchRepo),
              trainerService: TrainerService(
                repository: trainerRepo,
                batchRepository: batchRepo,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No class sessions scheduled yet'), findsOneWidget);
      expect(find.text('Schedule First Class'), findsOneWidget);
    });

    testWidgets('Clicking Add Class opens form dialog and can be cancelled', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final timetableRepo = _WidgetMemoryTimetableRepository();
      final batchRepo = _WidgetMemoryBatchRepository();
      final trainerRepo = _WidgetMemoryTrainerRepository();

      final batch = _makeBatch(
        id: 'b-fsd',
        name: 'FSD Feb 2026',
        courseName: 'Full Stack',
      );
      batchRepo.batches[batch.id] = batch;

      final trainer = _makeTrainer(
        id: 't-rohan',
        fullName: 'Rohan Kulkarni',
        email: 'rohan@demo.com',
      );
      trainerRepo.trainers[trainer.id] = trainer;

      final timetableService = TimetableService(
        timetableRepository: timetableRepo,
        batchRepository: batchRepo,
        trainerRepository: trainerRepo,
      );

      final owner = const AppUser(
        id: 'demo-owner',
        name: 'Aarav Mehta',
        email: 'owner@demo.com',
        role: AppRole.owner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableScreen(
              user: owner,
              timetableService: timetableService,
              batchService: BatchService(repository: batchRepo),
              trainerService: TrainerService(
                repository: trainerRepo,
                batchRepository: batchRepo,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap Add Class
      await tester.tap(find.text('Add Class'));
      await tester.pumpAndSettle();

      expect(find.text('Add Class Session'), findsOneWidget);
      expect(find.text('Select Batch *'), findsOneWidget);
      expect(find.text('Assigned Trainer *'), findsOneWidget);
      expect(find.text('Schedule Class'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Class Session'), findsNothing);
    });

    testWidgets('Trainer view hides Add Class and shows personal title', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final timetableRepo = _WidgetMemoryTimetableRepository();
      final batchRepo = _WidgetMemoryBatchRepository();
      final trainerRepo = _WidgetMemoryTrainerRepository();

      final timetableService = TimetableService(
        timetableRepository: timetableRepo,
        batchRepository: batchRepo,
        trainerRepository: trainerRepo,
      );

      final trainerUser = const AppUser(
        id: 'demo-trainer',
        name: 'Rohan Kulkarni',
        email: 'trainer@demo.com',
        role: AppRole.trainer,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableScreen(
              user: trainerUser,
              timetableService: timetableService,
              batchService: BatchService(repository: batchRepo),
              trainerService: TrainerService(
                repository: trainerRepo,
                batchRepository: batchRepo,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('My Timetable & Sessions'), findsOneWidget);
      expect(find.textContaining('Trainer Personalized Schedule'), findsOneWidget);
      expect(find.text('Add Class'), findsNothing);
      expect(find.text('Load Sample Schedule'), findsNothing);
      expect(find.text('Filter Trainer'), findsNothing);
    });

    testWidgets('Counselor view has view-only permissions and counselor banner', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final timetableRepo = _WidgetMemoryTimetableRepository();
      final batchRepo = _WidgetMemoryBatchRepository();
      final trainerRepo = _WidgetMemoryTrainerRepository();

      final timetableService = TimetableService(
        timetableRepository: timetableRepo,
        batchRepository: batchRepo,
        trainerRepository: trainerRepo,
      );

      final counselorUser = const AppUser(
        id: 'demo-counselor',
        name: 'Priya Shah',
        email: 'counselor@demo.com',
        role: AppRole.counselor,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableScreen(
              user: counselorUser,
              timetableService: timetableService,
              batchService: BatchService(repository: batchRepo),
              trainerService: TrainerService(
                repository: trainerRepo,
                batchRepository: batchRepo,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Timetable Management'), findsOneWidget);
      expect(find.textContaining('Counselor Schedule Access'), findsOneWidget);
      expect(find.text('Add Class'), findsNothing);
      expect(find.text('Load Sample Schedule'), findsNothing);
      expect(find.text('Filter Trainer'), findsOneWidget);
    });

    testWidgets('Switching between Weekly Grid and Daily List updates view', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final timetableRepo = _WidgetMemoryTimetableRepository();
      final batchRepo = _WidgetMemoryBatchRepository();
      final trainerRepo = _WidgetMemoryTrainerRepository();

      final session = ClassSession(
        id: 's-fsd',
        instituteId: 'demo-institute',
        batchId: 'b-fsd',
        batchName: 'FSD Feb 2026 B',
        courseId: 'c-fsd',
        courseName: 'Full Stack Development',
        trainerId: 'demo-trainer',
        trainerName: 'Rohan Kulkarni',
        startAt: mondayThisWeek.add(const Duration(hours: 11)),
        endAt: mondayThisWeek.add(const Duration(hours: 13)),
        deliveryMode: 'hybrid',
        roomId: 'room-204',
        roomName: 'Tech Studio 204',
        meetingLink: '',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );
      timetableRepo.sessions[session.id] = session;

      final timetableService = TimetableService(
        timetableRepository: timetableRepo,
        batchRepository: batchRepo,
        trainerRepository: trainerRepo,
      );

      final owner = const AppUser(
        id: 'demo-owner',
        name: 'Aarav Mehta',
        email: 'owner@demo.com',
        role: AppRole.owner,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimetableScreen(
              user: owner,
              timetableService: timetableService,
              batchService: BatchService(repository: batchRepo),
              trainerService: TrainerService(
                repository: trainerRepo,
                batchRepository: batchRepo,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Switch to Daily List
      await tester.tap(find.text('Daily List'));
      await tester.pumpAndSettle();

      expect(find.text('1 classes'), findsOneWidget);
      expect(find.text('Tech Studio 204'), findsOneWidget);

      // Tap on the session row in Daily List to open detail dialog
      await tester.tap(find.text('FSD Feb 2026 B').first);
      await tester.pumpAndSettle();

      expect(find.text('Course'), findsOneWidget);
      expect(find.text('Assigned Trainer'), findsOneWidget);
      expect(find.text('Scheduled Time'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned Trainer'), findsNothing);
    });
  });
}

// ---------------------------------------------------------------------------
// WIDGET TEST HELPERS & REPOSITORIES
// ---------------------------------------------------------------------------

Batch _makeBatch({
  required String id,
  required String name,
  String courseId = 'c-1',
  String courseName = 'Sample Course',
  String trainerId = 'demo-trainer',
  String trainerName = 'Rohan Kulkarni',
}) =>
    Batch(
      id: id,
      instituteId: 'demo-institute',
      name: name,
      courseId: courseId,
      courseName: courseName,
      trainerId: trainerId,
      trainerName: trainerName,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 7, 1),
      capacity: 25,
      scheduleDescription: 'Mon 9 AM',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Trainer _makeTrainer({
  required String id,
  required String fullName,
  required String email,
}) =>
    Trainer(
      id: id,
      instituteId: 'demo-institute',
      fullName: fullName,
      email: email,
      emailNormalized: email.trim().toLowerCase(),
      phone: '+91 98200 00000',
      expertise: const ['Flutter'],
      qualifications: 'B.Tech',
      experienceYears: 6,
      availability: const TrainerAvailability(),
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class _WidgetMemoryTimetableRepository
    implements TimetableRepository, TimetableSeedRepository {
  final Map<String, ClassSession> sessions = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<ClassSession>> watchSessions({
    TimetableAccessScope scope = const TimetableAccessScope(),
    int limit = 300,
  }) async* {
    List<ClassSession> visible() => _filter(scope).take(limit).toList();
    yield visible();
    yield* _changes.stream.map((_) => visible());
  }

  @override
  Future<List<ClassSession>> getSessions({
    TimetableAccessScope scope = const TimetableAccessScope(),
  }) async =>
      _filter(scope);

  List<ClassSession> _filter(TimetableAccessScope scope) {
    var result = sessions.values.where((s) {
      if (scope.instituteId != null && s.instituteId != scope.instituteId) {
        return false;
      }
      if (scope.trainerId != null && s.trainerId != scope.trainerId) {
        return false;
      }
      if (scope.batchId != null && s.batchId != scope.batchId) {
        return false;
      }
      return true;
    }).toList();
    result.sort((a, b) => a.startAt.compareTo(b.startAt));
    return result;
  }

  @override
  Future<ClassSession?> getSessionById(String id) async => sessions[id];

  @override
  Future<ClassSession> createSession(ClassSession session) async {
    final toAdd = session.id.isEmpty
        ? session.copyWith(id: 'gen-${sessions.length + 1}')
        : session;
    sessions[toAdd.id] = toAdd;
    _changes.add(null);
    return toAdd;
  }

  @override
  Future<ClassSession> updateSession(ClassSession session) async {
    sessions[session.id] = session;
    _changes.add(null);
    return session;
  }

  @override
  Future<ClassSession> cancelSession(String id) async {
    final s = sessions[id];
    if (s == null) throw StateError('Not found');
    final cancelled = s.copyWith(status: 'cancelled');
    sessions[id] = cancelled;
    _changes.add(null);
    return cancelled;
  }

  @override
  Future<bool> isSessionsCollectionEmpty() async => sessions.isEmpty;

  @override
  Future<int> countExistingSampleSessions(List<ClassSession> sampleList) async {
    return sampleList.where((s) => sessions.containsKey(s.id)).length;
  }

  @override
  Future<void> createMissingSampleSessions(List<ClassSession> sampleList) async {
    for (final s in sampleList) {
      if (!sessions.containsKey(s.id)) {
        sessions[s.id] = s;
      }
    }
    _changes.add(null);
  }
}

class _WidgetMemoryBatchRepository implements BatchRepository {
  final Map<String, Batch> batches = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Batch>> watchBatches({
    BatchAccessScope scope = const BatchAccessScope(),
    int limit = 200,
  }) async* {
    yield batches.values.take(limit).toList();
    yield* _changes.stream.map((_) => batches.values.take(limit).toList());
  }

  @override
  Future<List<Batch>> getBatches({
    BatchAccessScope scope = const BatchAccessScope(),
  }) async =>
      batches.values.toList();

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
  Future<Batch> archiveBatch(Batch batch) async {
    final updated = batch.copyWith(status: 'archived');
    batches[batch.id] = updated;
    _changes.add(null);
    return updated;
  }

  @override
  Future<bool> isBatchesCollectionEmpty() async => batches.isEmpty;
}

class _WidgetMemoryTrainerRepository implements TrainerRepository {
  final Map<String, Trainer> trainers = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Trainer>> watchTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
    int limit = 200,
  }) async* {
    yield trainers.values.take(limit).toList();
    yield* _changes.stream.map((_) => trainers.values.take(limit).toList());
  }

  @override
  Future<List<Trainer>> getTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
  }) async =>
      trainers.values.toList();

  @override
  Future<Trainer?> getTrainerById(String id) async => trainers[id];

  @override
  Future<Trainer> createTrainer(Trainer trainer) async {
    trainers[trainer.id] = trainer;
    _changes.add(null);
    return trainer;
  }

  @override
  Future<Trainer> updateTrainer(Trainer trainer) async {
    trainers[trainer.id] = trainer;
    _changes.add(null);
    return trainer;
  }

  @override
  Future<Trainer> setTrainerStatus(String id, String status) async {
    final t = trainers[id];
    if (t == null) throw StateError('Not found');
    final updated = t.copyWith(status: status);
    trainers[id] = updated;
    _changes.add(null);
    return updated;
  }

  @override
  Future<bool> isEmailTaken(
    String instituteId,
    String emailNormalized, {
    String? excludeTrainerId,
  }) async =>
      false;

  @override
  Future<bool> isTrainersCollectionEmpty() async => trainers.isEmpty;
}
