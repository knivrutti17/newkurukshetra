# Firebase demo account provisioning

This project already expects a real Firebase-authenticated user identity and a Firestore role profile at `users/{uid}`. The Flutter app reads the authenticated UID, loads the matching Firestore document, and resolves the role from `role` as one of:

- `owner`
- `counselor`
- `trainer`
- `accounts`

The app also checks `isActive` and `instituteId` before allowing access.

## Required Firebase setup

1. Open the Firebase Console for project `kurukshetra-c6c32`.
2. Go to **Build > Authentication > Sign-in method**.
3. Enable **Email/Password**.
4. Go to **Build > Firestore Database** and enable Cloud Firestore for the project.
5. Make sure the project ID matches the project used by the Flutter app.

## Secure admin credentials

Never commit service-account JSON files or store them in source control.

Use a local environment variable or a secure credential file outside the repo:

```bash
export FIREBASE_PROJECT_ID=kurukshetra-c6c32
export FIREBASE_SERVICE_ACCOUNT_PATH="/absolute/path/to/service-account.json"
```

If you already have Application Default Credentials configured, you can omit `FIREBASE_SERVICE_ACCOUNT_PATH` and the script will use ADC instead.

## Script location

The script is here:

```bash
scripts/provision_demo_users.mjs
```

It creates or repairs the following four development users if they are missing:

- `owner@demo.com` → `owner`
- `counselor@demo.com` → `counselor`
- `trainer@demo.com` → `trainer`
- `accounts@demo.com` → `accounts`

The script does not change an existing user's password automatically. If an account already exists, it only repairs the role profile and claims unless you explicitly run `--apply --reset-password`.

## Run the script locally

This script is safe by default and does a dry run unless you pass `--apply`.

From the repository root:

```bash
npm install firebase-admin
node scripts/provision_demo_users.mjs
node scripts/provision_demo_users.mjs --apply
```

To reset an existing password intentionally:

```bash
node scripts/provision_demo_users.mjs --apply --reset-password
```

If you prefer to use a local `.env` file, keep it out of source control and load it securely before running the command.

## What the script does

For each demo account, the script:

- checks whether the email already exists in Firebase Authentication
- creates the Firebase Auth user only if it is missing
- sets custom claims for `role` and `instituteId`
- ensures a Firestore profile exists at `users/{uid}` with:
  - `uid`
  - `email`
  - `name`
  - `role`
  - `instituteId`
  - `isActive`
  - timestamps

The app then resolves the user by reading `users/{uid}` after Firebase Authentication succeeds. That matches the current app logic in the repository.

## Verification in Firebase Console

After running the script successfully:

1. Open **Authentication > Users**
2. Confirm the four demo emails exist
3. Open **Firestore Database** and inspect the `users` collection
4. Confirm each UID has a matching document with the correct role and `isActive: true`

## If an account already exists

The script is idempotent:

- it does not reset passwords
- it does not create duplicate Firebase users
- it repairs any missing role profile fields or claims

## Removing development accounts later

If these demo accounts are no longer needed, delete them from Firebase Console under **Authentication > Users** and remove their Firestore `users/{uid}` documents from Firestore. Do not remove or alter production users.

## Important note

This is for fictional development accounts only. The script intentionally does not create a public provisioning API, does not weaken Firestore rules, and does not assign Owner privileges from the client.
