import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/approval_action.dart';
import 'package:kurukshetra/data/repositories/approval_repository.dart';
import 'package:kurukshetra/data/services/approval_seed_service.dart';
import 'package:kurukshetra/data/services/approval_service.dart';
import 'package:kurukshetra/features/approvals/screens/approvals_screen.dart';

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
    return _controller.stream;
  }

  void pushInitial() {
    _controller.add(storage.values.toList());
  }

  @override
  Future<List<ApprovalAction>> getActions({
    ApprovalAccessScope scope = const ApprovalAccessScope(),
  }) async {
    return storage.values.toList();
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
    final existing = storage[id]!;
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
  Future<bool> isActionsCollectionEmpty() async => storage.isEmpty;

  @override
  Future<int> countExistingSampleActions(List<ApprovalAction> actions) async {
    return actions.where((a) => storage.containsKey(a.id)).length;
  }

  @override
  Future<void> createMissingSampleActions(List<ApprovalAction> actions) async {
    for (final a in actions) {
      storage[a.id] = a;
    }
    _notify();
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  const owner = AppUser(
    id: 'owner-1',
    name: 'Aarav Mehta',
    email: 'owner@demo.com',
    role: AppRole.owner,
  );

  const accounts = AppUser(
    id: 'accounts-1',
    name: 'Vikram Joshi',
    email: 'accounts@demo.com',
    role: AppRole.accounts,
  );

  const counselor = AppUser(
    id: 'counselor-1',
    name: 'Priya Sharma',
    email: 'counselor@demo.com',
    role: AppRole.counselor,
  );

  final now = DateTime(2026, 3, 1, 10, 0);

  ApprovalAction makeAction({
    required String id,
    required String type,
    required String title,
    String description = 'Test request justification',
    String requestedBy = 'Staff Member',
    String status = 'pending',
    Map<String, dynamic> payload = const {},
  }) {
    return ApprovalAction(
      id: id,
      instituteId: 'demo-institute',
      type: type,
      title: title,
      description: description,
      payload: payload,
      requestedBy: requestedBy,
      requestedAt: now,
      status: status,
      updatedAt: now,
    );
  }

  group('ApprovalsScreen Widget Tests', () {
    testWidgets('Owner sees KPI cards, table rows, and approves an action',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _FakeApprovalRepository();
      addTearDown(repo.dispose);

      final act = makeAction(
        id: 'act-concession',
        type: 'fee_concession',
        title: 'Fee Concession for Aarav',
        description: 'Merit-based concession of ₹5,000',
        requestedBy: 'Counselor Priya',
        payload: {'concessionAmount': 5000, 'student': 'Aarav'},
      );
      repo.storage[act.id] = act;

      final service = ApprovalService(repository: repo);
      final seedService = ApprovalSeedService(approvalRepository: repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalsScreen(
              user: owner,
              approvalService: service,
              seedService: seedService,
            ),
          ),
        ),
      );

      repo.pushInitial();
      await tester.pumpAndSettle();

      // Verify KPI overview cards
      expect(find.text('Pending Review'), findsWidgets);
      expect(find.text('Approved Actions'), findsOneWidget);
      expect(find.text('Rejected Actions'), findsOneWidget);
      expect(find.text('Total Requests'), findsOneWidget);

      // Verify row content
      expect(find.text('Fee Concession for Aarav'), findsOneWidget);
      expect(find.text('Counselor Priya'), findsOneWidget);

      // Find and tap the Decide button
      final decideButton = find.widgetWithText(ElevatedButton, 'Decide');
      expect(decideButton, findsOneWidget);
      await tester.ensureVisible(decideButton);
      await tester.pumpAndSettle();
      await tester.tap(decideButton);
      await tester.pumpAndSettle();

      // Detail dialog is visible
      expect(find.text('Merit-based concession of ₹5,000'), findsOneWidget);
      expect(find.text('concessionAmount:'), findsOneWidget);
      expect(find.text('Approve Action'), findsOneWidget);
      expect(find.text('Reject Action'), findsOneWidget);

      // Tap Approve Action
      await tester.tap(find.text('Approve Action'));
      await tester.pumpAndSettle();

      // Check that status updated in repo
      expect(repo.storage['act-concession']?.isApproved, isTrue);
      expect(repo.storage['act-concession']?.approvedBy, contains('Aarav Mehta'));
    });

    testWidgets('Owner rejects an action with mandatory rejection reason',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _FakeApprovalRepository();
      addTearDown(repo.dispose);

      final act = makeAction(
        id: 'act-refund',
        type: 'refund_request',
        title: 'Fee Refund for Rohan',
        description: 'Course dropout refund request',
        requestedBy: 'Counselor Priya',
      );
      repo.storage[act.id] = act;

      final service = ApprovalService(repository: repo);
      final seedService = ApprovalSeedService(approvalRepository: repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalsScreen(
              user: owner,
              approvalService: service,
              seedService: seedService,
            ),
          ),
        ),
      );

      repo.pushInitial();
      await tester.pumpAndSettle();

      // Open detail dialog
      final decideButton = find.widgetWithText(ElevatedButton, 'Decide');
      await tester.ensureVisible(decideButton);
      await tester.pumpAndSettle();
      await tester.tap(decideButton);
      await tester.pumpAndSettle();

      // Tap Reject Action
      await tester.tap(find.text('Reject Action'));
      await tester.pumpAndSettle();

      // Prompt dialog is visible
      expect(find.text('Reject Action Request'), findsOneWidget);
      expect(find.text('Confirm Rejection'), findsOneWidget);

      // Attempt to submit empty reason
      await tester.tap(find.text('Confirm Rejection'));
      await tester.pumpAndSettle();

      expect(find.text('Rejection reason is mandatory.'), findsOneWidget);

      // Enter valid reason
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Rejection Reason *'),
        'Refund window expired under institute policy',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Rejection'));
      await tester.pumpAndSettle();

      expect(repo.storage['act-refund']?.isRejected, isTrue);
      expect(
        repo.storage['act-refund']?.rejectionReason,
        'Refund window expired under institute policy',
      );
    });

    testWidgets('Accounts staff can decide financial actions but only view academic actions',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _FakeApprovalRepository();
      addTearDown(repo.dispose);

      final feeAct = makeAction(
        id: 'act-fee',
        type: 'fee_concession',
        title: 'Concession Request',
      );
      final transferAct = makeAction(
        id: 'act-transfer',
        type: 'batch_transfer',
        title: 'Batch Transfer Request',
      );

      repo.storage[feeAct.id] = feeAct;
      repo.storage[transferAct.id] = transferAct;

      final service = ApprovalService(repository: repo);
      final seedService = ApprovalSeedService(approvalRepository: repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalsScreen(
              user: accounts,
              approvalService: service,
              seedService: seedService,
            ),
          ),
        ),
      );

      repo.pushInitial();
      await tester.pumpAndSettle();

      // For fee action: Decide button
      expect(find.widgetWithText(ElevatedButton, 'Decide'), findsOneWidget);
      // For transfer action: Details button (read-only for Accounts)
      expect(find.widgetWithText(ElevatedButton, 'Details'), findsOneWidget);
    });

    testWidgets('Counselor has view-only access and cannot see seed sample button',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final repo = _FakeApprovalRepository();
      addTearDown(repo.dispose);

      final service = ApprovalService(repository: repo);
      final seedService = ApprovalSeedService(approvalRepository: repo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalsScreen(
              user: counselor,
              approvalService: service,
              seedService: seedService,
            ),
          ),
        ),
      );

      repo.pushInitial();
      await tester.pumpAndSettle();

      // Seed button is not shown for Counselor
      expect(find.text('Seed Sample Actions'), findsNothing);
    });
  });
}
