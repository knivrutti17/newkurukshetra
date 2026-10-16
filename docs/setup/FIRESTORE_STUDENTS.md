# Student Management Firestore setup

The application now initializes Firebase and starts an **anonymous Firebase
Authentication session** without changing the visible local demo login. That
identity is only suitable for a fictional-data demo; the Owner, Counselor,
Trainer, and Accounts roles in the UI are local state and are not trusted by
Firebase.

## Current project state

The checked-in `firebase.json` configures FlutterFire output only. It has no
Firestore section, and this repository has no `firestore.rules` file. No
Firebase configuration or rules were changed by the Student Management work.

A read-only request made during implementation to project `kurukshetra-c6c32`
received `SERVICE_DISABLED`: the Cloud Firestore API has not been enabled for
that project. Until that is corrected, the Students page will show a database
error and cannot persist any records.

## Required demo setup

1. In the Firebase console, create or enable the default **Cloud Firestore
   (Native mode)** database for `kurukshetra-c6c32`. Do not use Test Mode for a
   deployed database.
2. In Firebase Authentication, enable the **Anonymous** sign-in provider. The
   app will then create or reuse an anonymous session at startup; the existing
   four demo-login screens remain unchanged.
3. Deploy Firestore rules that require an authenticated request. A temporary
   fictional-data demo may use `request.auth != null` for the `students`
   collection. It is deliberately not included as a deployed rule in this
   repository, and it must not be used with real student data.

No billing-plan upgrade or paid Firebase service is required for these steps.

## Production authorization

Before storing any real student data, replace the anonymous-demo approach with
trusted Firebase Authentication and role/institute claims issued by a secure
backend. Enforce access in Firestore rules (and, where needed, a backend), not
with the local `AppRole` enum. At minimum, rules should limit every student
record to the authenticated user's institute and restrict counselor/trainer
access to their assigned records.

Firestore rules cannot securely hide individual fields from a user who can
read a `students` document. The Accounts UI currently hides non-fee fields for
the demo, but production must provide a separate fee-safe projection
collection or backend endpoint for Accounts Staff instead of granting direct
read access to full student documents.
