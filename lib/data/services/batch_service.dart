import '../models/app_user.dart';
import '../models/batch.dart';
import '../models/course.dart';
import '../repositories/batch_repository.dart';

class BatchValidationException implements Exception {
  const BatchValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BatchService {
  BatchService({BatchRepository? repository})
    : _repository = repository ?? FirestoreBatchRepository();

  final BatchRepository _repository;

  bool canManage(AppUser user) => user.role == AppRole.owner;

  Stream<List<Batch>> watchForUser(AppUser user) =>
      _repository.watchBatches(scope: _scopeFor(user));

  Future<List<Batch>> getForUser(AppUser user) =>
      _repository.getBatches(scope: _scopeFor(user));

  Future<Batch> createForUser(
    AppUser user,
    Batch batch, {
    Course? course,
  }) async {
    _ensureCanManage(user);
    if (course != null && course.isArchived) {
      throw const BatchValidationException(
        'Cannot create a batch for an archived course.',
      );
    }
    _validate(batch);
    return _repository.createBatch(batch);
  }

  Future<Batch> updateForUser(AppUser user, Batch batch) async {
    _ensureCanManage(user);
    _validate(batch);
    return _repository.updateBatch(batch);
  }

  Future<Batch> archiveForUser(AppUser user, Batch batch) async {
    _ensureCanManage(user);
    return _repository.archiveBatch(batch);
  }

  BatchAccessScope _scopeFor(AppUser user) => switch (user.role) {
    AppRole.trainer => BatchAccessScope(trainerId: user.id),
    _ => const BatchAccessScope(),
  };

  void _ensureCanManage(AppUser user) {
    if (!canManage(user)) {
      throw const BatchValidationException(
        'Your demo role has view-only batch access.',
      );
    }
  }

  void _validate(Batch batch) {
    if (batch.name.trim().isEmpty) {
      throw const BatchValidationException('Batch name is required.');
    }
    if (batch.courseId.trim().isEmpty) {
      throw const BatchValidationException('Please select a course for the batch.');
    }
    if (batch.trainerId.trim().isEmpty) {
      throw const BatchValidationException('Please select a trainer for the batch.');
    }
    if (batch.capacity <= 0) {
      throw const BatchValidationException('Batch capacity must be greater than 0.');
    }
    if (batch.endDate.isBefore(batch.startDate)) {
      throw const BatchValidationException(
        'Batch end date cannot be earlier than its start date.',
      );
    }
  }
}

