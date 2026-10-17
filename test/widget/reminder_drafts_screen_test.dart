import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/app_user.dart';
import 'package:kurukshetra/data/models/reminder_draft.dart';
import 'package:kurukshetra/data/repositories/reminder_draft_repository.dart';
import 'package:kurukshetra/data/services/reminder_draft_service.dart';
import 'package:kurukshetra/features/reminders/screens/reminder_drafts_screen.dart';

class _FakeReminderDraftRepository implements ReminderDraftRepository {
  _FakeReminderDraftRepository(List<ReminderDraft> initial) {
    _drafts.addAll(initial);
    _controller = StreamController<List<ReminderDraft>>.broadcast(
      onListen: () => _controller.add(List.unmodifiable(_drafts)),
    );
  }

  final List<ReminderDraft> _drafts = [];
  late final StreamController<List<ReminderDraft>> _controller;

  void _notify() {
    _controller.add(List.unmodifiable(_drafts));
  }

  @override
  Stream<List<ReminderDraft>> watchDrafts({String instituteId = 'demo-institute'}) {
    return _controller.stream;
  }

  @override
  Future<List<ReminderDraft>> getDrafts({String instituteId = 'demo-institute'}) async {
    return List.unmodifiable(_drafts);
  }

  @override
  Future<ReminderDraft?> getDraftForInstallment({
    required String instituteId,
    required String feeInstallmentId,
  }) async {
    try {
      return _drafts.firstWhere((d) => d.feeInstallmentId == feeInstallmentId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ReminderDraft> saveDraft(ReminderDraft draft) async {
    final idx = _drafts.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      _drafts[idx] = draft;
    } else {
      _drafts.add(draft);
    }
    _notify();
    return draft;
  }

  @override
  Future<ReminderDraft> updateDraft(ReminderDraft draft) async {
    final idx = _drafts.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      _drafts[idx] = draft;
    }
    _notify();
    return draft;
  }

  @override
  Future<ReminderDraft> approveDraft(ReminderDraft draft, String approvedBy) async {
    final updated = draft.copyWith(
      status: ReminderDraftStatus.approved,
      approvedBy: approvedBy,
      approvedAt: DateTime.now(),
    );
    final idx = _drafts.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      _drafts[idx] = updated;
    }
    _notify();
    return updated;
  }

  @override
  Future<ReminderDraft> cancelDraft(ReminderDraft draft, String cancelledBy) async {
    final updated = draft.copyWith(
      status: ReminderDraftStatus.cancelled,
      cancelledBy: cancelledBy,
      cancelledAt: DateTime.now(),
    );
    final idx = _drafts.indexWhere((d) => d.id == draft.id);
    if (idx >= 0) {
      _drafts[idx] = updated;
    }
    _notify();
    return updated;
  }
}

void main() {
  const accountsUser = AppUser(
    id: 'accounts-1',
    name: 'Neha Gupta',
    email: 'accounts@institute.test',
    role: AppRole.accounts,
    instituteId: 'demo-institute',
  );

  const trainerUser = AppUser(
    id: 'trainer-1',
    name: 'Rohan Kulkarni',
    email: 'trainer@institute.test',
    role: AppRole.trainer,
    instituteId: 'demo-institute',
  );

  final today = DateTime.now();

  final draft1 = ReminderDraft(
    id: 'rem-1',
    instituteId: 'demo-institute',
    studentId: 'STU-001',
    studentName: 'Aarav Sharma',
    feeInstallmentId: 'INST-101',
    outstandingAmountAtDraft: 5000.0,
    dueDateAtDraft: today.subtract(const Duration(days: 3)),
    message: 'Hello Aarav Sharma, your instalment is overdue.',
    status: ReminderDraftStatus.draft,
    createdBy: 'accounts-1',
    createdAt: today.subtract(const Duration(days: 2)),
    updatedAt: today.subtract(const Duration(days: 2)),
  );

  final draft2 = ReminderDraft(
    id: 'rem-2',
    instituteId: 'demo-institute',
    studentId: 'STU-002',
    studentName: 'Priya Patel',
    feeInstallmentId: 'INST-102',
    outstandingAmountAtDraft: 12000.0,
    dueDateAtDraft: today.add(const Duration(days: 5)),
    message: 'Hello Priya Patel, instalment due soon.',
    status: ReminderDraftStatus.approved,
    createdBy: 'accounts-1',
    createdAt: today.subtract(const Duration(days: 5)),
    updatedAt: today.subtract(const Duration(days: 1)),
  );

  group('ReminderDraftsScreen Widget Tests', () {
    testWidgets('non-financial roles see restricted view', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDraftsScreen(
              user: trainerUser,
              service: ReminderDraftService(
                repository: _FakeReminderDraftRepository([]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Financial information is restricted'), findsOneWidget);
      expect(
        find.text('Only Owner/Admin and Accounts Staff can access reminder drafts.'),
        findsOneWidget,
      );
    });

    testWidgets('accounts staff sees summary cards and desktop data table', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeRepo = _FakeReminderDraftRepository([draft1, draft2]);
      final service = ReminderDraftService(repository: fakeRepo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDraftsScreen(
              user: accountsUser,
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header and summary cards
      expect(find.text('Reminder Drafts'), findsOneWidget);
      expect(find.text('Total drafts'), findsOneWidget);
      expect(find.text('Awaiting review'), findsOneWidget);
      expect(find.text('Approved'), findsNWidgets(2)); // Summary card + table chip
      expect(find.text('Cancelled'), findsOneWidget);

      // Value counts: Total: 2, Awaiting review: 1, Approved: 1, Cancelled: 0
      expect(find.text('2'), findsOneWidget);

      // Desktop table columns
      expect(find.text('STUDENT'), findsOneWidget);
      expect(find.text('INSTALMENT'), findsOneWidget);
      expect(find.text('OUTSTANDING'), findsOneWidget);
      expect(find.text('DUE DATE'), findsOneWidget);
      expect(find.text('STATUS'), findsOneWidget);
      expect(find.text('ACTIONS'), findsOneWidget);

      // Student rows
      expect(find.text('Aarav Sharma'), findsOneWidget);
      expect(find.text('STU-001'), findsOneWidget);
      expect(find.text('INST-101'), findsOneWidget);
      expect(find.text('₹5000.00'), findsOneWidget);

      expect(find.text('Priya Patel'), findsOneWidget);
      expect(find.text('STU-002'), findsOneWidget);
      expect(find.text('INST-102'), findsOneWidget);
      expect(find.text('₹12000.00'), findsOneWidget);

      // Action buttons: Aarav is draft so has Approve button
      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
      // Both have View / Edit
      expect(find.widgetWithText(OutlinedButton, 'View / Edit'), findsNWidgets(2));
    });

    testWidgets('cancelling a draft updates its status', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeRepo = _FakeReminderDraftRepository([draft1]);
      final service = ReminderDraftService(repository: fakeRepo);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReminderDraftsScreen(
              user: accountsUser,
              service: service,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Cancel button for draft1
      final cancelButton = find.widgetWithText(TextButton, 'Cancel');
      await tester.ensureVisible(cancelButton);
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();

      // Confirmation dialog
      expect(find.text('Cancel reminder draft?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel draft'));
      await tester.pumpAndSettle();

      expect(find.text('Reminder draft cancelled.'), findsOneWidget);
      expect(fakeRepo._drafts.first.status, ReminderDraftStatus.cancelled);
    });
  });
}
