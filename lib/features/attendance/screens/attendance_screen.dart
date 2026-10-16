import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/batch.dart';
import '../../../data/models/student.dart';
import '../../../data/services/attendance_service.dart';
import '../../../data/services/batch_service.dart';
import '../../../data/services/student_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    required this.user,
    this.batchService,
    this.firebaseSetupMessage,
    super.key,
  });

  final AppUser user;
  final BatchService? batchService;
  final String? firebaseSetupMessage;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final StudentService _studentService;
  late final AttendanceService _attendanceService;
  late final BatchService _batchService;
  late Stream<List<Student>> _students;
  late Stream<List<AttendanceRecord>> _history;
  late Stream<List<Batch>> _batches;

  DateTime _classDate = DateTime.now();
  DateTime? _historyDate;
  String? _selectedBatchId;
  String? _historyBatchId;
  Map<String, AttendanceStatus> _statuses = <String, AttendanceStatus>{};
  Map<String, AttendanceRecord> _existingRecords =
      <String, AttendanceRecord>{};
  bool _isSessionLoading = false;
  bool _isSaving = false;
  Object? _sessionError;
  int _sessionRequest = 0;

  bool get _canManage => _attendanceService.canManage(widget.user);
  bool get _isAccounts => widget.user.role == AppRole.accounts;

  @override
  void initState() {
    super.initState();
    _studentService = StudentService();
    _attendanceService = AttendanceService();
    _batchService = widget.batchService ?? BatchService();
    _students = _studentService.watchForUser(widget.user);
    _history = _attendanceService.watchHistoryForUser(widget.user);
    _batches = _batchService.watchForUser(widget.user);
  }

  void _reloadStudents() {
    setState(() => _students = _studentService.watchForUser(widget.user));
  }

  void _reloadBatches() {
    setState(() => _batches = _batchService.watchForUser(widget.user));
  }

  void _reloadHistory() {
    setState(() => _history = _attendanceService.watchHistoryForUser(widget.user));
  }

  @override
  Widget build(BuildContext context) {
    if (_isAccounts) {
      return const _AccountsNoAccess();
    }
    return StreamBuilder<List<Batch>>(
      stream: _batches,
      builder: (context, batchesSnapshot) {
        if (batchesSnapshot.hasError) {
          return _AttendancePage(
            child: _ErrorState(
              title: 'Unable to load batches',
              message: _friendlyError(batchesSnapshot.error!),
              onRetry: _reloadBatches,
            ),
          );
        }
        if (!batchesSnapshot.hasData) {
          return const _AttendancePage(child: _LoadingState());
        }
        final realBatches = batchesSnapshot.data!;

        return StreamBuilder<List<Student>>(
          stream: _students,
          builder: (context, studentsSnapshot) {
            if (studentsSnapshot.hasError) {
              return _AttendancePage(
                child: _ErrorState(
                  title: 'Unable to load enrolled students',
                  message: _friendlyError(studentsSnapshot.error!),
                  onRetry: _reloadStudents,
                ),
              );
            }
            if (!studentsSnapshot.hasData) {
              return const _AttendancePage(child: _LoadingState());
            }
            return _buildWithStudents(studentsSnapshot.data!, realBatches);
          },
        );
      },
    );
  }

  Widget _buildWithStudents(List<Student> students, List<Batch> realBatches) {
    final activeBatches = realBatches
        .where((b) => !b.isArchived)
        .map((b) => _BatchOption(id: b.id, name: b.name))
        .toList();
    final allBatches = realBatches
        .map((b) => _BatchOption(id: b.id, name: b.name))
        .toList();

    final selectedBatchAvailable = activeBatches.any(
      (batch) => batch.id == _selectedBatchId,
    );
    final selectedBatchId = selectedBatchAvailable ? _selectedBatchId : null;
    final selectedBatchStudents = _studentsForBatch(students, selectedBatchId);

    return _AttendancePage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeader(user: widget.user, canManage: _canManage),
          const SizedBox(height: 18),
          _roleNotice(widget.user.role),
          if (widget.firebaseSetupMessage != null) ...[
            const SizedBox(height: 12),
            _FirebaseSetupNotice(message: widget.firebaseSetupMessage!),
          ],
          const SizedBox(height: 18),
          if (activeBatches.isEmpty)
            _NoBatchesAvailableState(canManage: _canManage)
          else ...[
            _SessionControls(
              batches: activeBatches,
              selectedBatchId: selectedBatchId,
              classDate: _classDate,
              onBatchChanged: (batchId) =>
                  _selectBatch(batchId, students),
              onDatePressed: () => _pickClassDate(students),
            ),
            const SizedBox(height: 18),
            if (selectedBatchId == null)
              const _ChooseBatchState()
            else
              _buildSession(
                selectedBatchStudents,
                activeBatches.firstWhere((batch) => batch.id == selectedBatchId),
              ),
            const SizedBox(height: 28),
            _buildHistory(students, allBatches),
          ],
        ],
      ),
    );
  }

  Widget _buildSession(List<Student> students, _BatchOption batch) {
    if (_isSessionLoading) {
      return const _LoadingState(label: 'Loading saved attendance…');
    }
    if (_sessionError != null) {
      return _ErrorState(
        title: 'Unable to load this attendance session',
        message: _friendlyError(_sessionError!),
        onRetry: () => _loadSession(batch.id, students),
      );
    }
    if (students.isEmpty) {
      return const _NoEnrolledStudentsState();
    }

    final statusValues = students
        .map((student) => _statusFor(student.id))
        .whereType<AttendanceStatus>();
    final counts = _attendanceService.countsFor(statusValues);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SessionSummary(
          batchName: batch.name,
          classDate: _classDate,
          counts: counts,
          savedRecordCount: _existingRecords.length,
          canManage: _canManage,
          isSaving: _isSaving,
          onSave: () => _saveSession(batch.id, students),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: students
                  .map(
                    (student) => _AttendanceStudentRow(
                      student: student,
                      status: _statusFor(student.id),
                      canManage: _canManage,
                      onStatusChanged: (status) => setState(
                        () => _statuses[student.id] = status,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory(List<Student> students, List<_BatchOption> batches) =>
      StreamBuilder<List<AttendanceRecord>>(
        stream: _history,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(
              title: 'Unable to load attendance history',
              message: _friendlyError(snapshot.error!),
              onRetry: _reloadHistory,
            );
          }
          if (!snapshot.hasData) {
            return const _LoadingState(label: 'Loading attendance history…');
          }
          final filtered = snapshot.data!
              .where(
                (record) =>
                    (_historyBatchId == null ||
                        record.batchId == _historyBatchId) &&
                    (_historyDate == null ||
                        _sameDate(record.classDate, _historyDate!)),
              )
              .toList();
          final counts = _attendanceService.countsFor(
            filtered.map((record) => record.status),
          );
          final percentages = {
            for (final item in _attendanceService.percentagesFor(filtered))
              item.studentId: item,
          };
          final studentNames = {
            for (final student in students) student.id: student.fullName,
          };
          final batchNames = {for (final batch in batches) batch.id: batch.name};

          return _HistorySection(
            batches: batches,
            selectedBatchId: _historyBatchId,
            selectedDate: _historyDate,
            records: filtered,
            counts: counts,
            studentNames: studentNames,
            batchNames: batchNames,
            percentages: percentages,
            onBatchChanged: (value) => setState(() => _historyBatchId = value),
            onDatePressed: _pickHistoryDate,
            onClearDate: () => setState(() => _historyDate = null),
          );
        },
      );

  List<Student> _studentsForBatch(List<Student> students, String? batchId) => students
      .where(
        (student) =>
            student.status == 'active' && student.batchId == batchId,
      )
      .toList()
    ..sort((left, right) => left.fullName.compareTo(right.fullName));

  AttendanceStatus? _statusFor(String studentId) {
    final saved = _statuses[studentId];
    if (saved != null) {
      return saved;
    }
    return _canManage ? AttendanceStatus.present : null;
  }

  Future<void> _selectBatch(String? batchId, List<Student> students) async {
    setState(() {
      _selectedBatchId = batchId;
      _statuses = <String, AttendanceStatus>{};
      _existingRecords = <String, AttendanceRecord>{};
      _sessionError = null;
    });
    if (batchId != null) {
      await _loadSession(batchId, _studentsForBatch(students, batchId));
    }
  }

  Future<void> _pickClassDate(List<Student> students) async {
    final now = DateTime.now();
    final initialDate = _classDate.isAfter(now) ? now : _classDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _classDate = picked);
    if (_selectedBatchId != null) {
      await _loadSession(
        _selectedBatchId!,
        _studentsForBatch(students, _selectedBatchId),
      );
    }
  }

  Future<void> _loadSession(String batchId, List<Student> students) async {
    final request = ++_sessionRequest;
    setState(() {
      _isSessionLoading = true;
      _sessionError = null;
    });
    try {
      final records = await _attendanceService.loadSessionForUser(
        user: widget.user,
        batchId: batchId,
        classDate: _classDate,
        students: students,
      );
      if (!mounted || request != _sessionRequest) {
        return;
      }
      final existing = {for (final record in records) record.studentId: record};
      final statuses = <String, AttendanceStatus>{
        for (final record in records) record.studentId: record.status,
      };
      if (_canManage) {
        for (final student in students) {
          statuses.putIfAbsent(student.id, () => AttendanceStatus.present);
        }
      }
      setState(() {
        _existingRecords = existing;
        _statuses = statuses;
      });
    } catch (error) {
      if (mounted && request == _sessionRequest) {
        setState(() => _sessionError = error);
      }
    } finally {
      if (mounted && request == _sessionRequest) {
        setState(() => _isSessionLoading = false);
      }
    }
  }

  Future<void> _saveSession(String batchId, List<Student> students) async {
    if (!_canManage || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final count = await _attendanceService.saveSessionForUser(
        user: widget.user,
        batchId: batchId,
        classDate: _classDate,
        students: students,
        statuses: _statuses,
        existingRecords: _existingRecords,
      );
      await _loadSession(batchId, students);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Attendance saved for $count students.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickHistoryDate() async {
    final now = DateTime.now();
    final rawInitial = _historyDate ?? _classDate;
    final initialDate = rawInitial.isAfter(now) ? now : rawInitial;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _historyDate = picked);
    }
  }
}

class _AttendancePage extends StatelessWidget {
  const _AttendancePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1440),
      child: child,
    ),
  );
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.user, required this.canManage});

  final AppUser user;
  final bool canManage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Attendance Management',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          color: AppTheme.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        canManage
            ? 'Load a batch, record its class session, and revisit it safely.'
            : 'Review recorded attendance for students available to your demo role.',
        style: TextStyle(color: Colors.blueGrey.shade600),
      ),
    ],
  );
}

class _SessionControls extends StatelessWidget {
  const _SessionControls({
    required this.batches,
    required this.selectedBatchId,
    required this.classDate,
    required this.onBatchChanged,
    required this.onDatePressed,
  });

  final List<_BatchOption> batches;
  final String? selectedBatchId;
  final DateTime classDate;
  final ValueChanged<String?> onBatchChanged;
  final VoidCallback onDatePressed;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              key: ValueKey('batch-$selectedBatchId'),
              initialValue: selectedBatchId,
              decoration: const InputDecoration(
                labelText: 'Batch',
                prefixIcon: Icon(Icons.groups_outlined),
              ),
              hint: const Text('Select a batch'),
              items: batches
                  .map(
                    (batch) => DropdownMenuItem(
                      value: batch.id,
                      child: Text(batch.name),
                    ),
                  )
                  .toList(),
              onChanged: onBatchChanged,
            ),
          ),
          SizedBox(
            width: 220,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onDatePressed,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Class date',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                child: Text(_formatDate(classDate)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({
    required this.batchName,
    required this.classDate,
    required this.counts,
    required this.savedRecordCount,
    required this.canManage,
    required this.isSaving,
    required this.onSave,
  });

  final String batchName;
  final DateTime classDate;
  final AttendanceCounts counts;
  final int savedRecordCount;
  final bool canManage;
  final bool isSaving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$batchName · ${_formatDate(classDate)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    savedRecordCount == 0
                        ? 'No records have been saved for this session yet.'
                        : '$savedRecordCount saved records loaded. Saving updates the same records.',
                    style: TextStyle(color: Colors.blueGrey.shade600),
                  ),
                ],
              ),
              _CountBadge(
                label: 'Present',
                value: counts.present,
                color: const Color(0xFF047857),
              ),
              _CountBadge(
                label: 'Absent',
                value: counts.absent,
                color: const Color(0xFFB42318),
              ),
              _CountBadge(
                label: 'Late',
                value: counts.late,
                color: const Color(0xFFD97706),
              ),
              if (canManage)
                FilledButton.icon(
                  onPressed: isSaving ? null : onSave,
                  icon: isSaving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(isSaving ? 'Saving…' : 'Save attendance'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            canManage
                ? 'Selections are not attendance records until Save Attendance confirms the write.'
                : 'Only recorded statuses are shown. Students without a record are not treated as absent.',
            style: const TextStyle(color: Color(0xFF526277), fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '$label $value',
      style: TextStyle(color: color, fontWeight: FontWeight.w800),
    ),
  );
}

class _AttendanceStudentRow extends StatelessWidget {
  const _AttendanceStudentRow({
    required this.student,
    required this.status,
    required this.canManage,
    required this.onStatusChanged,
  });

  final Student student;
  final AttendanceStatus? status;
  final bool canManage;
  final ValueChanged<AttendanceStatus> onStatusChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFE8F0FF),
          child: Text(
            student.fullName.isEmpty ? '?' : student.fullName.substring(0, 1),
            style: const TextStyle(
              color: AppTheme.brand,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                student.fullName,
                style: const TextStyle(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Student ID: ${student.id}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (canManage)
          Wrap(
            spacing: 6,
            children: AttendanceStatus.values
                .map(
                  (option) => ChoiceChip(
                    label: Text(option.label),
                    selected: status == option,
                    selectedColor: _statusColor(option).withValues(alpha: .17),
                    labelStyle: TextStyle(
                      color: status == option
                          ? _statusColor(option)
                          : Colors.blueGrey.shade700,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => onStatusChanged(option),
                  ),
                )
                .toList(),
          )
        else
          _AttendanceStatusChip(status: status),
      ],
    ),
  );
}

class _AttendanceStatusChip extends StatelessWidget {
  const _AttendanceStatusChip({required this.status});

  final AttendanceStatus? status;

  @override
  Widget build(BuildContext context) {
    if (status == null) {
      return const Text(
        'Not recorded',
        style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700),
      );
    }
    final color = _statusColor(status!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status!.label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.batches,
    required this.selectedBatchId,
    required this.selectedDate,
    required this.records,
    required this.counts,
    required this.studentNames,
    required this.batchNames,
    required this.percentages,
    required this.onBatchChanged,
    required this.onDatePressed,
    required this.onClearDate,
  });

  final List<_BatchOption> batches;
  final String? selectedBatchId;
  final DateTime? selectedDate;
  final List<AttendanceRecord> records;
  final AttendanceCounts counts;
  final Map<String, String> studentNames;
  final Map<String, String> batchNames;
  final Map<String, StudentAttendancePercentage> percentages;
  final ValueChanged<String?> onBatchChanged;
  final VoidCallback onDatePressed;
  final VoidCallback onClearDate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Attendance History',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: AppTheme.ink,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 5),
      const Tooltip(
        message:
            'Percentage = Present sessions ÷ all recorded Present, Absent, and Late sessions × 100. Unrecorded students are excluded.',
        child: Text(
          'Percentages count only recorded statuses: Present ÷ (Present + Absent + Late).',
          style: TextStyle(color: Color(0xFF526277)),
        ),
      ),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('history-batch-$selectedBatchId'),
                  initialValue: selectedBatchId,
                  decoration: const InputDecoration(labelText: 'Filter by batch'),
                  hint: const Text('All batches'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('All batches'),
                    ),
                    ...batches.map(
                      (batch) => DropdownMenuItem(
                        value: batch.id,
                        child: Text(batch.name),
                      ),
                    ),
                  ],
                  onChanged: onBatchChanged,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onDatePressed,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  selectedDate == null
                      ? 'Filter by date'
                      : _formatDate(selectedDate!),
                ),
              ),
              if (selectedDate != null)
                TextButton.icon(
                  onPressed: onClearDate,
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear date'),
                ),
              _CountBadge(
                label: 'Present',
                value: counts.present,
                color: const Color(0xFF047857),
              ),
              _CountBadge(
                label: 'Absent',
                value: counts.absent,
                color: const Color(0xFFB42318),
              ),
              _CountBadge(
                label: 'Late',
                value: counts.late,
                color: const Color(0xFFD97706),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      if (records.isEmpty)
        const _NoHistoryState()
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(const Color(0xFFF6F8FC)),
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('CLASS DATE')),
                DataColumn(label: Text('BATCH')),
                DataColumn(label: Text('STUDENT')),
                DataColumn(label: Text('STATUS')),
                DataColumn(label: Text('ATTENDANCE %')),
              ],
              rows: records
                  .map(
                    (record) => DataRow(
                      cells: [
                        DataCell(Text(_formatDate(record.classDate))),
                        DataCell(
                          SizedBox(
                            width: 170,
                            child: Text(
                              batchNames[record.batchId] ?? record.batchId,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 220,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  studentNames[record.studentId] ?? record.studentId,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  record.studentId,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.blueGrey.shade600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(_AttendanceStatusChip(status: record.status)),
                        DataCell(
                          Text(
                            '${(percentages[record.studentId]?.value ?? 0).toStringAsFixed(1)}%',
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
    ],
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({this.label = 'Loading attendance…'});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(label),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 42),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

class _NoBatchesAvailableState extends StatelessWidget {
  const _NoBatchesAvailableState({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.groups_outlined, size: 44, color: AppTheme.brand),
          const SizedBox(height: 12),
          Text(
            'No batches available in Firestore',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            canManage
                ? 'Create a batch in Course & Batch Management before recording attendance.'
                : 'Batches will appear here once created by an Owner.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
        ],
      ),
    ),
  );
}

class _ChooseBatchState extends StatelessWidget {
  const _ChooseBatchState();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(36),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.touch_app_outlined, color: AppTheme.brand),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text('Select a batch to load students and its saved class attendance.'),
          ),
        ],
      ),
    ),
  );
}

class _NoEnrolledStudentsState extends StatelessWidget {
  const _NoEnrolledStudentsState();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(36),
      child: Center(
        child: Text('This batch has no active enrolled students to record.'),
      ),
    ),
  );
}

class _NoHistoryState extends StatelessWidget {
  const _NoHistoryState();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(38),
      child: Column(
        children: [
          Icon(Icons.history_toggle_off_rounded, size: 42, color: AppTheme.brand),
          SizedBox(height: 12),
          Text('No recorded attendance matches these filters.'),
        ],
      ),
    ),
  );
}

class _AccountsNoAccess extends StatelessWidget {
  const _AccountsNoAccess();

  @override
  Widget build(BuildContext context) => const _AttendancePage(
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(42),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline_rounded, size: 46, color: AppTheme.brand),
            SizedBox(height: 14),
            Text(
              'Attendance is not available to Accounts Staff.',
              style: TextStyle(
                color: AppTheme.ink,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This demo role has no attendance editing or unrestricted attendance history.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}

class _FirebaseSetupNotice extends StatelessWidget {
  const _FirebaseSetupNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E5),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.warning_amber_rounded, color: Color(0xFF9A6700)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: const TextStyle(color: Color(0xFF7A4B00))),
        ),
      ],
    ),
  );
}

class _RoleNotice extends StatelessWidget {
  const _RoleNotice({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppTheme.brand, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: const TextStyle(color: AppTheme.ink))),
      ],
    ),
  );
}

Widget _roleNotice(AppRole role) => switch (role) {
  AppRole.owner => const _RoleNotice(
    icon: Icons.admin_panel_settings_outlined,
    message: 'Owner access: review and manage attendance across the institute.',
  ),
  AppRole.counselor => const _RoleNotice(
    icon: Icons.visibility_outlined,
    message: 'Counselor access: review recorded attendance for assigned students only.',
  ),
  AppRole.trainer => const _RoleNotice(
    icon: Icons.fact_check_outlined,
    message: 'Trainer access: mark and edit attendance only for students in assigned batches.',
  ),
  AppRole.accounts => const _RoleNotice(
    icon: Icons.lock_outline_rounded,
    message: 'Accounts Staff does not have attendance access.',
  ),
};

class _BatchOption {
  const _BatchOption({required this.id, required this.name});

  final String id;
  final String name;
}

Color _statusColor(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => const Color(0xFF047857),
  AttendanceStatus.absent => const Color(0xFFB42318),
  AttendanceStatus.late => const Color(0xFFD97706),
};

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')} ${_monthName(value.month)} ${value.year}';

String _monthName(int month) => const <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][month - 1];

bool _sameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

String _friendlyError(Object error) {
  if (error is AttendanceAccessException) {
    return error.message;
  }
  if (error is FirebaseException) {
    final detail = error.message?.trim();
    return detail == null || detail.isEmpty
        ? 'Firestore ${error.code}. Check Firebase setup and security rules.'
        : 'Firestore ${error.code}: $detail';
  }
  return 'Could not complete the attendance database request. Please try again.';
}
