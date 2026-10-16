import '../models/approval_action.dart';
import '../repositories/approval_repository.dart';

class ApprovalSeedResult {
  const ApprovalSeedResult({
    required this.actionsCreated,
    required this.actionsSkipped,
    required this.alreadyHadData,
  });

  final int actionsCreated;
  final int actionsSkipped;
  final bool alreadyHadData;
}

/// Seeds deterministic sample approval requests for the InstituteOS Approvals Center.
///
/// Safe to execute repeatedly without duplicating data.
class ApprovalSeedService {
  ApprovalSeedService({
    ApprovalSeedRepository? approvalRepository,
  }) : _approvalRepository =
            approvalRepository ?? FirestoreApprovalRepository();

  final ApprovalSeedRepository _approvalRepository;

  Future<ApprovalSeedResult> loadSampleData() async {
    final sampleActions = _sampleActions;

    final isEmpty = await _approvalRepository.isActionsCollectionEmpty();
    if (!isEmpty) {
      final existingCount = await _approvalRepository
          .countExistingSampleActions(sampleActions);
      if (existingCount == sampleActions.length) {
        return ApprovalSeedResult(
          actionsCreated: 0,
          actionsSkipped: sampleActions.length,
          alreadyHadData: true,
        );
      }
    }

    final existingCount = await _approvalRepository
        .countExistingSampleActions(sampleActions);
    await _approvalRepository.createMissingSampleActions(sampleActions);

    return ApprovalSeedResult(
      actionsCreated: sampleActions.length - existingCount,
      actionsSkipped: existingCount,
      alreadyHadData: false,
    );
  }

  List<ApprovalAction> get _sampleActions {
    final now = DateTime.now();

    return <ApprovalAction>[
      ApprovalAction(
        id: 'sample-approval-concession-1',
        instituteId: 'demo-institute',
        type: 'fee_concession',
        title: 'Fee Concession Request - Rahul Sharma',
        description:
            'Requesting ₹5,000 concession based on exceptional academic merit and scholarship eligibility.',
        payload: const {
          'Student Name': 'Rahul Sharma',
          'Course': 'Data Analytics',
          'Batch': 'DA Jan 2026 A',
          'Requested Concession': '₹5,000',
          'Justification': 'Merit scholarship recommendation by Counselor',
        },
        requestedBy: 'Priya Shah (Counselor)',
        requestedAt: now.subtract(const Duration(days: 2, hours: 3)),
        status: 'pending',
        updatedAt: now.subtract(const Duration(days: 2, hours: 3)),
      ),
      ApprovalAction(
        id: 'sample-approval-transfer-2',
        instituteId: 'demo-institute',
        type: 'batch_transfer',
        title: 'Cohort Shift: Ananya Roy to DA May 2026 B',
        description:
            'Student requested evening cohort shift due to new office work hours.',
        payload: const {
          'Student Name': 'Ananya Roy',
          'Current Batch': 'DA Jan 2026 A',
          'Target Batch': 'DA May 2026 B',
          'Attendance Record': '88% Present',
          'Transfer Fee Paid': 'Waived',
        },
        requestedBy: 'Priya Shah (Counselor)',
        requestedAt: now.subtract(const Duration(days: 1, hours: 5)),
        status: 'pending',
        updatedAt: now.subtract(const Duration(days: 1, hours: 5)),
      ),
      ApprovalAction(
        id: 'sample-approval-attendance-3',
        instituteId: 'demo-institute',
        type: 'attendance_override',
        title: 'Medical Leave Attendance Waiver - Vikram Malhotra',
        description:
            'Waiver requested for 3 missed lab sessions supported by verified doctor certificate.',
        payload: const {
          'Student Name': 'Vikram Malhotra',
          'Batch': 'Full Stack Development (Feb 2026)',
          'Missed Sessions': '3 sessions (Oct 5 - Oct 9)',
          'Certificate Verified': 'Yes',
        },
        requestedBy: 'Rohan Kulkarni (Trainer)',
        requestedAt: now.subtract(const Duration(days: 4)),
        status: 'approved',
        approvedBy: 'Aarav Mehta (Owner / Admin)',
        approvedAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 3)),
      ),
      ApprovalAction(
        id: 'sample-approval-refund-4',
        instituteId: 'demo-institute',
        type: 'refund_request',
        title: 'Discontinuation Partial Refund - Kunal Deshmukh',
        description:
            'Student requested course withdrawal and partial tuition refund after week 4.',
        payload: const {
          'Student Name': 'Kunal Deshmukh',
          'Paid to Date': '₹25,000',
          'Requested Refund': '₹15,000',
          'Withdrawal Reason': 'Relocation',
        },
        requestedBy: 'Neha Iyer (Accounts Staff)',
        requestedAt: now.subtract(const Duration(days: 5)),
        status: 'rejected',
        rejectedBy: 'Aarav Mehta (Owner / Admin)',
        rejectedAt: now.subtract(const Duration(days: 4)),
        rejectionReason:
            'Withdrawal submitted outside the institutional 14-day refund window policy.',
        updatedAt: now.subtract(const Duration(days: 4)),
      ),
      ApprovalAction(
        id: 'sample-approval-schedule-5',
        instituteId: 'demo-institute',
        type: 'schedule_override',
        title: 'Extra Saturday Lab - Tech Studio 204',
        description:
            'Requesting classroom allocation for a 4-hour advanced Flutter state management hands-on lab.',
        payload: const {
          'Cohort': 'FSD Feb 2026 B',
          'Requested Date': 'Saturday (10:00 AM - 02:00 PM)',
          'Room': 'Tech Studio 204',
          'Instructor': 'Rohan Kulkarni',
        },
        requestedBy: 'Rohan Kulkarni (Trainer)',
        requestedAt: now.subtract(const Duration(hours: 6)),
        status: 'pending',
        updatedAt: now.subtract(const Duration(hours: 6)),
      ),
    ];
  }
}

