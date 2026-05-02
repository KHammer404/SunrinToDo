const NEIS_BASE_URL = "https://open.neis.go.kr/hub";
const OFFICE_CODE = "B10";
const SCHOOL_CODE = "7010536";
const DEFAULT_EVENT_SYNC_HORIZON_DAYS = 14;

function createNotificationDispatcher({
  admin,
  db,
  messaging,
  logger = console,
  neisApiKey = process.env.NEIS_API_KEY || "",
  now = () => new Date(),
}) {
  const Timestamp = admin.firestore.Timestamp;
  const FieldValue = admin.firestore.FieldValue;

  function logInfo(message, data = undefined) {
    logger.info(message, data);
  }

  function logWarn(message, data = undefined) {
    if (logger.warn) {
      logger.warn(message, data);
      return;
    }
    logger.info(message, data);
  }

  function toDate(value) {
    if (!value) return null;
    if (value instanceof Date) return value;
    if (typeof value.toDate === "function") return value.toDate();

    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  function toKstParts(date) {
    const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
    return {
      year: kst.getUTCFullYear(),
      month: kst.getUTCMonth(),
      day: kst.getUTCDate(),
    };
  }

  function fromKst(year, month, day, hour, minute = 0) {
    return new Date(Date.UTC(year, month, day, hour - 9, minute, 0, 0));
  }

  function startOfKstDay(date) {
    const { year, month, day } = toKstParts(date);
    return fromKst(year, month, day, 0, 0);
  }

  function endOfKstDayOffset(date, offsetDays) {
    const { year, month, day } = toKstParts(date);
    return fromKst(year, month, day + offsetDays, 23, 59);
  }

  function pad2(value) {
    return String(value).padStart(2, "0");
  }

  function formatKstDateKey(parts) {
    return `${parts.year}${pad2(parts.month + 1)}${pad2(parts.day)}`;
  }

  function kstMinutesSinceMidnight(date) {
    const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
    return kst.getUTCHours() * 60 + kst.getUTCMinutes();
  }

  function eventCategoryLabel(category) {
    switch (category) {
      case "exam":
        return "시험";
      case "performance":
        return "수행평가";
      case "assignment":
        return "과제";
      case "notice":
        return "공지";
      default:
        return "일정";
    }
  }

  function shouldCreateReminder(category, userData) {
    const settings = userData.notificationSettings || {};
    if (category === "exam") {
      return settings.examEnabled === true;
    }
    if (category === "performance") {
      return settings.performanceEnabled === true;
    }
    return false;
  }

  function idealReminderDate(startDate) {
    const { year, month, day } = toKstParts(startDate);
    return fromKst(year, month, day - 1, 18, 0);
  }

  function buildReminderDate(startDate) {
    const reminderAt = idealReminderDate(startDate);
    const current = now();
    if (reminderAt <= current) {
      return new Date(current.getTime() + 60 * 1000);
    }
    return reminderAt;
  }

  async function upsertEventReminder({
    eventId,
    userId,
    startDate,
    type,
  }) {
    const notificationId = `${eventId}_${userId}_${type}`;
    const notificationRef = db.collection("notifications").doc(notificationId);
    const scheduledAt = Timestamp.fromDate(buildReminderDate(startDate));

    await db.runTransaction(async (transaction) => {
      const existing = await transaction.get(notificationRef);
      if (existing.exists && existing.data().sent === true) {
        return;
      }

      transaction.set(notificationRef, {
        userId,
        eventId,
        scheduledAt,
        type,
        sent: false,
      });
    });
  }

  async function clearPendingEventNotifications(eventId) {
    const snapshot = await db
      .collection("notifications")
      .where("eventId", "==", eventId)
      .where("sent", "==", false)
      .get();

    if (snapshot.empty) {
      return 0;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    return snapshot.size;
  }

  async function syncEventNotificationsForEvent(eventId, afterData) {
    if (!afterData) {
      const deletedCount = await clearPendingEventNotifications(eventId);
      logInfo("Deleted pending notifications for removed event", {
        eventId,
        deletedCount,
      });
      return { eventId, targetCount: 0, deletedCount };
    }

    const deletedCount = await clearPendingEventNotifications(eventId);
    const startDate = toDate(afterData.startDate);
    if (!startDate || startDate < startOfKstDay(now())) {
      logInfo("Skipped event reminder sync because event is stale", {
        eventId,
        deletedCount,
      });
      return { eventId, targetCount: 0, deletedCount };
    }

    const memberIds = Array.isArray(afterData.memberIds)
      ? afterData.memberIds
      : [];
    const targetUserIds =
      afterData.classId === "personal"
        ? [afterData.createdBy]
        : memberIds;

    const uniqueUserIds = [...new Set(targetUserIds)].filter(Boolean);
    if (uniqueUserIds.length === 0) {
      logInfo("Skipped event reminder sync because no target users exist", {
        eventId,
        deletedCount,
      });
      return { eventId, targetCount: 0, deletedCount };
    }

    const type = "event_default";
    let reminderCount = 0;
    for (const userId of uniqueUserIds) {
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data() || {};

      if (!shouldCreateReminder(afterData.category, userData)) {
        continue;
      }

      await upsertEventReminder({
        eventId,
        userId,
        startDate,
        type,
      });
      reminderCount += 1;
    }

    logInfo("Synced notifications for event", {
      eventId,
      targetCount: uniqueUserIds.length,
      reminderCount,
      deletedCount,
    });
    return { eventId, targetCount: uniqueUserIds.length, reminderCount };
  }

  async function syncUpcomingEventNotifications({
    horizonDays = DEFAULT_EVENT_SYNC_HORIZON_DAYS,
  } = {}) {
    const current = now();
    const windowStart = startOfKstDay(current);
    const windowEnd = endOfKstDayOffset(current, horizonDays);
    const snapshot = await db
      .collection("events")
      .where("startDate", ">=", Timestamp.fromDate(windowStart))
      .where("startDate", "<=", Timestamp.fromDate(windowEnd))
      .get();

    let reminderCount = 0;
    for (const eventDoc of snapshot.docs) {
      const result = await syncEventNotificationsForEvent(
        eventDoc.id,
        eventDoc.data(),
      );
      reminderCount += result.reminderCount || 0;
    }

    logInfo("Synced upcoming event notifications", {
      eventCount: snapshot.size,
      reminderCount,
      horizonDays,
    });
    return {
      eventCount: snapshot.size,
      reminderCount,
      horizonDays,
    };
  }

  function cleanDishNames(raw) {
    return String(raw || "")
      .replace(/<br\s*\/?>/gi, "\n")
      .replace(/\d+\./g, "")
      .replace(/[()]/g, "")
      .split("\n")
      .map((dish) => dish.trim())
      .filter(Boolean);
  }

  function shortMealBody(dishes) {
    const body = dishes.slice(0, 6).join(", ");
    if (body.length <= 160) {
      return body;
    }
    return `${body.substring(0, 157)}...`;
  }

  async function fetchLunchMeal(dateKey) {
    if (!neisApiKey) {
      logWarn("Skipped meal notification because NEIS_API_KEY is missing");
      return null;
    }

    const params = new URLSearchParams({
      KEY: neisApiKey,
      Type: "json",
      ATPT_OFCDC_SC_CODE: OFFICE_CODE,
      SD_SCHUL_CODE: SCHOOL_CODE,
      MLSV_YMD: dateKey,
    });

    const response = await fetch(
      `${NEIS_BASE_URL}/mealServiceDietInfo?${params.toString()}`,
    );

    if (!response.ok) {
      throw new Error(`NEIS meal request failed: HTTP ${response.status}`);
    }

    const data = await response.json();
    if (data.RESULT) {
      return null;
    }

    const rows = data.mealServiceDietInfo?.[1]?.row;
    if (!Array.isArray(rows)) {
      throw new Error("Unexpected NEIS meal response shape");
    }

    const lunch = rows.find((row) => String(row.MMEAL_SC_NM || "") === "중식");
    if (!lunch) {
      return null;
    }

    return {
      name: lunch.MMEAL_SC_NM || "중식",
      dishes: cleanDishNames(lunch.DDISH_NM),
      calories: lunch.CAL_INFO || "",
    };
  }

  function isMealNotificationDue(settings, nowMinutes) {
    if (!settings || settings.mealEnabled !== true) {
      return false;
    }

    const hour = settings.mealHour;
    const minute = settings.mealMinute;
    if (!Number.isInteger(hour) || !Number.isInteger(minute)) {
      return false;
    }

    const targetMinutes = hour * 60 + minute;
    return nowMinutes >= targetMinutes && nowMinutes < targetMinutes + 15;
  }

  async function removeInvalidTokens(userDoc, invalidTokens) {
    if (invalidTokens.length === 0) {
      return;
    }

    await userDoc.ref.set(
      {
        fcmTokens: FieldValue.arrayRemove(...invalidTokens),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }

  function collectInvalidTokens(response, tokens) {
    const invalidTokens = [];
    response.responses.forEach((result, index) => {
      if (!result.error) {
        return;
      }

      const code = result.error.code;
      if (
        code === "messaging/invalid-registration-token" ||
        code === "messaging/registration-token-not-registered"
      ) {
        invalidTokens.push(tokens[index]);
      }
    });
    return invalidTokens;
  }

  async function sendMealNotification({ userDoc, dateKey, meal }) {
    const userData = userDoc.data() || {};
    const tokens = Array.isArray(userData.fcmTokens)
      ? userData.fcmTokens.filter(
          (token) => typeof token === "string" && token.length > 0,
        )
      : [];

    if (tokens.length === 0) {
      return { sent: false, reason: "no_tokens" };
    }

    const notificationRef = db
      .collection("notifications")
      .doc(`meal_${dateKey}_${userDoc.id}`);

    try {
      await notificationRef.create({
        userId: userDoc.id,
        scheduledAt: Timestamp.fromDate(now()),
        type: "meal",
        sent: false,
      });
    } catch (error) {
      if (error.code === 6 || error.code === "already-exists") {
        return { sent: false, reason: "already_sent" };
      }
      throw error;
    }

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: "오늘의 급식",
        body: meal.dishes.length > 0
          ? shortMealBody(meal.dishes)
          : "오늘 중식 정보를 확인해 보세요",
      },
      data: {
        notificationId: notificationRef.id,
        type: "meal",
        route: "meal",
        date: dateKey,
      },
      android: {
        priority: "high",
      },
      apns: {
        headers: {
          "apns-priority": "10",
        },
      },
    });

    await removeInvalidTokens(userDoc, collectInvalidTokens(response, tokens));
    await notificationRef.update({ sent: true });
    return {
      sent: true,
      successCount: response.successCount,
      failureCount: response.failureCount,
    };
  }

  async function dispatchMealNotifications() {
    const current = now();
    const dateKey = formatKstDateKey(toKstParts(current));
    const nowMinutes = kstMinutesSinceMidnight(current);

    const usersSnapshot = await db
      .collection("users")
      .where("notificationSettings.mealEnabled", "==", true)
      .get();

    const dueUsers = usersSnapshot.docs.filter((userDoc) => {
      const settings = userDoc.data().notificationSettings || {};
      return isMealNotificationDue(settings, nowMinutes);
    });

    if (dueUsers.length === 0) {
      logInfo("No meal notification targets for this window");
      return { dateKey, targetCount: 0, sentCount: 0 };
    }

    const meal = await fetchLunchMeal(dateKey);
    if (!meal) {
      logInfo("Skipped meal notification because no lunch data exists", {
        dateKey,
      });
      return { dateKey, targetCount: dueUsers.length, sentCount: 0 };
    }

    let sentCount = 0;
    for (const userDoc of dueUsers) {
      const result = await sendMealNotification({ userDoc, dateKey, meal });
      if (result.sent) {
        sentCount += 1;
      }
    }

    logInfo("Dispatched meal notifications", {
      dateKey,
      targetCount: dueUsers.length,
      sentCount,
    });
    return { dateKey, targetCount: dueUsers.length, sentCount };
  }

  async function maybeRescheduleEventNotification({
    notificationDoc,
    notification,
    eventData,
    userData,
    current,
  }) {
    if (!shouldCreateReminder(eventData.category, userData)) {
      await notificationDoc.ref.delete();
      return true;
    }

    const startDate = toDate(eventData.startDate);
    if (!startDate || startDate < startOfKstDay(current)) {
      await notificationDoc.ref.delete();
      return true;
    }

    const reminderAt = idealReminderDate(startDate);
    if (reminderAt > current) {
      await notificationDoc.ref.update({
        scheduledAt: Timestamp.fromDate(reminderAt),
      });
      return true;
    }

    const scheduledAt = toDate(notification.scheduledAt);
    if (!scheduledAt || scheduledAt > current) {
      return true;
    }

    return false;
  }

  async function dispatchScheduledNotifications() {
    const current = now();
    const snapshot = await db
      .collection("notifications")
      .where("sent", "==", false)
      .where("scheduledAt", "<=", Timestamp.fromDate(current))
      .limit(50)
      .get();

    if (snapshot.empty) {
      logInfo("No scheduled notifications to send");
      return { scannedCount: 0, sentCount: 0 };
    }

    let sentCount = 0;
    for (const notificationDoc of snapshot.docs) {
      const notification = notificationDoc.data();
      const userId = notification.userId;
      const eventId = notification.eventId;

      if (!eventId && notification.type === "meal") {
        await notificationDoc.ref.update({ sent: true });
        continue;
      }

      const [userDoc, eventDoc] = await Promise.all([
        db.collection("users").doc(userId).get(),
        eventId ? db.collection("events").doc(eventId).get() : null,
      ]);

      if (eventId && (!eventDoc || !eventDoc.exists)) {
        await notificationDoc.ref.delete();
        logInfo("Deleted stale notification for missing event", {
          notificationId: notificationDoc.id,
          eventId,
        });
        continue;
      }

      const userData = userDoc.data() || {};
      const eventData = eventDoc && eventDoc.exists ? eventDoc.data() : null;
      if (eventData) {
        const handled = await maybeRescheduleEventNotification({
          notificationDoc,
          notification,
          eventData,
          userData,
          current,
        });
        if (handled) {
          continue;
        }
      }

      const tokens = Array.isArray(userData.fcmTokens)
        ? userData.fcmTokens.filter(
            (token) => typeof token === "string" && token.length > 0,
          )
        : [];

      if (tokens.length === 0) {
        await notificationDoc.ref.update({ sent: true });
        continue;
      }

      const title = eventData
        ? `${eventCategoryLabel(eventData.category)} 일정 알림`
        : "일정 알림";
      const body = eventData
        ? `${eventData.title} 일정이 예정되어 있어요`
        : "예정된 일정 알림이 도착했어요";

      const response = await messaging.sendEachForMulticast({
        tokens,
        notification: {
          title,
          body,
        },
        data: {
          notificationId: notificationDoc.id,
          eventId: eventId || "",
          type: notification.type || "",
          route: "calendar",
        },
        android: {
          priority: "high",
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
        },
      });

      await removeInvalidTokens(userDoc, collectInvalidTokens(response, tokens));
      await notificationDoc.ref.update({ sent: true });
      sentCount += 1;

      logInfo("Dispatched notification", {
        notificationId: notificationDoc.id,
        successCount: response.successCount,
        failureCount: response.failureCount,
      });
    }

    return { scannedCount: snapshot.size, sentCount };
  }

  async function runScheduledNotificationJobs() {
    const eventSync = await syncUpcomingEventNotifications();
    const mealDispatch = await dispatchMealNotifications();
    const scheduledDispatch = await dispatchScheduledNotifications();
    return { eventSync, mealDispatch, scheduledDispatch };
  }

  return {
    dispatchMealNotifications,
    dispatchScheduledNotifications,
    runScheduledNotificationJobs,
    syncEventNotificationsForEvent,
    syncUpcomingEventNotifications,
  };
}

module.exports = { createNotificationDispatcher };
