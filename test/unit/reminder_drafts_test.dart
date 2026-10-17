import 'package:flutter_test/flutter_test.dart';
import 'package:kurukshetra/data/models/fee_installment.dart';
import 'package:kurukshetra/data/models/reminder_draft.dart';

void main() {
  group('ReminderDraft', () {
    test('detects stale reminders after instalment is paid', () {
      final date = DateTime(2026, 5, 10);
      final reminder = ReminderDraft(
        id: 'reminder-1',
        instituteId: 'demo-institute',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        feeInstallmentId: 'inst-1',
        outstandingAmountAtDraft: 2500,
        dueDateAtDraft: date,
        message: 'Hello Aisha',
        status: ReminderDraftStatus.approved,
        createdBy: 'accounts-1',
        createdAt: date,
        updatedAt: date,
      );

      final installment = FeeInstallment(
        id: 'inst-1',
        instituteId: 'demo-institute',
        studentId: 'student-1',
        studentName: 'Aisha Khan',
        courseId: 'course-1',
        batchId: 'batch-1',
        amountDue: 2500,
        dueDate: date,
        createdAt: date,
        updatedAt: date,
        status: 'paid',
        paidAmount: 2500,
      );

      expect(reminder.isObsoleteForInstallment(installment), isTrue);
    });

    test('builds a reminder message from the live instalment values', () {
      final reminder = ReminderDraft.buildFromInstallment(
        id: 'reminder-2',
        instituteId: 'demo-institute',
        studentId: 'student-2',
        studentName: 'Rohan Patel',
        feeInstallmentId: 'inst-2',
        createdBy: 'accounts-1',
        messageTemplate: 'Hello {studentName}, our records show an outstanding instalment of {outstandingAmount} for your course. The due date was {dueDate}. Please contact the accounts team if you have already made the payment or need assistance.',
        installment: FeeInstallment(
          id: 'inst-2',
          instituteId: 'demo-institute',
          studentId: 'student-2',
          studentName: 'Rohan Patel',
          courseId: 'course-1',
          batchId: 'batch-1',
          amountDue: 4000,
          dueDate: DateTime(2026, 5, 15),
          createdAt: DateTime(2026, 4, 1),
          updatedAt: DateTime(2026, 4, 1),
          status: 'pending',
          paidAmount: 750,
        ),
      );

      expect(reminder.message, contains('Rohan Patel'));
      expect(reminder.message, contains('₹3,250.00'));
      expect(reminder.message, contains('15/05/2026'));
    });
  });
}
