const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { createNotificationDispatcher } = require("./notification_dispatcher");

admin.initializeApp();

const dispatcher = createNotificationDispatcher({
  admin,
  db: admin.firestore(),
  messaging: admin.messaging(),
  logger,
});

exports.syncEventNotifications = onDocumentWritten(
  "events/{eventId}",
  async (event) => {
    const eventId = event.params.eventId;
    const afterData = event.data.after.exists
      ? event.data.after.data()
      : null;

    await dispatcher.syncEventNotificationsForEvent(eventId, afterData);
  },
);

exports.dispatchMealNotifications = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Seoul",
  },
  async () => {
    await dispatcher.dispatchMealNotifications();
  },
);

exports.dispatchScheduledNotifications = onSchedule(
  {
    schedule: "every 15 minutes",
    timeZone: "Asia/Seoul",
  },
  async () => {
    await dispatcher.dispatchScheduledNotifications();
  },
);
