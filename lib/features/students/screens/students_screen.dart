import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/batch.dart';
import '../../../data/models/course.dart';
import '../../../data/models/student.dart';
import '../../../data/services/batch_service.dart';
import '../../../data/services/course_service.dart';
import '../../../data/services/student_seed_service.dart';
import '../../../data/services/student_service.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({
    required this.user,
    this.firebaseSetupMessage,
    super.key,
  });

  final AppUser user;
  final String? firebaseSetupMessage;

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  static const _pageSize = 10;

  late final StudentService _studentService;
  late final StudentSeedService _seedService;
  late Stream<List<Student>> _students;
  final TextEditingController _searchController = TextEditingController();

  String? _courseFilter;
  String? _batchFilter;
  String? _statusFilter;
  int _page = 0;
  bool _isSeeding = false;

  bool get _canManage => _studentService.canManage(widget.user);
  bool get _isAccountsView => _studentService.isAccountsView(widget.user);

  @override
  void initState() {
    super.initState();
    _studentService = StudentService();
    _seedService = StudentSeedService();
    _students = _studentService.watchForUser(widget.user);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() => _page = 0);

  void _reload() {
    setState(() => _students = _studentService.watchForUser(widget.user));
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Student>>(
    stream: _students,
    builder: (context, snapshot) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PageHeader(
                user: widget.user,
                canManage: _canManage,
                isSeeding: _isSeeding,
                onAdd: _openStudentForm,
                onLoadSamples: _loadSampleStudents,
              ),
              const SizedBox(height: 18),
              _roleNotice(widget.user.role),
              if (widget.firebaseSetupMessage != null) ...[
                const SizedBox(height: 12),
                _FirebaseSetupNotice(message: widget.firebaseSetupMessage!),
              ],
              const SizedBox(height: 18),
              if (snapshot.hasError)
                _ErrorState(
                  message: _friendlyFirestoreError(snapshot.error!),
                  onRetry: _reload,
                )
              else if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const _LoadingState()
              else
                _buildStudentList(snapshot.data ?? const <Student>[]),
            ],
          ),
        ),
      );
    },
  );

  Widget _roleNotice(AppRole role) => switch (role) {
    AppRole.owner => const _AccessNotice(
      icon: Icons.admin_panel_settings_outlined,
      message: 'Owner access: view, add, edit, archive, and load fictional sample students.',
    ),
    AppRole.counselor => const _AccessNotice(
      icon: Icons.support_agent_outlined,
      message: 'Counselor access: manage only students assigned to this demo counselor account.',
    ),
    AppRole.trainer => const _AccessNotice(
      icon: Icons.visibility_outlined,
      message: 'Trainer access is view-only and shows students assigned to this demo trainer account.',
    ),
    AppRole.accounts => const _AccessNotice(
      icon: Icons.account_balance_wallet_outlined,
      message: 'Accounts access is view-only and presents only fields useful for fee operations.',
    ),
  };

  Widget _buildStudentList(List<Student> students) {
    final courses = students.map((student) => student.courseName).toSet()
      ..removeWhere((value) => value.isEmpty);
    final batches = students.map((student) => student.batchName).toSet()
      ..removeWhere((value) => value.isEmpty);
    final sortedCourses = courses.toList()..sort();
    final sortedBatches = batches.toList()..sort();
    final filtered = students.where(_matchesFilters).toList();
    final totalPages = filtered.isEmpty
        ? 1
        : (filtered.length / _pageSize).ceil();
    final currentPage = _page >= totalPages ? totalPages - 1 : _page;
    final pageStudents = filtered
        .skip(currentPage * _pageSize)
        .take(_pageSize)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StudentFilters(
          searchController: _searchController,
          courses: sortedCourses,
          batches: sortedBatches,
          course: _courseFilter,
          batch: _batchFilter,
          status: _statusFilter,
          onCourseChanged: (value) =>
              setState(() { _courseFilter = value; _page = 0; }),
          onBatchChanged: (value) =>
              setState(() { _batchFilter = value; _page = 0; }),
          onStatusChanged: (value) =>
              setState(() { _statusFilter = value; _page = 0; }),
          onClear: _clearFilters,
          canClear: _hasActiveFilters,
        ),
        const SizedBox(height: 18),
        if (students.isEmpty)
          _EmptyState(
            isOwner: widget.user.role == AppRole.owner,
            isSeeding: _isSeeding,
            onLoadSamples: _loadSampleStudents,
          )
        else if (filtered.isEmpty)
          const _NoMatchesState()
        else ...[
          _StudentTable(
            students: pageStudents,
            accountsView: _isAccountsView,
            canManage: _canManage,
            onView: _openStudentDetails,
            onEdit: _openStudentForm,
            onArchive: _confirmArchive,
          ),
          const SizedBox(height: 12),
          _PaginationBar(
            page: currentPage,
            pageCount: totalPages,
            resultCount: filtered.length,
            onPrevious: currentPage == 0
                ? null
                : () => setState(() => _page = currentPage - 1),
            onNext: currentPage >= totalPages - 1
                ? null
                : () => setState(() => _page = currentPage + 1),
          ),
        ],
      ],
    );
  }

  bool _matchesFilters(Student student) {
    final search = _searchController.text.trim().toLowerCase();
    final isSearchMatch =
        search.isEmpty ||
        student.fullName.toLowerCase().contains(search) ||
        student.id.toLowerCase().contains(search);
    return isSearchMatch &&
        (_courseFilter == null || student.courseName == _courseFilter) &&
        (_batchFilter == null || student.batchName == _batchFilter) &&
        (_statusFilter == null || student.status == _statusFilter);
  }

  bool get _hasActiveFilters =>
      _searchController.text.isNotEmpty ||
      _courseFilter != null ||
      _batchFilter != null ||
      _statusFilter != null;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _courseFilter = null;
      _batchFilter = null;
      _statusFilter = null;
      _page = 0;
    });
  }

  Future<void> _openStudentForm([Student? student]) async {
    if (!_canManage) {
      return;
    }
    final saved = await showDialog<Student>(
      context: context,
      builder: (context) => _StudentFormDialog(
        user: widget.user,
        student: student,
        studentService: _studentService,
      ),
    );
    if (!mounted || saved == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          student == null
              ? '${saved.fullName} was added to Firestore.'
              : '${saved.fullName} was updated in Firestore.',
        ),
      ),
    );
  }

  Future<void> _openStudentDetails(Student student) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _StudentDetailsDialog(
        student: student,
        accountsView: _isAccountsView,
      ),
    );
  }

  Future<void> _confirmArchive(Student student) async {
    if (!_canManage || student.isArchived) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive student?'),
        content: Text(
          '${student.fullName} will remain in Firestore, but their status will be changed to archived.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _studentService.archiveForUser(widget.user, student);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${student.fullName} was archived.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyFirestoreError(error))),
      );
    }
  }

  Future<void> _loadSampleStudents() async {
    if (_isSeeding || widget.user.role != AppRole.owner) {
      return;
    }
    setState(() => _isSeeding = true);
    try {
      final result = await _seedService.loadSampleStudents();
      if (!mounted) {
        return;
      }
      final message = result.collectionAlreadyHadData
          ? 'No sample students were added: the collection already has data. '
                '${result.skippedCount} sample records skipped.'
          : 'Loaded ${result.createdCount} fictional sample students. '
                '${result.skippedCount} records skipped.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyFirestoreError(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSeeding = false);
      }
    }
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.user,
    required this.canManage,
    required this.isSeeding,
    required this.onAdd,
    required this.onLoadSamples,
  });

  final AppUser user;
  final bool canManage;
  final bool isSeeding;
  final VoidCallback onAdd;
  final VoidCallback onLoadSamples;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (user.role == AppRole.owner)
            OutlinedButton.icon(
              onPressed: isSeeding ? null : onLoadSamples,
              icon: isSeeding
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.dataset_outlined),
              label: Text(isSeeding ? 'Loading samples…' : 'Load sample students'),
            ),
          if (canManage)
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add student'),
            ),
        ],
      );
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Student Management',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Search, manage, and retain student records in Cloud Firestore.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
        ],
      );
      if (constraints.maxWidth < 760) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 14), actions],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: title), const SizedBox(width: 16), actions],
      );
    },
  );
}

class _AccessNotice extends StatelessWidget {
  const _AccessNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

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

class _StudentFilters extends StatelessWidget {
  const _StudentFilters({
    required this.searchController,
    required this.courses,
    required this.batches,
    required this.course,
    required this.batch,
    required this.status,
    required this.onCourseChanged,
    required this.onBatchChanged,
    required this.onStatusChanged,
    required this.onClear,
    required this.canClear,
  });

  final TextEditingController searchController;
  final List<String> courses;
  final List<String> batches;
  final String? course;
  final String? batch;
  final String? status;
  final ValueChanged<String?> onCourseChanged;
  final ValueChanged<String?> onBatchChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onClear;
  final bool canClear;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 290,
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Search students',
                hintText: 'Name or student ID',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            width: 190,
            child: _FilterDropdown(
              label: 'Course',
              value: course,
              items: courses,
              onChanged: onCourseChanged,
            ),
          ),
          SizedBox(
            width: 190,
            child: _FilterDropdown(
              label: 'Batch',
              value: batch,
              items: batches,
              onChanged: onBatchChanged,
            ),
          ),
          SizedBox(
            width: 150,
            child: _FilterDropdown(
              label: 'Status',
              value: status,
              items: Student.statuses,
              onChanged: onStatusChanged,
            ),
          ),
          if (canClear)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear'),
            ),
        ],
      ),
    ),
  );
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey('$label-${value ?? 'all'}'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    hint: Text('All $label'),
    items: [
      DropdownMenuItem<String>(value: null, child: Text('All $label')),
      ...items.map(
        (item) => DropdownMenuItem<String>(
          value: item,
          child: Text(item, overflow: TextOverflow.ellipsis),
        ),
      ),
    ],
    onChanged: onChanged,
  );
}

class _StudentTable extends StatelessWidget {
  const _StudentTable({
    required this.students,
    required this.accountsView,
    required this.canManage,
    required this.onView,
    required this.onEdit,
    required this.onArchive,
  });

  final List<Student> students;
  final bool accountsView;
  final bool canManage;
  final ValueChanged<Student> onView;
  final ValueChanged<Student> onEdit;
  final ValueChanged<Student> onArchive;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(const Color(0xFFF6F8FC)),
        columnSpacing: 22,
        columns: [
          const DataColumn(label: Text('STUDENT ID')),
          const DataColumn(label: Text('FULL NAME')),
          if (!accountsView) const DataColumn(label: Text('EMAIL')),
          const DataColumn(label: Text('PHONE')),
          const DataColumn(label: Text('COURSE')),
          const DataColumn(label: Text('BATCH')),
          if (!accountsView) const DataColumn(label: Text('ENROLLMENT DATE')),
          const DataColumn(label: Text('STATUS')),
          const DataColumn(label: Text('ACTIONS')),
        ],
        rows: students
            .map(
              (student) => DataRow(
                onSelectChanged: (_) => onView(student),
                cells: [
                  DataCell(_TableText(student.id, width: 170)),
                  DataCell(_TableText(student.fullName, width: 160, bold: true)),
                  if (!accountsView)
                    DataCell(_TableText(student.email, width: 210)),
                  DataCell(_TableText(student.phone, width: 130)),
                  DataCell(_TableText(student.courseName, width: 180)),
                  DataCell(_TableText(student.batchName, width: 150)),
                  if (!accountsView)
                    DataCell(Text(_formatDate(student.enrollmentDate))),
                  DataCell(_StatusPill(status: student.status)),
                  DataCell(
                    _StudentActions(
                      student: student,
                      canManage: canManage,
                      onView: () => onView(student),
                      onEdit: () => onEdit(student),
                      onArchive: () => onArchive(student),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    ),
  );
}

class _TableText extends StatelessWidget {
  const _TableText(this.value, {required this.width, this.bold = false});

  final String value;
  final double width;
  final bool bold;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Text(
      value.isEmpty ? '—' : value,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400),
    ),
  );
}

class _StudentActions extends StatelessWidget {
  const _StudentActions({
    required this.student,
    required this.canManage,
    required this.onView,
    required this.onEdit,
    required this.onArchive,
  });

  final Student student;
  final bool canManage;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_StudentAction>(
    tooltip: 'Student actions',
    onSelected: (action) => switch (action) {
      _StudentAction.view => onView(),
      _StudentAction.edit => onEdit(),
      _StudentAction.archive => onArchive(),
    },
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: _StudentAction.view,
        child: ListTile(
          leading: Icon(Icons.visibility_outlined),
          title: Text('View'),
        ),
      ),
      if (canManage) ...[
        const PopupMenuItem(
          value: _StudentAction.edit,
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit'),
          ),
        ),
        if (!student.isArchived)
          const PopupMenuItem(
            value: _StudentAction.archive,
            child: ListTile(
              leading: Icon(Icons.archive_outlined),
              title: Text('Archive'),
            ),
          ),
      ],
    ],
    icon: const Icon(Icons.more_horiz_rounded),
  );
}

enum _StudentAction { view, edit, archive }

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.page,
    required this.pageCount,
    required this.resultCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int pageCount;
  final int resultCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        '$resultCount result${resultCount == 1 ? '' : 's'} · Page ${page + 1} of $pageCount',
        style: TextStyle(color: Colors.blueGrey.shade700),
      ),
      const Spacer(),
      IconButton(
        tooltip: 'Previous page',
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      IconButton(
        tooltip: 'Next page',
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ],
  );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(48),
      child: Center(child: CircularProgressIndicator()),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isOwner,
    required this.isSeeding,
    required this.onLoadSamples,
  });

  final bool isOwner;
  final bool isSeeding;
  final VoidCallback onLoadSamples;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.people_outline_rounded, size: 46, color: AppTheme.brand),
          const SizedBox(height: 14),
          Text(
            'No students yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            isOwner
                ? 'Add a student or load fictional sample records to create the collection.'
                : 'No student records are assigned to this demo role.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
          if (isOwner) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: isSeeding ? null : onLoadSamples,
              icon: const Icon(Icons.dataset_outlined),
              label: const Text('Load sample students'),
            ),
          ],
        ],
      ),
    ),
  );
}

class _NoMatchesState extends StatelessWidget {
  const _NoMatchesState();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, size: 42, color: AppTheme.brand),
          const SizedBox(height: 12),
          Text(
            'No students match these filters.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 42),
          const SizedBox(height: 12),
          Text(
            'Unable to load students',
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

class _StudentFormDialog extends StatefulWidget {
  const _StudentFormDialog({
    required this.user,
    required this.student,
    required this.studentService,
  });

  final AppUser user;
  final Student? student;
  final StudentService studentService;

  @override
  State<_StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<_StudentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _courseController;
  late final TextEditingController _batchController;
  late DateTime _enrollmentDate;
  late String _status;
  bool _isSaving = false;

  List<Course> _courses = <Course>[];
  List<Batch> _batches = <Batch>[];
  String? _selectedCourseId;
  String? _selectedBatchId;
  bool _loadingOptions = true;

  @override
  void initState() {
    super.initState();
    final student = widget.student;
    _nameController = TextEditingController(text: student?.fullName ?? '');
    _emailController = TextEditingController(text: student?.email ?? '');
    _phoneController = TextEditingController(text: student?.phone ?? '');
    _courseController = TextEditingController(text: student?.courseName ?? '');
    _batchController = TextEditingController(text: student?.batchName ?? '');
    _selectedCourseId = student?.courseId;
    _selectedBatchId = student?.batchId;
    _enrollmentDate = student?.enrollmentDate ?? DateTime.now();
    _status = student?.status ?? 'active';
    _loadCourseBatchOptions();
  }

  Future<void> _loadCourseBatchOptions() async {
    try {
      final courses = await CourseService().getForUser(widget.user);
      final batches = await BatchService().getForUser(widget.user);
      if (mounted) {
        setState(() {
          _courses = courses;
          _batches = batches;
          _loadingOptions = false;

          // Try matching course by id or name
          if (_selectedCourseId == null || _selectedCourseId!.isEmpty) {
            final match = courses.where(
              (c) => c.name.toLowerCase() == _courseController.text.trim().toLowerCase(),
            );
            if (match.isNotEmpty) {
              _selectedCourseId = match.first.id;
            }
          }
          // Try matching batch by id or name
          if (_selectedBatchId == null || _selectedBatchId!.isEmpty) {
            final match = batches.where(
              (b) => b.name.toLowerCase() == _batchController.text.trim().toLowerCase(),
            );
            if (match.isNotEmpty) {
              _selectedBatchId = match.first.id;
            }
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingOptions = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _courseController.dispose();
    _batchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeCourses = _courses.where((c) => !c.isArchived).toList();
    if (widget.student != null &&
        _selectedCourseId != null &&
        !activeCourses.any((c) => c.id == _selectedCourseId)) {
      final existing = _courses.where((c) => c.id == _selectedCourseId);
      if (existing.isNotEmpty) activeCourses.add(existing.first);
    }

    final availableBatches = _batches.where((b) {
      final matchesCourse = _selectedCourseId == null || b.courseId == _selectedCourseId;
      final isActive = !b.isArchived || b.id == _selectedBatchId;
      return matchesCourse && isActive;
    }).toList();

    return AlertDialog(
      title: Text(widget.student == null ? 'Add student' : 'Edit student'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: _emailValidator,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 14),
                if (!_loadingOptions && activeCourses.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('student-course-$_selectedCourseId'),
                    initialValue: _selectedCourseId,
                    decoration: const InputDecoration(labelText: 'Course'),
                    hint: const Text('Select a course'),
                    items: activeCourses
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (val) {
                            setState(() {
                              _selectedCourseId = val;
                              final match = _courses.where((c) => c.id == val);
                              if (match.isNotEmpty) {
                                _courseController.text = match.first.name;
                              }
                              _selectedBatchId = null;
                              _batchController.clear();
                            });
                          },
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Please select a course.' : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    key: ValueKey('student-batch-$_selectedBatchId-$_selectedCourseId'),
                    initialValue: _selectedBatchId,
                    decoration: const InputDecoration(labelText: 'Batch'),
                    hint: Text(
                      _selectedCourseId == null
                          ? 'Select a course first'
                          : availableBatches.isEmpty
                              ? 'No active batches for this course'
                              : 'Select a batch',
                    ),
                    items: availableBatches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(b.name),
                          ),
                        )
                        .toList(),
                    onChanged: _isSaving || availableBatches.isEmpty
                        ? null
                        : (val) {
                            setState(() {
                              _selectedBatchId = val;
                              final match = _batches.where((b) => b.id == val);
                              if (match.isNotEmpty) {
                                _batchController.text = match.first.name;
                              }
                            });
                          },
                    validator: (val) =>
                        val == null || val.isEmpty ? 'Please select a batch.' : null,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _courseController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Course'),
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _batchController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Batch'),
                    validator: _requiredValidator,
                  ),
                ],
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickEnrollmentDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Enrollment date',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(_formatDate(_enrollmentDate)),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: Student.statuses
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(_capitalized(status)),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _status = value ?? 'active'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(widget.student == null ? 'Add student' : 'Save changes'),
        ),
      ],
    );
  }

  Future<void> _pickEnrollmentDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _enrollmentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (selected != null && mounted) {
      setState(() => _enrollmentDate = selected);
    }
  }

  Future<void> _save() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final now = DateTime.now();

    final selectedCourse = _courses.cast<Course?>().firstWhere(
      (c) => c?.id == _selectedCourseId,
      orElse: () => null,
    );
    final selectedBatch = _batches.cast<Batch?>().firstWhere(
      (b) => b?.id == _selectedBatchId,
      orElse: () => null,
    );

    final courseName = selectedCourse?.name ?? _courseController.text.trim();
    final courseId = selectedCourse?.id ??
        (widget.student?.courseName == courseName && widget.student!.courseId.isNotEmpty
            ? widget.student!.courseId
            : Student.identifierFromName(courseName));

    final batchName = selectedBatch?.name ?? _batchController.text.trim();
    final batchId = selectedBatch?.id ??
        (widget.student?.batchName == batchName && widget.student!.batchId.isNotEmpty
            ? widget.student!.batchId
            : Student.identifierFromName(batchName));

    final draft = Student(
      id: widget.student?.id ?? '',
      instituteId: widget.student?.instituteId ?? 'demo-institute',
      fullName: _nameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      phone: _phoneController.text.trim(),
      courseId: courseId,
      courseName: courseName,
      batchId: batchId,
      batchName: batchName,
      enrollmentDate: _enrollmentDate,
      status: _status,
      createdAt: widget.student?.createdAt ?? now,
      updatedAt: now,
      counselorId: widget.student?.counselorId,
      trainerId: selectedBatch?.trainerId ?? widget.student?.trainerId,
    );
    setState(() => _isSaving = true);
    try {
      final saved = widget.student == null
          ? await widget.studentService.createForUser(widget.user, draft)
          : await widget.studentService.updateForUser(widget.user, draft);
      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyFirestoreError(error))),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  String? _requiredValidator(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required.';
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())) {
      return 'Enter a valid email address.';
    }
    return null;
  }
}

class _StudentDetailsDialog extends StatelessWidget {
  const _StudentDetailsDialog({
    required this.student,
    required this.accountsView,
  });

  final Student student;
  final bool accountsView;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Expanded(child: Text(student.fullName)),
        _StatusPill(status: student.status),
      ],
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DetailRow(label: 'Student ID', value: student.id),
            _DetailRow(label: 'Full name', value: student.fullName),
            if (!accountsView) _DetailRow(label: 'Email', value: student.email),
            _DetailRow(label: 'Phone number', value: student.phone),
            _DetailRow(label: 'Course', value: student.courseName),
            _DetailRow(label: 'Batch', value: student.batchName),
            if (!accountsView)
              _DetailRow(
                label: 'Enrollment date',
                value: _formatDate(student.enrollmentDate),
              ),
            if (!accountsView)
              _DetailRow(label: 'Institute ID', value: student.instituteId),
            if (!accountsView)
              _DetailRow(label: 'Created', value: _formatDateTime(student.createdAt)),
            if (!accountsView)
              _DetailRow(label: 'Last updated', value: _formatDateTime(student.updatedAt)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.blueGrey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: Text(value.isEmpty ? '—' : value)),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => const Color(0xFF047857),
      'inactive' => const Color(0xFFD97706),
      _ => const Color(0xFF6B7280),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _capitalized(status),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

String _friendlyFirestoreError(Object error) {
  if (error is FirebaseException) {
    final detail = error.message?.trim();
    if (detail != null && detail.isNotEmpty) {
      return 'Firestore ${error.code}: $detail';
    }
    return 'Firestore ${error.code}. Check Firebase setup and security rules.';
  }
  return 'Could not complete the database request. Please try again.';
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')} ${_monthName(date.month)} ${date.year}';

String _formatDateTime(DateTime date) =>
    '${_formatDate(date)} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String _monthName(int month) => const <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][month - 1];

String _capitalized(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
