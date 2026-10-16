# InstituteOS Project Structure

This repository is organized for **InstituteOS - AI Operations Copilot**, a Flutter Web application with Firebase and TypeScript Cloud Functions planned for future implementation.

## Application and assets

- `assets/` stores future images, icons, and fonts.
- `lib/main.dart` is the existing Flutter entry point and remains unchanged.
- `lib/app.dart` is a reserved application-shell module; it intentionally contains no implementation yet.
- `lib/core/` holds cross-cutting constants, enums, errors, routing, theme, utilities, and reusable core widgets.
- `lib/data/` is reserved for shared data models, repositories, and services.
- `lib/shared/` contains shared validators, formatters, and Dart extensions.

## Feature modules

Each feature is self-contained under `lib/features/`:

- `auth/` - authentication screens, widgets, and controllers.
- `dashboard/` - dashboard screens and widgets.
- `copilot/` - the primary AI Operations Copilot module. Its models, screens, widgets, controllers, and services will support chat, conversation history, structured results, AI requests, explanations, visual result components, prompts, follow-ups, and action previews.
- `students/`, `courses/`, `batches/`, `trainers/`, `attendance/`, `fees/`, and `timetable/` - institute operations modules.
- `alerts/`, `approvals/`, `reports/`, `recordings/`, `certificates/`, `staff/`, `audit/`, and `settings/` - supporting operational and administrative modules.

## Testing

- `test/unit/`, `test/widget/`, and `test/features/` reserve space for Flutter tests.
- `integration_test/` reserves space for end-to-end Flutter tests.

## Cloud Functions

- `functions/src/` is reserved for future Firebase Cloud Functions written in TypeScript.
- `functions/src/auth/` will contain authorization checks.
- `functions/src/copilot/` will contain secure AI orchestration.
- `functions/src/tools/` contains dedicated student, attendance, fee, and timetable tool areas for predefined backend operations.
- `functions/src/actions/`, `approvals/`, and `audit/` support future action preparation, approval workflows, and audit logging.
- `functions/src/shared/` holds backend utilities, while `functions/test/` is reserved for backend tests.

No Functions configuration, dependencies, source implementation, or deployment artifacts were added as part of this structure-only setup.

## Documentation and tooling

- `docs/architecture/`, `docs/database/`, `docs/api/`, and `docs/setup/` reserve documentation by subject.
- `scripts/` is reserved for safe development and maintenance automation.

Empty scaffold directories contain `.gitkeep` files so their structure is retained in Git.

