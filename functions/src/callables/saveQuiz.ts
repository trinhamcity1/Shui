import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin";
import { requireAuth } from "../lib/auth";
import { parseInput } from "../lib/validate";
import { QuizInputSchema, splitQuizForStorage } from "../schemas/quiz";

export const saveQuiz = onCall(async (request) => {
  const uid = requireAuth(request);
  const input = parseInput(QuizInputSchema, request.data);
  const isAdmin = request.auth!.token.role === "admin";

  const videoRef = db.collection("videos").doc(input.videoId);
  const currentRef = videoRef.collection("quiz").doc("current");
  const answersRef = videoRef.collection("quiz").doc("answers");

  const stored = await db.runTransaction(async (t) => {
    const [videoSnap, currentSnap] = await Promise.all([t.get(videoRef), t.get(currentRef)]);
    if (!videoSnap.exists) {
      throw new HttpsError("not-found", "Video not found.");
    }
    const video = videoSnap.data()!;
    if (video.createdBy !== uid && !isAdmin) {
      throw new HttpsError("permission-denied", "You do not own this video.");
    }

    const nextVersion = currentSnap.exists ? (currentSnap.data()!.version ?? 0) + 1 : 1;
    const { current, answers } = splitQuizForStorage(input, nextVersion, uid, FieldValue.serverTimestamp());

    t.set(currentRef, current);
    t.set(answersRef, answers);
    t.update(videoRef, { hasQuiz: true, updatedAt: FieldValue.serverTimestamp() });

    return current;
  });

  return stored;
});
