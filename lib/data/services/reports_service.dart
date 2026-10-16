import '../models/attendance_record.dart';
import '../models/student_alert.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/batch_repository.dart';
import '../repositories/fee_repository.dart';
import '../repositories/student_alert_repository.dart';
import '../repositories/student_repository.dart';
import '../repositories/timetable_repository.dart';
import '../repositories/trainer_repository.dart';
import '../repositories/approval_repository.dart';

class StudentReportData {
  const StudentReportData({
    required this.totalStudents,
    required this.activeStudents,
    required this.inactiveStudents,
    required this.studentsByCourse,
    required this.studentsByBatch,
  });

  final int totalStudents;
  final int activeStudents;
  final int inactiveStudents;
  final Map<String, int> studentsByCourse;
  final Map<String, int> studentsByBatch;
}

class AttendanceThresholdStudent {
  const AttendanceThresholdStudent({
    required this.studentId,
    required this.studentName,
    required this.batchName,
    required this.percentage,
    required this.totalSessions,
  });

  final String studentId;
  final String studentName;
  final String batchName;
  final double percentage;
  final int totalSessions;
}

class AttendanceReportData {
  const AttendanceReportData({
    required this.totalRecords,
    required this.presentCount,
    required this.absentCount,
    required this.lateCount,
    required this.overallPercentage,
    required this.batchPercentages,
    required this.studentsBelowThreshold,
  });

  final int totalRecords;
  final int presentCount;
  final int absentCount;
  final int lateCount;
  final double overallPercentage;
  final Map<String, double> batchPercentages;
  final List<AttendanceThresholdStudent> studentsBelowThreshold;
}

class FeeReportData {
  const FeeReportData({
    required this.totalDue,
    required this.totalCollected,
    required this.outstandingBalance,
    required this.overdueCount,
    required this.overdueAmount,
    required this.collectionRate,
  });

  final double totalDue;
  final double totalCollected;
  final double outstandingBalance;
  final int overdueCount;
  final double overdueAmount;
  final double collectionRate;
}

class TrainerTimetableReportData {
  const TrainerTimetableReportData({
    required this.totalTrainers,
    required this.activeTrainers,
    required this.inactiveTrainers,
    required this.trainerBatchAssignments,
    required this.totalClasses,
    required this.scheduledClasses,
    required this.completedClasses,
    required this.cancelledClasses,
    required this.inPersonClasses,
    required this.onlineClasses,
    required this.hybridClasses,
  });

  final int totalTrainers;
  final int activeTrainers;
  final int inactiveTrainers;
  final Map<String, int> trainerBatchAssignments;
  final int totalClasses;
  final int scheduledClasses;
  final int completedClasses;
  final int cancelledClasses;
  final int inPersonClasses;
  final int onlineClasses;
  final int hybridClasses;
}

class OperationalSummaryData {
  const OperationalSummaryData({
    required this.totalStudents,
    required this.activeBatches,
    required this.pendingApprovals,
    required this.openAlerts,
    required this.todayClasses,
    required this.overallFeeCollectionRate,
  });

  final int totalStudents;
  final int activeBatches;
  final int pendingApprovals;
  final int openAlerts;
  final int todayClasses;
  final double overallFeeCollectionRate;
}

/// Service that computes accurate institutional analytics from real Firestore records.
class ReportsService {
  ReportsService({
    StudentRepository? studentRepository,
    AttendanceRepository? attendanceRepository,
    FeeRepository? feeRepository,
    BatchRepository? batchRepository,
    TrainerRepository? trainerRepository,
    TimetableRepository? timetableRepository,
    StudentAlertRepository? alertRepository,
    ApprovalRepository? approvalRepository,
  })  : _studentRepository = studentRepository ?? FirestoreStudentRepository(),
        _attendanceRepository =
            attendanceRepository ?? FirestoreAttendanceRepository(),
        _feeRepository = feeRepository ?? FirestoreFeeRepository(),
        _batchRepository = batchRepository ?? FirestoreBatchRepository(),
        _trainerRepository = trainerRepository ?? FirestoreTrainerRepository(),
        _timetableRepository =
            timetableRepository ?? FirestoreTimetableRepository(),
        _alertRepository = alertRepository ?? FirestoreStudentAlertRepository(),
        _approvalRepository =
            approvalRepository ?? FirestoreApprovalRepository();

  final StudentRepository _studentRepository;
  final AttendanceRepository _attendanceRepository;
  final FeeRepository _feeRepository;
  final BatchRepository _batchRepository;
  final TrainerRepository _trainerRepository;
  final TimetableRepository _timetableRepository;
  final StudentAlertRepository _alertRepository;
  final ApprovalRepository _approvalRepository;

  Future<StudentReportData> getStudentReport({
    String instituteId = 'demo-institute',
    String? courseFilter,
    String? batchFilter,
  }) async {
    final allStudents = await _studentRepository
        .watchStudents(scope: StudentAccessScope(instituteId: instituteId))
        .first;

    final students = allStudents.where((s) {
      if (courseFilter != null &&
          courseFilter != 'all' &&
          s.courseId != courseFilter &&
          s.courseName.toLowerCase() != courseFilter.toLowerCase()) {
        return false;
      }
      if (batchFilter != null &&
          batchFilter != 'all' &&
          s.batchId != batchFilter &&
          s.batchName.toLowerCase() != batchFilter.toLowerCase()) {
        return false;
      }
      return true;
    }).toList();

    var active = 0;
    var inactive = 0;
    final byCourse = <String, int>{};
    final byBatch = <String, int>{};

    for (final s in students) {
      if (s.status == 'active') {
        active++;
      } else {
        inactive++;
      }

      final cName = s.courseName.isNotEmpty ? s.courseName : 'Unassigned';
      byCourse[cName] = (byCourse[cName] ?? 0) + 1;

      final bName = s.batchName.isNotEmpty ? s.batchName : 'Unassigned';
      byBatch[bName] = (byBatch[bName] ?? 0) + 1;
    }

    return StudentReportData(
      totalStudents: students.length,
      activeStudents: active,
      inactiveStudents: inactive,
      studentsByCourse: byCourse,
      studentsByBatch: byBatch,
    );
  }

  Future<AttendanceReportData> getAttendanceReport({
    String instituteId = 'demo-institute',
    String? batchId,
    DateTime? startDate,
    DateTime? endDate,
    double threshold = 75.0,
  }) async {
    final allRecords = await _attendanceRepository
        .watchAttendanceHistory(
          scope: AttendanceAccessScope(instituteId: instituteId),
        )
        .first;

    final records = allRecords.where((r) {
      if (batchId != null && batchId != 'all' && r.batchId != batchId) {
        return false;
      }
      if (startDate != null && r.classDate.isBefore(startDate)) {
        return false;
      }
      if (endDate != null && r.classDate.isAfter(endDate)) {
        return false;
      }
      return true;
    }).toList();

    final students = await _studentRepository
        .watchStudents(scope: StudentAccessScope(instituteId: instituteId))
        .first;
    final studentMap = {for (final s in students) s.id: s};

    var present = 0;
    var absent = 0;
    var late = 0;

    final batchTotals = <String, ({int present, int total})>{};
    final studentTotals = <String, ({int present, int total, String batch})>{};

    for (final r in records) {
      final isPresent = r.status == AttendanceStatus.present;
      final isAbsent = r.status == AttendanceStatus.absent;
      final isLate = r.status == AttendanceStatus.late;

      if (isPresent) present++;
      if (isAbsent) absent++;
      if (isLate) late++;

      // Batch aggregations
      final bKey = r.batchId.isNotEmpty ? r.batchId : 'General';
      final currentBatch = batchTotals[bKey] ?? (present: 0, total: 0);
      batchTotals[bKey] = (
        present: currentBatch.present + (isPresent ? 1 : 0),
        total: currentBatch.total + 1,
      );

      // Student aggregations
      final currentStudent =
          studentTotals[r.studentId] ?? (present: 0, total: 0, batch: bKey);
      studentTotals[r.studentId] = (
        present: currentStudent.present + (isPresent ? 1 : 0),
        total: currentStudent.total + 1,
        batch: bKey,
      );
    }

    final totalRecords = records.length;
    final overallPct =
        totalRecords == 0 ? 0.0 : (present / totalRecords) * 100.0;

    final batchPercentages = <String, double>{};
    for (final entry in batchTotals.entries) {
      batchPercentages[entry.key] = entry.value.total == 0
          ? 0.0
          : (entry.value.present / entry.value.total) * 100.0;
    }

    final belowThreshold = <AttendanceThresholdStudent>[];
    for (final entry in studentTotals.entries) {
      if (entry.value.total == 0) continue;
      final pct = (entry.value.present / entry.value.total) * 100.0;
      if (pct < threshold) {
        final s = studentMap[entry.key];
        belowThreshold.add(
          AttendanceThresholdStudent(
            studentId: entry.key,
            studentName: s?.fullName ?? 'Student (${entry.key})',
            batchName: s?.batchName ?? entry.value.batch,
            percentage: pct,
            totalSessions: entry.value.total,
          ),
        );
      }
    }

    belowThreshold.sort((a, b) => a.percentage.compareTo(b.percentage));

    return AttendanceReportData(
      totalRecords: totalRecords,
      presentCount: present,
      absentCount: absent,
      lateCount: late,
      overallPercentage: overallPct,
      batchPercentages: batchPercentages,
      studentsBelowThreshold: belowThreshold,
    );
  }

  Future<FeeReportData> getFeeReport({
    String instituteId = 'demo-institute',
  }) async {
    final installments = await _feeRepository.getInstallments(
      scope: FeeAccessScope(instituteId: instituteId),
    );

    var totalDue = 0.0;
    var totalCollected = 0.0;
    var overdueCount = 0;
    var overdueAmount = 0.0;

    final now = DateTime.now();
    for (final inst in installments) {
      totalDue += inst.amountDue;
      totalCollected += inst.paidAmount;

      final isOverdue = inst.status == 'overdue' ||
          (inst.status != 'paid' && inst.dueDate.isBefore(now));

      if (isOverdue) {
        overdueCount++;
        overdueAmount += inst.outstandingBalance;
      }
    }

    final outstanding = totalDue - totalCollected;
    final collectionRate =
        totalDue == 0.0 ? 0.0 : (totalCollected / totalDue) * 100.0;

    return FeeReportData(
      totalDue: totalDue,
      totalCollected: totalCollected,
      outstandingBalance: outstanding < 0 ? 0 : outstanding,
      overdueCount: overdueCount,
      overdueAmount: overdueAmount,
      collectionRate: collectionRate,
    );
  }

  Future<TrainerTimetableReportData> getTrainerTimetableReport({
    String instituteId = 'demo-institute',
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trainers = await _trainerRepository.getTrainers(
      scope: TrainerAccessScope(instituteId: instituteId),
    );
    final batches = await _batchRepository.getBatches(
      scope: BatchAccessScope(instituteId: instituteId),
    );
    final sessions = await _timetableRepository.getSessions(
      scope: TimetableAccessScope(
        instituteId: instituteId,
        startDate: startDate,
        endDate: endDate,
      ),
    );

    var activeTrainers = 0;
    var inactiveTrainers = 0;
    final trainerAssignments = <String, int>{};

    for (final t in trainers) {
      if (t.isActive) {
        activeTrainers++;
      } else {
        inactiveTrainers++;
      }

      final count = batches
          .where((b) => !b.isArchived && b.trainerId == t.id)
          .length;
      trainerAssignments[t.fullName] = count;
    }

    var scheduled = 0;
    var completed = 0;
    var cancelled = 0;
    var inPerson = 0;
    var online = 0;
    var hybrid = 0;

    for (final s in sessions) {
      if (s.isScheduled) scheduled++;
      if (s.isCompleted) completed++;
      if (s.isCancelled) cancelled++;

      if (s.isInPerson) inPerson++;
      if (s.isOnline) online++;
      if (s.isHybrid) hybrid++;
    }

    return TrainerTimetableReportData(
      totalTrainers: trainers.length,
      activeTrainers: activeTrainers,
      inactiveTrainers: inactiveTrainers,
      trainerBatchAssignments: trainerAssignments,
      totalClasses: sessions.length,
      scheduledClasses: scheduled,
      completedClasses: completed,
      cancelledClasses: cancelled,
      inPersonClasses: inPerson,
      onlineClasses: online,
      hybridClasses: hybrid,
    );
  }

  Future<OperationalSummaryData> getOperationalSummary({
    String instituteId = 'demo-institute',
  }) async {
    final students = await _studentRepository
        .watchStudents(scope: StudentAccessScope(instituteId: instituteId))
        .first;
    final batches = await _batchRepository.getBatches(
      scope: BatchAccessScope(instituteId: instituteId),
    );
    final actions = await _approvalRepository.getActions(
      scope: ApprovalAccessScope(instituteId: instituteId),
    );
    final alerts = await _alertRepository.getAlertsForScan(instituteId);
    final sessions = await _timetableRepository.getSessions(
      scope: TimetableAccessScope(instituteId: instituteId),
    );
    final feeReport = await getFeeReport(instituteId: instituteId);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayClasses = sessions.where((s) {
      return !s.isCancelled &&
          s.startAt.year == today.year &&
          s.startAt.month == today.month &&
          s.startAt.day == today.day;
    }).length;

    return OperationalSummaryData(
      totalStudents: students.length,
      activeBatches: batches.where((b) => !b.isArchived).length,
      pendingApprovals: actions.where((a) => a.isPending).length,
      openAlerts: alerts.where((a) => !a.status.isClosed).length,
      todayClasses: todayClasses,
      overallFeeCollectionRate: feeReport.collectionRate,
    );
  }
}
