import 'package:firebase_ai/firebase_ai.dart';
import 'package:intl/intl.dart';

import '../../../data/models/app_user.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/fee_installment.dart';
import '../../../data/models/reminder_draft.dart';
import '../../../data/models/student_alert.dart';
import '../../../data/services/approval_service.dart';
import '../../../data/services/attendance_service.dart';
import '../../../data/services/batch_service.dart';
import '../../../data/services/fee_service.dart';
import '../../../data/services/reminder_draft_service.dart';
import '../../../data/services/student_risk_alert_service.dart';
import '../../../data/services/student_service.dart';
import '../../../data/services/timetable_service.dart';
import '../models/copilot_tool_result.dart';

/// The only path through which the model can see operational data.
///
/// Each callable uses the same role-scoped application services as the product
/// UI, removes unnecessary personal fields, applies a bounded result limit,
/// and records an explainable result for the conversation. The model receives
/// no Firestore client, collection name, or unrestricted query primitive.
class CopilotToolRegistry {
  CopilotToolRegistry({
    required this.user,
    StudentService? studentService,
    AttendanceService? attendanceService,
    FeeService? feeService,
    BatchService? batchService,
    TimetableService? timetableService,
    StudentRiskAlertService? riskAlertService,
    ApprovalService? approvalService,
    ReminderDraftService? reminderDraftService,
  }) : _studentService = studentService ?? StudentService(),
       _attendanceServiceInstance = attendanceService,
       _feeServiceInstance = feeService,
       _batchServiceInstance = batchService,
       _timetableServiceInstance = timetableService,
       _riskAlertServiceInstance = riskAlertService,
       _approvalServiceInstance = approvalService,
       _reminderDraftServiceInstance = reminderDraftService;

  static const _maxRows = 30;

  /// A convenience guard for the standard application build. This is not an
  /// authorization boundary: deployed Firestore rules remain responsible for
  /// every write. Keeping it off by default prevents the Copilot from adding
  /// a sensitive reminder-draft write path before those rules are verified.
  static const _reminderDraftWritesEnabled = bool.fromEnvironment(
    'COPILOT_ENABLE_REMINDER_DRAFT_WRITES',
    defaultValue: false,
  );

  final AppUser user;
  final StudentService _studentService;
  AttendanceService? _attendanceServiceInstance;
  FeeService? _feeServiceInstance;
  BatchService? _batchServiceInstance;
  TimetableService? _timetableServiceInstance;
  StudentRiskAlertService? _riskAlertServiceInstance;
  ApprovalService? _approvalServiceInstance;
  ReminderDraftService? _reminderDraftServiceInstance;
  final List<CopilotToolResult> _results = <CopilotToolResult>[];

  AttendanceService get _attendanceService =>
      _attendanceServiceInstance ??= AttendanceService();
  FeeService get _feeService => _feeServiceInstance ??= FeeService();
  BatchService get _batchService => _batchServiceInstance ??= BatchService();
  TimetableService get _timetableService =>
      _timetableServiceInstance ??= TimetableService();
  StudentRiskAlertService get _riskAlertService =>
      _riskAlertServiceInstance ??= StudentRiskAlertService();
  ApprovalService get _approvalService =>
      _approvalServiceInstance ??= ApprovalService();
  ReminderDraftService get _reminderDraftService =>
      _reminderDraftServiceInstance ??= ReminderDraftService();

  List<AutoFunctionDeclaration> get declarations {
    final tools = <AutoFunctionDeclaration>[
      AutoFunctionDeclaration(
        name: 'search_students',
        description: 'Search only the students this signed-in user is allowed to view. Use for student, course, batch, or status questions.',
        parameters: <String, Schema>{
          'query': Schema.string(
            description: 'Name or student id search text.',
          ),
          'batch': Schema.string(description: 'Optional batch name or id.'),
          'course': Schema.string(description: 'Optional course name or id.'),
          'status': Schema.string(description: 'Optional student status.'),
        },
        optionalParameters: const <String>[
          'query',
          'batch',
          'course',
          'status',
        ],
        callable: _searchStudents,
      ),
      AutoFunctionDeclaration(
        name: 'list_batches',
        description: 'List authorized batches with their course, trainer, capacity, and current enrollment count.',
        parameters: <String, Schema>{
          'query': Schema.string(
            description: 'Optional batch or course search text.',
          ),
        },
        optionalParameters: const <String>['query'],
        callable: _listBatches,
      ),
    ];

    if (_canReadAttendance) {
      tools.add(
        AutoFunctionDeclaration(
          name: 'find_low_attendance',
          description: 'Find authorized students below an attendance threshold using recorded attendance. It can narrow to a batch or student IDs from a previous result.',
          parameters: <String, Schema>{
            'threshold': Schema.number(
              description: 'Attendance percentage threshold, default 75.',
            ),
            'batch': Schema.string(description: 'Optional batch name or id.'),
            'student_ids': Schema.array(
              items: Schema.string(),
              description:
                  'Optional student IDs from a previous authorized result.',
            ),
            'from_date': Schema.string(
              description: 'Optional YYYY-MM-DD date.',
            ),
            'to_date': Schema.string(description: 'Optional YYYY-MM-DD date.'),
          },
          optionalParameters: const <String>[
            'threshold',
            'batch',
            'student_ids',
            'from_date',
            'to_date',
          ],
          callable: _findLowAttendance,
        ),
      );
    }

    if (_canReadFees) {
      tools.add(
        AutoFunctionDeclaration(
          name: 'list_overdue_instalments',
          description: 'List actual authorized fee instalments that are genuinely overdue and still have an outstanding balance.',
          parameters: <String, Schema>{
            'batch': Schema.string(description: 'Optional batch name or id.'),
            'student_query': Schema.string(
              description: 'Optional student name or id.',
            ),
          },
          optionalParameters: const <String>['batch', 'student_query'],
          callable: _listOverdueInstallments,
        ),
      );
      if (_reminderDraftWritesEnabled) {
        tools.add(
          AutoFunctionDeclaration(
            name: 'prepare_reminder_draft',
            description: 'Prepare a preview only of a reminder draft for one authorized outstanding instalment. This never sends a message or writes a draft; the user must explicitly confirm the preview in the app.',
            parameters: <String, Schema>{
              'fee_installment_id': Schema.string(
                description: 'The authorized instalment ID to use.',
              ),
            },
            callable: _prepareReminderDraft,
          ),
        );
      }
    }

    if (_canReadTimetable) {
      tools.add(
        AutoFunctionDeclaration(
          name: 'list_timetable',
          description: 'List permitted timetable sessions. With no date it lists today; pass an ISO date for a specific day.',
          parameters: <String, Schema>{
            'date': Schema.string(description: 'Optional YYYY-MM-DD date.'),
            'batch': Schema.string(description: 'Optional batch name or id.'),
          },
          optionalParameters: const <String>['date', 'batch'],
          callable: _listTimetable,
        ),
      );
    }

    if (_canReadRiskAlerts) {
      tools.add(
        AutoFunctionDeclaration(
          name: 'list_risk_alerts',
          description: 'List only the current user’s authorized existing risk alerts and their evidence/follow-up status.',
          parameters: <String, Schema>{
            'status': Schema.string(description: 'Optional alert status.'),
          },
          optionalParameters: const <String>['status'],
          callable: _listRiskAlerts,
        ),
      );
    }

    if (_canReadApprovals) {
      tools.add(
        AutoFunctionDeclaration(
          name: 'list_approval_requests',
          description: 'List approval requests the signed-in user is allowed to review, without approving or rejecting anything.',
          parameters: <String, Schema>{
            'status': Schema.string(description: 'Optional approval status.'),
          },
          optionalParameters: const <String>['status'],
          callable: _listApprovalRequests,
        ),
      );
    }
    return tools;
  }

  List<CopilotToolResult> takeResults() {
    final snapshot = List<CopilotToolResult>.unmodifiable(_results);
    _results.clear();
    return snapshot;
  }

  void clearResults() => _results.clear();

  Future<CopilotToolResult> executeConfirmedAction(
    CopilotActionPreview preview,
  ) async {
    if (preview.type != 'create_reminder_draft' || !_canReadFees) {
      throw StateError('This Copilot action is not permitted for your role.');
    }
    if (!_reminderDraftWritesEnabled) {
      throw StateError(
        'Copilot reminder-draft writes are disabled for this build until the required Firestore authorization rules have been deployed and verified.',
      );
    }
    final installmentId = preview.payload['feeInstallmentId']?.toString() ?? '';
    if (installmentId.isEmpty) {
      throw StateError('The action preview does not identify an instalment.');
    }

    // Revalidate from the current authorized dataset; never trust a saved chat
    // preview for balance, recipient, or institute fields.
    final installments = await _feeService.getInstallmentsForUser(user);
    final installment = installments.cast<FeeInstallment?>().firstWhere(
      (item) => item?.id == installmentId,
      orElse: () => null,
    );
    if (installment == null || installment.instituteId != user.instituteId) {
      throw StateError('This instalment is no longer available to you.');
    }
    if (installment.isPaid || installment.outstandingBalance <= 0) {
      throw StateError(
        'This instalment is fully paid now, so no reminder draft was created.',
      );
    }

    final draft = _reminderDraftService.draftFromInstallment(
      user: user,
      installment: installment,
      messageTemplate: _reminderDraftService.buildTemplateMessage(
        studentName: installment.studentName,
        outstandingAmount: installment.outstandingBalance,
        dueDate: installment.dueDate,
      ),
    );
    final saved = await _reminderDraftService.saveDraftForUser(user, draft);
    return CopilotToolResult(
      queryId: 'create_reminder_draft',
      source: 'Reminder Drafts / Fee Installments',
      summary:
          'A reminder draft was saved for ${saved.studentName}. It was not sent and remains in the existing approval workflow.',
      filters: <String, Object?>{'feeInstallmentId': installment.id},
      rows: <Map<String, Object?>>[
        <String, Object?>{
          'Student': saved.studentName,
          'Outstanding': _currency(saved.outstandingAmountAtDraft),
          'Due date': _date(saved.dueDateAtDraft),
          'Draft status': saved.status.value,
        },
      ],
      calculation: 'The current outstanding balance was rechecked immediately before the draft was saved.',
    );
  }

  Future<Map<String, Object?>> _searchStudents(
    Map<String, Object?> args,
  ) async {
    final query = _text(args, 'query');
    final batch = _text(args, 'batch');
    final course = _text(args, 'course');
    final status = _text(args, 'status');
    final students = await _studentService.watchForUser(user).first;
    final matches = students
        .where((student) {
          return _matches(query, <String>[student.fullName, student.id]) &&
              _matches(batch, <String>[student.batchId, student.batchName]) &&
              _matches(course, <String>[
                student.courseId,
                student.courseName,
              ]) &&
              (status.isEmpty ||
                  student.status.toLowerCase() == status.toLowerCase());
        })
        .take(_maxRows)
        .toList(growable: false);
    return _record(
      CopilotToolResult(
        queryId: 'search_students',
        source: 'Students',
        summary: '${matches.length} authorized student record(s) matched.',
        filters: <String, Object?>{
          if (query.isNotEmpty) 'query': query,
          if (batch.isNotEmpty) 'batch': batch,
          if (course.isNotEmpty) 'course': course,
          if (status.isNotEmpty) 'status': status,
          'limit': _maxRows,
        },
        rows: matches
            .map(
              (student) => <String, Object?>{
                'Student ID': student.id,
                'Student': student.fullName,
                'Course': student.courseName,
                'Batch': student.batchName,
                'Status': student.status,
                'Enrolled': _date(student.enrollmentDate),
              },
            )
            .toList(growable: false),
      ),
    );
  }

  Future<Map<String, Object?>> _listBatches(Map<String, Object?> args) async {
    final query = _text(args, 'query');
    final batches = await _batchService.getForUser(user);
    final students = await _studentService.watchForUser(user).first;
    final matches = batches
        .where(
          (batch) =>
              _matches(query, <String>[batch.id, batch.name, batch.courseName]),
        )
        .take(_maxRows)
        .toList(growable: false);
    return _record(
      CopilotToolResult(
        queryId: 'list_batches',
        source: 'Courses & Batches / Students',
        summary: '${matches.length} authorized batch record(s) matched.',
        filters: <String, Object?>{
          if (query.isNotEmpty) 'query': query,
          'limit': _maxRows,
        },
        rows: matches
            .map(
              (batch) => <String, Object?>{
                'Batch ID': batch.id,
                'Batch': batch.name,
                'Course': batch.courseName,
                'Trainer': batch.trainerName,
                'Enrolled': students
                    .where((student) => student.batchId == batch.id)
                    .length,
                'Capacity': batch.capacity,
                'Status': batch.status,
              },
            )
            .toList(growable: false),
      ),
    );
  }

  Future<Map<String, Object?>> _findLowAttendance(
    Map<String, Object?> args,
  ) async {
    if (!_canReadAttendance) return _denied('find_low_attendance');
    final threshold = _number(args, 'threshold', fallback: 75).clamp(0, 100);
    final batch = _text(args, 'batch');
    final selectedIds = _stringList(args['student_ids']);
    final from = _parseDate(_text(args, 'from_date'));
    final to = _endOfDay(_parseDate(_text(args, 'to_date')));
    final students = await _studentService.watchForUser(user).first;
    final allowed = students
        .where((student) {
          return _matches(batch, <String>[
                student.batchId,
                student.batchName,
              ]) &&
              (selectedIds.isEmpty || selectedIds.contains(student.id));
        })
        .toList(growable: false);
    final allowedById = {for (final student in allowed) student.id: student};
    final records = await _attendanceService.watchHistoryForUser(user).first;
    final totals = <String, ({int present, int total})>{};
    for (final record in records) {
      if (!allowedById.containsKey(record.studentId) ||
          (from != null && record.classDate.isBefore(from)) ||
          (to != null && record.classDate.isAfter(to))) {
        continue;
      }
      final current = totals[record.studentId] ?? (present: 0, total: 0);
      totals[record.studentId] = (
        present:
            current.present +
            (record.status == AttendanceStatus.present ? 1 : 0),
        total: current.total + 1,
      );
    }
    final rows = <Map<String, Object?>>[];
    for (final entry in totals.entries) {
      final total = entry.value.total;
      if (total == 0) continue;
      final percentage = entry.value.present / total * 100;
      if (percentage < threshold) {
        final student = allowedById[entry.key]!;
        rows.add(<String, Object?>{
          'Student ID': student.id,
          'Student': student.fullName,
          'Batch': student.batchName,
          'Attendance': '${percentage.toStringAsFixed(1)}%',
          'Present sessions': entry.value.present,
          'Recorded sessions': total,
        });
      }
    }
    rows.sort(
      (left, right) => (left['Attendance'] as String).compareTo(
        right['Attendance'] as String,
      ),
    );
    return _record(
      CopilotToolResult(
        queryId: 'find_low_attendance',
        source: 'Attendance / Students',
        summary:
            '${rows.length} authorized student(s) are below ${threshold.toStringAsFixed(0)}% attendance.',
        filters: <String, Object?>{
          'threshold': threshold,
          if (batch.isNotEmpty) 'batch': batch,
          if (selectedIds.isNotEmpty) 'studentIds': selectedIds,
          if (from != null) 'from': _date(from),
          if (to != null) 'to': _date(to),
        },
        rows: rows.take(_maxRows).toList(growable: false),
        calculation: 'Attendance = recorded Present sessions / all recorded sessions × 100. Late records are not counted as present.',
      ),
    );
  }

  Future<Map<String, Object?>> _listOverdueInstallments(
    Map<String, Object?> args,
  ) async {
    if (!_canReadFees) return _denied('list_overdue_instalments');
    final batch = _text(args, 'batch');
    final studentQuery = _text(args, 'student_query');
    final now = DateTime.now();
    final installments = await _feeService.getInstallmentsForUser(user);
    final matches = installments
        .where((item) {
          final currentStatus = FeeInstallment.deriveStatus(
            amountDue: item.amountDue,
            paidAmount: item.paidAmount,
            dueDate: item.dueDate,
            asOf: now,
          );
          return currentStatus == 'overdue' &&
              item.outstandingBalance > 0 &&
              _matches(batch, <String>[item.batchId]) &&
              _matches(studentQuery, <String>[
                item.studentName,
                item.studentId,
              ]);
        })
        .take(_maxRows)
        .toList(growable: false);
    return _record(
      CopilotToolResult(
        queryId: 'list_overdue_instalments',
        source: 'Fee Installments',
        summary: '${matches.length} overdue authorized instalment(s) found.',
        filters: <String, Object?>{
          if (batch.isNotEmpty) 'batch': batch,
          if (studentQuery.isNotEmpty) 'studentQuery': studentQuery,
          'asOf': _date(now),
          'limit': _maxRows,
        },
        rows: matches
            .map(
              (item) => <String, Object?>{
                'Instalment ID': item.id,
                'Student': item.studentName,
                'Batch': item.batchId,
                'Due date': _date(item.dueDate),
                'Outstanding': _currency(item.outstandingBalance),
              },
            )
            .toList(growable: false),
        calculation: 'An instalment is overdue when its due date has passed and amount due minus recorded payments is greater than zero.',
      ),
    );
  }

  Future<Map<String, Object?>> _prepareReminderDraft(
    Map<String, Object?> args,
  ) async {
    if (!_canReadFees) return _denied('prepare_reminder_draft');
    final installmentId = _text(args, 'fee_installment_id');
    final installments = await _feeService.getInstallmentsForUser(user);
    final installment = installments.cast<FeeInstallment?>().firstWhere(
      (item) => item?.id == installmentId,
      orElse: () => null,
    );
    if (installment == null) {
      return _record(
        CopilotToolResult(
          queryId: 'prepare_reminder_draft',
          source: 'Fee Installments',
          summary: 'No authorized instalment matched "$installmentId".',
          filters: <String, Object?>{'feeInstallmentId': installmentId},
        ),
      );
    }
    if (installment.isPaid || installment.outstandingBalance <= 0) {
      return _record(
        CopilotToolResult(
          queryId: 'prepare_reminder_draft',
          source: 'Fee Installments',
          summary: 'No reminder can be prepared because this instalment is fully paid.',
          filters: <String, Object?>{'feeInstallmentId': installmentId},
        ),
      );
    }
    final message = _reminderDraftService.buildTemplateMessage(
      studentName: installment.studentName,
      outstandingAmount: installment.outstandingBalance,
      dueDate: installment.dueDate,
    );
    return _record(
      CopilotToolResult(
        queryId: 'prepare_reminder_draft',
        source: 'Reminder Drafts / Fee Installments',
        summary: 'A reminder draft preview is ready. Explicit confirmation is required before it is saved; it will not be sent.',
        filters: <String, Object?>{'feeInstallmentId': installment.id},
        rows: <Map<String, Object?>>[
          <String, Object?>{
            'Student': installment.studentName,
            'Outstanding': _currency(installment.outstandingBalance),
            'Due date': _date(installment.dueDate),
            'Message preview': message,
          },
        ],
        actionPreview: CopilotActionPreview(
          type: 'create_reminder_draft',
          title: 'Create reminder draft',
          description:
              'Save a draft for ${installment.studentName} using the current outstanding balance. It will not send a message.',
          payload: <String, Object?>{'feeInstallmentId': installment.id},
        ),
      ),
    );
  }

  Future<Map<String, Object?>> _listTimetable(Map<String, Object?> args) async {
    if (!_canReadTimetable) return _denied('list_timetable');
    final requestedDate =
        _parseDate(_text(args, 'date')) ?? _startOfDay(DateTime.now());
    final batch = _text(args, 'batch');
    final sessions = await _timetableService.getForUser(
      user,
      startDate: requestedDate,
      endDate: _endOfDay(requestedDate),
    );
    final matches = sessions
        .where(
          (item) => _matches(batch, <String>[item.batchId, item.batchName]),
        )
        .where((item) => !item.isCancelled)
        .take(_maxRows)
        .toList(growable: false);
    return _record(
      CopilotToolResult(
        queryId: 'list_timetable',
        source: 'Timetable',
        summary: '${matches.length} permitted scheduled class(es) found.',
        filters: <String, Object?>{
          'date': _date(requestedDate),
          if (batch.isNotEmpty) 'batch': batch,
        },
        rows: matches
            .map(
              (item) => <String, Object?>{
                'Time':
                    '${DateFormat('h:mm a').format(item.startAt)}–${DateFormat('h:mm a').format(item.endAt)}',
                'Batch': item.batchName,
                'Course': item.courseName,
                'Trainer': item.trainerName,
                'Mode': item.deliveryModeLabel,
                'Room': item.roomName,
              },
            )
            .toList(growable: false),
      ),
    );
  }

  Future<Map<String, Object?>> _listRiskAlerts(
    Map<String, Object?> args,
  ) async {
    if (!_canReadRiskAlerts) return _denied('list_risk_alerts');
    final status = _text(args, 'status').toLowerCase();
    final alerts = await _riskAlertService.watchForUser(user).first;
    final matches = alerts
        .where((item) => status.isEmpty || item.status.value == status)
        .take(_maxRows)
        .toList(growable: false);
    return _record(
      CopilotToolResult(
        queryId: 'list_risk_alerts',
        source: 'Risk Alerts',
        summary: '${matches.length} authorized alert(s) matched.',
        filters: <String, Object?>{if (status.isNotEmpty) 'status': status},
        rows: matches
            .map(
              (item) => <String, Object?>{
                'Student': item.studentName,
                'Batch': item.batchName,
                'Alert': item.title,
                'Severity': item.severity.label,
                'Status': item.status.label,
                'Evidence': item.reason,
              },
            )
            .toList(growable: false),
      ),
    );
  }

  Future<Map<String, Object?>> _listApprovalRequests(
    Map<String, Object?> args,
  ) async {
    if (!_canReadApprovals) return _denied('list_approval_requests');
    final status = _text(args, 'status');
    final actions = await _approvalService.getForUser(user, status: status);
    final permitted = actions
        .where((action) {
          return user.role == AppRole.owner ||
              _approvalService.canReview(user, action);
        })
        .take(_maxRows)
        .toList(growable: false);
    return _record(
      CopilotToolResult(
        queryId: 'list_approval_requests',
        source: 'Approvals',
        summary:
            '${permitted.length} approval request(s) available for review.',
        filters: <String, Object?>{if (status.isNotEmpty) 'status': status},
        rows: permitted
            .map(
              (item) => <String, Object?>{
                'Request ID': item.id,
                'Type': item.typeLabel,
                'Title': item.title,
                'Requested by': item.requestedBy,
                'Status': item.statusLabel,
                'Requested': _date(item.requestedAt),
              },
            )
            .toList(growable: false),
      ),
    );
  }

  bool get _canReadAttendance =>
      user.role == AppRole.owner ||
      user.role == AppRole.counselor ||
      user.role == AppRole.trainer;

  bool get _canReadFees =>
      user.role == AppRole.owner || user.role == AppRole.accounts;

  bool get _canReadTimetable =>
      user.role == AppRole.owner ||
      user.role == AppRole.counselor ||
      user.role == AppRole.trainer;

  bool get _canReadRiskAlerts => true;

  bool get _canReadApprovals =>
      user.role == AppRole.owner || user.role == AppRole.accounts;

  Map<String, Object?> _record(CopilotToolResult result) {
    _results.add(result);
    return result.toFunctionResponse();
  }

  Map<String, Object?> _denied(String queryId) => _record(
    CopilotToolResult(
      queryId: queryId,
      source: 'InstituteOS authorization',
      summary: 'This signed-in role is not authorized to access that data.',
      filters: const <String, Object?>{},
    ),
  );

  static String _text(Map<String, Object?> args, String key) =>
      args[key]?.toString().trim() ?? '';

  static double _number(
    Map<String, Object?> args,
    String key, {
    required double fallback,
  }) {
    final value = args[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static List<String> _stringList(Object? value) => value is List
      ? value
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList()
      : const <String>[];

  static bool _matches(String query, Iterable<String> candidates) {
    if (query.trim().isEmpty) return true;
    final normalized = query.trim().toLowerCase();
    return candidates.any((value) => value.toLowerCase().contains(normalized));
  }

  static DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null ? null : _startOfDay(parsed);
  }

  static DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime? _endOfDay(DateTime? value) => value == null
      ? null
      : DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  static String _date(DateTime value) =>
      DateFormat('dd MMM yyyy').format(value);

  static String _currency(double value) => NumberFormat.currency(
    symbol: '₹',
    locale: 'en_IN',
    decimalDigits: 2,
  ).format(value);
}
