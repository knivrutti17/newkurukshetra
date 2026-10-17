import '../models/app_user.dart';
import '../models/batch.dart';
import '../models/trainer.dart';
import '../repositories/batch_repository.dart';
import '../repositories/trainer_repository.dart';

class TrainerValidationException implements Exception {
  const TrainerValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class TrainerService {
  TrainerService({
    TrainerRepository? repository,
    BatchRepository? batchRepository,
  }) : _repository = repository ?? FirestoreTrainerRepository(),
       _batchRepository = batchRepository ?? FirestoreBatchRepository();

  final TrainerRepository _repository;
  final BatchRepository _batchRepository;

  TrainerRepository get repository => _repository;
  BatchRepository get batchRepository => _batchRepository;

  static final _emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+(\.[\w\-]+)+$');

  bool canManage(AppUser user) => user.role == AppRole.owner;

  Stream<List<Trainer>> watchForUser(AppUser user) =>
      _repository.watchTrainers(scope: _scopeFor(user));

  Future<List<Trainer>> getForUser(AppUser user) =>
      _repository.getTrainers(scope: _scopeFor(user));

  Future<Trainer?> getTrainerById(String id) => _repository.getTrainerById(id);

  Future<Trainer> createTrainer(AppUser user, Trainer trainer) async {
    _ensureCanManage(user);
    _validate(trainer);

    final normalized = trainer.email.trim().toLowerCase();
    final isTaken = await _repository.isEmailTaken(
      trainer.instituteId,
      normalized,
    );
    if (isTaken) {
      throw TrainerValidationException(
        'A trainer with email "${trainer.email.trim()}" already exists in this institute.',
      );
    }

    return _repository.createTrainer(
      trainer.copyWith(emailNormalized: normalized),
    );
  }

  Future<Trainer> updateTrainer(AppUser user, Trainer trainer) async {
    _ensureCanManage(user);
    _validate(trainer);

    final normalized = trainer.email.trim().toLowerCase();
    final isTaken = await _repository.isEmailTaken(
      trainer.instituteId,
      normalized,
      excludeTrainerId: trainer.id,
    );
    if (isTaken) {
      throw TrainerValidationException(
        'Another trainer with email "${trainer.email.trim()}" already exists in this institute.',
      );
    }

    return _repository.updateTrainer(
      trainer.copyWith(emailNormalized: normalized),
    );
  }

  Future<Trainer> deactivateTrainer(AppUser user, String id) async {
    _ensureCanManage(user);
    return _repository.setTrainerStatus(id, 'inactive');
  }

  Future<Trainer> activateTrainer(AppUser user, String id) async {
    _ensureCanManage(user);
    return _repository.setTrainerStatus(id, 'active');
  }

  Future<Batch> assignTrainerToBatch(
    AppUser user, {
    required String batchId,
    required String trainerId,
  }) async {
    _ensureCanManage(user);

    final trainer = await _repository.getTrainerById(trainerId);
    if (trainer == null) {
      throw const TrainerValidationException('Trainer not found.');
    }
    if (!trainer.isActive) {
      throw const TrainerValidationException(
        'Cannot assign an inactive trainer to a batch.',
      );
    }

    final batches = await _batchRepository.getBatches(
      scope: BatchAccessScope(instituteId: trainer.instituteId),
    );
    final batch = batches.cast<Batch?>().firstWhere(
      (b) => b?.id == batchId,
      orElse: () => null,
    );
    if (batch == null) {
      throw const TrainerValidationException('Batch not found.');
    }

    if (batch.trainerId == trainer.id &&
        batch.trainerName == trainer.fullName) {
      return batch;
    }

    final updated = batch.copyWith(
      trainerId: trainer.id,
      trainerName: trainer.fullName,
    );
    return _batchRepository.updateBatch(updated);
  }

  Future<Batch> unassignTrainerFromBatch(
    AppUser user, {
    required String batchId,
  }) async {
    _ensureCanManage(user);

    final batches = await _batchRepository.getBatches(
      scope: BatchAccessScope(instituteId: user.instituteId),
    );
    final batch = batches.cast<Batch?>().firstWhere(
      (b) => b?.id == batchId,
      orElse: () => null,
    );
    if (batch == null) {
      throw const TrainerValidationException('Batch not found.');
    }

    final updated = batch.copyWith(trainerId: '', trainerName: 'Unassigned');
    return _batchRepository.updateBatch(updated);
  }

  TrainerAccessScope _scopeFor(AppUser user) => switch (user.role) {
    AppRole.trainer => TrainerAccessScope(
      instituteId: user.instituteId,
      trainerId: user.id,
    ),
    _ => TrainerAccessScope(instituteId: user.instituteId),
  };

  void _ensureCanManage(AppUser user) {
    if (!canManage(user)) {
      throw const TrainerValidationException(
        'Your demo role has view-only trainer access.',
      );
    }
  }

  void _validate(Trainer trainer) {
    if (trainer.fullName.trim().isEmpty) {
      throw const TrainerValidationException('Trainer full name is required.');
    }
    final email = trainer.email.trim();
    if (email.isEmpty) {
      throw const TrainerValidationException('Trainer email is required.');
    }
    if (!_emailRegex.hasMatch(email)) {
      throw const TrainerValidationException(
        'Please enter a valid email address (e.g. trainer@example.com).',
      );
    }
    if (trainer.experienceYears < 0) {
      throw const TrainerValidationException(
        'Experience years cannot be negative.',
      );
    }
  }
}
