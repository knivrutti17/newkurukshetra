import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/batch.dart';

class BatchAccessScope {
  const BatchAccessScope({
    this.instituteId = 'demo-institute',
    this.trainerId,
  });

  final String? instituteId;
  final String? trainerId;
}

abstract interface class BatchRepository {
  Stream<List<Batch>> watchBatches({
    BatchAccessScope scope = const BatchAccessScope(),
    int limit = 200,
  });

  Future<List<Batch>> getBatches({
    BatchAccessScope scope = const BatchAccessScope(),
  });

  Future<Batch> createBatch(Batch batch);
  Future<Batch> updateBatch(Batch batch);
  Future<Batch> archiveBatch(Batch batch);
  Future<bool> isBatchesCollectionEmpty();
}

abstract interface class BatchSeedRepository {
  Future<bool> isBatchesCollectionEmpty();
  Future<void> createMissingSampleBatches(List<Batch> batches);
  Future<int> countExistingSampleBatches(List<Batch> batches);
}

class FirestoreBatchRepository
    implements BatchRepository, BatchSeedRepository {
  FirestoreBatchRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _batches =>
      _firestore.collection('batches');

  @override
  Stream<List<Batch>> watchBatches({
    BatchAccessScope scope = const BatchAccessScope(),
    int limit = 200,
  }) {
    Query<Map<String, dynamic>> query = _batches.limit(limit);
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.trainerId != null) {
      query = query.where('trainerId', isEqualTo: scope.trainerId);
    }
    return query.snapshots().map((snapshot) {
      final batches = snapshot.docs.map(Batch.fromFirestore).toList();
      batches.sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
      return batches;
    });
  }

  @override
  Future<List<Batch>> getBatches({
    BatchAccessScope scope = const BatchAccessScope(),
  }) async {
    Query<Map<String, dynamic>> query = _batches;
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.trainerId != null) {
      query = query.where('trainerId', isEqualTo: scope.trainerId);
    }
    final snapshot = await query.get();
    final batches = snapshot.docs.map(Batch.fromFirestore).toList();
    batches.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return batches;
  }

  @override
  Future<Batch> createBatch(Batch batch) async {
    final now = DateTime.now();
    final document = batch.id.isEmpty ? _batches.doc() : _batches.doc(batch.id);
    final saved = batch.copyWith(
      id: document.id,
      createdAt: now,
      updatedAt: now,
    );
    await document.set(saved.toFirestore());
    return saved;
  }

  @override
  Future<Batch> updateBatch(Batch batch) async {
    if (batch.id.isEmpty) {
      throw ArgumentError.value(batch.id, 'batch.id', 'Cannot be empty');
    }
    final saved = batch.copyWith(updatedAt: DateTime.now());
    await _batches.doc(saved.id).update(saved.toUpdateMap());
    return saved;
  }

  @override
  Future<Batch> archiveBatch(Batch batch) =>
      updateBatch(batch.copyWith(status: 'archived'));

  @override
  Future<bool> isBatchesCollectionEmpty() async {
    final snapshot = await _batches.limit(1).get();
    return snapshot.docs.isEmpty;
  }

  @override
  Future<int> countExistingSampleBatches(List<Batch> batches) async {
    final ids = batches.map((item) => item.id).toList();
    final snapshots = await Future.wait(ids.map((id) => _batches.doc(id).get()));
    return snapshots.where((item) => item.exists).length;
  }

  @override
  Future<void> createMissingSampleBatches(List<Batch> batches) async {
    final batch = _firestore.batch();
    for (final item in batches) {
      final ref = _batches.doc(item.id);
      batch.set(ref, item.toFirestore(), SetOptions(merge: false));
    }
    await batch.commit();
  }
}

