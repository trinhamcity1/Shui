import { GroundingContext } from "../grounding";

/**
 * Hand-written `GroundingContext`s — no live Firestore read, so these run
 * anywhere with no emulator and no seed data. `civics-*` mirror the real
 * seeded civics topic's shape (prompts/phase-01-backend.md's official 2025
 * question set); the rest cover cases civics alone doesn't: a video with no
 * transcript at all, and one with no quiz at all, since both are real,
 * expected states this app ships with today.
 */
export interface EvalFixture {
  id: string;
  description: string;
  context: GroundingContext;
}

export const fixtures: EvalFixture[] = [
  {
    id: "civics-branches-of-government",
    description: "Civics video with a full transcript, quiz, and a learner who passed on the first try.",
    context: {
      video: {
        title: "The Three Branches of Government",
        description: "What Congress, the President, and the courts each do, and why the split exists.",
        transcript:
          "The United States government has three branches. The legislative branch, Congress, makes laws — " +
          "it's made up of the Senate and the House of Representatives. The executive branch, headed by the " +
          "President, enforces laws. The judicial branch, headed by the Supreme Court, interprets laws and can " +
          "decide if a law is constitutional. This split exists so no single branch holds all the power — each " +
          "branch checks the others.",
      },
      topic: {
        title: "Principles of American Democracy",
        description: "The core structure and ideas the U.S. government is built on.",
        previousVideoTitle: "What Is the Rule of Law?",
        nextVideoTitle: "Checks and Balances in Practice",
      },
      quiz: [
        {
          questionId: "q1",
          prompt: "What does the legislative branch do?",
          correctAnswerText: "Makes laws",
          explanation: "Congress (Senate + House) writes and passes laws.",
        },
        {
          questionId: "q2",
          prompt: "Who is the head of the judicial branch?",
          correctAnswerText: "The Supreme Court",
          explanation: "The Supreme Court interprets laws and rules on constitutionality.",
        },
      ],
      learnerRecord: {
        quizAttempts: 1,
        quizBestScore: 1.0,
        quizPassed: true,
        missedQuestionPrompts: [],
        topicMasteryPercent: 82,
      },
      recentMessages: [],
    },
  },
  {
    id: "civics-bill-of-rights-missed",
    description: "Civics video where the learner failed the quiz and missed a specific question — tests targeted probing.",
    context: {
      video: {
        title: "The Bill of Rights",
        description: "The first ten amendments to the Constitution and what each protects.",
        transcript:
          "The Bill of Rights is the first ten amendments to the U.S. Constitution. The First Amendment " +
          "protects freedom of speech, religion, press, assembly, and petition. The Second Amendment protects " +
          "the right to bear arms. The Fourth Amendment protects against unreasonable searches and seizures. " +
          "The Fifth Amendment protects against self-incrimination and double jeopardy, and guarantees due " +
          "process.",
      },
      topic: {
        title: "Rights and Responsibilities",
        description: "What the Constitution guarantees, and what it asks of citizens in return.",
        previousVideoTitle: "Who Can Vote?",
        nextVideoTitle: "Amending the Constitution",
      },
      quiz: [
        {
          questionId: "q1",
          prompt: "What does the First Amendment protect?",
          correctAnswerText: "Freedom of speech, religion, press, assembly, and petition",
          explanation: "It's the amendment most people think of first for a reason — it bundles five protections.",
        },
        {
          questionId: "q2",
          prompt: "What does the Fifth Amendment guarantee?",
          correctAnswerText: "Due process, and protection against self-incrimination and double jeopardy",
          explanation: "\"Pleading the Fifth\" refers to the self-incrimination protection specifically.",
        },
      ],
      learnerRecord: {
        quizAttempts: 2,
        quizBestScore: 0.5,
        quizPassed: false,
        missedQuestionPrompts: ["What does the Fifth Amendment guarantee?"],
        topicMasteryPercent: 41,
      },
      recentMessages: [],
    },
  },
  {
    id: "no-transcript",
    description: "A video that has never had a transcript generated — tests the honest-degradation path.",
    context: {
      video: {
        title: "Reading a Paycheck",
        description: "Gross pay, net pay, and the deductions in between.",
        transcript: null,
      },
      topic: {
        title: "Money & Finance",
        description: "Personal finance basics for a first job or a first budget.",
        previousVideoTitle: null,
        nextVideoTitle: "Building a Simple Budget",
      },
      quiz: [
        {
          questionId: "q1",
          prompt: "What's the difference between gross pay and net pay?",
          correctAnswerText: "Net pay is gross pay minus deductions like taxes",
          explanation: "Gross is what you're paid before anything is taken out; net is what actually lands in your account.",
        },
      ],
      learnerRecord: {
        quizAttempts: 0,
        quizBestScore: null,
        quizPassed: false,
        missedQuestionPrompts: [],
        topicMasteryPercent: null,
      },
      recentMessages: [],
    },
  },
  {
    id: "no-quiz-mid-conversation",
    description: "A video with no quiz at all, and an existing thread history — tests continuity and the no-quiz fallback.",
    context: {
      video: {
        title: "Active Listening in One Minute",
        description: "One concrete technique: reflect back what you heard before responding.",
        transcript:
          "Active listening means reflecting back what someone said before you respond, in your own words. It " +
          "signals you actually heard them, and it catches misunderstandings early — before they turn into a " +
          "bigger disagreement.",
      },
      topic: {
        title: "Language & Communication",
        description: "Small, concrete techniques for being understood and understanding others.",
        previousVideoTitle: null,
        nextVideoTitle: null,
      },
      quiz: null,
      learnerRecord: {
        quizAttempts: 0,
        quizBestScore: null,
        quizPassed: false,
        missedQuestionPrompts: [],
        topicMasteryPercent: null,
      },
      recentMessages: [
        { role: "user", content: "Is this different from just repeating what someone said?" },
        {
          role: "assistant",
          content:
            "Yes — repeating is word-for-word; reflecting is putting it in your own words, which proves you " +
            "understood the meaning, not just the sounds.",
        },
      ],
    },
  },
  {
    id: "long-transcript",
    description: "A transcript comfortably over the truncation budget — tests that grounding still produces a coherent prompt.",
    context: {
      video: {
        title: "A Brief History of the Printing Press",
        description: "How movable type changed who could read, and how fast ideas could spread.",
        transcript: "Gutenberg's press, movable type, and how literacy spread across Europe. ".repeat(600),
      },
      topic: {
        title: "History & Culture",
        description: "Events and inventions that changed how people live, learn, and connect.",
        previousVideoTitle: "Before Writing: Oral Tradition",
        nextVideoTitle: "The Printing Press and the Reformation",
      },
      quiz: [
        {
          questionId: "q1",
          prompt: "What did movable type make possible that hand-copying couldn't?",
          correctAnswerText: "Printing many identical copies quickly",
          explanation: "Hand-copying was slow and introduced errors; movable type let one set of type produce many identical pages.",
        },
      ],
      learnerRecord: {
        quizAttempts: 0,
        quizBestScore: null,
        quizPassed: false,
        missedQuestionPrompts: [],
        topicMasteryPercent: 15,
      },
      recentMessages: [],
    },
  },
];
