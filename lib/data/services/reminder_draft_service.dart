import 'package:intl/intl.dart';

import '../models/app_user.dart';
import '../models/fee_installment.dart';
import '../models/reminder_draft.dart';
import '../repositories/reminder_draft_repository.dart';

class ReminderAccessException implements Exception {
  const ReminderAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReminderDraftOverview {
  const ReminderDraftOverview({
    required this.total,
    required this.awaitingReview,
    required this.approved,
    required this.cancelled,
  });

  final int total;
  final int awaitingReview;
  final int approved;
  final int cancelled;
}

class ReminderDraftService {
  ReminderDraftService({ReminderDraftRepository? repository})
    : _repository = repository ?? ReminderDraftRepository();

  final ReminderDraftRepository _repository;

  bool canView(AppUser user) =>
      user.role == AppRole.owner || user.role == AppRole.accounts;

  bool canManage(AppUser user) => canView(user);

  Stream<List<ReminderDraft>> watchDraftsForUser(AppUser user) {
    if (!canView(user)) {
      return Stream.value(const <ReminderDraft>[]);
    }
    return _repository.watchDrafts(instituteId: user.instituteId);
  }

  Future<List<ReminderDraft>> getDraftsForUser(AppUser user) {
    if (!canView(user)) {
      return Future.value(const <ReminderDraft>[]);
    }
    return _repository.getDrafts(instituteId: user.instituteId);
  }

  Future<ReminderDraft> saveDraftForUser(
    AppUser user,
    ReminderDraft draft,
  ) async {
    _ensureCanManage(user);
    final record = draft.copyWith(
      id: draft.id.isEmpty
          ? ReminderDraft.documentId(
              instituteId: draft.instituteId,
              feeInstallmentId: draft.feeInstallmentId,
            )
          : draft.id,
      updatedAt: DateTime.now(),
    );
    return _repository.saveDraft(record);
  }

  Future<ReminderDraft> updateDraftForUser(
    AppUser user,
    ReminderDraft draft,
  ) async {
    _ensureCanManage(user);
    return _repository.updateDraft(draft.copyWith(updatedAt: DateTime.now()));
  }

  Future<ReminderDraft> approveDraftForUser(
    AppUser user,
    ReminderDraft draft,
  ) async {
    _ensureCanManage(user);
    return _repository.approveDraft(draft, user.id);
  }

  Future<ReminderDraft> cancelDraftForUser(
    AppUser user,
    ReminderDraft draft,
  ) async {
    _ensureCanManage(user);
    return _repository.cancelDraft(draft, user.id);
  }

  ReminderDraftOverview calculateOverview(List<ReminderDraft> drafts) {
    return ReminderDraftOverview(
      total: drafts.length,
      awaitingReview: drafts
          .where((draft) => draft.status == ReminderDraftStatus.draft)
          .length,
      approved: drafts
          .where((draft) => draft.status == ReminderDraftStatus.approved)
          .length,
      cancelled: drafts
          .where((draft) => draft.status == ReminderDraftStatus.cancelled)
          .length,
    );
  }

  ReminderDraft draftFromInstallment({
    required AppUser user,
    required FeeInstallment installment,
    required String messageTemplate,
    String? customMessage,
  }) {
    final draft = ReminderDraft.buildFromInstallment(
      id: ReminderDraft.documentId(
        instituteId: installment.instituteId,
        feeInstallmentId: installment.id,
      ),
      instituteId: installment.instituteId,
      studentId: installment.studentId,
      studentName: installment.studentName,
      feeInstallmentId: installment.id,
      createdBy: user.id,
      installment: installment,
      messageTemplate: messageTemplate,
    );
    if (customMessage != null && customMessage.trim().isNotEmpty) {
      return draft.copyWith(message: customMessage.trim());
    }
    return draft;
  }

  String buildTemplateMessage({
    required String studentName,
    required double outstandingAmount,
    required DateTime dueDate,
  }) {
    final formattedAmount = NumberFormat.currency(
      symbol: '₹',
      decimalDigits: 2,
      locale: 'en_IN',
    ).format(outstandingAmount);
    final formattedDate = DateFormat('dd/MM/yyyy').format(dueDate);
    return 'Hello $studentName, our records show an outstanding instalment of $formattedAmount for your course, due on $formattedDate. If you have already paid, please contact the accounts team so we can verify your payment. Please contact us if you need assistance.';
  }

  void _ensureCanManage(AppUser user) {
    if (!canManage(user)) {
      throw const ReminderAccessException(
        'Your role does not have permission to manage reminder drafts.',
      );
    }
  }
}
