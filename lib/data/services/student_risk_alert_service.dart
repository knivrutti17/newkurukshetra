import '../models/app_user.dart';
import '../models/student_alert.dart';
import '../repositories/risk_scan_data_repository.dart';
import '../repositories/student_alert_repository.dart';
import 'risk_rule_engine.dart';

class RiskAlertAccessException implements Exception {
  const RiskAlertAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RiskScanResult {
  const RiskScanResult({
    required this.created,
    required this.updated,
    required this.preservedClosed,
    required this.errors,
    required this.completedAt,
  });

  final int created;
  final int updated;
  final int preservedClosed;
  final int errors;
  final DateTime completedAt;
}

/// Authorizes the demo UI and coordinates a deliberate owner-triggered scan.
/// Firestore rules and trusted user claims are still required for production
/// enforcement; this service never treats the local AppRole as a trust boundary.
class StudentRiskAlertService {
  StudentRiskAlertService({
    StudentAlertRepository? alertRepository,
    RiskScanDataRepository? scanDataRepository,
    RiskRuleEngine? ruleEngine,
    this.instituteId = 'demo-institute',
  }) : _alertRepository = alertRepository ?? FirestoreStudentAlertRepository(),
       _scanDataRepository =
           scanDataRepository ?? FirestoreRiskScanDataRepository(),
       _ruleEngine = ruleEngine ?? RiskRuleEngine();

  final StudentAlertRepository _alertRepository;
  final RiskScanDataRepository _scanDataRepository;
  final RiskRuleEngine _ruleEngine;
  final String instituteId;

  bool canRunScan(AppUser user) => user.role == AppRole.owner;

  bool canAssign(AppUser user) => user.role == AppRole.owner;

  bool canClose(AppUser user) => user.role == AppRole.owner;

  bool canView(AppUser user, StudentAlert alert) => switch (user.role) {
    AppRole.owner => true,
    AppRole.counselor =>
      alert.alertType.isAcademic && alert.counselorId == user.id,
    AppRole.trainer => alert.alertType.isAcademic && alert.trainerId == user.id,
    AppRole.accounts => alert.alertType == StudentAlertType.overdueFees,
  };

  bool canUpdate(AppUser user, StudentAlert alert) => canView(user, alert);

  Stream<List<StudentAlert>> watchForUser(AppUser user) => _alertRepository
      .watchAlerts(_scopeFor(user))
      .map((alerts) => alerts.where((alert) => canView(user, alert)).toList());

  Future<DateTime?> getLastSuccessfulScan({String? forInstituteId}) =>
      _alertRepository.getLastSuccessfulScan(forInstituteId ?? instituteId);

  Future<RiskScanResult> runScan(AppUser user, {DateTime? now}) async {
    if (!canRunScan(user)) {
      throw const RiskAlertAccessException(
        'Only the Owner can run an institute-wide risk scan.',
      );
    }
    final scanInstituteId = _instituteIdFor(user);
    final data = await _scanDataRepository.loadInstituteData(scanInstituteId);
    final completedAt = now ?? DateTime.now();
    final candidates = _ruleEngine.evaluate(
      students: data.students,
      attendance: data.attendance,
      installments: data.installments,
      payments: data.payments,
      asOf: completedAt,
      includeFinancialRules: true,
    );
    final write = await _alertRepository.synchronizeScan(
      instituteId: scanInstituteId,
      candidates: candidates,
      now: completedAt,
    );
    // This is intentionally written last: failures in source reads or alert
    // writes never claim a successful completed scan.
    await _alertRepository.recordSuccessfulScan(
      instituteId: scanInstituteId,
      completedAt: completedAt,
      completedBy: user.id,
    );
    return RiskScanResult(
      created: write.created,
      updated: write.updated,
      preservedClosed: write.preservedClosed,
      errors: 0,
      completedAt: completedAt,
    );
  }

  Future<StudentAlert> updateFollowUp({
    required AppUser user,
    required StudentAlert alert,
    StudentAlertStatus? status,
    String? note,
    String? assignedTo,
    String? closureReason,
    DateTime? now,
  }) async {
    if (!canUpdate(user, alert)) {
      throw const RiskAlertAccessException(
        'Your role is not authorized to update this alert.',
      );
    }
    final nextStatus = status ?? alert.status;
    _validateUpdate(
      user: user,
      current: alert.status,
      next: nextStatus,
      assignedTo: assignedTo,
      closureReason: closureReason,
    );
    return _alertRepository.updateFollowUp(
      alertId: alert.id,
      now: now ?? DateTime.now(),
      update: AlertFollowUpUpdate(
        actorId: user.id,
        actorName: user.name,
        status: status,
        note: note,
        assignedTo: assignedTo,
        closureReason: closureReason,
      ),
    );
  }

  AlertAccessScope _scopeFor(AppUser user) => switch (user.role) {
    AppRole.owner => AlertAccessScope(instituteId: _instituteIdFor(user)),
    AppRole.counselor => AlertAccessScope(
      instituteId: _instituteIdFor(user),
      counselorId: user.id,
      academicOnly: true,
    ),
    AppRole.trainer => AlertAccessScope(
      instituteId: _instituteIdFor(user),
      trainerId: user.id,
      academicOnly: true,
    ),
    AppRole.accounts => AlertAccessScope(
      instituteId: _instituteIdFor(user),
      financialOnly: true,
    ),
  };

  String _instituteIdFor(AppUser user) =>
      user.instituteId == 'demo-institute' ? instituteId : user.instituteId;

  void _validateUpdate({
    required AppUser user,
    required StudentAlertStatus current,
    required StudentAlertStatus next,
    required String? assignedTo,
    required String? closureReason,
  }) {
    if (assignedTo != null && !canAssign(user)) {
      throw const RiskAlertAccessException(
        'Only the Owner can assign follow-up owners.',
      );
    }
    if (next.isClosed && !canClose(user)) {
      throw const RiskAlertAccessException(
        'Only the Owner can resolve or dismiss an alert.',
      );
    }
    if (current.isClosed && !next.isClosed && !canClose(user)) {
      throw const RiskAlertAccessException(
        'Only the Owner can reopen an alert.',
      );
    }
    if (current.isClosed && !canClose(user)) {
      throw const RiskAlertAccessException(
        'Closed alerts can only be updated by the Owner.',
      );
    }
    if (next.isClosed && (closureReason?.trim().isEmpty ?? true)) {
      throw const RiskAlertAccessException(
        'Add a reason before resolving or dismissing an alert.',
      );
    }
    if (current.isClosed &&
        next != StudentAlertStatus.newAlert &&
        next != current) {
      throw const RiskAlertAccessException(
        'Closed alerts can only be reopened as New.',
      );
    }
    if (!canClose(user) &&
        next != current &&
        next != StudentAlertStatus.inReview &&
        next != StudentAlertStatus.followUp) {
      throw const RiskAlertAccessException(
        'You can move an assigned alert to In review or Follow-up pending only.',
      );
    }
  }
}
