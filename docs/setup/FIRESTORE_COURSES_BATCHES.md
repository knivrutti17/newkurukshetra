# Course & Batch Management Firestore Setup

This document describes the Firestore schema, indexing, and role permissions for **Course & Batch Management** in InstituteOS.

## Collections

### 1. `courses/`
Stores official training programs offered by the institute.

| Field | Type | Description |
|---|---|---|
| `instituteId` | `string` | Tenant identifier (default `demo-institute`). |
| `name` | `string` | Course name (e.g. `"Data Analytics"`). |
| `description` | `string` | Syllabus and overview. |
| `duration` | `string` | Formatted duration (e.g. `"6 Months"`). |
| `feeAmount` | `number` | Course tuition fee (non-negative). |
| `status` | `string` | `"active"` or `"archived"`. |
| `createdAt` | `timestamp` | Time of creation. |
| `updatedAt` | `timestamp` | Time of last modification. |

### 2. `batches/`
Stores specific classroom and training cohorts running under a course.

| Field | Type | Description |
|---|---|---|
| `instituteId` | `string` | Tenant identifier (default `demo-institute`). |
| `name` | `string` | Batch name (e.g. `"DA Jan 2026 A"`). |
| `courseId` | `string` | Reference ID to parent `courses` document. |
| `courseName` | `string` | Cached course name for display. |
| `trainerId` | `string` | Assigned trainer user ID (e.g. `"demo-trainer"`). |
| `trainerName` | `string` | Assigned trainer full name. |
| `startDate` | `timestamp` | Start date of batch sessions. |
| `endDate` | `timestamp` | Scheduled completion date (must be $\ge$ `startDate`). |
| `capacity` | `number` | Maximum enrollment capacity ($> 0$). |
| `scheduleDescription` | `string` | Timetable summary (e.g. `"Mon-Wed-Fri, 09:00 AM - 11:00 AM"`). |
| `status` | `string` | `"active"` or `"archived"`. |
| `createdAt` | `timestamp` | Time of creation. |
| `updatedAt` | `timestamp` | Time of last modification. |

---

## Integrations

1. **Student Management**:
   - The student creation and editing form queries available courses and batches from Firestore.
   - When a course is chosen, the batch dropdown dynamically filters to batches belonging to that course.
   - Assigning a student to a batch also links the batch's `trainerId` to the student record.
   - Backward compatibility: Existing student records with legacy names continue to be displayed safely.

2. **Attendance Management**:
   - The attendance session selector now queries real batch records from `batches` in Firestore.
   - Active batches are available for recording new attendance sessions.
   - Archived batches remain accessible in the Attendance History section so past attendance records and IDs are never lost or corrupted.
   - If no batches exist in Firestore, an empty state guides the user to create a batch in Course & Batch Management first.

---

## Role Permissions (Demo UI)

- **Owner / Admin**: Full access. Can create, edit, archive courses and batches, and trigger sample data seeding.
- **Counselor**: View-only access to courses and active batches to guide admissions.
- **Trainer**: View-only access scoped to batches assigned to them (`trainerId == user.id`), displaying live enrollment vs capacity.
- **Accounts Staff**: View-only access to course fees, durations, and batch schedules for fee planning.

---

## Security Rules (Demo vs Production)

For local/demo testing with anonymous authentication:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /courses/{courseId} {
      allow read, write: if request.auth != null;
    }
    match /batches/{batchId} {
      allow read, write: if request.auth != null;
    }
  }
}
```
*Note*: In production, write operations on `courses` and `batches` must be restricted to authenticated owners/administrators via custom claims (`request.auth.token.role == 'owner'`).

