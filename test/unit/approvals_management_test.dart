import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/approval_action.dart';
import 'package:kurukshetra/data/repositories/approval_repository.dart';
import 'package:kurukshetra/data/services/approval_seed_service.dart';
import 'package:kurukshetra/data/services/approval_service.dart';

class _FakeApprovalRepository
    implements ApprovalRepository, ApprovalSeedRepository {
  final Map<String, ApprovalAction> storage = {};
  final StreamController<List<ApprovalAction>> _controller =
      StreamController<List<ApprovalAction>>.broadcast();

  void _notify() {
    _controller.add(storage.values.toList());
  }

  @override
  Stream<List<ApprovalAction>> watchActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
    int limit = 300,
  }) {
    return Stream.value(_filter(scope));
  }

  @override
  Future<List<ApprovalAction>> getActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
  }) async {
    return _filter(scope);
  }

  List<ApprovalAction> _filter(ApprovalAccessScope scope) {
    var list = storage.values.toList();
    if (scope.instituteId != null) {
      list = list.where((a) => a.instituteId == scope.instituteId).toList();
    }
    if (scope.status != null) {
      list = list.where((a) => a.status == scope.status).toList();
    }
    if (scope.type != null) {
      list = list.where((a) => a.type == scope.type).toList();
    }
    return list;
  }

  @override
  Future<ApprovalAction?> getActionById(String id) async {
    return storage[id];
  }

  @override
  Future<ApprovalAction> createAction(ApprovalAction action) async {
    storage[action.id] = action;
    _notify();
    return action;
  }

  @override
  Future<ApprovalAction> updateDecision(
    String id, {
    required String status,
    String? reviewer,
    String? rejectionReason,
    required DateTime decisionAt,
  }) async {
    final existing = storage[id];
    if (existing == null) {
      throw Exception('Not found');
    }

    final updated = existing.copyWith(
      status: status,
      approvedBy: status == 'approved' ? reviewer : null,
      approvedAt: status == 'approved' ? decisionAt : null,
      rejectedBy: status == 'rejected' ? reviewer : null,
      rejectedAt: status == 'rejected' ? decisionAt : null,
      rejectionReason: status == 'rejected' ? rejectionReason : null,
      updatedAt: decisionAt,
    );

    storage[id] = updated;
    _notify();
    return updated;
  }

  @override
  Future<bool> isActionsCollectionEmpty() async {
    return storage.isEmpty;
  }

  @override
  Future<int> countExistingSampleActions(List<ApprovalAction> actions) async {
    var count = 0;
    for (final a in actions) {
      if (storage.containsKey(a.id)) {
        count++;
      }
    }
    return count;
  }

  @override
  Future<void> createMissingSampleActions(List<ApprovalAction> actions) async {
    for (final a in actions) {
      if (!storage.containsKey(a.id)) {
        storage[a.id] = a;
      }
    }
    _notify();
  }
}

ApprovalAction _makeAction({
  required String id,
  String instituteId = 'demo-institute',
  required String type,
  required String title,
  String description = 'Test description',
  Map<String, dynamic> payload = const {},
  String requestedBy = 'Staff Member',
  DateTime? requestedAt,
  String status = 'pending',
  String? approvedBy,
  DateTime? approvedAt,
  String? rejectedBy,
  DateTime? rejectedAt,
  String? rejectionReason,
  DateTime? updatedAt,
}) {
  final now = DateTime(2026, 3, 1, 10, 0);
  return ApprovalAction(
    id: id,
    instituteId: instituteId,
    type: type,
    title: title,
    description: description,
    payload: payload,
    requestedBy: requestedBy,
    requestedAt: requestedAt ?? now,
    status: status,
    approvedBy: approvedBy,
    approvedAt: approvedAt,
    rejectedBy: rejectedBy,
    rejectedAt: rejectedAt,
    rejectionReason: rejectionReason,
    updatedAt: updatedAt ?? now,
  );
}

void main() {
  const owner = AppUser(
    id: 'owner-1',
    name: 'Aarav Mehta',
    email: 'owner@institute.com',
    role: AppRole.owner,
  );

  const counselor = AppUser(
    id: 'counselor-1',
    name: 'Priya Sharma',
    email: 'priya@institute.com',
    role: AppRole.counselor,
  );

  const trainer = AppUser(
    id: 'trainer-1',
    name: 'Rohan Kulkarni',
    email: 'rohan@institute.com',
    role: AppRole.trainer,
  );

  const accounts = AppUser(
    id: 'accounts-1',
    name: 'Vikram Joshi',
    email: 'vikram@institute.com',
    role: AppRole.accounts,
  );

  final testTime = DateTime(2026, 3, 1, 10, 0);

  group('ApprovalAction Model Tests', () {
    test('Correctly exposes labels and status flags', () {
      final action = _makeAction(
        id: 'act-1',
        type: 'fee_concession',
        title: 'Fee Concession Request',
        description: 'Concession of 5000',
        requestedBy: 'Counselor Priya',
        requestedAt: testTime,
        status: 'pending',
      );

      expect(action.isPending, isTrue);
      expect(action.isApproved, isFalse);
      expect(action.isRejected, isFalse);
      expect(action.typeLabel, 'Fee Concession');
      expect(action.statusLabel, 'Pending Review');

      final approved = action.copyWith(
        status: 'approved',
        approvedBy: 'Aarav Mehta (Owner)',
        approvedAt: testTime,
      );
      expect(approved.isApproved, isTrue);
      expect(approved.isPending, isFalse);
      expect(approved.statusLabel, 'Approved');

      final rejected = action.copyWith(
        status: 'rejected',
        rejectedBy: 'Aarav Mehta (Owner)',
        rejectedAt: testTime,
        rejectionReason: 'Not eligible under policy',
      );
      expect(rejected.isRejected, isTrue);
      expect(rejected.rejectionReason, 'Not eligible under policy');
      expect(rejected.statusLabel, 'Rejected');
    });

    test('Serializes to firestore map and update map cleanly', () {
      final action = _makeAction(
        id: 'act-2',
        type: 'batch_transfer',
        title: 'Transfer Request',
        description: 'Morning to evening',
        requestedBy: 'Counselor Priya',
        requestedAt: testTime,
        status: 'pending',
        payload: {'studentId': 'std-1'},
      );

      final map = action.toFirestore();
      expect(map['type'], 'batch_transfer');
      expect(map['status'], 'pending');
      expect(map['payload']['studentId'], 'std-1');

      final updateMap = action.toUpdateMap();
      expect(updateMap.containsKey('requestedAt'), isFalse);
      expect(updateMap['type'], 'batch_transfer');
    });
  });

  group('ApprovalService Permissions & Review Scope', () {
    late _FakeApprovalRepository fakeRepo;
    late ApprovalService service;

    setUp(() {
      fakeRepo = _FakeApprovalRepository();
      service = ApprovalService(repository: fakeRepo);
    });

    test('canManage returns true for Owner and Accounts only', () {
      expect(service.canManage(owner), isTrue);
      expect(service.canManage(accounts), isTrue);
      expect(service.canManage(counselor), isFalse);
      expect(service.canManage(trainer), isFalse);
    });

    test('canReview permits Owner on all types, but Accounts only on financial types', () {
      final financialAction = _makeAction(
        id: 'a1',
        type: 'fee_concession',
        title: 'Fee concession',
        description: 'Discount',
        requestedBy: 'Counselor',
        requestedAt: testTime,
        status: 'pending',
      );

      final refundAction = _makeAction(
        id: 'a2',
        type: 'refund_request',
        title: 'Fee refund',
        description: 'Refund 2000',
        requestedBy: 'Accounts',
        requestedAt: testTime,
        status: 'pending',
      );

      final academicAction = _makeAction(
        id: 'a3',
        type: 'batch_transfer',
        title: 'Batch transfer',
        description: 'Transfer batch',
        requestedBy: 'Counselor',
        requestedAt: testTime,
        status: 'pending',
      );

      expect(service.canReview(owner, financialAction), isTrue);
      expect(service.canReview(owner, academicAction), isTrue);

      expect(service.canReview(accounts, financialAction), isTrue);
      expect(service.canReview(accounts, refundAction), isTrue);
      expect(service.canReview(accounts, academicAction), isFalse);

      expect(service.canReview(counselor, financialAction), isFalse);
      expect(service.canReview(trainer, academicAction), isFalse);
    });
  });

  group('ApprovalService Approve and Reject Actions', () {
    late _FakeApprovalRepository fakeRepo;
    late ApprovalService service;

    setUp(() {
      fakeRepo = _FakeApprovalRepository();
      service = ApprovalService(repository: fakeRepo);
    });

    test('Owner successfully approves an action', () async {
      final action = _makeAction(
        id: 'act-transfer',
        type: 'batch_transfer',
        title: 'Batch Transfer',
        description: 'Transfer to Batch B',
        requestedBy: 'Counselor Priya',
        requestedAt: testTime,
        status: 'pending',
      );
      await fakeRepo.createAction(action);

      final result = await service.approveAction(owner, 'act-transfer');
      expect(result.status, 'approved');
      expect(result.approvedBy, contains('Aarav Mehta'));

      final stored = await fakeRepo.getActionById('act-transfer');
      expect(stored?.isApproved, isTrue);
    });

    test('Accounts staff cannot approve academic actions', () async {
      final action = _makeAction(
        id: 'act-acad',
        type: 'attendance_override',
        title: 'Attendance fix',
        description: 'Mark present',
        requestedBy: 'Trainer Rohan',
        requestedAt: testTime,
        status: 'pending',
      );
      await fakeRepo.createAction(action);

      expect(
        () => service.approveAction(accounts, 'act-acad'),
        throwsA(isA<ApprovalValidationException>()),
      );
    });

    test('Accounts staff can approve fee concession requests', () async {
      final action = _makeAction(
        id: 'act-fee',
        type: 'fee_concession',
        title: 'Concession',
        description: 'Concession 1000',
        requestedBy: 'Counselor',
        requestedAt: testTime,
        status: 'pending',
      );
      await fakeRepo.createAction(action);

      final result = await service.approveAction(accounts, 'act-fee');
      expect(result.status, 'approved');
      expect(result.approvedBy, contains('Vikram Joshi'));
    });

    test('Mandatory rejection reason is strictly enforced', () async {
      final action = _makeAction(
        id: 'act-rej',
        type: 'fee_concession',
        title: 'Concession',
        description: 'Concession 1000',
        requestedBy: 'Counselor',
        requestedAt: testTime,
        status: 'pending',
      );
      await fakeRepo.createAction(action);

      // Empty string
      expect(
        () => service.rejectAction(owner, 'act-rej', reason: ''),
        throwsA(isA<ApprovalValidationException>().having(
          (e) => e.message,
          'message',
          contains('rejection reason is mandatory'),
        )),
      );

      // Whitespace only
      expect(
        () => service.rejectAction(owner, 'act-rej', reason: '   '),
        throwsA(isA<ApprovalValidationException>()),
      );

      // Valid reason succeeds
      final rejected = await service.rejectAction(
        owner,
        'act-rej',
        reason: 'Budget limit exceeded for this quarter',
      );
      expect(rejected.status, 'rejected');
      expect(rejected.rejectionReason, 'Budget limit exceeded for this quarter');
      expect(rejected.rejectedBy, contains('Aarav Mehta'));
    });

    test('Re-deciding an already approved or rejected action is rejected', () async {
      final action = _makeAction(
        id: 'act-double',
        type: 'fee_concession',
        title: 'Concession',
        description: 'Concession 1000',
        requestedBy: 'Counselor',
        requestedAt: testTime,
        status: 'pending',
      );
      await fakeRepo.createAction(action);

      await service.approveAction(owner, 'act-double');

      // Attempting to approve again
      expect(
        () => service.approveAction(owner, 'act-double'),
        throwsA(isA<ApprovalValidationException>().having(
          (e) => e.message,
          'message',
          contains('already been decided'),
        )),
      );

      // Attempting to reject already approved
      expect(
        () => service.rejectAction(owner, 'act-double', reason: 'Changed mind'),
        throwsA(isA<ApprovalValidationException>().having(
          (e) => e.message,
          'message',
          contains('already been decided'),
        )),
      );
    });

    test('createRequest validates non-empty title and creates pending record', () async {
      expect(
        () => service.createRequest(
          owner,
          _makeAction(
            id: 'err-1',
            type: 'batch_transfer',
            title: '   ',
            description: 'desc',
            requestedBy: 'Counselor',
            requestedAt: testTime,
            status: 'pending',
          ),
        ),
        throwsA(isA<ApprovalValidationException>()),
      );

      final created = await service.createRequest(
        owner,
        _makeAction(
          id: 'valid-1',
          type: 'batch_transfer',
          title: 'Valid Request',
          description: 'Valid Desc',
          requestedBy: 'Counselor',
          requestedAt: testTime,
          status: 'pending',
        ),
      );
      expect(created.id, 'valid-1');
      expect(created.status, 'pending');
    });
  });

  group('ApprovalSeedService Deterministic Seeding', () {
    test('Seeds 5 sample records and avoids duplicates on subsequent run', () async {
      final fakeRepo = _FakeApprovalRepository();
      final seedService = ApprovalSeedService(approvalRepository: fakeRepo);

      final result1 = await seedService.loadSampleData();
      expect(result1.actionsCreated, 5);
      expect(result1.actionsSkipped, 0);
      expect(result1.alreadyHadData, isFalse);
      expect(fakeRepo.storage.length, 5);

      final result2 = await seedService.loadSampleData();
      expect(result2.actionsCreated, 0);
      expect(result2.actionsSkipped, 5);
      expect(result2.alreadyHadData, isTrue);
      expect(fakeRepo.storage.length, 5);
    });
  });
}
