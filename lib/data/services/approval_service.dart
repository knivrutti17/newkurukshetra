import '../models/app_user.dart';
import '../models/approval_action.dart';
import '../repositories/approval_repository.dart';

class ApprovalValidationException implements Exception {
  const ApprovalValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Coordinates workflow for administrative and academic approvals.
class ApprovalService {
  ApprovalService({ApprovalRepository? repository})
    : _repository = repository ?? FirestoreApprovalRepository();

  final ApprovalRepository _repository;

  ApprovalRepository get repository => _repository;

  bool canManage(AppUser user) =>
      user.role == AppRole.owner || user.role == AppRole.accounts;

  bool canReview(AppUser user, ApprovalAction action) {
    if (user.role == AppRole.owner) return true;
    if (user.role == AppRole.accounts) {
      return action.type == 'fee_concession' || action.type == 'refund_request';
    }
    return false;
  }

  Stream<List<ApprovalAction>> watchForUser(
    AppUser user, {
    String? status,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _repository.watchActions(
      scope: ApprovalAccessScope(
        instituteId: user.instituteId,
        status: status,
        type: type,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  Future<List<ApprovalAction>> getForUser(
    AppUser user, {
    String? status,
    String? type,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _repository.getActions(
      scope: ApprovalAccessScope(
        instituteId: user.instituteId,
        status: status,
        type: type,
        startDate: startDate,
        endDate: endDate,
      ),
    );
  }

  Future<ApprovalAction?> getActionById(String id) =>
      _repository.getActionById(id);

  Future<ApprovalAction> approveAction(AppUser user, String actionId) async {
    final existing = await _repository.getActionById(actionId);
    if (existing == null) {
      throw const ApprovalValidationException('Action record not found.');
    }

    if (!canReview(user, existing)) {
      throw ApprovalValidationException(
        'Your role (${user.role.label}) is not authorized to approve ${existing.typeLabel} requests.',
      );
    }

    if (!existing.isPending) {
      throw ApprovalValidationException(
        'This action has already been decided (${existing.statusLabel}).',
      );
    }

    final reviewerStr = '${user.name} (${user.role.label})';
    return _repository.updateDecision(
      actionId,
      status: 'approved',
      reviewer: reviewerStr,
      decisionAt: DateTime.now(),
    );
  }

  Future<ApprovalAction> rejectAction(
    AppUser user,
    String actionId, {
    required String reason,
  }) async {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const ApprovalValidationException(
        'A rejection reason is mandatory to reject this request.',
      );
    }

    final existing = await _repository.getActionById(actionId);
    if (existing == null) {
      throw const ApprovalValidationException('Action record not found.');
    }

    if (!canReview(user, existing)) {
      throw ApprovalValidationException(
        'Your role (${user.role.label}) is not authorized to reject ${existing.typeLabel} requests.',
      );
    }

    if (!existing.isPending) {
      throw ApprovalValidationException(
        'This action has already been decided (${existing.statusLabel}).',
      );
    }

    final reviewerStr = '${user.name} (${user.role.label})';
    return _repository.updateDecision(
      actionId,
      status: 'rejected',
      reviewer: reviewerStr,
      rejectionReason: trimmedReason,
      decisionAt: DateTime.now(),
    );
  }

  Future<ApprovalAction> createRequest(
    AppUser user,
    ApprovalAction action,
  ) async {
    if (action.title.trim().isEmpty) {
      throw const ApprovalValidationException('Action title cannot be empty.');
    }
    return _repository.createAction(action);
  }
}
