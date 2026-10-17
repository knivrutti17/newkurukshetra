# Firebase AI Copilot setup

The Copilot uses the Firebase AI Logic Flutter SDK and the same Firebase app
configuration already used by InstituteOS. It does not contain a Gemini,
OpenAI, or other private provider key in Flutter source.

## What is already in the application

- `firebase_ai` and `firebase_app_check` are installed.
- The default provider is Firebase AI Logic with the Gemini Developer API
  (`FirebaseAI.googleAI()`), using `gemini-3.5-flash-lite` by default.
- The model name is build-time configurable with
  `--dart-define=COPILOT_GEMINI_MODEL=<supported-model>`.
- An already-configured Agent Platform Gemini API project can instead use
  `--dart-define=COPILOT_AI_PROVIDER=agent_platform`.
- Operational data reaches the model only through the role-scoped functions in
  `CopilotToolRegistry`; the model has no Firestore client or direct query tool.
- Conversations are stored in `copilotConversations/{conversationId}` with a
  `messages` subcollection. The parent and every message include `userId` and
  `instituteId` for rule enforcement and ownership checks.
- Read-only Copilot tools remain available to their UI roles. Copilot-created
  reminder drafts are deliberately disabled in a normal build. Enable that
  optional write path only after the Firestore rules below have been deployed
  and tested, by adding
  `--dart-define=COPILOT_ENABLE_REMINDER_DRAFT_WRITES=true` to the release
  build command. This flag is a fail-closed product guard, not authorization;
  an altered client can never be trusted.

## One-time Firebase Console work still required

This repository cannot verify or change Console-side AI/provider settings.
Using a project owner account for the existing `kurukshetra-c6c32` project:

1. Open **Firebase Console → AI Services → AI Logic** and connect the existing
   Firebase project to the **Gemini Developer API**. Choose a no-cost model tier
   if the Console offers it. Do not create or paste a provider key into the app.
2. Open **Firebase Console → App Check**, register the existing Web app with a
   reCAPTCHA v3 provider, and enforce App Check for Firebase AI Logic when the
   app has been tested. This step is required for reliable production access.
3. Start or build the Web app with its public reCAPTCHA site key supplied outside
   source control:

   ```powershell
   flutter run -d chrome --dart-define=FIREBASE_APP_CHECK_RECAPTCHA_SITE_KEY=<web-site-key>
   ```

The site key is an App Check attestation setting, not a Gemini credential. The
app intentionally shows a configuration notice when it is absent rather than
pretending AI calls are protected.

## Local Web development without a reCAPTCHA key

Do not add a Gemini, OpenAI, or other provider key to a Flutter Web build.
Those keys can be extracted from browser code. Firebase AI Logic keeps its
managed provider access on Firebase's side, but it requires a valid App Check
token when the project enforces App Check.

For localhost development only, start the app with the App Check debug
provider instead of reCAPTCHA:

```powershell
flutter run -d chrome --dart-define=FIREBASE_APP_CHECK_DEBUG=true
```

Open the browser developer tools, copy the generated `AppCheck debug token`,
then add it under **Firebase Console â†’ Security â†’ App Check â†’ Apps â†’
Manage debug tokens** for the existing Web app. Restart the local debug build
and use the Copilot normally. The optional
`FIREBASE_APP_CHECK_DEBUG_TOKEN=<registered-token>` define can be used only on
your own development machine to reuse a registered token.

The debug provider is intentionally ignored in profile and release builds.
For a deployed Web app, register the production reCAPTCHA provider and build
with `FIREBASE_APP_CHECK_RECAPTCHA_SITE_KEY`; do not ship a debug token.

## Firestore rules prerequisite

No Firestore rules file was present in this project, so no security rules were
created or deployed automatically. There is therefore no repository evidence
that the currently deployed database rules protect these records. Before
enabling Copilot data access in production, add, test, and deploy a reviewed
Firestore rules policy. The policy must make Firebase Authentication identity
and the user's trusted role/institute assignment authoritative; it must not
trust an `AppUser`, a client query filter, or a role value supplied by Flutter.

At a minimum, the policy must:

- Permit `copilotConversations` create only when
  `request.auth.uid == request.resource.data.userId`, and require the incoming
  `instituteId` to match the caller's trusted institute.
- Permit conversation read, update, and delete only to its owner in that same
  institute. For updates, prevent `userId` and `instituteId` from changing.
- Require every `messages` read/write to match the owner and institute of its
  parent conversation. Do not authorize a message merely because its own
  client-supplied fields look correct.
- Enforce the same institute, role, and assigned-counselor/trainer scope on
  students, attendance, batches, timetables, alerts, approvals, fees,
  payments, and reminder drafts. Owners/accounts alone may read financial
  records; trainers must be denied `feeInstallments`, `payments`, and
  `reminderDrafts` by the database itself.
- Restrict writes to the fields and role transitions that each workflow permits
  (including reminder draft creation/approval). If that validation needs data
  or invariants Firestore rules cannot safely express, perform the write in a
  trusted backend such as a callable Cloud Function or Cloud Run service.

Store the reviewed rules in the repository, add their path to `firebase.json`,
test them with the Emulator Suite, then deploy them with an authenticated
project-owner session. Only then is it appropriate to opt in to the Copilot
reminder-draft write flag. Client-side checks and the UI are defense in depth;
they are not a replacement for Firestore rules or a trusted backend.

## Live verification checklist

After the Console steps, sign in with each existing role and verify:

1. A greeting receives a Gemini response.
2. A student search and a low-attendance question show a source card and actual
   Firestore rows.
3. A follow-up such as “which of them?” is resolved using the saved prior tool
   context and a fresh authorized query when needed.
4. A Trainer does not receive financial tools or fee data.
5. Creating a reminder first shows a preview; only explicit confirmation writes
   a draft, rechecks the current balance, and never sends a message.
