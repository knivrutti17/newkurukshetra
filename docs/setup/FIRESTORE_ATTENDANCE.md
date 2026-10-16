# Attendance Management Firestore Setup

This document describes the Firestore data structure, duplicate prevention mechanism, and authorization model for **Attendance Management** in InstituteOS.

## Document Structure

Attendance records are stored in the top-level collection:
```
attendance/
```

Each document represents one student's attendance for one batch session on a specific calendar date.

### Deterministic Document ID

To guarantee duplicate prevention and safe repeat edits, document IDs follow a deterministic pattern:
```
{instituteId}--{batchId}--{YYYYMMDD}--{studentId}
```

Example:
```
demo-institute--da-2026-a--20260710--student-a
```

When an attendance session is re-opened and saved (even if the trainer changes a student from Present to Absent), Firestore upserts the document by this exact ID. No duplicate records can ever be created for the same student on the same date for a batch.

### Document Fields

| Field | Type | Description |
|---|---|---|
| `instituteId` | `string` | Institute tenant identifier (e.g. `demo-institute`). |
| `studentId` | `string` | The enrolled student document ID. |
| `batchId` | `string` | Identifier of the course batch (e.g. `da-2026-a`). |
| `classDate` | `timestamp` | Normalized class date (UTC midnight of the session date). |
| `status` | `string` | Attendance status: `"present"`, `"absent"`, or `"late"`. |
| `createdAt` | `timestamp` | Time the first record was created. Preserved across edits. |
| `updatedAt` | `timestamp` | Time the record was last modified. |
| `recordedBy` | `string` | User ID of the trainer or owner who recorded the session. |
| `counselorId` | `string` (optional) | Assigned counselor ID for scoped viewing. |
| `trainerId` | `string` (optional) | Assigned trainer ID for batch ownership and scoped viewing. |

---

## Role Permissions (Demo UI)

- **Owner / Admin**: Full access. Can mark and edit attendance for all batches, and view full attendance history across the institute.
- **Trainer**: Can mark and edit attendance for students in batches assigned to them (`trainerId == user.id`). Can view attendance history for their assigned students.
- **Counselor**: Read-only access. Can view recorded attendance and history only for students assigned to them (`counselorId == user.id`). Cannot mark or save attendance.
- **Accounts Staff**: No access. Attendance section is hidden from navigation and direct access displays an access-denied state.

---

## Current Status & Live Firebase Blocker

During live verification with project `kurukshetra-c6c32`, requests fail with:
```
SERVICE_DISABLED: Cloud Firestore API has not been used in project 84512715421 before or it is disabled.
```

### Manual Setup Steps to Enable Live Firestore

1. **Enable Cloud Firestore API**:
   - Go to [Firebase Console](https://console.firebase.google.com/) and open project `kurukshetra-c6c32`.
   - Navigate to **Build > Firestore Database**.
   - Click **Create database** (Native mode, choose your preferred cloud region).
2. **Enable Anonymous Authentication**:
   - In Firebase Console, navigate to **Build > Authentication > Sign-in method**.
   - Enable the **Anonymous** provider. (This allows the demo bootstrap to obtain an anonymous Firebase token without affecting the local role-based demo accounts).
3. **Configure Firestore Security Rules**:
   - For demo testing with anonymous authentication, configure rules:
     ```javascript
     rules_version = '2';
     service cloud.firestore {
       match /databases/{database}/documents {
         match /students/{studentId} {
           allow read, write: if request.auth != null;
         }
         match /attendance/{attendanceId} {
           allow read, write: if request.auth != null;
         }
       }
     }
     ```
   - *Note*: Production deployments must enforce institute isolation and role claims (`request.auth.token.role`) rather than simple authenticated access.

