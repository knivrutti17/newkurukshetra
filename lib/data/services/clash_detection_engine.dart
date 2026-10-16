import '../models/batch.dart';
import '../models/class_session.dart';
import '../models/trainer.dart';

/// Pure, deterministic conflict detection engine for class sessions.
class ClashDetectionEngine {
  const ClashDetectionEngine._();

  static const List<String> _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static const List<String> _weekdayShortNames = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  static String _formatDate(DateTime dt) {
    final dayOfWeek = _weekdayShortNames[dt.weekday - 1];
    final month = _monthNames[dt.month - 1];
    return '$dayOfWeek, $month ${dt.day}';
  }

  /// Evaluates a candidate [ClassSession] against [existingSessions] and optional
  /// associated [trainer] and [batch] records.
  ///
  /// Returns a list of [ScheduleConflict]s. An empty list means the schedule is clash-free.
  static List<ScheduleConflict> detectConflicts({
    required ClassSession candidate,
    required List<ClassSession> existingSessions,
    Trainer? trainer,
    Batch? batch,
  }) {
    final conflicts = <ScheduleConflict>[];

    // 1. Time validity
    if (!candidate.endAt.isAfter(candidate.startAt)) {
      conflicts.add(
        const ScheduleConflict(
          type: ScheduleConflictType.availabilityConflict,
          message: 'Class end time must be after start time.',
        ),
      );
      return conflicts;
    }

    // 2. Inactive status checks
    if (batch != null && batch.status.toLowerCase() == 'archived') {
      conflicts.add(
        ScheduleConflict(
          type: ScheduleConflictType.statusConflict,
          message:
              'Batch "${batch.name}" is archived. New classes cannot be scheduled for archived batches.',
        ),
      );
    }

    if (trainer != null && trainer.isInactive) {
      conflicts.add(
        ScheduleConflict(
          type: ScheduleConflictType.statusConflict,
          message:
              'Trainer "${trainer.fullName}" is marked as inactive. Please activate the trainer or reassign.',
        ),
      );
    }

    // 3. Trainer availability (day of week)
    if (trainer != null && trainer.availability.weekdays.isNotEmpty) {
      final sessionWeekday = _weekdayNames[candidate.startAt.weekday - 1];
      final isAvailableDay = trainer.availability.weekdays.any(
        (day) => day.toLowerCase() == sessionWeekday.toLowerCase(),
      );

      if (!isAvailableDay) {
        conflicts.add(
          ScheduleConflict(
            type: ScheduleConflictType.availabilityConflict,
            message:
                'Trainer "${trainer.fullName}" is not marked as available on ${sessionWeekday}s (Available: ${trainer.availability.weekdays.join(', ')}).',
          ),
        );
      }
    }

    // 4. Overlap checks against active existing sessions
    for (final existing in existingSessions) {
      // Exclude self (when editing)
      if (candidate.id.isNotEmpty && existing.id == candidate.id) {
        continue;
      }

      // Exclude cancelled sessions - cancelled classes never cause clashes
      if (existing.isCancelled) {
        continue;
      }

      // Check time overlap: A.start < B.end AND B.start < A.end
      final isOverlapping = candidate.startAt.isBefore(existing.endAt) &&
          existing.startAt.isBefore(candidate.endAt);

      if (!isOverlapping) {
        continue;
      }

      final existingDateStr = _formatDate(existing.startAt);
      final existingTimeStr =
          '${_formatTime(existing.startAt)} - ${_formatTime(existing.endAt)}';

      // Check trainer double-booking
      if (candidate.trainerId.isNotEmpty &&
          existing.trainerId.isNotEmpty &&
          candidate.trainerId == existing.trainerId) {
        conflicts.add(
          ScheduleConflict(
            type: ScheduleConflictType.trainerConflict,
            message:
                'Trainer "${candidate.trainerName.isNotEmpty ? candidate.trainerName : trainer?.fullName ?? 'Assigned Trainer'}" is already teaching "${existing.batchName}" on $existingDateStr ($existingTimeStr).',
            conflictingSession: existing,
          ),
        );
      }

      // Check batch overlap
      if (candidate.batchId.isNotEmpty &&
          existing.batchId.isNotEmpty &&
          candidate.batchId == existing.batchId) {
        conflicts.add(
          ScheduleConflict(
            type: ScheduleConflictType.batchConflict,
            message:
                'Batch "${candidate.batchName.isNotEmpty ? candidate.batchName : batch?.name ?? 'This Batch'}" already has a class scheduled on $existingDateStr ($existingTimeStr).',
            conflictingSession: existing,
          ),
        );
      }

      // Check classroom double-booking
      final candidateUsesRoom =
          (candidate.isInPerson || candidate.isHybrid) &&
              (candidate.roomId.isNotEmpty || candidate.roomName.isNotEmpty);
      final existingUsesRoom =
          (existing.isInPerson || existing.isHybrid) &&
              (existing.roomId.isNotEmpty || existing.roomName.isNotEmpty);

      if (candidateUsesRoom && existingUsesRoom) {
        final sameRoom = (candidate.roomId.isNotEmpty &&
                candidate.roomId == existing.roomId) ||
            (candidate.roomName.isNotEmpty &&
                candidate.roomName.toLowerCase().trim() ==
                    existing.roomName.toLowerCase().trim());

        if (sameRoom) {
          conflicts.add(
            ScheduleConflict(
              type: ScheduleConflictType.roomConflict,
              message:
                  'Classroom "${candidate.roomName}" is already reserved for "${existing.batchName}" on $existingDateStr ($existingTimeStr).',
              conflictingSession: existing,
            ),
          );
        }
      }
    }

    return conflicts;
  }
}

