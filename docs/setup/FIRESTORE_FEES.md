# Fee & Instalment Management Firestore Setup

This document describes the Firestore schema, transactions, indexing, and role permissions for **Fee & Instalment Management** in InstituteOS.

## Collections

### 1. `feeInstallments/`
Stores scheduled tuition fee instalments for enrolled students.

| Field | Type | Description |
|---|---|---|
| `instituteId` | `string` | Tenant identifier (default `demo-institute`). |
| `studentId` | `string` | Reference ID to parent `students` document. |
| `studentName` | `string` | Cached student full name for quick display. |
| `courseId` | `string` | Reference ID to course. |
| `batchId` | `string` | Reference ID to batch cohort. |
| `amountDue` | `number` | Instalment amount due in rupees ($> 0$). |
| `paidAmount` | `number` | Total verified amount collected in rupees ($\ge 0$). |
| `dueDate` | `timestamp` | Due date for the instalment. |
| `status` | `string` | Derived payment status: `"pending"`, `"partiallyPaid"`, `"paid"`, or `"overdue"`. |
| `createdAt` | `timestamp` | Time of creation. |
| `updatedAt` | `timestamp` | Time of last modification. |

#### Status Derivation Rules
- **`paid`**: Total payments recorded $\ge$ amount due. **A paid instalment never becomes overdue**, even after the due date.
- **`overdue`**: Current date is after the end of the due date ($23:59:59$) and outstanding balance $> 0$.
- **`partiallyPaid`**: Total payments recorded $> 0$ and $<$ amount due, before the due date has expired.
- **`pending`**: Zero payments recorded and the due date is in the future.

#### Precision Guarantee
All currency calculations, balances, and overdue checks use integer paise arithmetic (`(amount * 100).round()`) to prevent floating-point inaccuracies.

---

### 2. `payments/`
Stores individual payment transactions against an instalment.

| Field | Type | Description |
|---|---|---|
| `instituteId` | `string` | Tenant identifier (default `demo-institute`). |
| `feeInstallmentId` | `string` | Reference ID to the parent `feeInstallments` record. |
| `studentId` | `string` | Reference ID to the paying student. |
| `amount` | `number` | Payment transaction amount in rupees ($> 0$). |
| `paymentDate` | `timestamp` | Date and time the payment was made. |
| `paymentMethod` | `string` | Method: `"Cash"`, `"UPI"`, `"Bank Transfer"`, `"Cheque"`, or `"Card"`. |
| `referenceNumber` | `string?` | Optional transaction or cheque reference number. |
| `recordedBy` | `string` | User ID of the staff member who recorded the payment. |
| `createdAt` | `timestamp` | Time the transaction record was logged. |

#### Transactional Atomicity
Recording a payment runs inside a Firestore transaction (`runTransaction`):
1. Reads the current `feeInstallments` record.
2. Validates that the new payment does not exceed the remaining outstanding balance.
3. Simultaneously updates `paidAmount`, `status`, and `updatedAt` on the instalment while writing the new `payments` document.

---

## Integrations

1. **Student Management**:
   - The Add Instalment form loads verified active students from the `students` collection in Firestore.
   - Selecting a student automatically populates their enrolled course and batch where available.
   - Inactive or archived students are prevented from having new instalments scheduled.

2. **Course & Batch Management**:
   - Batch filter queries real batch records from the `batches` collection.
   - Filter dropdowns dynamically narrow down fee records by batch.

---

## Role Permissions (Demo UI)

- **Owner / Admin**: Full access. Can create instalments, record payments, inspect payment history, view all financial summaries, and trigger sample fee data seeding.
- **Accounts Staff**: Full fee management access. Can create instalments, record payments, and view payment history and financial metrics.
- **Counselor**: Restricted. Financial details and fee amounts are hidden to maintain fee confidentiality.
- **Trainer**: Restricted. Trainers do not have access to fee schedules, collections, or balances.

---

## Security Rules (Demo vs Production)

For local/demo testing:
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /feeInstallments/{installmentId} {
      allow read, write: if request.auth != null;
    }
    match /payments/{paymentId} {
      allow read, write: if request.auth != null;
    }
  }
}
```

*Production Note*: In production, write and read operations on `feeInstallments` and `payments` must be restricted to users with `owner` or `accounts` custom claims:
```javascript
match /feeInstallments/{installmentId} {
  allow read, write: if request.auth != null &&
    (request.auth.token.role == 'owner' || request.auth.token.role == 'accounts');
}
match /payments/{paymentId} {
  allow read, write: if request.auth != null &&
    (request.auth.token.role == 'owner' || request.auth.token.role == 'accounts');
}
```

