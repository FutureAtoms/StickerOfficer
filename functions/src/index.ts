import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

/**
 * Fan-out on write: When a pack is published, add it to followers' feeds
 */
export const onPackPublished = functions.firestore
  .document("packs/{packId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const packId = context.params.packId;

    // Only trigger when status changes to "published"
    if (before.status === "published" || after.status !== "published") {
      return null;
    }

    const authorId = after.authorId;
    const followersSnapshot = await db
      .collection(`users/${authorId}/followers`)
      .get();

    const batch = db.batch();
    const feedItem = {
      packId,
      packName: after.name,
      authorId: after.authorId,
      authorName: after.authorName,
      previewUrl: after.previewUrls?.[0] || "",
      stickerCount: after.stickerCount || 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    for (const follower of followersSnapshot.docs) {
      const feedRef = db
        .collection(`users/${follower.id}/feed`)
        .doc(packId);
      batch.set(feedRef, feedItem);
    }

    return batch.commit();
  });

/**
 * Update trending scores periodically
 */
export const updateTrendingScores = functions.pubsub
  .schedule("every 1 hours")
  .onRun(async () => {
    const packsSnapshot = await db
      .collection("packs")
      .where("isPublic", "==", true)
      .where("status", "==", "published")
      .orderBy("publishedAt", "desc")
      .limit(100)
      .get();

    const batch = db.batch();

    for (const pack of packsSnapshot.docs) {
      const data = pack.data();
      const score = (data.likeCount || 0) * 2 + (data.downloadCount || 0) * 3;

      const trendingRef = db.collection("trending").doc(pack.id);
      batch.set(trendingRef, {
        score,
        packId: pack.id,
        name: data.name,
        authorName: data.authorName,
        previewUrls: data.previewUrls || [],
        stickerCount: data.stickerCount || 0,
        likeCount: data.likeCount || 0,
        downloadCount: data.downloadCount || 0,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return batch.commit();
  });

/**
 * Send push notification when someone likes a pack
 */
export const onLikeCreated = functions.firestore
  .document("likes/{likeId}")
  .onCreate(async (snapshot) => {
    const data = snapshot.data();
    if (data.targetType !== "pack") return null;

    const packDoc = await db.collection("packs").doc(data.targetId).get();
    if (!packDoc.exists) return null;

    const packData = packDoc.data()!;
    const authorDoc = await db
      .collection("users")
      .doc(packData.authorId)
      .get();
    if (!authorDoc.exists) return null;

    const authorData = authorDoc.data()!;
    const tokens: string[] = authorData.fcmTokens || [];

    if (tokens.length === 0) return null;

    // Increment like count
    await packDoc.ref.update({
      likeCount: admin.firestore.FieldValue.increment(1),
    });

    // Send notification
    const actorDoc = await db.collection("users").doc(data.userId).get();
    const actorName = actorDoc.data()?.displayName || "Someone";

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title: "New like!",
        body: `${actorName} liked your pack "${packData.name}"`,
      },
      data: {
        type: "like",
        packId: data.targetId,
      },
    };

    return admin.messaging().sendEachForMulticast(message);
  });

/**
 * Challenge status auto-transition
 */
export const manageChallengeStatus = functions.pubsub
  .schedule("every 1 hours")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    // Activate upcoming challenges
    const upcomingSnapshot = await db
      .collection("challenges")
      .where("status", "==", "upcoming")
      .where("startDate", "<=", now)
      .get();

    for (const doc of upcomingSnapshot.docs) {
      await doc.ref.update({status: "active"});
    }

    // Move to voting phase
    const activeSnapshot = await db
      .collection("challenges")
      .where("status", "==", "active")
      .where("endDate", "<=", now)
      .get();

    for (const doc of activeSnapshot.docs) {
      await doc.ref.update({status: "voting"});
    }

    return null;
  });

/**
 * AI Generation proxy — protects Hugging Face API key
 */
export const generateSticker = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Must be logged in to generate stickers"
    );
  }

  const {prompt} = data;
  if (!prompt || typeof prompt !== "string" || prompt.length > 500) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Invalid prompt"
    );
  }

  // Rate limiting check
  const userId = context.auth.uid;
  const userDoc = await db.collection("users").doc(userId).get();
  const isPremium = userDoc.data()?.isPremium || false;
  const dailyLimit = isPremium ? 999 : 5;

  // TODO: Implement daily usage counter and Hugging Face API call
  // For now, return placeholder
  return {
    success: true,
    images: [],
    remaining: dailyLimit,
  };
});
