import '../models/attendance_record.dart';
import '../models/fee_installment.dart';
import '../models/payment.dart';
import '../models/student.dart';
import '../models/student_alert.dart';

/// Settings are deliberately small and deterministic so every alert can show
/// the exact rule that produced it. They can later be supplied from institute
/// configuration without changing the evaluator.
class RiskRuleSettings {
  const RiskRuleSettings({
    this.attendanceThreshold = 75,
    this.minimumAttendanceSessions = 5,
    this.recentAbsenceDays = 30,
    this.repeatedAbsenceCount = 3,
  });

  final double attendanceThreshold;
  final int minimumAttendanceSessions;
  final int recentAbsenceDays;
  final int repeatedAbsenceCount;
}

class ProposedStudentAlert {
  const ProposedStudentAlert({
    required this.student,
    required this.type,
    required this.severity,
    required this.title,
    required this.reason,
    required this.evidence,
  });

  final Student student;
  final StudentAlertType type;
  final StudentAlertSeverity severity;
  final String title;
  final String reason;
  final Map<String, dynamic> evidence;

  String get id => StudentAlert.deterministicId(
    instituteId: student.instituteId,
    studentId: student.id,
    type: type,
  );
}

/// Pure, explainable risk-rule evaluation over already-authorized records.
/// This class never reads Firestore and is safe to unit test.
class RiskRuleEngine {
  RiskRuleEngine({this.settings = const RiskRuleSettings()});

  final RiskRuleSettings settings;

  List<ProposedStudentAlert> evaluate({
    required Iterable<Student> students,
    required Iterable<AttendanceRecord> attendance,
    required Iterable<FeeInstallment> installments,
    required Iterable<Payment> payments,
    DateTime? asOf,
    bool includeFinancialRules = true,
  }) {
    final today = _dateOnly(asOf ?? DateTime.now());
    final recordsByStudent = <String, List<AttendanceRecord>>{};
    for (final record in attendance) {
      recordsByStudent.putIfAbsent(record.studentId, () => []).add(record);
    }

    final paymentsByInstallment = <String, List<Payment>>{};
    for (final payment in payments) {
      paymentsByInstallment
          .putIfAbsent(payment.feeInstallmentId, () => [])
          .add(payment);
    }
    final installmentsByStudent = <String, List<FeeInstallment>>{};
    for (final installment in installments) {
      installmentsByStudent
          .putIfAbsent(installment.studentId, () => [])
          .add(installment);
    }

    final results = <ProposedStudentAlert>[];
    for (final student in students.where((item) => item.status == 'active')) {
      final studentRecords = recordsByStudent[student.id] ?? const [];
      final attendanceAlerts = _attendanceAlerts(
        student,
        studentRecords,
        today,
      );
      results.addAll(attendanceAlerts);

      final overdue = includeFinancialRules
          ? _overdueInstallments(
              installmentsByStudent[student.id] ?? const [],
              paymentsByInstallment,
              today,
            )
          : const <_OverdueInstallment>[];
      if (overdue.isNotEmpty) {
        final outstandingPaise = overdue.fold<int>(
          0,
          (total, item) => total + item.outstandingPaise,
        );
        final oldestDue = overdue
            .map((item) => item.installment.dueDate)
            .reduce((left, right) => left.isBefore(right) ? left : right);
        results.add(
          ProposedStudentAlert(
            student: student,
            type: StudentAlertType.overdueFees,
            severity: overdue.length > 1 || outstandingPaise >= 200000
                ? StudentAlertSeverity.high
                : StudentAlertSeverity.medium,
            title: 'Overdue instalment${overdue.length == 1 ? '' : 's'}',
            reason:
                '₹${(outstandingPaise / 100).toStringAsFixed(2)} is outstanding '
                'across ${overdue.length} overdue instalment${overdue.length == 1 ? '' : 's'}; '
                'the oldest was due ${_dateLabel(oldestDue)}.',
            evidence: <String, dynamic>{
              'overdueInstalmentCount': overdue.length,
              'outstandingBalance': outstandingPaise / 100,
              'oldestDueDate': _dateOnly(oldestDue),
              'instalments': overdue
                  .map(
                    (item) => <String, dynamic>{
                      'id': item.installment.id,
                      'dueDate': _dateOnly(item.installment.dueDate),
                      'amountDue': item.installment.amountDue,
                      'paidAmount': item.paidAmount,
                      'outstandingBalance': item.outstandingPaise / 100,
                    },
                  )
                  .toList(),
            },
          ),
        );
      }

      // A combined alert is intentionally only produced in the owner scan,
      // and role visibility later restricts it to the owner.
      if (attendanceAlerts.isNotEmpty && overdue.isNotEmpty) {
        results.add(
          ProposedStudentAlert(
            student: student,
            type: StudentAlertType.combinedRisk,
            severity: StudentAlertSeverity.high,
            title: 'Attendance and fee follow-up needed',
            reason:
                '${attendanceAlerts.length} attendance concern${attendanceAlerts.length == 1 ? '' : 's'} '
                'and ₹${(overdue.fold<int>(0, (sum, item) => sum + item.outstandingPaise) / 100).toStringAsFixed(2)} '
                'in overdue instalments require coordinated review.',
            evidence: <String, dynamic>{
              'attendanceAlertTypes': attendanceAlerts
                  .map((item) => item.type.value)
                  .toList(),
              'overdueInstalmentCount': overdue.length,
              'outstandingBalance':
                  overdue.fold<int>(
                    0,
                    (sum, item) => sum + item.outstandingPaise,
                  ) /
                  100,
            },
          ),
        );
      }
    }
    return results;
  }

  List<ProposedStudentAlert> _attendanceAlerts(
    Student student,
    List<AttendanceRecord> records,
    DateTime today,
  ) {
    // Every AttendanceRecord status in the established model is recognized.
    // Missing records never enter this list and therefore never become absences.
    final recordedSessions = records.length;
    final presentSessions = records
        .where((item) => item.status == AttendanceStatus.present)
        .length;
    final percentage = recordedSessions == 0
        ? 0.0
        : presentSessions / recordedSessions * 100;
    final results = <ProposedStudentAlert>[];

    if (recordedSessions >= settings.minimumAttendanceSessions &&
        percentage < settings.attendanceThreshold) {
      results.add(
        ProposedStudentAlert(
          student: student,
          type: StudentAlertType.lowAttendance,
          severity: percentage < 60
              ? StudentAlertSeverity.high
              : StudentAlertSeverity.medium,
          title:
              'Attendance below ${settings.attendanceThreshold.toStringAsFixed(0)}%',
          reason:
              '$presentSessions of $recordedSessions recorded sessions were present '
              '(${percentage.toStringAsFixed(1)}%), below the '
              '${settings.attendanceThreshold.toStringAsFixed(0)}% threshold.',
          evidence: <String, dynamic>{
            'presentSessions': presentSessions,
            'recordedSessions': recordedSessions,
            'attendancePercentage': percentage,
            'threshold': settings.attendanceThreshold,
            'minimumSessions': settings.minimumAttendanceSessions,
          },
        ),
      );
    }

    final periodEnd = today;
    final periodStart = today.subtract(
      Duration(days: settings.recentAbsenceDays - 1),
    );
    final absences = records.where((record) {
      final date = _dateOnly(record.classDate);
      return record.status == AttendanceStatus.absent &&
          !date.isBefore(periodStart) &&
          !date.isAfter(periodEnd);
    }).length;
    if (absences >= settings.repeatedAbsenceCount) {
      results.add(
        ProposedStudentAlert(
          student: student,
          type: StudentAlertType.repeatedAbsence,
          severity: absences >= settings.repeatedAbsenceCount + 2
              ? StudentAlertSeverity.high
              : StudentAlertSeverity.medium,
          title: 'Repeated recorded absences',
          reason:
              '$absences recorded absences from ${_dateLabel(periodStart)} to '
              '${_dateLabel(periodEnd)} triggered the ${settings.repeatedAbsenceCount}-absence '
              'threshold. These are not assumed to be consecutive.',
          evidence: <String, dynamic>{
            'absenceCount': absences,
            'threshold': settings.repeatedAbsenceCount,
            'periodDays': settings.recentAbsenceDays,
            'periodStart': periodStart,
            'periodEnd': periodEnd,
          },
        ),
      );
    }
    return results;
  }

  List<_OverdueInstallment> _overdueInstallments(
    List<FeeInstallment> installments,
    Map<String, List<Payment>> paymentsByInstallment,
    DateTime today,
  ) {
    final results = <_OverdueInstallment>[];
    for (final installment in installments) {
      final payments = paymentsByInstallment[installment.id] ?? const [];
      // The current fee implementation stores paidAmount atomically with each
      // payment. For older imported data without payment rows, retain that
      // established balance rather than falsely calling a paid record overdue.
      final paymentPaise = payments.fold<int>(
        0,
        (sum, payment) => sum + payment.amountPaise,
      );
      final paidPaise = payments.isEmpty
          ? installment.paidAmountPaise
          : paymentPaise;
      final outstandingPaise = (installment.amountDuePaise - paidPaise).clamp(
        0,
        installment.amountDuePaise,
      );
      final dueDate = _dateOnly(installment.dueDate);
      if (dueDate.isBefore(today) && outstandingPaise > 0) {
        results.add(
          _OverdueInstallment(
            installment: installment,
            paidAmount: paidPaise / 100,
            outstandingPaise: outstandingPaise,
          ),
        );
      }
    }
    return results;
  }
}

class _OverdueInstallment {
  const _OverdueInstallment({
    required this.installment,
    required this.paidAmount,
    required this.outstandingPaise,
  });

  final FeeInstallment installment;
  final double paidAmount;
  final int outstandingPaise;
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateLabel(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
