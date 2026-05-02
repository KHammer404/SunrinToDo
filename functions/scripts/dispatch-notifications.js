#!/usr/bin/env node
const admin = require("firebase-admin");
const { createNotificationDispatcher } = require("../notification_dispatcher");

function parseServiceAccount(raw) {
  if (!raw) return null;

  try {
    return JSON.parse(raw);
  } catch (_) {
    return JSON.parse(Buffer.from(raw, "base64").toString("utf8"));
  }
}

function initializeFirebaseAdmin() {
  if (admin.apps.length > 0) return;

  const projectId = process.env.FIREBASE_PROJECT_ID;
  if (!projectId) {
    throw new Error("FIREBASE_PROJECT_ID is required");
  }
  const serviceAccount = parseServiceAccount(
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON,
  );

  if (serviceAccount) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId,
    });
    return;
  }

  admin.initializeApp({ projectId });
}

async function main() {
  initializeFirebaseAdmin();

  const dispatcher = createNotificationDispatcher({
    admin,
    db: admin.firestore(),
    messaging: admin.messaging(),
    logger: console,
  });

  const result = await dispatcher.runScheduledNotificationJobs();
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
