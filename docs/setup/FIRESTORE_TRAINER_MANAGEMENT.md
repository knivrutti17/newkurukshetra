# Firestore Trainer Management — Architecture, Rules & Integration Guide

## 1. Overview
The **Trainer Management** module in InstituteOS enables comprehensive administration of institute faculty and instructors:
- **Trainer Profiles**: Full contact information, areas of expertise, qualifications, and years of experience.
- **Availability & Scheduling**: Structured weekday availability, preferred teaching hours, unavailable dates/times, and scheduling notes.
- **Batch Assignment**: Bidirectional integration with Cloud Firestore `batches` collection, supporting assignment of active trainers with stable ID tracking.
- **Role Isolation**: Owner full management, Counselor read-only scheduling visibility, and Trainer self-profile views.
- **Repeat-Safe Seeding**: One-click deterministic sample data loading without accidental overwrites.

---

## 2. Cloud Firestore Schema

### Collection: `trainers`
Document ID: Deterministic identifier (e.g. `demo-trainer`, `trainer-pooja-verma`) or auto-generated Firestore ID.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Document ID matching the Firestore key |
| `instituteId` | `String` | Institute scoping key (default: `'demo-institute'`) |
| `fullName` | `String` | Instructor's full name (e.g. `'Rohan Kulkarni'`) |
| `email` | `String` | Display email address (e.g. `'trainer@demo.com'`) |
| `emailNormalized` | `String` | Lowercased, trimmed email for duplicate prevention |
| `phone` | `String` | Contact phone number |
| `expertise` | `List<String>` | Array of subject tags (e.g. `['Flutter', 'Dart', 'Node.js']`) |
| `qualifications` | `String` | Academic and industry credentials |
| `experienceYears` | `int` | Non-negative integer representing years in industry |
| `availability` | `Map<String, dynamic>` | Structured availability details (see below) |
| `status` | `String` | `'active'` or `'inactive'` |
| `createdAt` | `Timestamp` | Record creation timestamp |
| `updatedAt` | `Timestamp` | Record last modification timestamp |

### `availability` Map Structure
```json
{
  "weekdays": ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"],
  "preferredTimeRange": "Morning (09:00 AM - 01:30 PM)",
  "unavailableNotes": "Unavailable Sunday afternoons",
  "generalNotes": "Lead instructor for full stack web and mobile engineering cohorts."
}
```

---

## 3. Integration with `batches` Collection

The `batches` collection maintains stable trainer assignments using two existing fields:
- `trainerId`: Foreign key reference to document in `trainers`.
- `trainerName`: Denormalized instructor name for fast table rendering without additional joins.

### Assignment Invariants
1. **Active Status Requirement**: Only instructors with `status == 'active'` can be assigned to batches.
2. **Institute Isolation**: The trainer's `instituteId` must match the batch's `instituteId`.
3. **Deactivation Protection**: If a trainer is assigned to one or more active batches, the Owner is shown a prominent warning modal and must explicitly acknowledge the impact before deactivation proceeds.
4. **Historical Record Preservation**: Deactivating an instructor or reassigning a batch never deletes past attendance records or student enrollment logs.

---

## 4. Role-Based Permissions Matrix

| Capability | Owner / Admin | Counselor | Trainer | Accounts Staff |
|---|:---:|:---:|:---:|:---:|
| View All Institute Trainers | Yes | Yes (Read-only) | Scoped to own record | Yes (Read-only) |
| Add / Edit Trainer Profile | Yes | No | No | No |
| Deactivate / Activate Trainer | Yes | No | No | No |
| Assign Trainer to Batch | Yes | No | No | No |
| Load Sample Trainers | Yes | No | No | No |

---

## 5. Security Rules

### Production Cloud Firestore Rules (`firestore.rules`)
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Helper functions
    function isAuthenticated() {
      return request.auth != null;
    }

    function isOwner() {
      return isAuthenticated() && request.auth.token.role == 'owner';
    }

    function isSameInstitute(instituteId) {
      return isAuthenticated() && request.auth.token.instituteId == instituteId;
    }

    // Trainers collection
    match /trainers/{trainerId} {
      allow read: if isAuthenticated() && (
        isOwner() ||
        request.auth.uid == trainerId ||
        request.auth.token.role in ['counselor', 'accounts']
      );
      
      allow create, update, delete: if isOwner();
    }
  }
}
```

---

## 6. Composite Indexes

When running queries across `instituteId` and `status` or sorting alphabetically:

```json
{
  "collectionGroup": "trainers",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "instituteId", "order": "ASCENDING" },
    { "fieldPath": "emailNormalized", "order": "ASCENDING" }
  ]
}
```
*(Single-field indexes on `instituteId` and `emailNormalized` are automatically created by Firestore).*

