# Firestore Approvals Center + Reports & Analytics — Architecture & Integration Guide

## 1. Overview
The **Approvals Center** and **Reports & Analytics** modules in InstituteOS provide human-in-the-loop administrative governance and real-time institutional intelligence directly computed from Cloud Firestore:
- **Approvals Center**: Centralized workflow for reviewing high-impact academic and financial requests (fee concessions, batch transfers, attendance overrides, fee refunds, and schedule clashes).
- **Reports & Analytics**: Real-time aggregation of students, batches, attendance history, fee collections, faculty assignments, risk alerts, and scheduled timetable sessions into role-tailored dashboards.
- **Decision Invariants**:
  - Approving a request marks it `approved` (or `awaiting_execution`). It does **not** automatically mutate downstream entities (e.g. fee balances or timetable sessions) without deliberate human action.
  - Rejecting a request strictly mandates a non-empty, audited rejection reason.
  - Atomic transactions prevent concurrent reviews or repeated decisions on already decided actions.
- **Pure Zero-Dependency Visualization**:
  - All charts and distributions are rendered using Flutter native widgets (`LinearProgressIndicator`, custom container bars, `DataTable`). No external charting dependencies or `intl` formatting packages are used.
  - Native currency and date formatting handles Indian numbering (₹) and clean timestamps.

---

## 2. Cloud Firestore Schema

### Collection: `pendingActions`
Document ID: Deterministic identifier (e.g. `sample-approval-concession-1`) or auto-generated Firestore ID.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Document ID matching Firestore document key |
| `instituteId` | `String` | Tenant/Institute scoping key (default: `'demo-institute'`) |
| `type` | `String` | Action category: `'fee_concession'`, `'batch_transfer'`, `'attendance_override'`, `'refund_request'`, `'schedule_override'` |
| `title` | `String` | Short human-readable request title |
| `description` | `String` | Request justification and operational context |
| `payload` | `Map<String, dynamic>` | Key-value action parameters (e.g. `studentId`, `batchId`, `amount`, `concessionPaise`) |
| `requestedBy` | `String` | Requesting staff member identity and role |
| `requestedAt` | `Timestamp` | Submission timestamp |
| `status` | `String` | `'pending'`, `'approved'`, `'rejected'`, or `'awaiting_execution'` |
| `approvedBy` | `String?` | Reviewer identity when approved |
| `approvedAt` | `Timestamp?` | Approval decision timestamp |
| `rejectedBy` | `String?` | Reviewer identity when rejected |
| `rejectedAt` | `Timestamp?` | Rejection decision timestamp |
| `rejectionReason`| `String?` | Mandatory audited reason if status is `'rejected'` |
| `updatedAt` | `Timestamp` | Last modification timestamp |

---

## 3. Reports & Analytics Data Models & Aggregates

The `ReportsService` queries real Firestore collections (`students`, `batches`, `attendance`, `feeInstallments`, `trainers`, `classSessions`, `studentAlerts`, `pendingActions`) without client-side mock fabrications:

### 1. Operational Summary (`OperationalSummaryData`)
- `totalStudents`: Count of registered students.
- `activeBatches`: Count of active cohorts (`!isArchived`).
- `pendingApprovals`: Actions awaiting decision (`isPending`).
- `openAlerts`: Active risk alerts (`!status.isClosed`).
- `todayClasses`: Active sessions scheduled for the current date.
- `overallFeeCollectionRate`: Percentage of collected revenue vs total billed dues.

### 2. Student Enrollment Report (`StudentReportData`)
- Filterable by Course ID and Batch ID.
- Active vs Inactive students breakdown.
- Distribution bars by Course and by Batch.

### 3. Attendance Analytics (`AttendanceReportData`)
- Overall attendance rate: `(presentCount / totalRecords) * 100`.
- Defaulter Threshold Slider (50% to 95%, default 75%).
- Ranked list of students below threshold with batch names and actual percentages.

### 4. Fee & Financials (`FeeReportData`)
- Total Billed (`totalDue`), Total Collected (`totalCollected`), Outstanding Balance (`outstandingBalance`).
- Overdue Installment Count and Overdue Amount.
- Overall Collection Rate percentage and recovery visualizer.

### 5. Faculty & Timetable (`TrainerTimetableReportData`)
- Active vs Inactive faculty count.
- Cohort load distribution per trainer.
- Scheduled, Completed, and Cancelled class metrics.
- Delivery mode breakdown: In-person, Online, and Hybrid classes.

---

## 4. Role-Based Permissions & Scoping Matrix

| Role | Approvals Review Scope | Reports Tabs Visible | Financial Reports Access |
|---|---|---|---|
| **Owner / Admin** | All requests (Academic + Financial) | 5 Tabs: Operational Overview, Student Enrollments, Attendance Analytics, Fee & Financials, Faculty & Timetable | Full access |
| **Accounts Staff** | Financial requests only (`fee_concession`, `refund_request`) | 2 Tabs: Financial Overview, Fee & Revenue Reports | Full access |
| **Counselor** | View-only (or submitted requests) | 3 Tabs: Counseling Overview, Student Enrollments, Attendance Analytics | Hidden |
| **Trainer** | View-only (or submitted requests) | 2 Tabs: Cohort Attendance, Class Timetable | Hidden |

---

## 5. Security Rules (Cloud Firestore)

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /pendingActions/{actionId} {
      // Any authenticated staff member can view actions
      allow read: if request.auth != null;
      
      // Staff members can submit pending requests
      allow create: if request.auth != null 
                    && request.resource.data.status == 'pending'
                    && request.resource.data.title.size() > 0;
                    
      // Reviewers can decide pending actions; rejection requires reason
      allow update: if request.auth != null
                    && (request.resource.data.status != 'rejected' 
                        || (request.resource.data.rejectionReason != null && request.resource.data.rejectionReason.size() > 0));
    }
  }
}
```

---

## 6. Deterministic Sample Seeding

Use the "Seed Sample Actions" button on the Approvals screen to populate 5 diverse demonstration workflows:
1. `sample-approval-concession-1`: Fee concession request for Aarav Mehta (₹5,000 merit concession).
2. `sample-approval-transfer-2`: Batch transfer for Diya Patel (Full Stack Web morning to evening cohort).
3. `sample-approval-attendance-3`: Attendance override for Rohan Kulkarni (Medical leave override).
4. `sample-approval-refund-4`: Security deposit refund for Priya Nair.
5. `sample-approval-schedule-5`: Weekend lab double-session schedule override for Python AI batch.

Seeding is deterministic and repeat-safe: subsequent runs verify existing document IDs and skip duplicate creations without overwriting existing review states.

