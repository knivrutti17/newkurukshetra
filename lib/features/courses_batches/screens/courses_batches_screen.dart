import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/app_user.dart';
import '../../../data/models/batch.dart';
import '../../../data/models/course.dart';
import '../../../data/models/student.dart';
import '../../../data/services/batch_service.dart';
import '../../../data/services/course_batch_seed_service.dart';
import '../../../data/services/course_service.dart';
import '../../../data/services/student_service.dart';

class CoursesBatchesScreen extends StatefulWidget {
  const CoursesBatchesScreen({
    required this.user,
    this.initialTab = 0,
    this.firebaseSetupMessage,
    this.courseService,
    this.batchService,
    this.seedService,
    this.studentService,
    super.key,
  });

  final AppUser user;
  final int initialTab;
  final String? firebaseSetupMessage;
  final CourseService? courseService;
  final BatchService? batchService;
  final CourseBatchSeedService? seedService;
  final StudentService? studentService;

  @override
  State<CoursesBatchesScreen> createState() => _CoursesBatchesScreenState();
}

class _CoursesBatchesScreenState extends State<CoursesBatchesScreen>
    with SingleTickerProviderStateMixin {
  late final CourseService _courseService;
  late final BatchService _batchService;
  late final CourseBatchSeedService _seedService;
  late final StudentService _studentService;
  late final TabController _tabController;

  late Stream<List<Course>> _coursesStream;
  late Stream<List<Batch>> _batchesStream;
  late Stream<List<Student>> _studentsStream;

  bool _isSeeding = false;

  bool get _canManage => _courseService.canManage(widget.user);
  bool get _isTrainer => widget.user.role == AppRole.trainer;

  @override
  void initState() {
    super.initState();
    _courseService = widget.courseService ?? CourseService();
    _batchService = widget.batchService ?? BatchService();
    _seedService = widget.seedService ?? CourseBatchSeedService();
    _studentService = widget.studentService ?? StudentService();

    final tabIndex = _isTrainer ? 1 : widget.initialTab.clamp(0, 1);
    _tabController = TabController(length: 2, vsync: this, initialIndex: tabIndex);

    _coursesStream = _courseService.watchForUser(widget.user);
    _batchesStream = _batchService.watchForUser(widget.user);
    _studentsStream = _studentService.watchForUser(widget.user);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reloadCourses() {
    setState(() => _coursesStream = _courseService.watchForUser(widget.user));
  }

  void _reloadBatches() {
    setState(() => _batchesStream = _batchService.watchForUser(widget.user));
  }

  Future<void> _loadSampleData() async {
    if (_isSeeding) return;
    setState(() => _isSeeding = true);
    try {
      final result = await _seedService.loadSampleData();
      if (!mounted) return;
      if (result.alreadyHadData) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sample data check: Courses and Batches already have existing records.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sample data loaded: ${result.coursesCreated} courses and ${result.batchesCreated} batches created.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sample data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1440),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            user: widget.user,
            canManage: _canManage,
            isSeeding: _isSeeding,
            onLoadSamples: _canManage ? _loadSampleData : null,
          ),
          const SizedBox(height: 16),
          _RoleBanner(role: widget.user.role),
          if (widget.firebaseSetupMessage != null) ...[
            const SizedBox(height: 12),
            _NoticeBox(
              message: widget.firebaseSetupMessage!,
              icon: Icons.warning_amber_rounded,
              background: const Color(0xFFFFF3E5),
              textColor: const Color(0xFF7A4B00),
            ),
          ],
          const SizedBox(height: 18),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.brand,
            unselectedLabelColor: Colors.blueGrey.shade600,
            indicatorColor: AppTheme.brand,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(icon: Icon(Icons.school_outlined), text: 'Courses'),
              Tab(icon: Icon(Icons.groups_outlined), text: 'Batches'),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) => _tabController.index == 0
                ? _buildCoursesView()
                : _buildBatchesView(),
          ),
        ],
      ),
    ),
  );

  Widget _buildCoursesView() => StreamBuilder<List<Course>>(
    stream: _coursesStream,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _ErrorCard(
          title: 'Unable to load courses',
          message: snapshot.error.toString(),
          onRetry: _reloadCourses,
        );
      }
      if (!snapshot.hasData) {
        return const _LoadingCard(label: 'Loading courses…');
      }
      return _CoursesList(
        courses: snapshot.data!,
        user: widget.user,
        canManage: _canManage,
        courseService: _courseService,
      );
    },
  );

  Widget _buildBatchesView() => StreamBuilder<List<Course>>(
    stream: _coursesStream,
    builder: (context, coursesSnapshot) => StreamBuilder<List<Student>>(
      stream: _studentsStream,
      builder: (context, studentsSnapshot) => StreamBuilder<List<Batch>>(
        stream: _batchesStream,
        builder: (context, batchesSnapshot) {
          if (batchesSnapshot.hasError) {
            return _ErrorCard(
              title: 'Unable to load batches',
              message: batchesSnapshot.error.toString(),
              onRetry: _reloadBatches,
            );
          }
          if (!batchesSnapshot.hasData) {
            return const _LoadingCard(label: 'Loading batches…');
          }
          final courses = coursesSnapshot.data ?? const <Course>[];
          final students = studentsSnapshot.data ?? const <Student>[];
          return _BatchesList(
            batches: batchesSnapshot.data!,
            courses: courses,
            students: students,
            user: widget.user,
            canManage: _canManage,
            batchService: _batchService,
          );
        },
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.canManage,
    required this.isSeeding,
    required this.onLoadSamples,
  });

  final AppUser user;
  final bool canManage;
  final bool isSeeding;
  final VoidCallback? onLoadSamples;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16,
    runSpacing: 12,
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Course & Batch Management',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage course offerings, batch schedules, trainers, and student capacity.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
        ],
      ),
      if (canManage)
        OutlinedButton.icon(
          onPressed: isSeeding ? null : onLoadSamples,
          icon: isSeeding
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high_rounded),
          label: Text(isSeeding ? 'Seeding data…' : 'Load Sample Courses & Batches'),
        ),
    ],
  );
}

class _RoleBanner extends StatelessWidget {
  const _RoleBanner({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final (icon, message) = switch (role) {
      AppRole.owner => (
        Icons.admin_panel_settings_outlined,
        'Owner access: Create, edit, and archive courses and batches.',
      ),
      AppRole.counselor => (
        Icons.visibility_outlined,
        'Counselor access: View available courses and batch timings to guide prospective students.',
      ),
      AppRole.trainer => (
        Icons.co_present_outlined,
        'Trainer access: View assigned batches and monitor enrolled student counts.',
      ),
      AppRole.accounts => (
        Icons.account_balance_wallet_outlined,
        'Accounts Staff access: View course fees and batch allocations for fee operations.',
      ),
    };

    return _NoticeBox(
      message: message,
      icon: icon,
      background: const Color(0xFFEAF2FF),
      textColor: AppTheme.ink,
    );
  }
}

class _NoticeBox extends StatelessWidget {
  const _NoticeBox({
    required this.message,
    required this.icon,
    required this.background,
    required this.textColor,
  });

  final String message;
  final IconData icon;
  final Color background;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: textColor, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: textColor))),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// COURSES LIST & DIALOG
// ---------------------------------------------------------------------------

class _CoursesList extends StatefulWidget {
  const _CoursesList({
    required this.courses,
    required this.user,
    required this.canManage,
    required this.courseService,
  });

  final List<Course> courses;
  final AppUser user;
  final bool canManage;
  final CourseService courseService;

  @override
  State<_CoursesList> createState() => _CoursesListState();
}

class _CoursesListState extends State<_CoursesList> {
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Course> get _filteredCourses {
    final query = _searchController.text.trim().toLowerCase();
    return widget.courses.where((course) {
      final matchesSearch =
          query.isEmpty ||
          course.name.toLowerCase().contains(query) ||
          course.description.toLowerCase().contains(query) ||
          course.duration.toLowerCase().contains(query);
      final matchesStatus = switch (_statusFilter) {
        'active' => !course.isArchived,
        'archived' => course.isArchived,
        _ => true,
      };
      return matchesSearch && matchesStatus;
    }).toList();
  }

  void _openCourseForm([Course? course]) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CourseFormDialog(
        user: widget.user,
        course: course,
        courseService: widget.courseService,
      ),
    );
  }

  Future<void> _archiveCourse(Course course) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Course'),
        content: Text(
          'Are you sure you want to archive "${course.name}"? Existing batches and student records will remain preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.courseService.archiveForUser(widget.user, course);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Course "${course.name}" archived.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not archive course: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCourses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Search courses…',
                          isDense: true,
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () => setState(() => _searchController.clear()),
                                )
                              : null,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Courses')),
                          DropdownMenuItem(value: 'active', child: Text('Active Only')),
                          DropdownMenuItem(value: 'archived', child: Text('Archived')),
                        ],
                        onChanged: (val) => setState(() => _statusFilter = val ?? 'all'),
                      ),
                    ),
                  ],
                ),
                if (widget.canManage)
                  FilledButton.icon(
                    onPressed: () => _openCourseForm(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Course'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.school_outlined, size: 48, color: AppTheme.brand),
                    const SizedBox(height: 12),
                    Text(
                      widget.courses.isEmpty
                          ? 'No courses created yet.'
                          : 'No courses match the current filters.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.courses.isEmpty
                          ? (widget.canManage
                              ? 'Click "Add Course" or load sample data to begin.'
                              : 'Courses will appear here once created by an Owner.')
                          : 'Try modifying your search or status filter.',
                      style: TextStyle(color: Colors.blueGrey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(Color(0xFFF6F8FC)),
                columnSpacing: 28,
                columns: const [
                  DataColumn(label: Text('COURSE NAME')),
                  DataColumn(label: Text('DURATION')),
                  DataColumn(label: Text('FEE AMOUNT')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('DESCRIPTION')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: filtered
                    .map(
                      (course) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              course.name,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          DataCell(Text(course.duration)),
                          DataCell(Text('₹${course.feeAmount.toStringAsFixed(0)}')),
                          DataCell(_StatusBadge(isArchived: course.isArchived)),
                          DataCell(
                            SizedBox(
                              width: 300,
                              child: Text(
                                course.description.isEmpty ? '—' : course.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            widget.canManage
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, size: 20),
                                        tooltip: 'Edit Course',
                                        onPressed: () => _openCourseForm(course),
                                      ),
                                      if (!course.isArchived)
                                        IconButton(
                                          icon: const Icon(Icons.archive_outlined, size: 20),
                                          tooltip: 'Archive Course',
                                          onPressed: () => _archiveCourse(course),
                                        ),
                                    ],
                                  )
                                : const Text('—'),
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
}

class _CourseFormDialog extends StatefulWidget {
  const _CourseFormDialog({
    required this.user,
    required this.courseService,
    this.course,
  });

  final AppUser user;
  final Course? course;
  final CourseService courseService;

  @override
  State<_CourseFormDialog> createState() => _CourseFormDialogState();
}

class _CourseFormDialogState extends State<_CourseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _durationController;
  late final TextEditingController _feeController;
  late final TextEditingController _descriptionController;
  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.course;
    _nameController = TextEditingController(text: c?.name ?? '');
    _durationController = TextEditingController(text: c?.duration ?? '');
    _feeController = TextEditingController(
      text: c != null ? c.feeAmount.toStringAsFixed(0) : '',
    );
    _descriptionController = TextEditingController(text: c?.description ?? '');
    _status = c?.status ?? 'active';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    _feeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final fee = double.tryParse(_feeController.text.trim()) ?? 0.0;
      final draft = Course(
        id: widget.course?.id ?? '',
        instituteId: widget.course?.instituteId ?? 'demo-institute',
        name: _nameController.text.trim(),
        duration: _durationController.text.trim(),
        feeAmount: fee,
        description: _descriptionController.text.trim(),
        status: _status,
        createdAt: widget.course?.createdAt ?? now,
        updatedAt: now,
      );

      if (widget.course == null) {
        await widget.courseService.createForUser(widget.user, draft);
      } else {
        await widget.courseService.updateForUser(widget.user, draft);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.course == null
                ? 'Course "${draft.name}" created successfully.'
                : 'Course "${draft.name}" updated successfully.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save course: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.course == null ? 'Add Course' : 'Edit Course'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Course Name *'),
                validator: (val) =>
                    (val == null || val.trim().isEmpty) ? 'Course name is required' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _durationController,
                      decoration: const InputDecoration(
                        labelText: 'Duration *',
                        hintText: 'e.g. 6 Months, 12 Weeks',
                      ),
                      validator: (val) =>
                          (val == null || val.trim().isEmpty) ? 'Duration is required' : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _feeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Fee Amount (₹) *',
                        prefixText: '₹ ',
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Fee is required';
                        }
                        final amount = double.tryParse(val.trim());
                        if (amount == null) return 'Enter a valid amount';
                        if (amount < 0) return 'Fee cannot be negative';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Key topics and syllabus summary…',
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'archived', child: Text('Archived')),
                ],
                onChanged: _isSaving ? null : (val) => setState(() => _status = val ?? 'active'),
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
        onPressed: _isSaving ? null : _submit,
        child: _isSaving
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(widget.course == null ? 'Create Course' : 'Save Changes'),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// BATCHES LIST & DIALOG
// ---------------------------------------------------------------------------

class _BatchesList extends StatefulWidget {
  const _BatchesList({
    required this.batches,
    required this.courses,
    required this.students,
    required this.user,
    required this.canManage,
    required this.batchService,
  });

  final List<Batch> batches;
  final List<Course> courses;
  final List<Student> students;
  final AppUser user;
  final bool canManage;
  final BatchService batchService;

  @override
  State<_BatchesList> createState() => _BatchesListState();
}

class _BatchesListState extends State<_BatchesList> {
  final TextEditingController _searchController = TextEditingController();
  String? _courseFilter;
  String? _trainerFilter;
  String _statusFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int _enrolledCount(String batchId) => widget.students
      .where((s) => s.status == 'active' && s.batchId == batchId)
      .length;

  List<Batch> get _filteredBatches {
    final query = _searchController.text.trim().toLowerCase();
    return widget.batches.where((batch) {
      final matchesSearch =
          query.isEmpty ||
          batch.name.toLowerCase().contains(query) ||
          batch.courseName.toLowerCase().contains(query) ||
          batch.trainerName.toLowerCase().contains(query) ||
          batch.scheduleDescription.toLowerCase().contains(query);
      final matchesCourse = _courseFilter == null || batch.courseId == _courseFilter;
      final matchesTrainer =
          _trainerFilter == null || batch.trainerId == _trainerFilter;
      final matchesStatus = switch (_statusFilter) {
        'active' => !batch.isArchived,
        'archived' => batch.isArchived,
        _ => true,
      };
      return matchesSearch && matchesCourse && matchesTrainer && matchesStatus;
    }).toList();
  }

  void _openBatchForm([Batch? batch]) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BatchFormDialog(
        user: widget.user,
        batch: batch,
        courses: widget.courses,
        batchService: widget.batchService,
      ),
    );
  }

  Future<void> _archiveBatch(Batch batch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Archive Batch'),
        content: Text(
          'Are you sure you want to archive "${batch.name}"? Existing student enrollments and attendance records will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB42318)),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await widget.batchService.archiveForUser(widget.user, batch);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Batch "${batch.name}" archived.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not archive batch: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredBatches;
    final trainerOptions = {
      for (final b in widget.batches)
        if (b.trainerId.isNotEmpty) b.trainerId: b.trainerName,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Search batches…',
                          isDense: true,
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () => setState(() => _searchController.clear()),
                                )
                              : null,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _courseFilter,
                        decoration: const InputDecoration(
                          labelText: 'Filter by Course',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Courses')),
                          ...widget.courses.map(
                            (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                          ),
                        ],
                        onChanged: (val) => setState(() => _courseFilter = val),
                      ),
                    ),
                    if (widget.user.role != AppRole.trainer)
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String?>(
                          initialValue: _trainerFilter,
                          decoration: const InputDecoration(
                            labelText: 'Filter by Trainer',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('All Trainers')),
                            ...trainerOptions.entries.map(
                              (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                            ),
                          ],
                          onChanged: (val) => setState(() => _trainerFilter = val),
                        ),
                      ),
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('All Batches')),
                          DropdownMenuItem(value: 'active', child: Text('Active Only')),
                          DropdownMenuItem(value: 'archived', child: Text('Archived')),
                        ],
                        onChanged: (val) => setState(() => _statusFilter = val ?? 'all'),
                      ),
                    ),
                  ],
                ),
                if (widget.canManage)
                  FilledButton.icon(
                    onPressed: () => _openBatchForm(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Batch'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.groups_outlined, size: 48, color: AppTheme.brand),
                    const SizedBox(height: 12),
                    Text(
                      widget.batches.isEmpty
                          ? 'No batches created yet.'
                          : 'No batches match the current filters.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.batches.isEmpty
                          ? (widget.canManage
                              ? 'Click "Add Batch" or load sample data to begin.'
                              : 'Batches will appear here once created by an Owner.')
                          : 'Try modifying your search or filters.',
                      style: TextStyle(color: Colors.blueGrey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(Color(0xFFF6F8FC)),
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('BATCH NAME')),
                  DataColumn(label: Text('COURSE')),
                  DataColumn(label: Text('TRAINER')),
                  DataColumn(label: Text('ENROLLMENT / CAPACITY')),
                  DataColumn(label: Text('SCHEDULE')),
                  DataColumn(label: Text('DATES')),
                  DataColumn(label: Text('STATUS')),
                  DataColumn(label: Text('ACTIONS')),
                ],
                rows: filtered.map((batch) {
                  final enrolled = _enrolledCount(batch.id);
                  final isFull = enrolled >= batch.capacity && batch.capacity > 0;

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          batch.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(Text(batch.courseName)),
                      DataCell(Text(batch.trainerName)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$enrolled / ${batch.capacity}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: isFull ? const Color(0xFFB42318) : AppTheme.ink,
                              ),
                            ),
                            if (isFull) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE4E2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'FULL',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFB42318),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 180,
                          child: Text(
                            batch.scheduleDescription.isEmpty ? '—' : batch.scheduleDescription,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Text('${_formatDate(batch.startDate)} – ${_formatDate(batch.endDate)}'),
                      ),
                      DataCell(_StatusBadge(isArchived: batch.isArchived)),
                      DataCell(
                        widget.canManage
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    tooltip: 'Edit Batch',
                                    onPressed: () => _openBatchForm(batch),
                                  ),
                                  if (!batch.isArchived)
                                    IconButton(
                                      icon: const Icon(Icons.archive_outlined, size: 20),
                                      tooltip: 'Archive Batch',
                                      onPressed: () => _archiveBatch(batch),
                                    ),
                                ],
                              )
                            : const Text('—'),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}

class _BatchFormDialog extends StatefulWidget {
  const _BatchFormDialog({
    required this.user,
    required this.courses,
    required this.batchService,
    this.batch,
  });

  final AppUser user;
  final Batch? batch;
  final List<Course> courses;
  final BatchService batchService;

  @override
  State<_BatchFormDialog> createState() => _BatchFormDialogState();
}

class _BatchFormDialogState extends State<_BatchFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;
  late final TextEditingController _scheduleController;

  String? _selectedCourseId;
  String? _selectedTrainerId;
  late DateTime _startDate;
  late DateTime _endDate;
  late String _status;
  bool _isSaving = false;

  static const _availableTrainers = [
    (id: 'demo-trainer', name: 'Rohan Kulkarni'),
    (id: 'trainer-2', name: 'Pooja Verma'),
    (id: 'trainer-3', name: 'Aditya Sen'),
  ];

  @override
  void initState() {
    super.initState();
    final b = widget.batch;
    _nameController = TextEditingController(text: b?.name ?? '');
    _capacityController = TextEditingController(
      text: b != null ? b.capacity.toString() : '25',
    );
    _scheduleController = TextEditingController(text: b?.scheduleDescription ?? '');

    _selectedCourseId = b?.courseId;
    _selectedTrainerId = b?.trainerId ?? 'demo-trainer';
    _startDate = b?.startDate ?? DateTime.now();
    _endDate = b?.endDate ?? DateTime.now().add(const Duration(days: 180));
    _status = b?.status ?? 'active';

    if (_selectedCourseId == null && widget.courses.isNotEmpty) {
      final activeCourses = widget.courses.where((c) => !c.isArchived).toList();
      if (activeCourses.isNotEmpty) {
        _selectedCourseId = activeCourses.first.id;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    _scheduleController.dispose();
    super.dispose();
  }

  Course? get _selectedCourse {
    if (_selectedCourseId == null) return null;
    return widget.courses.cast<Course?>().firstWhere(
      (c) => c?.id == _selectedCourseId,
      orElse: () => null,
    );
  }

  String get _trainerName {
    final match = _availableTrainers.cast<({String id, String name})?>().firstWhere(
      (t) => t?.id == _selectedTrainerId,
      orElse: () => null,
    );
    return match?.name ?? 'Trainer';
  }

  Future<void> _submit() async {
    if (_isSaving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedCourseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a course.')),
      );
      return;
    }

    if (_endDate.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date cannot be earlier than start date.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final course = _selectedCourse;
      final capacity = int.tryParse(_capacityController.text.trim()) ?? 20;

      final draft = Batch(
        id: widget.batch?.id ?? '',
        instituteId: widget.batch?.instituteId ?? 'demo-institute',
        name: _nameController.text.trim(),
        courseId: _selectedCourseId!,
        courseName: course?.name ?? (widget.batch?.courseName ?? ''),
        trainerId: _selectedTrainerId!,
        trainerName: _trainerName,
        startDate: _startDate,
        endDate: _endDate,
        capacity: capacity,
        scheduleDescription: _scheduleController.text.trim(),
        status: _status,
        createdAt: widget.batch?.createdAt ?? now,
        updatedAt: now,
      );

      if (widget.batch == null) {
        await widget.batchService.createForUser(
          widget.user,
          draft,
          course: course,
        );
      } else {
        await widget.batchService.updateForUser(widget.user, draft);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.batch == null
                ? 'Batch "${draft.name}" created successfully.'
                : 'Batch "${draft.name}" updated successfully.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save batch: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (selected != null && mounted) {
      setState(() {
        _startDate = selected;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(days: 90));
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2035),
    );
    if (selected != null && mounted) {
      setState(() => _endDate = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCourses = widget.courses.where((c) => !c.isArchived).toList();
    if (widget.batch != null &&
        _selectedCourseId != null &&
        !activeCourses.any((c) => c.id == _selectedCourseId)) {
      final existing = widget.courses.where((c) => c.id == _selectedCourseId);
      if (existing.isNotEmpty) activeCourses.add(existing.first);
    }

    return AlertDialog(
      title: Text(widget.batch == null ? 'Add Batch' : 'Edit Batch'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Batch Name *',
                    hintText: 'e.g. DA Jan 2026 A',
                  ),
                  validator: (val) =>
                      (val == null || val.trim().isEmpty) ? 'Batch name is required' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCourseId,
                  decoration: const InputDecoration(labelText: 'Course *'),
                  hint: const Text('Select a course'),
                  items: activeCourses
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text('${c.name}${c.isArchived ? " (Archived)" : ""}'),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving ? null : (val) => setState(() => _selectedCourseId = val),
                  validator: (val) => val == null ? 'Course is required' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedTrainerId,
                  decoration: const InputDecoration(labelText: 'Assigned Trainer *'),
                  items: _availableTrainers
                      .map(
                        (t) => DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.name} (${t.id})'),
                        ),
                      )
                      .toList(),
                  onChanged: _isSaving ? null : (val) => setState(() => _selectedTrainerId = val),
                  validator: (val) => val == null ? 'Trainer is required' : null,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickStartDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Start Date *',
                            suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                          ),
                          child: Text(_formatDate(_startDate)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickEndDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'End Date *',
                            suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                          ),
                          child: Text(_formatDate(_endDate)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _capacityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Batch Capacity *',
                          hintText: 'e.g. 25',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Capacity is required';
                          final cap = int.tryParse(val.trim());
                          if (cap == null || cap <= 0) return 'Must be > 0';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'archived', child: Text('Archived')),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (val) => setState(() => _status = val ?? 'active'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _scheduleController,
                  decoration: const InputDecoration(
                    labelText: 'Schedule Description *',
                    hintText: 'e.g. Mon-Wed-Fri, 09:00 AM - 11:00 AM',
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Schedule description is required'
                      : null,
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
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(widget.batch == null ? 'Create Batch' : 'Save Changes'),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isArchived});

  final bool isArchived;

  @override
  Widget build(BuildContext context) {
    final color = isArchived ? Colors.grey : const Color(0xFF047857);
    final bg = isArchived ? const Color(0xFFF2F4F7) : const Color(0xFFECFDF3);
    final label = isArchived ? 'Archived' : 'Active';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
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
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
    ),
  );
}

String _formatDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')} ${_monthName(value.month)} ${value.year}';

String _monthName(int month) => const <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][month - 1];

