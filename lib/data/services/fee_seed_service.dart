import '../models/fee_installment.dart';
import '../models/payment.dart';
import '../repositories/fee_repository.dart';

class FeeSeedResult {
  const FeeSeedResult({
    required this.installmentsCreated,
    required this.installmentsSkipped,
    required this.paymentsCreated,
    required this.paymentsSkipped,
    required this.alreadyHadData,
  });

  final int installmentsCreated;
  final int installmentsSkipped;
  final int paymentsCreated;
  final int paymentsSkipped;
  final bool alreadyHadData;
}

/// Populates sample fee instalments and payment transactions with deterministic IDs.
///
/// Safe to run repeatedly: never overwrites existing records and skips duplicates.
class FeeSeedService {
  FeeSeedService({FeeSeedRepository? feeRepository})
    : _feeRepository = feeRepository ?? FirestoreFeeRepository();

  final FeeSeedRepository _feeRepository;

  Future<FeeSeedResult> loadSampleFees() async {
    final sampleInstallments = _sampleInstallments;
    final samplePayments = _samplePayments;

    final isEmpty = await _feeRepository.isFeeInstallmentsEmpty();
    if (!isEmpty) {
      return FeeSeedResult(
        installmentsCreated: 0,
        installmentsSkipped: sampleInstallments.length,
        paymentsCreated: 0,
        paymentsSkipped: samplePayments.length,
        alreadyHadData: true,
      );
    }

    final existingCount =
        await _feeRepository.countExistingSampleInstallments(sampleInstallments);

    await _feeRepository.createMissingSampleInstallmentsAndPayments(
      installments: sampleInstallments,
      payments: samplePayments,
    );

    return FeeSeedResult(
      installmentsCreated: sampleInstallments.length - existingCount,
      installmentsSkipped: existingCount,
      paymentsCreated: samplePayments.length,
      paymentsSkipped: 0,
      alreadyHadData: false,
    );
  }

  List<FeeInstallment> get _sampleInstallments => <FeeInstallment>[
    FeeInstallment(
      id: 'sample-inst-01-aisha-1',
      instituteId: 'demo-institute',
      studentId: 'sample-01-aisha-khan',
      studentName: 'Aisha Khan',
      courseId: 'data-analytics',
      batchId: 'da-jan-2026-a',
      amountDue: 22500,
      dueDate: DateTime(2026, 2, 8),
      createdAt: DateTime(2026, 1, 8),
      updatedAt: DateTime(2026, 2, 5),
      status: 'paid',
      paidAmount: 22500,
    ),
    FeeInstallment(
      id: 'sample-inst-01-aisha-2',
      instituteId: 'demo-institute',
      studentId: 'sample-01-aisha-khan',
      studentName: 'Aisha Khan',
      courseId: 'data-analytics',
      batchId: 'da-jan-2026-a',
      amountDue: 22500,
      dueDate: DateTime(2026, 12, 1),
      createdAt: DateTime(2026, 1, 8),
      updatedAt: DateTime(2026, 1, 8),
      status: 'pending',
      paidAmount: 0,
    ),
    FeeInstallment(
      id: 'sample-inst-02-vikram-1',
      instituteId: 'demo-institute',
      studentId: 'sample-02-vikram-rao',
      studentName: 'Vikram Rao',
      courseId: 'data-analytics',
      batchId: 'da-jan-2026-a',
      amountDue: 22500,
      dueDate: DateTime(2026, 1, 25),
      createdAt: DateTime(2026, 1, 10),
      updatedAt: DateTime(2026, 1, 20),
      status: 'overdue',
      paidAmount: 15000,
    ),
    FeeInstallment(
      id: 'sample-inst-03-meera-1',
      instituteId: 'demo-institute',
      studentId: 'sample-03-meera-nair',
      studentName: 'Meera Nair',
      courseId: 'full-stack-development',
      batchId: 'fsd-feb-2026-b',
      amountDue: 30000,
      dueDate: DateTime(2026, 3, 1),
      createdAt: DateTime(2026, 2, 2),
      updatedAt: DateTime(2026, 2, 2),
      status: 'overdue',
      paidAmount: 0,
    ),
    FeeInstallment(
      id: 'sample-inst-05-kavya-1',
      instituteId: 'demo-institute',
      studentId: 'sample-05-kavya-iyer',
      studentName: 'Kavya Iyer',
      courseId: 'digital-marketing',
      batchId: 'dm-mar-2026-a',
      amountDue: 17500,
      dueDate: DateTime(2026, 4, 15),
      createdAt: DateTime(2026, 3, 3),
      updatedAt: DateTime(2026, 4, 10),
      status: 'paid',
      paidAmount: 17500,
    ),
    FeeInstallment(
      id: 'sample-inst-07-sana-1',
      instituteId: 'demo-institute',
      studentId: 'sample-07-sana-shaikh',
      studentName: 'Sana Shaikh',
      courseId: 'ui-ux-design',
      batchId: 'ux-apr-2026-c',
      amountDue: 20000,
      dueDate: DateTime(2026, 11, 25),
      createdAt: DateTime(2026, 4, 1),
      updatedAt: DateTime(2026, 4, 1),
      status: 'pending',
      paidAmount: 0,
    ),
  ];

  List<Payment> get _samplePayments => <Payment>[
    Payment(
      id: 'sample-pay-01-aisha-1',
      instituteId: 'demo-institute',
      feeInstallmentId: 'sample-inst-01-aisha-1',
      studentId: 'sample-01-aisha-khan',
      amount: 22500,
      paymentDate: DateTime(2026, 2, 5),
      paymentMethod: 'UPI',
      referenceNumber: 'UPI/20260205/8812',
      recordedBy: 'demo-accounts',
      createdAt: DateTime(2026, 2, 5),
    ),
    Payment(
      id: 'sample-pay-02-vikram-1',
      instituteId: 'demo-institute',
      feeInstallmentId: 'sample-inst-02-vikram-1',
      studentId: 'sample-02-vikram-rao',
      amount: 15000,
      paymentDate: DateTime(2026, 1, 20),
      paymentMethod: 'Bank Transfer',
      referenceNumber: 'NEFT/HDFC/9921',
      recordedBy: 'demo-accounts',
      createdAt: DateTime(2026, 1, 20),
    ),
    Payment(
      id: 'sample-pay-05-kavya-1',
      instituteId: 'demo-institute',
      feeInstallmentId: 'sample-inst-05-kavya-1',
      studentId: 'sample-05-kavya-iyer',
      amount: 17500,
      paymentDate: DateTime(2026, 4, 10),
      paymentMethod: 'Card',
      referenceNumber: 'POS/CARD/4412',
      recordedBy: 'demo-accounts',
      createdAt: DateTime(2026, 4, 10),
    ),
  ];
}
