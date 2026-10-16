# Firestore Timetable Management — Architecture, Rules & Integration Guide

## 1. Overview
The **Timetable Management** module in InstituteOS enables institutional scheduling, classroom reservation, and faculty allocation with automated clash detection:
- **Weekly Calendar Grid & Daily List Views**: Intuitive weekly matrix with Monday–Saturday columns, past/future week navigation, "Today" anchor, and date-grouped list view.
- **Explainable Clash Detection**: Pure rule-based detection preventing trainer double-booking, classroom double-booking, batch overlapping, scheduling with inactive faculty/cohorts, and booking outside configured trainer availability weekdays.
- **Auditable Lifecycle**: Class sessions can be scheduled, edited, or cancelled. Historical records are preserved with status `cancelled` rather than permanently destroyed.
- **Role Isolation**:
  - **Owner**: Full schedule administration, live conflict override capability, classroom assignment, and repeat-safe sample schedule loader.
  - **Counselor**: Institutional schedule visibility across batches and trainers for counseling and advising.
  - **Trainer**: Scoped personal timetable (`my-timetable`) showing assigned cohort classes, physical classroom numbers, and virtual live links.
  - **Accounts Staff**: Read-only schedule visibility.
- **Repeat-Safe Sample Seeding**: Deterministic session IDs matching existing sample batches and trainers, preventing duplicates.

---

## 2. Cloud Firestore Schema

### Collection: `classSessions`
Document ID: Deterministic identifier (e.g. `sample-session-da-mon`) or auto-generated Firestore ID.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Document ID matching Firestore document key |
| `instituteId` | `String` | Tenant/Institute scoping key (default: `'demo-institute'`) |
| `batchId` | `String` | Foreign key reference to document in `batches` |
| `batchName` | `String` | Denormalized batch name for fast UI rendering |
| `courseId` | `String` | Foreign key reference to course in `courses` |
| `courseName` | `String` | Denormalized course name |
| `trainerId` | `String` | Foreign key reference to assigned instructor in `trainers` |
| `trainerName` | `String` | Denormalized trainer full name |
| `startAt` | `Timestamp` | Scheduled session start time |
| `endAt` | `Timestamp` | Scheduled session end time |
| `deliveryMode` | `String` | `'in_person'`, `'online'`, or `'hybrid'` |
| `roomId` | `String` | Normalized classroom ID |
| `roomName` | `String` | Human-readable room label (e.g. `'Lab 1 - Ground Floor'`) |
| `meetingLink` | `String` | Virtual class URL (Google Meet, Zoom, etc.) |
| `status` | `String` | `'scheduled'`, `'completed'`, or `'cancelled'` |
| `createdAt` | `Timestamp` | Record creation timestamp |
| `updatedAt` | `Timestamp` | Last modification timestamp |

---

## 3. Clash Detection & Scheduling Invariants

The `ClashDetectionEngine` evaluates every new or updated class session deterministically:

1. **Overlap Condition**:
   ```dart
   candidate.startAt.isBefore(existing.endAt) && existing.startAt.isBefore(candidate.endAt)
   ```
2. **Trainer Double-Booking**:
   A trainer cannot be assigned to more than one active class at the same time.
3. **Classroom Double-Booking**:
   For `in_person` and `hybrid` sessions, two active cohorts cannot reserve the same classroom or lab simultaneously.
4. **Batch Overlap**:
   A cohort cannot be scheduled for two concurrent lectures.
5. **Trainer Day-of-Week Availability**:
   Checks the trainer's `availability.weekdays` list. If a session is scheduled on an unconfigured day (e.g., Sunday when the instructor works Mon–Fri), a descriptive conflict is flagged.
6. **Inactive Entity Protection**:
   Classes cannot be scheduled for archived batches or inactive trainers.
7. **Exclusions**:
   - Cancelled sessions (`status == 'cancelled'`) never trigger clashes, freeing up classrooms and instructors.
   - Self-sessions are excluded during edit operations (`existing.id == candidate.id`).

---

## 4. Role-Based Permissions Matrix

| Capability | Owner | Counselor | Trainer | Accounts Staff |
|---|:---:|:---:|:---:|:---:|
| View All Timetables | Yes | Yes | Own Assigned Only | Yes |
| Schedule New Class | Yes | No | No | No |
| Edit Class Session | Yes | No | No | No |
| Cancel Class Session | Yes | No | No | No |
| Override Clash Warning | Yes | No | No | No |
| Seed Sample Timetable | Yes | No | No | No |

---

## 5. Security Rules (Firestore)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /classSessions/{sessionId} {
      allow read: if request.auth != null;
      allow create, update: if request.auth != null &&
        (request.auth.token.role == 'owner' || request.auth.token.role == 'admin');
      allow delete: if false; // Cancellation updates status, never deletes historical sessions
    }
  }
}
```

---

## 6. Deterministic Sample Seed Data

The `TimetableSeedService` generates deterministic sessions anchored to the current active week:

| ID | Day & Time | Batch | Trainer | Mode & Room |
|---|---|---|---|---|
| `sample-session-da-mon` | Mon 09:00 - 11:00 | DA Jan 2026 A | Rohan Kulkarni | In-Person (Lab 1 - Ground Floor) |
| `sample-session-fsd-mon` | Mon 11:30 - 13:30 | FSD Feb 2026 B | Rohan Kulkarni | Hybrid (Tech Studio 204) |
| `sample-session-da-tue` | Tue 10:00 - 12:00 | DA May 2026 B | Aditya Sen | Online Live (Zoom Link) |
| `sample-session-ux-tue` | Tue 14:00 - 16:00 | UX Apr 2026 C | Pooja Verma | In-Person (Design Studio A) |
| `sample-session-da-wed` | Wed 09:00 - 11:00 | DA Jan 2026 A | Rohan Kulkarni | In-Person (Lab 1 - Ground Floor) |
| `sample-session-fsd-wed` | Wed 11:30 - 13:30 | FSD Feb 2026 B | Rohan Kulkarni | Hybrid (Tech Studio 204) |
| `sample-session-da-thu` | Thu 10:00 - 12:00 | DA May 2026 B | Aditya Sen | Online Live (Zoom Link) |
| `sample-session-ux-thu` | Thu 14:00 - 16:00 | UX Apr 2026 C | Pooja Verma | In-Person (Design Studio A) |
| `sample-session-da-fri` | Fri 09:00 - 11:00 | DA Jan 2026 A | Rohan Kulkarni | In-Person (Lab 1 - Ground Floor) |
| `sample-session-dm-fri` | Fri 14:00 - 17:00 | DM Mar 2026 A | Ananya Joshi | In-Person (Seminar Hall B) |

