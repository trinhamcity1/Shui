import * as fs from "fs";
import * as path from "path";
import {
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
} from "firebase/firestore";

/**
 * One test per row of prompts/phase-01-backend.md §3, including the
 * negative case — "a rule without a failing-path test is not done."
 */

const PROJECT_ID = "demo-shui-rules-test";

let testEnv: RulesTestEnvironment;

beforeAll(async () => {
  const rules = fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8");
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

async function seedDoc(pathSegments: string, data: Record<string, unknown>) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), pathSegments), data);
  });
}

function creator(uid: string) {
  return testEnv.authenticatedContext(uid, { role: "creator", firebase: { sign_in_provider: "password" } });
}

function admin(uid: string) {
  return testEnv.authenticatedContext(uid, { role: "admin", firebase: { sign_in_provider: "password" } });
}

function learner(uid: string) {
  return testEnv.authenticatedContext(uid, { role: "learner", firebase: { sign_in_provider: "password" } });
}

function guest(uid: string) {
  return testEnv.authenticatedContext(uid, { role: "learner", firebase: { sign_in_provider: "anonymous" } });
}

function anon() {
  return testEnv.unauthenticatedContext();
}

// ---- categories/{categoryId} --------------------------------------------

describe("categories", () => {
  const category = {
    title: "Exam Prep",
    slug: "exam-prep",
    description: "Structured preparation for real tests.",
    sfSymbol: "checkmark.seal",
    accentHex: "F59E0B",
    sortOrder: 0,
    topicCount: 0,
    isActive: true,
  };

  test("anyone can read", async () => {
    await seedDoc("categories/exam-prep", category);
    await assertSucceeds(getDoc(doc(anon().firestore(), "categories/exam-prep")));
  });

  test("admin can create", async () => {
    await assertSucceeds(setDoc(doc(admin("a1").firestore(), "categories/exam-prep"), category));
  });

  test("non-admin cannot create (negative)", async () => {
    await assertFails(setDoc(doc(creator("c1").firestore(), "categories/exam-prep"), category));
    await assertFails(setDoc(doc(learner("l1").firestore(), "categories/exam-prep"), category));
  });

  test("delete is always denied, even for admin (negative)", async () => {
    await seedDoc("categories/exam-prep", category);
    await assertFails(deleteDoc(doc(admin("a1").firestore(), "categories/exam-prep")));
  });
});

// ---- topics/{topicId} ----------------------------------------------------

describe("topics", () => {
  const baseTopic = {
    title: "U.S. Citizenship Civics Test",
    subtitle: "128 official questions",
    description: "...",
    categoryId: "exam-prep",
    visibility: "private",
    createdBy: "owner1",
    createdByName: "Owner",
    videoCount: 0,
    totalDurationSec: 0,
    learnerCount: 0,
    tags: ["civics"],
    isDeleted: false,
  };

  test("public, not-deleted topic is readable by anyone", async () => {
    await seedDoc("topics/t1", { ...baseTopic, visibility: "public" });
    await assertSucceeds(getDoc(doc(anon().firestore(), "topics/t1")));
  });

  test("private topic is denied to a non-owner (negative)", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertFails(getDoc(doc(learner("someone-else").firestore(), "topics/t1")));
  });

  test("private topic is readable by its owner", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertSucceeds(getDoc(doc(creator("owner1").firestore(), "topics/t1")));
  });

  test("creator can create a topic they own, private, not deleted", async () => {
    await assertSucceeds(
      setDoc(doc(creator("owner1").firestore(), "topics/t2"), { ...baseTopic, createdBy: "owner1" })
    );
  });

  test("learner cannot create a topic (negative)", async () => {
    await assertFails(
      setDoc(doc(learner("l1").firestore(), "topics/t2"), { ...baseTopic, createdBy: "l1" })
    );
  });

  test("owner can edit plain fields", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertSucceeds(
      updateDoc(doc(creator("owner1").firestore(), "topics/t1"), { title: "Updated title" })
    );
  });

  test("owner cannot flip visibility via a direct client write (negative)", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertFails(
      updateDoc(doc(creator("owner1").firestore(), "topics/t1"), { visibility: "public" })
    );
  });

  test("delete is always denied — soft delete only (negative)", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertFails(deleteDoc(doc(creator("owner1").firestore(), "topics/t1")));
  });

  // ---- Phase 5 creator mode -------------------------------------------
  // The topic editor writes plain fields straight to Firestore (no
  // callable), so these are the rules that actually stand between a
  // creator and the fields only a Function may set.

  test("creator cannot create a topic already public — the publish gate must run (negative)", async () => {
    await assertFails(
      setDoc(doc(creator("owner1").firestore(), "topics/t2"), {
        ...baseTopic,
        createdBy: "owner1",
        visibility: "public",
      })
    );
  });

  test("creator cannot create a topic owned by someone else (negative)", async () => {
    await assertFails(
      setDoc(doc(creator("owner1").firestore(), "topics/t2"), { ...baseTopic, createdBy: "someone-else" })
    );
  });

  test("admin can read another creator's private topic — the all-topics admin view", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertSucceeds(getDoc(doc(admin("a1").firestore(), "topics/t1")));
  });

  test("admin can edit another creator's topic", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertSucceeds(updateDoc(doc(admin("a1").firestore(), "topics/t1"), { title: "Retitled by admin" }));
  });

  test("a different creator cannot edit someone else's topic (negative)", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertFails(updateDoc(doc(creator("other").firestore(), "topics/t1"), { title: "Hijacked" }));
  });

  test("owner cannot inflate learnerCount or videoCount by hand (negative)", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertFails(updateDoc(doc(creator("owner1").firestore(), "topics/t1"), { learnerCount: 9999 }));
    await assertFails(updateDoc(doc(creator("owner1").firestore(), "topics/t1"), { videoCount: 42 }));
  });

  test("owner cannot reassign a topic to another creator (negative)", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertFails(updateDoc(doc(creator("owner1").firestore(), "topics/t1"), { createdBy: "someone-else" }));
  });

  test("owner can edit the cover image and tags the editor actually writes", async () => {
    await seedDoc("topics/t1", baseTopic);
    await assertSucceeds(
      updateDoc(doc(creator("owner1").firestore(), "topics/t1"), {
        coverImageURL: "https://cdn.example.com/covers/t1.jpg",
        tags: ["civics", "government"],
        subtitle: "Updated subtitle",
      })
    );
  });
});

// ---- videos/{videoId} + quiz subdocs -------------------------------------

describe("videos", () => {
  const publicReadyVideo = {
    topicId: "t1",
    topicTitle: "Civics",
    categoryId: "exam-prep",
    topicVisibility: "public",
    title: "Video 1",
    description: "",
    order: 0,
    r2Key: "videos/v1.mp4",
    playbackURL: "https://example.com/v1.mp4",
    durationSeconds: 60,
    aspectRatio: 0.5625,
    sizeBytes: 1000,
    visibility: "public",
    status: "ready",
    createdBy: "owner1",
    hasQuiz: true,
    likeCount: 0,
    commentCount: 0,
    viewCount: 0,
    completionCount: 0,
    isDeleted: false,
  };

  test("ready + public + parent-public video is readable by anyone", async () => {
    await seedDoc("videos/v1", publicReadyVideo);
    await assertSucceeds(getDoc(doc(anon().firestore(), "videos/v1")));
  });

  test("private video is denied to a non-owner (negative)", async () => {
    await seedDoc("videos/v1", { ...publicReadyVideo, visibility: "private" });
    await assertFails(getDoc(doc(learner("someone-else").firestore(), "videos/v1")));
  });

  test("owner can read their own private video", async () => {
    await seedDoc("videos/v1", { ...publicReadyVideo, visibility: "private" });
    await assertSucceeds(getDoc(doc(creator("owner1").firestore(), "videos/v1")));
  });

  test("all client writes are denied, even for the owner (negative)", async () => {
    await seedDoc("videos/v1", publicReadyVideo);
    await assertFails(updateDoc(doc(creator("owner1").firestore(), "videos/v1"), { title: "Hacked" }));
    await assertFails(
      setDoc(doc(creator("owner1").firestore(), "videos/v2"), { ...publicReadyVideo, createdBy: "owner1" })
    );
  });

  describe("quiz/current", () => {
    const quizCurrent = {
      version: 1,
      questions: [{ id: "q1", prompt: "What is the supreme law?", options: [{ id: "a", text: "The Constitution" }], requiredCorrectCount: 1, orderIndex: 0 }],
      passThreshold: 0.6,
      updatedBy: "owner1",
    };

    test("readable by anyone when the parent video is public", async () => {
      await seedDoc("videos/v1", publicReadyVideo);
      await seedDoc("videos/v1/quiz/current", quizCurrent);
      await assertSucceeds(getDoc(doc(anon().firestore(), "videos/v1/quiz/current")));
    });

    test("denied when the parent video is private and the reader is not the owner (negative)", async () => {
      await seedDoc("videos/v1", { ...publicReadyVideo, visibility: "private" });
      await seedDoc("videos/v1/quiz/current", quizCurrent);
      await assertFails(getDoc(doc(learner("someone-else").firestore(), "videos/v1/quiz/current")));
    });

    test("client writes are denied, even for the owner (negative)", async () => {
      await seedDoc("videos/v1", publicReadyVideo);
      await assertFails(setDoc(doc(creator("owner1").firestore(), "videos/v1/quiz/current"), quizCurrent));
    });
  });

  describe("quiz/answers", () => {
    const quizAnswers = {
      version: 1,
      answers: [{ id: "q1", correctOptionIds: ["a"], explanation: "The Constitution is the supreme law." }],
    };

    test("owner can read the answer key", async () => {
      await seedDoc("videos/v1", publicReadyVideo);
      await seedDoc("videos/v1/quiz/answers", quizAnswers);
      await assertSucceeds(getDoc(doc(creator("owner1").firestore(), "videos/v1/quiz/answers")));
    });

    test("a learner (non-owner) can never read the answer key, even on a public video (negative)", async () => {
      await seedDoc("videos/v1", publicReadyVideo);
      await seedDoc("videos/v1/quiz/answers", quizAnswers);
      await assertFails(getDoc(doc(learner("someone-else").firestore(), "videos/v1/quiz/answers")));
    });

    test("client writes are denied, even for the owner (negative)", async () => {
      await seedDoc("videos/v1", publicReadyVideo);
      await assertFails(setDoc(doc(creator("owner1").firestore(), "videos/v1/quiz/answers"), quizAnswers));
    });
  });
});

// ---- users/{uid} ----------------------------------------------------------

describe("users", () => {
  const newUserDoc = {
    displayName: "Alice",
    handle: "alice",
    role: "learner",
    authProviders: ["password"],
    interests: [],
    currentStreak: 0,
    longestStreak: 0,
    totalVideosCompleted: 0,
    totalQuizzesPassed: 0,
    isGuest: false,
    isDeleted: false,
  };

  test("anyone can read any profile (documented public-subset judgment call)", async () => {
    await seedDoc("users/alice", newUserDoc);
    await assertSucceeds(getDoc(doc(anon().firestore(), "users/alice")));
  });

  test("owner can create their own doc as role learner with zeroed counters", async () => {
    await assertSucceeds(setDoc(doc(learner("alice").firestore(), "users/alice"), newUserDoc));
  });

  test("cannot create someone else's profile doc (negative)", async () => {
    await assertFails(setDoc(doc(learner("mallory").firestore(), "users/alice"), newUserDoc));
  });

  test("cannot self-assign a non-learner role on create (negative)", async () => {
    await assertFails(
      setDoc(doc(learner("alice").firestore(), "users/alice"), { ...newUserDoc, role: "admin" })
    );
  });

  test("owner can update a plain field", async () => {
    await seedDoc("users/alice", newUserDoc);
    await assertSucceeds(updateDoc(doc(learner("alice").firestore(), "users/alice"), { bio: "Hi!" }));
  });

  test("owner cannot self-promote role via a direct write (negative)", async () => {
    await seedDoc("users/alice", newUserDoc);
    await assertFails(updateDoc(doc(learner("alice").firestore(), "users/alice"), { role: "admin" }));
  });

  test("owner cannot un-delete or delete themselves via a direct write (negative)", async () => {
    await seedDoc("users/alice", newUserDoc);
    await assertFails(updateDoc(doc(learner("alice").firestore(), "users/alice"), { isDeleted: true }));
  });

  test("delete is always denied (negative)", async () => {
    await seedDoc("users/alice", newUserDoc);
    await assertFails(deleteDoc(doc(learner("alice").firestore(), "users/alice")));
  });

  for (const sub of [
    "topicProgress/t1",
    "videoProgress/v1",
    "likes/v1",
    "savedVideos/v1",
    "aiUsage/2026-07-30",
    "commentLikes/c1",
  ]) {
    describe(`users/{uid}/${sub.split("/")[0]}`, () => {
      test("owner can read", async () => {
        await seedDoc(`users/alice/${sub}`, { value: 1 });
        await assertSucceeds(getDoc(doc(learner("alice").firestore(), `users/alice/${sub}`)));
      });

      test("non-owner cannot read (negative)", async () => {
        await seedDoc(`users/alice/${sub}`, { value: 1 });
        await assertFails(getDoc(doc(learner("mallory").firestore(), `users/alice/${sub}`)));
      });

      test("client write is always denied, even for the owner (negative)", async () => {
        await assertFails(setDoc(doc(learner("alice").firestore(), `users/alice/${sub}`), { value: 1 }));
      });
    });
  }
});

// ---- handles/{handle} -----------------------------------------------------

describe("handles", () => {
  test("read is always denied (negative)", async () => {
    await seedDoc("handles/alice", { uid: "alice" });
    await assertFails(getDoc(doc(learner("alice").firestore(), "handles/alice")));
  });

  test("write is always denied, even for the matching uid (negative)", async () => {
    await assertFails(setDoc(doc(learner("alice").firestore(), "handles/alice"), { uid: "alice" }));
  });
});

// ---- videos/{videoId}/comments/{commentId} --------------------------------

describe("comments", () => {
  const parentVideo = {
    topicId: "t1",
    topicTitle: "Civics",
    categoryId: "exam-prep",
    topicVisibility: "public",
    title: "Video 1",
    order: 0,
    visibility: "public",
    status: "ready",
    createdBy: "owner1",
    isDeleted: false,
  };

  function freshComment(uid: string) {
    return {
      uid,
      authorName: "Bob",
      text: "Great video!",
      createdAt: Timestamp.now(),
      parentId: null,
      replyCount: 0,
      likeCount: 0,
      reportCount: 0,
      isDeleted: false,
    };
  }

  test("signed-in, non-guest user can create a comment on a visible video", async () => {
    await seedDoc("videos/v1", parentVideo);
    await assertSucceeds(
      setDoc(doc(learner("bob").firestore(), "videos/v1/comments/c1"), freshComment("bob"))
    );
  });

  test("guest (anonymous auth) is denied comment creation by rules, not by UI (negative)", async () => {
    await seedDoc("videos/v1", parentVideo);
    await assertFails(
      setDoc(doc(guest("guest1").firestore(), "videos/v1/comments/c1"), freshComment("guest1"))
    );
  });

  test("cannot create a comment impersonating another uid (negative)", async () => {
    await seedDoc("videos/v1", parentVideo);
    await assertFails(
      setDoc(doc(learner("bob").firestore(), "videos/v1/comments/c1"), freshComment("mallory"))
    );
  });

  test("author can edit text within 15 minutes of creation", async () => {
    await seedDoc("videos/v1", parentVideo);
    await seedDoc("videos/v1/comments/c1", freshComment("bob"));
    await assertSucceeds(
      updateDoc(doc(learner("bob").firestore(), "videos/v1/comments/c1"), {
        text: "Edited",
        editedAt: Timestamp.now(),
      })
    );
  });

  test("author cannot edit text after the 15 minute window (negative)", async () => {
    await seedDoc("videos/v1", parentVideo);
    await seedDoc("videos/v1/comments/c1", {
      ...freshComment("bob"),
      createdAt: Timestamp.fromMillis(Date.now() - 16 * 60 * 1000),
    });
    await assertFails(
      updateDoc(doc(learner("bob").firestore(), "videos/v1/comments/c1"), {
        text: "Too late",
        editedAt: Timestamp.now(),
      })
    );
  });

  test("author can soft-delete their own comment at any time", async () => {
    await seedDoc("videos/v1", parentVideo);
    await seedDoc("videos/v1/comments/c1", {
      ...freshComment("bob"),
      createdAt: Timestamp.fromMillis(Date.now() - 60 * 60 * 1000),
    });
    await assertSucceeds(
      updateDoc(doc(learner("bob").firestore(), "videos/v1/comments/c1"), { isDeleted: true })
    );
  });

  test("a different learner cannot edit or delete someone else's comment (negative)", async () => {
    await seedDoc("videos/v1", parentVideo);
    await seedDoc("videos/v1/comments/c1", freshComment("bob"));
    await assertFails(
      updateDoc(doc(learner("mallory").firestore(), "videos/v1/comments/c1"), { isDeleted: true })
    );
  });

  test("hard delete is always denied, even for the author (negative)", async () => {
    await seedDoc("videos/v1", parentVideo);
    await seedDoc("videos/v1/comments/c1", freshComment("bob"));
    await assertFails(deleteDoc(doc(learner("bob").firestore(), "videos/v1/comments/c1")));
  });
});

// ---- videos/{videoId}/aiThreads/{uid} + messages ---------------------------

describe("aiThreads", () => {
  test("owner can read their own thread", async () => {
    await seedDoc("videos/v1/aiThreads/alice", { uid: "alice", messageCount: 0 });
    await assertSucceeds(getDoc(doc(learner("alice").firestore(), "videos/v1/aiThreads/alice")));
  });

  test("non-owner cannot read another user's thread (negative)", async () => {
    await seedDoc("videos/v1/aiThreads/alice", { uid: "alice", messageCount: 0 });
    await assertFails(getDoc(doc(learner("mallory").firestore(), "videos/v1/aiThreads/alice")));
  });

  test("client writes are denied, even for the owner (negative)", async () => {
    await assertFails(
      setDoc(doc(learner("alice").firestore(), "videos/v1/aiThreads/alice"), { uid: "alice" })
    );
  });

  test("messages follow the same owner-read, Function-only-write rule", async () => {
    await seedDoc("videos/v1/aiThreads/alice/messages/m1", { role: "user", text: "hi" });
    await assertSucceeds(getDoc(doc(learner("alice").firestore(), "videos/v1/aiThreads/alice/messages/m1")));
    await assertFails(getDoc(doc(learner("mallory").firestore(), "videos/v1/aiThreads/alice/messages/m1")));
    await assertFails(
      setDoc(doc(learner("alice").firestore(), "videos/v1/aiThreads/alice/messages/m2"), { role: "user", text: "hi" })
    );
  });
});

// ---- reports/{reportId} -----------------------------------------------------

describe("reports", () => {
  test("admin can read", async () => {
    await seedDoc("reports/r1", { targetType: "comment", reporterUid: "bob", status: "open" });
    await assertSucceeds(getDoc(doc(admin("a1").firestore(), "reports/r1")));
  });

  test("non-admin cannot read (negative)", async () => {
    await seedDoc("reports/r1", { targetType: "comment", reporterUid: "bob", status: "open" });
    await assertFails(getDoc(doc(learner("bob").firestore(), "reports/r1")));
  });

  test("signed-in, non-guest user can file their own report", async () => {
    await assertSucceeds(
      setDoc(doc(learner("bob").firestore(), "reports/r1"), {
        targetType: "comment",
        reporterUid: "bob",
        status: "open",
      })
    );
  });

  test("guest cannot file a report (negative)", async () => {
    await assertFails(
      setDoc(doc(guest("g1").firestore(), "reports/r1"), {
        targetType: "comment",
        reporterUid: "g1",
        status: "open",
      })
    );
  });

  test("cannot file a report impersonating another uid (negative)", async () => {
    await assertFails(
      setDoc(doc(learner("bob").firestore(), "reports/r1"), {
        targetType: "comment",
        reporterUid: "mallory",
        status: "open",
      })
    );
  });

  test("update and delete are always denied, even for admin (negative)", async () => {
    await seedDoc("reports/r1", { targetType: "comment", reporterUid: "bob", status: "open" });
    await assertFails(updateDoc(doc(admin("a1").firestore(), "reports/r1"), { status: "actioned" }));
    await assertFails(deleteDoc(doc(admin("a1").firestore(), "reports/r1")));
  });
});

// ---- viewEvents/{eventId} ---------------------------------------------------

describe("viewEvents", () => {
  test("signed-in user can create their own view ping", async () => {
    await assertSucceeds(
      setDoc(doc(learner("bob").firestore(), "viewEvents/e1"), { uid: "bob", videoId: "v1" })
    );
  });

  test("cannot create a view ping under someone else's uid (negative)", async () => {
    await assertFails(
      setDoc(doc(learner("bob").firestore(), "viewEvents/e1"), { uid: "mallory", videoId: "v1" })
    );
  });

  test("read is always denied, even to the reporter (negative)", async () => {
    await seedDoc("viewEvents/e1", { uid: "bob", videoId: "v1" });
    await assertFails(getDoc(doc(learner("bob").firestore(), "viewEvents/e1")));
  });
});

// ---- users/{uid}/private/wallet --------------------------------------------

describe("wallet", () => {
  const wallet = { tier: "siltstone", creditBalanceCents: 500, hasUsedFreeLesson: true };

  test("owner can read their own wallet", async () => {
    await seedDoc("users/alice/private/wallet", wallet);
    await assertSucceeds(getDoc(doc(learner("alice").firestore(), "users/alice/private/wallet")));
  });

  test("a different user cannot read someone else's wallet (negative)", async () => {
    await seedDoc("users/alice/private/wallet", wallet);
    await assertFails(getDoc(doc(learner("mallory").firestore(), "users/alice/private/wallet")));
  });

  test("client writes are denied, even for the owner (negative)", async () => {
    await assertFails(
      setDoc(doc(learner("alice").firestore(), "users/alice/private/wallet"), { creditBalanceCents: 999999 })
    );
  });

  test("an anonymous guest cannot read anyone's wallet (negative)", async () => {
    await seedDoc("users/alice/private/wallet", wallet);
    await assertFails(getDoc(doc(guest("g1").firestore(), "users/alice/private/wallet")));
  });
});

// ---- users/{uid}/creditTransactions/{transactionId} ------------------------

describe("creditTransactions", () => {
  const row = { type: "topup", amountCents: 550, createdAt: Timestamp.now() };

  test("owner can read their own ledger", async () => {
    await seedDoc("users/alice/creditTransactions/t1", row);
    await assertSucceeds(getDoc(doc(learner("alice").firestore(), "users/alice/creditTransactions/t1")));
  });

  test("a different user cannot read someone else's ledger (negative)", async () => {
    await seedDoc("users/alice/creditTransactions/t1", row);
    await assertFails(getDoc(doc(learner("mallory").firestore(), "users/alice/creditTransactions/t1")));
  });

  test("client writes are denied, even for the owner (negative)", async () => {
    await assertFails(setDoc(doc(learner("alice").firestore(), "users/alice/creditTransactions/t1"), row));
  });
});

// ---- lessonCache/{cacheKey} -------------------------------------------------

describe("lessonCache", () => {
  test("no client can read it, signed in or not (negative)", async () => {
    await seedDoc("lessonCache/abc123", { canonicalTopic: "photosynthesis", sourceVideoId: "v1" });
    await assertFails(getDoc(doc(learner("alice").firestore(), "lessonCache/abc123")));
    await assertFails(getDoc(doc(anon().firestore(), "lessonCache/abc123")));
  });

  test("no client can write it, including admin (negative)", async () => {
    await assertFails(
      setDoc(doc(admin("a1").firestore(), "lessonCache/abc123"), { canonicalTopic: "photosynthesis" })
    );
  });
});

// ---- apiKeys/{keyId} ---------------------------------------------------------

describe("apiKeys", () => {
  test("no client can read a key doc, not even its own owner (negative)", async () => {
    await seedDoc("apiKeys/k1", { uid: "alice", keyHash: "deadbeef", revoked: false });
    await assertFails(getDoc(doc(learner("alice").firestore(), "apiKeys/k1")));
  });

  test("no client can write a key doc (negative)", async () => {
    await assertFails(setDoc(doc(learner("alice").firestore(), "apiKeys/k1"), { uid: "alice" }));
  });
});

// ---- appAccountTokens/{token} -----------------------------------------------

describe("appAccountTokens", () => {
  test("no client can read a token doc, not even the uid it points to (negative)", async () => {
    await seedDoc("appAccountTokens/tok1", { uid: "alice" });
    await assertFails(getDoc(doc(learner("alice").firestore(), "appAccountTokens/tok1")));
  });

  test("no client can write a token doc (negative)", async () => {
    await assertFails(setDoc(doc(learner("alice").firestore(), "appAccountTokens/tok1"), { uid: "alice" }));
  });
});

// ---- catch-all --------------------------------------------------------------

describe("everything else", () => {
  test("an undeclared collection denies both read and write (negative)", async () => {
    await assertFails(getDocs(collection(learner("bob").firestore(), "somethingUndeclared")));
    await assertFails(setDoc(doc(learner("bob").firestore(), "somethingUndeclared/x"), { a: 1 }));
  });
});
