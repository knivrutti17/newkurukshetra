import '../models/app_user.dart';
import '../models/batch.dart';
import '../models/class_session.dart';
import '../models/trainer.dart';
import '../repositories/batch_repository.dart';
import '../repositories/timetable_repository.dart';
import '../repositories/trainer_repository.dart';
import 'clash_detection_engine.dart';

class TimetableValidationException implements Exception {
  const TimetableValidationException(this.message, {this.conflicts = const []});

  final String message;
  final List<ScheduleConflict> conflicts;

  @override
  String toString() => message;
}

/// Coordinates class session creation, editing, cancellation, and conflict verification.
class TimetableService {
  TimetableService({
    TimetableRepository? timetableRepository,
    BatchRepository? batchRepository,
    TrainerRepository? trainerRepository,
  }) : _timetableRepository =
           timetableRepository ?? FirestoreTimetableRepository(),
       _batchRepository = batchRepository ?? FirestoreBatchRepository(),
       _trainerRepository = trainerRepository ?? FirestoreTrainerRepository();

  final TimetableRepository _timetableRepository;
  final BatchRepository _batchRepository;
  final TrainerRepository _trainerRepository;

  TimetableRepository get timetableRepository => _timetableRepository;
  BatchRepository get batchRepository => _batchRepository;
  TrainerRepository get trainerRepository => _trainerRepository;

  bool canManage(AppUser user) => user.role == AppRole.owner;

  Stream<List<ClassSession>> watchForUser(
    AppUser user, {
    String? batchId,
    String? trainerId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _timetableRepository.watchSessions(
      scope: _scopeFor(
        user,
        batchId: batchId,
        trainerId: trainerId,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  Future<List<ClassSession>> getForUser(
    AppUser user, {
    String? batchId,
    String? trainerId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _timetableRepository.getSessions(
      scope: _scopeFor(
        user,
        batchId: batchId,
        trainerId: trainerId,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  Future<ClassSession?> getSessionById(String id) =>
      _timetableRepository.getSessionById(id);

  /// Validates [session] against existing schedules, batches, and trainer constraints.
  Future<List<ScheduleConflict>> validateCandidate({
    required ClassSession session,
  }) async {
    _validateRequiredFields(session);

    // Fetch existing sessions in institute
    final existingSessions = await _timetableRepository.getSessions(
      scope: TimetableAccessScope(instituteId: session.instituteId),
    );

    // Fetch trainer and batch details if available
    Trainer? trainer;
    if (session.trainerId.isNotEmpty) {
      trainer = await _trainerRepository.getTrainerById(session.trainerId);
    }

    Batch? batch;
    if (session.batchId.isNotEmpty) {
      final batches = await _batchRepository.getBatches(
        scope: BatchAccessScope(instituteId: session.instituteId),
      );
      batch = batches.cast<Batch?>().firstWhere(
        (b) => b?.id == session.batchId,
        orElse: () => null,
      );
    }

    return ClashDetectionEngine.detectConflicts(
      candidate: session,
      existingSessions: existingSessions,
      trainer: trainer,
      batch: batch,
    );
  }

  Future<ClassSession> createSession(
    AppUser user,
    ClassSession session, {
    bool allowClashOverride = false,
  }) async {
    _ensureCanManage(user);
    final conflicts = await validateCandidate(session: session);

    if (conflicts.isNotEmpty && !allowClashOverride) {
      throw TimetableValidationException(
        conflicts.first.message,
        conflicts: conflicts,
      );
    }

    return _timetableRepository.createSession(session);
  }

  Future<ClassSession> updateSession(
    AppUser user,
    ClassSession session, {
    bool allowClashOverride = false,
  }) async {
    _ensureCanManage(user);
    final conflicts = await validateCandidate(session: session);

    if (conflicts.isNotEmpty && !allowClashOverride) {
      throw TimetableValidationException(
        conflicts.first.message,
        conflicts: conflicts,
      );
    }

    return _timetableRepository.updateSession(session);
  }

  Future<ClassSession> cancelSession(AppUser user, String id) async {
    _ensureCanManage(user);
    return _timetableRepository.cancelSession(id);
  }

  TimetableAccessScope _scopeFor(
    AppUser user, {
    String? batchId,
    String? trainerId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    if (user.role == AppRole.trainer) {
      return TimetableAccessScope(
        instituteId: user.instituteId,
        trainerId: user.id,
        batchId: batchId,
        startDate: startDate,
        endDate: endDate,
      );
    }

    return TimetableAccessScope(
      instituteId: user.instituteId,
      trainerId: trainerId,
      batchId: batchId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  void _ensureCanManage(AppUser user) {
    if (!canManage(user)) {
      throw const TimetableValidationException(
        'Your demo role has view-only timetable access.',
      );
    }
  }

  void _validateRequiredFields(ClassSession session) {
    if (session.batchId.trim().isEmpty) {
      throw const TimetableValidationException('Please select a batch.');
    }
    if (session.trainerId.trim().isEmpty) {
      throw const TimetableValidationException('Please select a trainer.');
    }
    if (!session.endAt.isAfter(session.startAt)) {
      throw const TimetableValidationException(
        'Class end time must be after start time.',
      );
    }
    if ((session.isInPerson || session.isHybrid) &&
        session.roomName.trim().isEmpty) {
      throw const TimetableValidationException(
        'Room name/number is required for In-Person or Hybrid classes.',
      );
    }
  }
}
