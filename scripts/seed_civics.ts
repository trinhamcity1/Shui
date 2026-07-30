/**
 * Seeds the 11 fixed categories and one real topic — the official 2025
 * U.S. Citizenship civics test — as prompts/phase-01-backend.md §6 describes.
 *
 * This seeds *structure and quizzes*, not footage: each video document is a
 * `status: "pending"` shell with no `playbackURL`. A creator uploads real
 * video against these shells later (Phase 5). Safe to re-run — every write
 * is `.set(..., { merge: true })` against a deterministic id.
 *
 * Usage:
 *   SEED_ADMIN_UID=<uid> npm run seed:civics
 *
 * Get a uid by running bootstrap-admin.ts first. Against the emulator suite,
 * run this via `firebase emulators:exec` (see functions/package.json's
 * seed:local) so FIRESTORE_EMULATOR_HOST/FIREBASE_AUTH_EMULATOR_HOST are set
 * and nothing touches a real project.
 */
import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? "shui-prod" });
const db = admin.firestore();

const ADMIN_UID = process.env.SEED_ADMIN_UID;
const CIVICS_TOPIC_ID = "uscis-civics-2025";
const CHUNK_SIZE = 5;

interface SourceQuestion {
  officialId2025: number;
  category: string;
  questionEN: string;
  answersEN: string[];
  is65_20_2025: boolean;
  requiredAnswerCount: number;
  note: string | null;
  dynamicType: string | null;
  officeholderRole: string | null;
}

const CATEGORIES: Array<{
  slug: string;
  title: string;
  description: string;
  sfSymbol: string;
  accentHex: string;
}> = [
  {
    slug: "personal-development",
    title: "Personal Development",
    description: "Habits, focus, discipline, and how to actually change behavior.",
    sfSymbol: "figure.mind.and.body",
    accentHex: "22C55E",
  },
  {
    slug: "book-summaries",
    title: "Book Summaries",
    description: "The core argument of a book in the time it takes to make coffee.",
    sfSymbol: "book.closed",
    accentHex: "8B5CF6",
  },
  {
    slug: "skills",
    title: "Skills",
    description: "Concrete, practical abilities you can start using today.",
    sfSymbol: "wrench.and.screwdriver",
    accentHex: "0EA5E9",
  },
  {
    slug: "exam-prep",
    title: "Exam Prep",
    description: "Structured preparation for real tests, one question at a time.",
    sfSymbol: "checkmark.seal",
    accentHex: "F59E0B",
  },
  {
    slug: "money-finance",
    title: "Money & Finance",
    description: "Personal finance, investing basics, and how money actually works.",
    sfSymbol: "dollarsign.circle",
    accentHex: "10B981",
  },
  {
    slug: "career-business",
    title: "Career & Business",
    description: "Interviews, negotiation, management, and building something.",
    sfSymbol: "briefcase",
    accentHex: "6366F1",
  },
  {
    slug: "language-communication",
    title: "Language & Communication",
    description: "Speaking, writing, and being understood.",
    sfSymbol: "bubble.left.and.bubble.right",
    accentHex: "EC4899",
  },
  {
    slug: "science-tech",
    title: "Science & Technology",
    description: "How the physical and digital world works, explained plainly.",
    sfSymbol: "atom",
    accentHex: "06B6D4",
  },
  {
    slug: "health-fitness",
    title: "Health & Fitness",
    description: "Training, nutrition, sleep, and the evidence behind them.",
    sfSymbol: "heart",
    accentHex: "EF4444",
  },
  {
    slug: "history-culture",
    title: "History & Culture",
    description: "Events, ideas, and people worth knowing about.",
    sfSymbol: "building.columns",
    accentHex: "A855F7",
  },
  {
    slug: "creativity-arts",
    title: "Creativity & Arts",
    description: "Craft and technique across writing, music, design, and film.",
    sfSymbol: "paintbrush",
    accentHex: "F97316",
  },
];

const SECTION_TITLES: Record<string, string> = {
  gov_principles: "Principles of American Democracy",
  gov_system: "System of Government",
  gov_rights: "Rights and Responsibilities",
  history_colonial: "Colonial Period and Independence",
  history_1800s: "The 1800s",
  history_recent: "Recent American History",
  symbols: "Symbols",
  holidays: "Holidays",
};

async function seedCategories(): Promise<void> {
  const batch = db.batch();
  CATEGORIES.forEach((category, index) => {
    batch.set(
      db.collection("categories").doc(category.slug),
      {
        title: category.title,
        slug: category.slug,
        description: category.description,
        sfSymbol: category.sfSymbol,
        accentHex: category.accentHex,
        sortOrder: index,
        topicCount: admin.firestore.FieldValue.increment(0),
        isActive: true,
      },
      { merge: true }
    );
  });
  await batch.commit();
  console.log(`Seeded ${CATEGORIES.length} categories.`);
}

function chunk<T>(items: T[], size: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

/** Deterministic (not random) so re-running the script produces identical
 * quiz content — required for the seed to actually be idempotent. */
function pickDistractors(pool: string[], count: number, seed: number): string[] {
  const sorted = [...new Set(pool)].sort();
  if (sorted.length === 0) return [];
  const picked: string[] = [];
  let index = seed % sorted.length;
  let guard = 0;
  while (picked.length < count && picked.length < sorted.length && guard < sorted.length * 2) {
    const candidate = sorted[index % sorted.length];
    if (candidate !== undefined && !picked.includes(candidate)) {
      picked.push(candidate);
    }
    index += 7;
    guard += 1;
  }
  return picked;
}

interface BuiltQuestion {
  id: string;
  prompt: string;
  options: Array<{ id: string; text: string }>;
  correctOptionIds: string[];
  requiredCorrectCount: number;
  explanation: string;
  orderIndex: number;
}

function buildQuizForChunk(chunkQuestions: SourceQuestion[], sectionQuestions: SourceQuestion[]): BuiltQuestion[] {
  return chunkQuestions.map((question, index) => {
    const correctAnswer = question.answersEN[0];
    if (correctAnswer === undefined) {
      throw new Error(`Question #${question.officialId2025} has no accepted answers.`);
    }

    const ownAnswers = new Set(question.answersEN.map((a) => a.toLowerCase()));
    const pool = sectionQuestions
      .filter((other) => other.officialId2025 !== question.officialId2025)
      .flatMap((other) => other.answersEN)
      .filter((answer) => !ownAnswers.has(answer.toLowerCase()));
    const distractors = pickDistractors(pool, 3, question.officialId2025);

    return {
      id: `q${question.officialId2025}`,
      prompt: question.questionEN,
      options: [
        { id: "correct", text: correctAnswer },
        ...distractors.map((text, i) => ({ id: `d${i + 1}`, text })),
      ],
      correctOptionIds: ["correct"],
      requiredCorrectCount: 1,
      explanation: `USCIS accepts: ${question.answersEN.join("; ")}.`,
      orderIndex: index,
    };
  });
}

async function seedCivicsTopic(): Promise<void> {
  if (!ADMIN_UID) {
    throw new Error(
      "SEED_ADMIN_UID is not set. Run bootstrap-admin.ts first to grant an account the admin " +
        "claim, then re-run with SEED_ADMIN_UID=<uid> npm run seed:civics."
    );
  }

  const sourcePath = path.join(__dirname, "sources", "official_2025_civics.json");
  const allQuestions: SourceQuestion[] = JSON.parse(fs.readFileSync(sourcePath, "utf8"));

  const skipped = allQuestions.filter((q) => q.dynamicType !== null);
  const usable = allQuestions.filter((q) => q.dynamicType === null);
  console.log(
    `Skipping ${skipped.length} time-sensitive/state-specific question(s): ` +
      skipped.map((q) => `#${q.officialId2025} (${q.questionEN})`).join(", ")
  );

  const bySection = new Map<string, SourceQuestion[]>();
  for (const question of usable) {
    const list = bySection.get(question.category) ?? [];
    list.push(question);
    bySection.set(question.category, list);
  }

  await db.collection("topics").doc(CIVICS_TOPIC_ID).set(
    {
      title: "U.S. Citizenship Civics Test (2025)",
      subtitle: "All 128 official questions, USCIS form M-1778 (09/25)",
      description:
        "Every question from the official 2025 U.S. Citizenship civics test, grouped by " +
        "section. Time-sensitive and state-specific questions — the current President, Vice " +
        "President, Speaker of the House, Chief Justice, your senators, your representative, " +
        "your governor, and your state capital — are covered separately, not guessed at here.",
      categoryId: "exam-prep",
      coverImageURL: null,
      visibility: "private",
      createdBy: ADMIN_UID,
      createdByName: "Shui",
      tags: ["civics", "citizenship", "uscis"],
      isDeleted: false,
    },
    { merge: true }
  );

  let videoCount = 0;
  let order = 0;

  for (const [sectionKey, sectionQuestions] of bySection) {
    const sectionTitle = SECTION_TITLES[sectionKey] ?? sectionKey;
    const chunks = chunk(sectionQuestions, CHUNK_SIZE);

    for (let chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
      const chunkQuestions = chunks[chunkIndex];
      if (!chunkQuestions || chunkQuestions.length === 0) continue;

      const videoId = `${CIVICS_TOPIC_ID}-${sectionKey}-${String(chunkIndex + 1).padStart(2, "0")}`;
      const videoTitle = chunks.length > 1 ? `${sectionTitle} (${chunkIndex + 1} of ${chunks.length})` : sectionTitle;
      const firstId = chunkQuestions[0]!.officialId2025;
      const lastId = chunkQuestions[chunkQuestions.length - 1]!.officialId2025;

      const videoRef = db.collection("videos").doc(videoId);
      await videoRef.set(
        {
          topicId: CIVICS_TOPIC_ID,
          topicTitle: "U.S. Citizenship Civics Test (2025)",
          categoryId: "exam-prep",
          topicVisibility: "private",
          title: videoTitle,
          description: `Questions ${firstId}–${lastId} of the official 2025 civics test.`,
          order,
          playbackURL: "",
          thumbnailURL: null,
          durationSeconds: 0,
          aspectRatio: 0.5625,
          sizeBytes: 0,
          transcript: null,
          visibility: "private",
          status: "pending",
          statusMessage: "Awaiting video upload — quiz and structure are seeded, footage is not.",
          createdBy: ADMIN_UID,
          hasQuiz: true,
          likeCount: 0,
          commentCount: 0,
          viewCount: 0,
          completionCount: 0,
          isDeleted: false,
        },
        { merge: true }
      );

      const questions = buildQuizForChunk(chunkQuestions, sectionQuestions);
      await videoRef
        .collection("quiz")
        .doc("current")
        .set(
          {
            version: 1,
            questions: questions.map((q) => ({
              id: q.id,
              prompt: q.prompt,
              options: q.options,
              requiredCorrectCount: q.requiredCorrectCount,
              orderIndex: q.orderIndex,
            })),
            passThreshold: 0.6,
            updatedBy: ADMIN_UID,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
      await videoRef
        .collection("quiz")
        .doc("answers")
        .set(
          {
            version: 1,
            answers: questions.map((q) => ({
              id: q.id,
              correctOptionIds: q.correctOptionIds,
              explanation: q.explanation,
            })),
          },
          { merge: true }
        );

      videoCount += 1;
      order += 1;
    }
  }

  console.log(
    `Seeded topic "${CIVICS_TOPIC_ID}" with ${videoCount} video shell(s) across ${bySection.size} section(s).`
  );
}

async function main(): Promise<void> {
  await seedCategories();
  await seedCivicsTopic();
  console.log("Done.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
