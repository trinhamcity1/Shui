import { db } from "../lib/admin";
import { StoredQuizAnswers, StoredQuizCurrent } from "../schemas/quiz";

export interface GroundingContext {
  video: {
    title: string;
    description: string;
    transcript: string | null;
  };
  topic: {
    title: string;
    description: string;
    previousVideoTitle: string | null;
    nextVideoTitle: string | null;
  };
  /** `null` when the video has no quiz at all — distinct from an empty array. */
  quiz: Array<{
    questionId: string;
    prompt: string;
    correctAnswerText: string;
    explanation: string;
  }> | null;
  learnerRecord: {
    quizAttempts: number;
    quizBestScore: number | null;
    quizPassed: boolean;
    missedQuestionPrompts: string[];
    topicMasteryPercent: number | null;
  };
  /** Oldest first — natural reading order for the model. */
  recentMessages: Array<{ role: "user" | "assistant"; content: string }>;
}

// ~3k tokens at a rough 4 chars/token — keeps context (and therefore cost)
// bounded regardless of how long a creator-provided transcript runs. A real
// relevance-ranked excerpt (keeping only segments near the learner's
// question) is the eventual right answer per the phase spec, but nothing in
// this app has a real transcript yet to rank against — a flat truncation is
// the honest, testable version of that requirement today.
const TRANSCRIPT_CHAR_BUDGET = 12000;

export async function assembleGroundingContext(params: {
  uid: string;
  videoId: string;
}): Promise<GroundingContext | null> {
  const videoRef = db.collection("videos").doc(params.videoId);
  const videoSnap = await videoRef.get();
  if (!videoSnap.exists) {
    return null;
  }
  const video = videoSnap.data()!;

  const [topicSnap, currentSnap, answersSnap, videoProgressSnap, topicProgressSnap, messagesSnap, siblingsSnap] =
    await Promise.all([
      db.collection("topics").doc(video.topicId).get(),
      videoRef.collection("quiz").doc("current").get(),
      videoRef.collection("quiz").doc("answers").get(),
      db.collection("users").doc(params.uid).collection("videoProgress").doc(params.videoId).get(),
      db.collection("users").doc(params.uid).collection("topicProgress").doc(video.topicId).get(),
      videoRef.collection("aiThreads").doc(params.uid).collection("messages").orderBy("createdAt", "desc").limit(10).get(),
      db
        .collection("videos")
        .where("topicId", "==", video.topicId)
        .where("status", "==", "ready")
        .where("isDeleted", "==", false)
        .orderBy("order")
        .get(),
    ]);

  const topic = topicSnap.exists ? topicSnap.data()! : null;

  let quiz: GroundingContext["quiz"] = null;
  if (currentSnap.exists && answersSnap.exists) {
    const current = currentSnap.data() as StoredQuizCurrent;
    const answers = answersSnap.data() as StoredQuizAnswers;
    const answersById = new Map(answers.answers.map((a) => [a.id, a]));
    quiz = current.questions.map((q) => {
      const answer = answersById.get(q.id);
      const correctIds = new Set(answer?.correctOptionIds ?? []);
      const correctAnswerText =
        q.options
          .filter((o) => correctIds.has(o.id))
          .map((o) => o.text)
          .join(" / ") || "(not available)";
      return { questionId: q.id, prompt: q.prompt, correctAnswerText, explanation: answer?.explanation ?? "" };
    });
  }

  const vp = videoProgressSnap.exists ? videoProgressSnap.data()! : null;
  const missedIds: string[] = vp?.lastMissedQuestionIds ?? [];
  const missedQuestionPrompts = quiz ? quiz.filter((q) => missedIds.includes(q.questionId)).map((q) => q.prompt) : [];
  const tp = topicProgressSnap.exists ? topicProgressSnap.data()! : null;

  const siblings = siblingsSnap.docs.map((d) => ({ id: d.id, title: d.data().title as string }));
  const currentIndex = siblings.findIndex((s) => s.id === params.videoId);
  const previousVideoTitle = currentIndex > 0 ? siblings[currentIndex - 1]!.title : null;
  const nextVideoTitle =
    currentIndex >= 0 && currentIndex < siblings.length - 1 ? siblings[currentIndex + 1]!.title : null;

  const rawTranscript: string | null = video.transcript ?? null;
  const transcript =
    rawTranscript && rawTranscript.length > TRANSCRIPT_CHAR_BUDGET
      ? `${rawTranscript.slice(0, TRANSCRIPT_CHAR_BUDGET)}\n[transcript truncated for length]`
      : rawTranscript;

  const recentMessages = messagesSnap.docs
    .map((d) => {
      const data = d.data();
      return { role: data.role as "user" | "assistant", content: data.text as string };
    })
    .reverse();

  return {
    video: { title: video.title, description: video.description, transcript },
    topic: {
      title: topic?.title ?? "",
      description: topic?.description ?? "",
      previousVideoTitle,
      nextVideoTitle,
    },
    quiz,
    learnerRecord: {
      quizAttempts: vp?.quizAttempts ?? 0,
      quizBestScore: vp?.quizBestScore ?? null,
      quizPassed: vp?.quizPassed ?? false,
      missedQuestionPrompts,
      topicMasteryPercent: tp?.masteryPercent ?? null,
    },
    recentMessages,
  };
}
