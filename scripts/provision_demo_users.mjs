#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';

import admin from 'firebase-admin';

const REQUIRED_PROJECT_ID = 'kurukshetra-c6c32';
const DEFAULT_INSTITUTE_ID = 'demo-institute';
const APPLY = process.argv.includes('--apply');
const RESET_PASSWORDS = process.argv.includes('--reset-password');
const RESET_TRAINER_PASSWORD = process.argv.includes('--reset-trainer-password');

const DEMO_ACCOUNTS = [
  {
    email: 'owner@demo.com',
    password: 'Owner@123',
    displayName: 'Aarav Mehta',
    role: 'owner',
  },
  {
    email: 'counselor@demo.com',
    password: 'Counselor@123',
    displayName: 'Priya Shah',
    role: 'counselor',
  },
  {
    email: 'trainer@demo.com',
    password: 'Trainer@123',
    displayName: 'Rohan Kulkarni',
    role: 'trainer',
  },
  {
    email: 'accounts@demo.com',
    password: 'Accounts@123',
    displayName: 'Neha Iyer',
    role: 'accounts',
  },
];

function parseServiceAccountPath() {
  const configuredPath =
    process.env.FIREBASE_SERVICE_ACCOUNT_PATH ??
    process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (!configuredPath) {
    return undefined;
  }

  const resolvedPath = path.resolve(configuredPath);
  if (!fs.existsSync(resolvedPath)) {
    throw new Error(
      `Service account file not found: ${resolvedPath}. Set FIREBASE_SERVICE_ACCOUNT_PATH or GOOGLE_APPLICATION_CREDENTIALS to a valid Firebase Admin SDK credential JSON file.`,
    );
  }

  return resolvedPath;
}

function validateProjectId(projectId) {
  if (!projectId) {
    throw new Error(
      'No Firebase project ID was configured. Set FIREBASE_PROJECT_ID to kurukshetra-c6c32 or set the default Google Cloud project.',
    );
  }

  if (projectId !== REQUIRED_PROJECT_ID) {
    throw new Error(
      `Configured Firebase project ID is "${projectId}", but this app expects "${REQUIRED_PROJECT_ID}". Aborting before making any changes.`,
    );
  }
}

async function ensureUserProfile({ db, uid, email, displayName, role }) {
  const profileRef = db.collection('users').doc(uid);
  const profile = {
    uid,
    email,
    name: displayName,
    role,
    instituteId: DEFAULT_INSTITUTE_ID,
    isActive: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await profileRef.set(profile, { merge: true });
}

async function ensureCustomClaims({ auth, uid, role }) {
  const user = await auth.getUser(uid);
  const currentClaims = user.customClaims ?? {};

  await auth.setCustomUserClaims(uid, {
    ...currentClaims,
    role,
    instituteId: DEFAULT_INSTITUTE_ID,
    isActive: true,
  });
}

async function maybeResetPassword({ auth, uid, password, resetPasswords }) {
  if (!resetPasswords) {
    return;
  }

  await auth.updateUser(uid, { password });
}

async function resetTrainerPassword({ auth, apply }) {
  const trainer = DEMO_ACCOUNTS.find((account) => account.email === 'trainer@demo.com');
  const existingUser = await auth.getUserByEmail(trainer.email);

  console.log(`Found existing Firebase Auth user: ${trainer.email} (uid: ${existingUser.uid})`);
  if (!apply) {
    console.log('Dry run: would update this user password only. No Firestore data or security rules will be changed.');
    return;
  }

  await auth.updateUser(existingUser.uid, { password: trainer.password });
  const verifiedUser = await auth.getUser(existingUser.uid);
  if (verifiedUser.uid !== existingUser.uid) {
    throw new Error('Password update verification failed: the existing user UID did not match.');
  }

  console.log(`Password update succeeded; existing account verified (uid: ${verifiedUser.uid}).`);
}

async function main() {
  const serviceAccountPath = parseServiceAccountPath();
  const projectId =
    process.env.FIREBASE_PROJECT_ID ??
    process.env.GCLOUD_PROJECT ??
    REQUIRED_PROJECT_ID;

  validateProjectId(projectId);

  const appConfig = { projectId };
  if (serviceAccountPath) {
    appConfig.credential = admin.credential.cert(serviceAccountPath);
  }

  admin.initializeApp(appConfig);

  const auth = admin.auth();
  const db = admin.firestore();

  console.log(`Using Firebase project: ${projectId}`);
  console.log(`Dry run: ${!APPLY}`);

  if (RESET_TRAINER_PASSWORD) {
    if (RESET_PASSWORDS) {
      throw new Error('Use --reset-trainer-password by itself to avoid resetting other demo accounts.');
    }
    await resetTrainerPassword({ auth, apply: APPLY });
    return;
  }

  if (!APPLY) {
    console.log('No changes will be applied. Re-run with --apply to create or repair the account records.');
  }

  if (RESET_PASSWORDS && !APPLY) {
    throw new Error('Password reset requires --apply. Re-run with both --apply --reset-password to update existing passwords.');
  }

  for (const account of DEMO_ACCOUNTS) {
    const label = `${account.email} (${account.role})`;

    try {
      const existingUser = await auth.getUserByEmail(account.email);
      console.log(`User already exists: ${label} (uid: ${existingUser.uid})`);

      if (APPLY) {
        await ensureCustomClaims({ auth, uid: existingUser.uid, role: account.role });
        await ensureUserProfile({
          db,
          uid: existingUser.uid,
          email: account.email,
          displayName: account.displayName,
          role: account.role,
        });
        await maybeResetPassword({
          auth,
          uid: existingUser.uid,
          password: account.password,
          resetPasswords: RESET_PASSWORDS,
        });
        console.log(`Profile repaired for ${label}.`);
      } else {
        console.log(`Would repair the existing profile and claims for ${label}.`);
      }
    } catch (error) {
      if (error && error.code === 'auth/user-not-found') {
        if (!APPLY) {
          console.log(`Would create user: ${label}`);
          continue;
        }

        const createdUser = await auth.createUser({
          email: account.email,
          password: account.password,
          displayName: account.displayName,
          emailVerified: true,
          disabled: false,
        });

        await ensureCustomClaims({ auth, uid: createdUser.uid, role: account.role });
        await ensureUserProfile({
          db,
          uid: createdUser.uid,
          email: account.email,
          displayName: account.displayName,
          role: account.role,
        });
        console.log(`Created Firebase Auth user and profile: ${label}`);
      } else {
        throw error;
      }
    }
  }

  if (!APPLY) {
    console.log('Dry run complete. Nothing was changed.');
    return;
  }

  console.log('Demo account provisioning finished successfully.');
  console.log('No passwords were printed in this output.');
}

main().catch((error) => {
  console.error('Demo account provisioning failed.');
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exitCode = 1;
});
