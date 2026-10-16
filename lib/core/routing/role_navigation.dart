import 'package:flutter/material.dart';

import '../../data/models/app_user.dart';

class NavigationSection {
  const NavigationSection({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

List<NavigationSection> navigationForRole(AppRole role) => switch (role) {
  AppRole.owner => const [
    NavigationSection(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.grid_view_rounded,
    ),
    NavigationSection(
      id: 'copilot',
      label: 'AI Copilot',
      icon: Icons.auto_awesome_rounded,
    ),
    NavigationSection(
      id: 'students',
      label: 'Students',
      icon: Icons.people_alt_outlined,
    ),
    NavigationSection(
      id: 'courses-batches',
      label: 'Courses & Batches',
      icon: Icons.school_outlined,
    ),
    NavigationSection(
      id: 'trainers',
      label: 'Trainers',
      icon: Icons.co_present_outlined,
    ),
    NavigationSection(
      id: 'attendance',
      label: 'Attendance',
      icon: Icons.fact_check_outlined,
    ),
    NavigationSection(
      id: 'fees',
      label: 'Fees',
      icon: Icons.account_balance_wallet_outlined,
    ),
    NavigationSection(
      id: 'timetable',
      label: 'Timetable',
      icon: Icons.calendar_month_outlined,
    ),
    NavigationSection(
      id: 'approvals',
      label: 'Approvals',
      icon: Icons.task_alt_outlined,
    ),
    NavigationSection(
      id: 'reports',
      label: 'Reports',
      icon: Icons.assessment_outlined,
    ),
    NavigationSection(
      id: 'staff-settings',
      label: 'Staff & Settings',
      icon: Icons.settings_outlined,
    ),
  ],
  AppRole.counselor => const [
    NavigationSection(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.grid_view_rounded,
    ),
    NavigationSection(
      id: 'copilot',
      label: 'AI Copilot',
      icon: Icons.auto_awesome_rounded,
    ),
    NavigationSection(
      id: 'students',
      label: 'Students',
      icon: Icons.people_alt_outlined,
    ),
    NavigationSection(
      id: 'courses-batches',
      label: 'Courses & Batches',
      icon: Icons.school_outlined,
    ),
    NavigationSection(
      id: 'follow-ups',
      label: 'Student Follow-ups',
      icon: Icons.forum_outlined,
    ),
  ],
  AppRole.trainer => const [
    NavigationSection(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.grid_view_rounded,
    ),
    NavigationSection(
      id: 'copilot',
      label: 'AI Copilot',
      icon: Icons.auto_awesome_rounded,
    ),
    NavigationSection(
      id: 'my-batches',
      label: 'My Batches',
      icon: Icons.groups_outlined,
    ),
    NavigationSection(
      id: 'attendance',
      label: 'Attendance',
      icon: Icons.fact_check_outlined,
    ),
    NavigationSection(
      id: 'my-timetable',
      label: 'My Timetable',
      icon: Icons.calendar_month_outlined,
    ),
  ],
  AppRole.accounts => const [
    NavigationSection(
      id: 'dashboard',
      label: 'Dashboard',
      icon: Icons.grid_view_rounded,
    ),
    NavigationSection(
      id: 'copilot',
      label: 'AI Copilot',
      icon: Icons.auto_awesome_rounded,
    ),
    NavigationSection(
      id: 'fee-management',
      label: 'Fee Management',
      icon: Icons.account_balance_wallet_outlined,
    ),
    NavigationSection(
      id: 'payments',
      label: 'Payments',
      icon: Icons.payments_outlined,
    ),
    NavigationSection(
      id: 'fee-reports',
      label: 'Fee Reports',
      icon: Icons.receipt_long_outlined,
    ),
    NavigationSection(
      id: 'reminder-drafts',
      label: 'Reminder Drafts',
      icon: Icons.mark_email_unread_outlined,
    ),
  ],
};
