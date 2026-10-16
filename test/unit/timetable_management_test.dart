import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/batch.dart';
import 'package:kurukshetra/data/models/class_session.dart';
import 'package:kurukshetra/data/models/trainer.dart';
import 'package:kurukshetra/data/repositories/batch_repository.dart';
import 'package:kurukshetra/data/repositories/timetable_repository.dart';
import 'package:kurukshetra/data/repositories/trainer_repository.dart';
import 'package:kurukshetra/data/services/clash_detection_engine.dart';
import 'package:kurukshetra/data/services/timetable_seed_service.dart';
import 'package:kurukshetra/data/services/timetable_service.dart';

void main() {
  group('ClassSession model', () {
    test('ClassSession serialization and getters', () {
      final now = DateTime(2026, 3, 16, 9, 0); // Monday
      final end = DateTime(2026, 3, 16, 11, 0);

      final session = ClassSession(
        id: 's-101',
        instituteId: 'demo-institute',
        batchId: 'b-1',
        batchName: 'DA Jan 2026 A',
        courseId: 'c-1',
        courseName: 'Data Analytics',
        trainerId: 't-1',
        trainerName: 'Rohan Kulkarni',
        startAt: now,
        endAt: end,
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: now,
        updatedAt: now,
      );

      expect(session.isScheduled, isTrue);
      expect(session.isCancelled, isFalse);
      expect(session.isCompleted, isFalse);
      expect(session.isInPerson, isTrue);
      expect(session.isOnline, isFalse);
      expect(session.isHybrid, isFalse);
      expect(session.duration, const Duration(hours: 2));
      expect(session.deliveryModeLabel, 'In-Person');
      expect(session.statusLabel, 'Scheduled');

      final firestoreMap = session.toFirestore();
      expect(firestoreMap['batchId'], 'b-1');
      expect(firestoreMap['trainerName'], 'Rohan Kulkarni');
      expect(firestoreMap['deliveryMode'], 'in_person');
      expect(firestoreMap['roomName'], 'Lab 101');

      final updateMap = session.toUpdateMap();
      expect(updateMap.containsKey('createdAt'), isFalse);
      expect(updateMap.containsKey('updatedAt'), isTrue);

      final cancelled = session.copyWith(status: 'cancelled');
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.statusLabel, 'Cancelled');
    });

    test('ClassSession deliveryMode and status labels', () {
      final now = DateTime(2026, 3, 16, 10, 0);
      final sessionOnline = ClassSession(
        id: 's-online',
        instituteId: 'demo-institute',
        batchId: 'b-2',
        batchName: 'Batch 2',
        courseId: 'c-2',
        courseName: 'Course 2',
        trainerId: 't-2',
        trainerName: 'Trainer 2',
        startAt: now,
        endAt: now.add(const Duration(hours: 1)),
        deliveryMode: 'online',
        roomId: '',
        roomName: '',
        meetingLink: 'https://meet.google.com/xyz',
        status: 'completed',
        createdAt: now,
        updatedAt: now,
      );

      expect(sessionOnline.isOnline, isTrue);
      expect(sessionOnline.deliveryModeLabel, 'Online Live');
      expect(sessionOnline.statusLabel, 'Completed');

      final sessionHybrid = sessionOnline.copyWith(
        deliveryMode: 'hybrid',
        status: 'scheduled',
      );
      expect(sessionHybrid.isHybrid, isTrue);
      expect(sessionHybrid.deliveryModeLabel, 'Hybrid');
    });
  });

  group('ClashDetectionEngine', () {
    final monday9am = DateTime(2026, 3, 16, 9, 0); // Monday
    final monday11am = DateTime(2026, 3, 16, 11, 0);
    final monday10am = DateTime(2026, 3, 16, 10, 0);
    final monday12pm = DateTime(2026, 3, 16, 12, 0);

    final baseTrainer = Trainer(
      id: 'trainer-rohan',
      instituteId: 'demo-institute',
      fullName: 'Rohan Kulkarni',
      email: 'rohan@demo.com',
      emailNormalized: 'rohan@demo.com',
      phone: '+91 98200 00000',
      expertise: const ['Flutter'],
      qualifications: 'B.Tech',
      experienceYears: 6,
      availability: const TrainerAvailability(
        weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      ),
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final baseBatch = Batch(
      id: 'batch-da',
      instituteId: 'demo-institute',
      name: 'DA Jan 2026 A',
      courseId: 'c-da',
      courseName: 'Data Analytics',
      trainerId: 'trainer-rohan',
      trainerName: 'Rohan Kulkarni',
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 7, 1),
      capacity: 25,
      scheduleDescription: 'Mon 9 AM',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    final existingSession = ClassSession(
      id: 'session-existing',
      instituteId: 'demo-institute',
      batchId: 'batch-da',
      batchName: 'DA Jan 2026 A',
      courseId: 'c-da',
      courseName: 'Data Analytics',
      trainerId: 'trainer-rohan',
      trainerName: 'Rohan Kulkarni',
      startAt: monday9am,
      endAt: monday11am,
      deliveryMode: 'in_person',
      roomId: 'room-101',
      roomName: 'Lab 101',
      meetingLink: '',
      status: 'scheduled',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    test('Valid session without clashes returns empty conflict list', () {
      final afternoonSession = ClassSession(
        id: 'session-afternoon',
        instituteId: 'demo-institute',
        batchId: 'batch-other',
        batchName: 'Other Batch',
        courseId: 'c-other',
        courseName: 'Other Course',
        trainerId: 'trainer-rohan',
        trainerName: 'Rohan Kulkarni',
        startAt: DateTime(2026, 3, 16, 14, 0),
        endAt: DateTime(2026, 3, 16, 16, 0),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: afternoonSession,
        existingSessions: [existingSession],
        trainer: baseTrainer,
        batch: baseBatch,
      );

      expect(conflicts, isEmpty);
    });

    test('End time before start time returns availabilityConflict', () {
      final invalidTimeSession = existingSession.copyWith(
        startAt: monday11am,
        endAt: monday9am,
      );

      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: invalidTimeSession,
        existingSessions: const [],
      );

      expect(conflicts, isNotEmpty);
      expect(conflicts.first.type, ScheduleConflictType.availabilityConflict);
      expect(conflicts.first.message, contains('Class end time must be after start time'));
    });

    test('Trainer double-booking is detected for overlapping time', () {
      final overlappingTrainerSession = ClassSession(
        id: 'candidate-different-batch',
        instituteId: 'demo-institute',
        batchId: 'batch-different',
        batchName: 'Different Batch',
        courseId: 'c-2',
        courseName: 'Course 2',
        trainerId: 'trainer-rohan',
        trainerName: 'Rohan Kulkarni',
        startAt: monday10am,
        endAt: monday12pm,
        deliveryMode: 'online',
        roomId: '',
        roomName: '',
        meetingLink: '',
        status: 'scheduled',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: overlappingTrainerSession,
        existingSessions: [existingSession],
        trainer: baseTrainer,
      );

      expect(
        conflicts.any((c) => c.type == ScheduleConflictType.trainerConflict),
        isTrue,
      );
      expect(conflicts.first.message, contains('Rohan Kulkarni'));
      expect(conflicts.first.message, contains('already teaching'));
    });

    test('Classroom double-booking is detected for in-person classes in same room', () {
      final overlappingRoomSession = ClassSession(
        id: 'candidate-other-trainer',
        instituteId: 'demo-institute',
        batchId: 'batch-fsd',
        batchName: 'FSD Feb 2026',
        courseId: 'c-fsd',
        courseName: 'Full Stack',
        trainerId: 'other-trainer',
        trainerName: 'Other Trainer',
        startAt: monday10am,
        endAt: monday12pm,
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: overlappingRoomSession,
        existingSessions: [existingSession],
      );

      expect(
        conflicts.any((c) => c.type == ScheduleConflictType.roomConflict),
        isTrue,
      );
      expect(conflicts.first.message, contains('Classroom "Lab 101" is already reserved'));
    });

    test('Batch overlap is detected when same batch has two simultaneous classes', () {
      final overlappingBatchSession = ClassSession(
        id: 'candidate-same-batch',
        instituteId: 'demo-institute',
        batchId: 'batch-da',
        batchName: 'DA Jan 2026 A',
        courseId: 'c-da',
        courseName: 'Data Analytics',
        trainerId: 'different-trainer',
        trainerName: 'Different Trainer',
        startAt: monday10am,
        endAt: monday12pm,
        deliveryMode: 'online',
        roomId: '',
        roomName: '',
        meetingLink: '',
        status: 'scheduled',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: overlappingBatchSession,
        existingSessions: [existingSession],
      );

      expect(
        conflicts.any((c) => c.type == ScheduleConflictType.batchConflict),
        isTrue,
      );
      expect(conflicts.first.message, contains('DA Jan 2026 A'));
    });

    test('Archived batch check triggers statusConflict', () {
      final archivedBatch = baseBatch.copyWith(status: 'archived');
      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: existingSession.copyWith(id: 'new-id'),
        existingSessions: const [],
        batch: archivedBatch,
      );

      expect(
        conflicts.any((c) => c.type == ScheduleConflictType.statusConflict),
        isTrue,
      );
      expect(conflicts.first.message, contains('archived'));
    });

    test('Inactive trainer check triggers statusConflict', () {
      final inactiveTrainer = baseTrainer.copyWith(status: 'inactive');
      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: existingSession.copyWith(id: 'new-id'),
        existingSessions: const [],
        trainer: inactiveTrainer,
      );

      expect(
        conflicts.any((c) => c.type == ScheduleConflictType.statusConflict),
        isTrue,
      );
      expect(conflicts.first.message, contains('inactive'));
    });

    test('Trainer availability weekday check detects classes scheduled outside available days', () {
      // Sunday March 22, 2026
      final sundaySession = ClassSession(
        id: 'sunday-class',
        instituteId: 'demo-institute',
        batchId: 'batch-da',
        batchName: 'DA Jan 2026 A',
        courseId: 'c-da',
        courseName: 'Data Analytics',
        trainerId: 'trainer-rohan',
        trainerName: 'Rohan Kulkarni',
        startAt: DateTime(2026, 3, 22, 10, 0),
        endAt: DateTime(2026, 3, 22, 12, 0),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: sundaySession,
        existingSessions: const [],
        trainer: baseTrainer, // Mon-Fri only
      );

      expect(
        conflicts.any((c) => c.type == ScheduleConflictType.availabilityConflict),
        isTrue,
      );
      expect(conflicts.first.message, contains('not marked as available on Sundays'));
    });

    test('Cancelled sessions do NOT trigger clashes', () {
      final cancelledSession = existingSession.copyWith(status: 'cancelled');

      final candidate = ClassSession(
        id: 'candidate-id',
        instituteId: 'demo-institute',
        batchId: 'batch-da',
        batchName: 'DA Jan 2026 A',
        courseId: 'c-da',
        courseName: 'Data Analytics',
        trainerId: 'trainer-rohan',
        trainerName: 'Rohan Kulkarni',
        startAt: monday9am,
        endAt: monday11am,
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: candidate,
        existingSessions: [cancelledSession],
        trainer: baseTrainer,
        batch: baseBatch,
      );

      expect(conflicts, isEmpty);
    });

    test('Self session is excluded during update', () {
      final conflicts = ClashDetectionEngine.detectConflicts(
        candidate: existingSession,
        existingSessions: [existingSession],
        trainer: baseTrainer,
        batch: baseBatch,
      );

      expect(conflicts, isEmpty);
    });
  });

  group('TimetableService', () {
    late _InMemoryTimetableRepository timetableRepo;
    late _InMemoryBatchRepository batchRepo;
    late _InMemoryTrainerRepository trainerRepo;
    late TimetableService service;

    final owner = _user(AppRole.owner, 'owner-1');
    final counselor = _user(AppRole.counselor, 'counselor-1');
    final trainer = _user(AppRole.trainer, 'trainer-rohan');
    final accounts = _user(AppRole.accounts, 'accounts-1');

    setUp(() {
      timetableRepo = _InMemoryTimetableRepository();
      batchRepo = _InMemoryBatchRepository();
      trainerRepo = _InMemoryTrainerRepository();

      service = TimetableService(
        timetableRepository: timetableRepo,
        batchRepository: batchRepo,
        trainerRepository: trainerRepo,
      );

      // Populate base batch and trainer
      batchRepo.createBatch(
        Batch(
          id: 'b-da',
          instituteId: 'demo-institute',
          name: 'DA Jan 2026 A',
          courseId: 'c-da',
          courseName: 'Data Analytics',
          trainerId: 'trainer-rohan',
          trainerName: 'Rohan Kulkarni',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 7, 1),
          capacity: 25,
          scheduleDescription: 'Mon 9 AM',
          status: 'active',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

      trainerRepo.createTrainer(
        Trainer(
          id: 'trainer-rohan',
          instituteId: 'demo-institute',
          fullName: 'Rohan Kulkarni',
          email: 'rohan@demo.com',
          emailNormalized: 'rohan@demo.com',
          phone: '+91 98200 00000',
          expertise: const ['Data'],
          qualifications: 'M.Tech',
          experienceYears: 7,
          availability: const TrainerAvailability(
            weekdays: ['Monday', 'Tuesday', 'Wednesday'],
          ),
          status: 'active',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
    });

    test('Role permissions: owner can manage, others cannot', () {
      expect(service.canManage(owner), isTrue);
      expect(service.canManage(counselor), isFalse);
      expect(service.canManage(trainer), isFalse);
      expect(service.canManage(accounts), isFalse);
    });

    test('Owner can create a clash-free class session', () async {
      final monday = DateTime(2026, 3, 16, 9, 0); // Monday
      final session = ClassSession(
        id: 's-new',
        instituteId: 'demo-institute',
        batchId: 'b-da',
        batchName: 'DA Jan 2026 A',
        courseId: 'c-da',
        courseName: 'Data Analytics',
        trainerId: 'trainer-rohan',
        trainerName: 'Rohan Kulkarni',
        startAt: monday,
        endAt: monday.add(const Duration(hours: 2)),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: monday,
        updatedAt: monday,
      );

      final created = await service.createSession(owner, session);
      expect(created.id, 's-new');
      expect(timetableRepo.sessions, hasLength(1));
    });

    test('Creating session validates required fields', () async {
      final monday = DateTime(2026, 3, 16, 9, 0);
      final missingBatch = ClassSession(
        id: 's-bad',
        instituteId: 'demo-institute',
        batchId: '',
        batchName: '',
        courseId: 'c-da',
        courseName: 'Data Analytics',
        trainerId: 'trainer-rohan',
        trainerName: 'Rohan Kulkarni',
        startAt: monday,
        endAt: monday.add(const Duration(hours: 2)),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: monday,
        updatedAt: monday,
      );

      await expectLater(
        service.createSession(owner, missingBatch),
        throwsA(isA<TimetableValidationException>()),
      );
    });

    test('Owner can override detected clashes with allowClashOverride: true', () async {
      final monday = DateTime(2026, 3, 16, 9, 0);
      final firstSession = ClassSession(
        id: 's-1',
        instituteId: 'demo-institute',
        batchId: 'b-da',
        batchName: 'DA Jan 2026 A',
        courseId: 'c-da',
        courseName: 'Data Analytics',
        trainerId: 'trainer-rohan',
        trainerName: 'Rohan Kulkarni',
        startAt: monday,
        endAt: monday.add(const Duration(hours: 2)),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: monday,
        updatedAt: monday,
      );
      await service.createSession(owner, firstSession);

      final conflictingSession = firstSession.copyWith(
        id: 's-2',
        roomId: 'room-202',
        roomName: 'Room 202',
      );

      // Rejection without override
      await expectLater(
        service.createSession(owner, conflictingSession, allowClashOverride: false),
        throwsA(isA<TimetableValidationException>()),
      );

      // Success with override
      final forced = await service.createSession(
        owner,
        conflictingSession,
        allowClashOverride: true,
      );
      expect(forced.id, 's-2');
      expect(timetableRepo.sessions, hasLength(2));
    });

    test('Cancelling a session marks status: cancelled without deleting document', () async {
      final monday = DateTime(2026, 3, 16, 9, 0);
      final session = ClassSession(
        id: 's-to-cancel',
        instituteId: 'demo-institute',
        batchId: 'b-da',
        batchName: 'DA Jan 2026 A',
        courseId: 'c-da',
        courseName: 'Data Analytics',
        trainerId: 'trainer-rohan',
        trainerName: 'Rohan Kulkarni',
        startAt: monday,
        endAt: monday.add(const Duration(hours: 2)),
        deliveryMode: 'in_person',
        roomId: 'room-101',
        roomName: 'Lab 101',
        meetingLink: '',
        status: 'scheduled',
        createdAt: monday,
        updatedAt: monday,
      );
      await service.createSession(owner, session);

      final cancelled = await service.cancelSession(owner, 's-to-cancel');
      expect(cancelled.isCancelled, isTrue);

      final persisted = await service.getSessionById('s-to-cancel');
      expect(persisted, isNotNull);
      expect(persisted!.status, 'cancelled');
    });

    test('Non-owner cannot cancel session', () async {
      await expectLater(
        service.cancelSession(counselor, 's-some-id'),
        throwsA(isA<TimetableValidationException>()),
      );
    });

    test('Trainer watchForUser filters only assigned sessions', () async {
      final monday = DateTime(2026, 3, 16, 9, 0);
      await service.createSession(
        owner,
        ClassSession(
          id: 's-trainer-1',
          instituteId: 'demo-institute',
          batchId: 'b-da',
          batchName: 'DA Jan 2026 A',
          courseId: 'c-da',
          courseName: 'Data Analytics',
          trainerId: 'trainer-rohan',
          trainerName: 'Rohan Kulkarni',
          startAt: monday,
          endAt: monday.add(const Duration(hours: 2)),
          deliveryMode: 'in_person',
          roomId: 'room-101',
          roomName: 'Lab 101',
          meetingLink: '',
          status: 'scheduled',
          createdAt: monday,
          updatedAt: monday,
        ),
      );

      await service.createSession(
        owner,
        ClassSession(
          id: 's-trainer-other',
          instituteId: 'demo-institute',
          batchId: 'b-other',
          batchName: 'Other Cohort',
          courseId: 'c-other',
          courseName: 'Other',
          trainerId: 'other-trainer-id',
          trainerName: 'Other Trainer',
          startAt: monday.add(const Duration(hours: 3)),
          endAt: monday.add(const Duration(hours: 5)),
          deliveryMode: 'online',
          roomId: '',
          roomName: '',
          meetingLink: '',
          status: 'scheduled',
          createdAt: monday,
          updatedAt: monday,
        ),
      );

      final trainerSessions = await service.getForUser(trainer);
      expect(trainerSessions, hasLength(1));
      expect(trainerSessions.first.trainerId, 'trainer-rohan');

      final ownerSessions = await service.getForUser(owner);
      expect(ownerSessions, hasLength(2));
    });
  });

  group('TimetableSeedService', () {
    test('Populates sample sessions deterministically and avoids duplicates on second run', () async {
      final repo = _InMemoryTimetableRepository();
      final seedService = TimetableSeedService(timetableRepository: repo);

      final firstRun = await seedService.loadSampleData(
        referenceDate: DateTime(2026, 3, 16),
      );
      expect(firstRun.alreadyHadData, isFalse);
      expect(firstRun.sessionsCreated, greaterThanOrEqualTo(5));
      expect(firstRun.sessionsSkipped, 0);

      final totalSeeded = repo.sessions.length;

      // Second run: repeat-safe
      final secondRun = await seedService.loadSampleData(
        referenceDate: DateTime(2026, 3, 16),
      );
      expect(secondRun.alreadyHadData, isTrue);
      expect(secondRun.sessionsCreated, 0);
      expect(secondRun.sessionsSkipped, totalSeeded);
      expect(repo.sessions, hasLength(totalSeeded));
    });
  });
}

// ---------------------------------------------------------------------------
// TEST MOCKS & HELPERS
// ---------------------------------------------------------------------------

AppUser _user(AppRole role, String id) => AppUser(
      id: id,
      name: 'User $id',
      email: '$id@demo.com',
      role: role,
    );

class _InMemoryTimetableRepository
    implements TimetableRepository, TimetableSeedRepository {
  final List<ClassSession> sessions = <ClassSession>[];
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
    var result = sessions.where((s) {
      if (scope.instituteId != null && s.instituteId != scope.instituteId) {
        return false;
      }
      if (scope.trainerId != null && s.trainerId != scope.trainerId) {
        return false;
      }
      if (scope.batchId != null && s.batchId != scope.batchId) {
        return false;
      }
      if (scope.startDate != null && s.endAt.isBefore(scope.startDate!)) {
        return false;
      }
      if (scope.endDate != null && s.startAt.isAfter(scope.endDate!)) {
        return false;
      }
      return true;
    }).toList();

    result.sort((a, b) => a.startAt.compareTo(b.startAt));
    return result;
  }

  @override
  Future<ClassSession?> getSessionById(String id) async {
    final match = sessions.where((s) => s.id == id);
    return match.isEmpty ? null : match.first;
  }

  @override
  Future<ClassSession> createSession(ClassSession session) async {
    final toAdd = session.id.isEmpty
        ? session.copyWith(id: 'gen-${sessions.length + 1}')
        : session;
    sessions.add(toAdd);
    _changes.add(null);
    return toAdd;
  }

  @override
  Future<ClassSession> updateSession(ClassSession session) async {
    final index = sessions.indexWhere((s) => s.id == session.id);
    if (index != -1) {
      sessions[index] = session;
      _changes.add(null);
    }
    return session;
  }

  @override
  Future<ClassSession> cancelSession(String id) async {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index == -1) throw StateError('Session not found: $id');
    final cancelled = sessions[index].copyWith(status: 'cancelled');
    sessions[index] = cancelled;
    _changes.add(null);
    return cancelled;
  }

  @override
  Future<bool> isSessionsCollectionEmpty() async => sessions.isEmpty;

  @override
  Future<int> countExistingSampleSessions(List<ClassSession> sampleList) async {
    final sampleIds = sampleList.map((s) => s.id).toSet();
    return sessions.where((s) => sampleIds.contains(s.id)).length;
  }

  @override
  Future<void> createMissingSampleSessions(List<ClassSession> sampleList) async {
    final existingIds = sessions.map((s) => s.id).toSet();
    for (final sample in sampleList) {
      if (!existingIds.contains(sample.id)) {
        sessions.add(sample);
      }
    }
    _changes.add(null);
  }
}

class _InMemoryBatchRepository implements BatchRepository {
  final List<Batch> batches = <Batch>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<List<Batch>> watchBatches({
    BatchAccessScope scope = const BatchAccessScope(),
    int limit = 200,
  }) async* {
    yield batches.take(limit).toList();
    yield* _changes.stream.map((_) => batches.take(limit).toList());
  }

  @override
  Future<List<Batch>> getBatches({
    BatchAccessScope scope = const BatchAccessScope(),
  }) async =>
      batches;

  @override
  Future<Batch> createBatch(Batch batch) async {
    batches.add(batch);
    _changes.add(null);
    return batch;
  }

  @override
  Future<Batch> updateBatch(Batch batch) async {
    final index = batches.indexWhere((b) => b.id == batch.id);
    if (index != -1) {
      batches[index] = batch;
      _changes.add(null);
    }
    return batch;
  }

  @override
  Future<Batch> archiveBatch(Batch batch) async {
    final index = batches.indexWhere((b) => b.id == batch.id);
    if (index == -1) throw StateError('Batch not found');
    final archived = batches[index].copyWith(status: 'archived');
    batches[index] = archived;
    _changes.add(null);
    return archived;
  }

  @override
  Future<bool> isBatchesCollectionEmpty() async => batches.isEmpty;
}

class _InMemoryTrainerRepository implements TrainerRepository {
  final List<Trainer> trainers = <Trainer>[];

  @override
  Stream<List<Trainer>> watchTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
    int limit = 200,
  }) async* {
    yield trainers;
  }

  @override
  Future<List<Trainer>> getTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
  }) async =>
      trainers;

  @override
  Future<Trainer?> getTrainerById(String id) async {
    final match = trainers.where((t) => t.id == id);
    return match.isEmpty ? null : match.first;
  }

  @override
  Future<Trainer> createTrainer(Trainer trainer) async {
    trainers.add(trainer);
    return trainer;
  }

  @override
  Future<Trainer> updateTrainer(Trainer trainer) async {
    final index = trainers.indexWhere((t) => t.id == trainer.id);
    if (index != -1) trainers[index] = trainer;
    return trainer;
  }

  @override
  Future<Trainer> setTrainerStatus(String id, String status) async {
    final index = trainers.indexWhere((t) => t.id == id);
    if (index == -1) throw StateError('Trainer not found');
    final updated = trainers[index].copyWith(status: status);
    trainers[index] = updated;
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
