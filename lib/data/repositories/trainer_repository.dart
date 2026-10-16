import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trainer.dart';

class TrainerAccessScope {
  const TrainerAccessScope({
    this.instituteId = 'demo-institute',
    this.trainerId,
  });

  final String? instituteId;
  final String? trainerId;
}

abstract interface class TrainerRepository {
  Stream<List<Trainer>> watchTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
    int limit = 200,
  });

  Future<List<Trainer>> getTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
  });

  Future<Trainer?> getTrainerById(String id);

  Future<Trainer> createTrainer(Trainer trainer);

  Future<Trainer> updateTrainer(Trainer trainer);

  Future<Trainer> setTrainerStatus(String id, String status);

  Future<bool> isEmailTaken(
    String instituteId,
    String emailNormalized, {
    String? excludeTrainerId,
  });

  Future<bool> isTrainersCollectionEmpty();
}

abstract interface class TrainerSeedRepository {
  Future<bool> isTrainersCollectionEmpty();
  Future<int> countExistingSampleTrainers(List<Trainer> trainers);
  Future<void> createMissingSampleTrainers(List<Trainer> trainers);
}

class FirestoreTrainerRepository
    implements TrainerRepository, TrainerSeedRepository {
  FirestoreTrainerRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _trainers =>
      _firestore.collection('trainers');

  @override
  Stream<List<Trainer>> watchTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
    int limit = 200,
  }) {
    Query<Map<String, dynamic>> query = _trainers.limit(limit);
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.trainerId != null) {
      query = query.where(FieldPath.documentId, isEqualTo: scope.trainerId);
    }
    return query.snapshots().map((snapshot) {
      final trainers = snapshot.docs.map(Trainer.fromFirestore).toList();
      trainers.sort(
        (left, right) =>
            left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase()),
      );
      return trainers;
    });
  }

  @override
  Future<List<Trainer>> getTrainers({
    TrainerAccessScope scope = const TrainerAccessScope(),
  }) async {
    Query<Map<String, dynamic>> query = _trainers;
    if (scope.instituteId != null) {
      query = query.where('instituteId', isEqualTo: scope.instituteId);
    }
    if (scope.trainerId != null) {
      query = query.where(FieldPath.documentId, isEqualTo: scope.trainerId);
    }
    final snapshot = await query.get();
    final trainers = snapshot.docs.map(Trainer.fromFirestore).toList();
    trainers.sort(
      (left, right) =>
          left.fullName.toLowerCase().compareTo(right.fullName.toLowerCase()),
    );
    return trainers;
  }

  @override
  Future<Trainer?> getTrainerById(String id) async {
    if (id.isEmpty) return null;
    final doc = await _trainers.doc(id).get();
    if (!doc.exists) return null;
    return Trainer.fromFirestore(doc);
  }

  @override
  Future<Trainer> createTrainer(Trainer trainer) async {
    final now = DateTime.now();
    final document =
        trainer.id.isEmpty ? _trainers.doc() : _trainers.doc(trainer.id);
    final saved = trainer.copyWith(
      id: document.id,
      emailNormalized: trainer.email.trim().toLowerCase(),
      createdAt: now,
      updatedAt: now,
    );
    await document.set(saved.toFirestore());
    return saved;
  }

  @override
  Future<Trainer> updateTrainer(Trainer trainer) async {
    if (trainer.id.isEmpty) {
      throw ArgumentError.value(trainer.id, 'trainer.id', 'Cannot be empty');
    }
    final now = DateTime.now();
    final saved = trainer.copyWith(
      emailNormalized: trainer.email.trim().toLowerCase(),
      updatedAt: now,
    );
    await _trainers.doc(saved.id).update(saved.toUpdateMap());
    return saved;
  }

  @override
  Future<Trainer> setTrainerStatus(String id, String status) async {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Cannot be empty');
    }
    final now = DateTime.now();
    await _trainers.doc(id).update({
      'status': status,
      'updatedAt': Timestamp.fromDate(now),
    });
    final updated = await getTrainerById(id);
    if (updated == null) {
      throw StateError('Trainer with id $id not found after status update');
    }
    return updated;
  }

  @override
  Future<bool> isEmailTaken(
    String instituteId,
    String emailNormalized, {
    String? excludeTrainerId,
  }) async {
    final query = _trainers
        .where('instituteId', isEqualTo: instituteId)
        .where('emailNormalized', isEqualTo: emailNormalized);
    final snapshot = await query.get();
    return snapshot.docs.any((doc) => doc.id != excludeTrainerId);
  }

  @override
  Future<bool> isTrainersCollectionEmpty() async {
    final snapshot = await _trainers.limit(1).get();
    return snapshot.docs.isEmpty;
  }

  @override
  Future<int> countExistingSampleTrainers(List<Trainer> trainers) async {
    final ids = trainers.map((t) => t.id).toList();
    final snapshots =
        await Future.wait(ids.map((id) => _trainers.doc(id).get()));
    return snapshots.where((snap) => snap.exists).length;
  }

  @override
  Future<void> createMissingSampleTrainers(List<Trainer> trainers) async {
    final batch = _firestore.batch();
    for (final item in trainers) {
      final ref = _trainers.doc(item.id);
      batch.set(ref, item.toFirestore(), SetOptions(merge: false));
    }
    await batch.commit();
  }
}

