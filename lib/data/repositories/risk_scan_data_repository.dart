import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/attendance_record.dart';
import '../models/fee_installment.dart';
import '../models/payment.dart';
import '../models/student.dart';

class RiskScanData {
  const RiskScanData({
    required this.students,
    required this.attendance,
    required this.installments,
    required this.payments,
  });

  final List<Student> students;
  final List<AttendanceRecord> attendance;
  final List<FeeInstallment> installments;
  final List<Payment> payments;
}

class RiskScanLimitException implements Exception {
  const RiskScanLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class RiskScanDataRepository {
  Future<RiskScanData> loadInstituteData(String instituteId);
}

/// Bounded, owner-only scan reads across existing collections. Every query
/// fetches one extra document; a limit failure means nothing is written and a
/// partial scan is never presented as complete.
class FirestoreRiskScanDataRepository implements RiskScanDataRepository {
  FirestoreRiskScanDataRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const int _studentLimit = 200;
  static const int _attendanceLimit = 3000;
  static const int _installmentLimit = 800;
  static const int _paymentLimit = 1000;

  final FirebaseFirestore _firestore;

  @override
  Future<RiskScanData> loadInstituteData(String instituteId) async {
    final studentSnapshot = await _readBounded(
      _firestore
          .collection('students')
          .where('instituteId', isEqualTo: instituteId),
      _studentLimit,
      'students',
    );

    final snapshots = await Future.wait([
      _readBounded(
        _firestore
            .collection('attendance')
            .where('instituteId', isEqualTo: instituteId),
        _attendanceLimit,
        'attendance records',
      ),
      _readBounded(
        _firestore
            .collection('feeInstallments')
            .where('instituteId', isEqualTo: instituteId),
        _installmentLimit,
        'fee instalments',
      ),
      _readBounded(
        _firestore
            .collection('payments')
            .where('instituteId', isEqualTo: instituteId),
        _paymentLimit,
        'payments',
      ),
    ]);
    final attendanceSnapshot = snapshots[0];
    final installmentSnapshot = snapshots[1];
    final paymentSnapshot = snapshots[2];

    return RiskScanData(
      students: studentSnapshot.docs.map(Student.fromFirestore).toList(),
      // Unknown/malformed statuses are deliberately excluded. A missing or
      // unrecognized record cannot turn into a present/absent value in a scan.
      attendance: attendanceSnapshot.docs
          .where((doc) => _isRecognizedAttendanceStatus(doc.data()['status']))
          .map(AttendanceRecord.fromFirestore)
          .toList(),
      installments: installmentSnapshot.docs
          .map(FeeInstallment.fromFirestore)
          .toList(),
      payments: paymentSnapshot.docs.map(Payment.fromFirestore).toList(),
    );
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _readBounded(
    Query<Map<String, dynamic>> query,
    int limit,
    String label,
  ) async {
    final snapshot = await query.limit(limit + 1).get();
    if (snapshot.docs.length > limit) {
      throw RiskScanLimitException(
        'Risk scan stopped before writing: more than $limit $label were found. '
        'Narrow or paginate the institute data before running a complete scan.',
      );
    }
    return snapshot;
  }

  bool _isRecognizedAttendanceStatus(dynamic value) =>
      value == 'present' || value == 'absent' || value == 'late';
}
