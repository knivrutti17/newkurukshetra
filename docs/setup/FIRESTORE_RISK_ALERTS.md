# Student Risk Alerts & Follow-up Center

This feature derives explainable, human-review indicators from the existing
top-level `students`, `attendance`, `feeInstallments`, and `payments`
collections. It does not use an AI service and it does not create alerts on a
page load. An Owner explicitly runs **Refresh Risk Scan**.

## Added collections

### `studentAlerts/{instituteId}--{studentId}--{alertType}`

The deterministic document ID is the deduplication key for an active student
and rule. A scan updates an active matching document rather than adding a
duplicate. It intentionally preserves `assignedTo`, `followUpNote`, and
`followUpHistory`; it never overwrites a `resolved` or `dismissed` alert.

| Field | Type | Purpose |
|---|---|---|
| `instituteId`, `studentId`, `studentName` | string | Tenant and student snapshot |
| `batchId`, `batchName` | string | Current batch snapshot |
| `alertType` | string | `lowAttendance`, `repeatedAbsence`, `overdueFees`, or `combinedRisk` |
| `severity` | string | `low`, `medium`, or `high` |
| `title`, `reason`, `evidence` | string/map | Human-readable rule result and precise evidence |
| `status` | string | `new`, `inReview`, `followUp`, `resolved`, or `dismissed` |
| `createdAt`, `updatedAt`, `resolvedAt` | Firestore timestamp | Lifecycle dates |
| `assignedTo`, `followUpNote`, `followUpHistory` | string/list | Follow-up owner and embedded history |
| `counselorId`, `trainerId` | string | Assignment data used for scoped academic views |
| `resolvedBy`, `closureReason` | string | Closure audit information |

### `riskScanMetadata/{instituteId}`

Stores `lastCompletedAt` and `lastCompletedBy` only after all source reads and
alert writes have completed successfully. It is not an alert collection and
does not contain student financial data.

## Rules implemented

- **Low attendance:** below 75%, calculated as present recorded sessions over
  all recognized recorded statuses. At least five records are required. Missing
  attendance documents are never assumed to be absences.
- **Repeated absences:** at least three recorded absences in the most recent
  30 calendar days. The alert states the dates and count and does not claim the
  absences were consecutive.
- **Overdue instalments:** a due date before the current date and a positive
  outstanding balance. Recorded payment rows are summed when they exist; the
  existing atomic `paidAmount` is used for older imported instalments with no
  payment rows. Fully paid records are excluded.
- **Combined risk:** generated only in the Owner’s full scan when both an
  attendance concern and an overdue fee concern exist. Counselors and trainers
  never receive it, so no financial details are exposed through their alert UI.

## Scan bounds and failures

The browser scan is deliberately bounded to protect Firestore free-tier reads:

| Source | Maximum complete scan size |
|---|---:|
| Students | 200 |
| Attendance records | 3,000 |
| Fee instalments | 800 |
| Payments | 1,000 |
| Existing alert records | 1,000 |

Every query reads one extra document. If any bound is exceeded, the scan stops
before writing alert records and reports the exact limit. Source-query,
permission, and write failures also leave the last-successful-scan timestamp
unchanged. For larger institutes, implement a trusted, paginated backend scan
before increasing these browser limits.

## Role and security limitation

The application currently authenticates Firebase anonymously while selecting a
local demo `AppRole` in the browser. Therefore role checks in the risk screen
are useful UI safeguards only, **not production authorization**. This feature
does not change Firebase configuration or deploy/relax Firestore rules.

Before production, replace the demo identity with trusted Firebase identities
and enforce all of the following in Firestore rules (and a server-side scanner
for financial aggregation):

- institute isolation on every source, alert, and metadata document;
- Owner-only scan and alert closure/reopen writes;
- counselor reads/updates limited to assigned academic alerts;
- trainer reads/updates limited to assigned-batch academic alerts;
- accounts reads/updates limited to overdue-fee alerts and permitted financial
  fields; and
- deny counselor/trainer reads of `overdueFees`, `combinedRisk`, payments, and
  fee values.

There is no existing audit-log collection in this workspace, so status/note
events are stored in the alert’s `followUpHistory` instead of adding a second
audit system. No email, WhatsApp, push, or other delivery action is performed.

## Indexes

The existing repository pattern queries by `instituteId` plus assignment for
counselors and trainers. Firestore may prompt for these composite indexes:

- `studentAlerts`: `instituteId ASC, counselorId ASC, alertType ASC`
- `studentAlerts`: `instituteId ASC, trainerId ASC, alertType ASC`
- `studentAlerts`: `instituteId ASC, alertType ASC`

Create only the index link supplied by Firestore if it is requested by your
project. The UI surfaces query errors rather than reporting empty results as a
successful scan.
