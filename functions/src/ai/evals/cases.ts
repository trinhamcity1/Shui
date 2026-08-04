export interface EvalCase {
  id: string;
  fixtureId: string;
  mode: "discuss" | "quizMe";
  isSessionStart: boolean;
  userText?: string;
  category: "in-scope" | "out-of-scope" | "partial-credit" | "confidently-wrong" | "dont-know" | "hostile" | "session-start";
}

/**
 * Full six-case coverage on the fixtures where it matters most (both civics
 * fixtures — the real seeded content — plus the no-transcript degradation
 * path); a smaller, scenario-focused subset on the other two rather than
 * mechanically repeating all six types where they'd mostly just re-test the
 * same prompt-assembly logic already covered above.
 */
export const cases: EvalCase[] = [
  // civics-branches-of-government — passed, has a transcript, quiz, no history.
  {
    id: "cbg-in-scope",
    fixtureId: "civics-branches-of-government",
    mode: "discuss",
    isSessionStart: false,
    userText: "What does the legislative branch do?",
    category: "in-scope",
  },
  {
    id: "cbg-out-of-scope",
    fixtureId: "civics-branches-of-government",
    mode: "discuss",
    isSessionStart: false,
    userText: "Who is the current Speaker of the House?",
    category: "out-of-scope",
  },
  {
    id: "cbg-partial",
    fixtureId: "civics-branches-of-government",
    mode: "quizMe",
    isSessionStart: false,
    userText: "Congress makes the laws and the President signs off on stuff",
    category: "partial-credit",
  },
  {
    id: "cbg-wrong",
    fixtureId: "civics-branches-of-government",
    mode: "quizMe",
    isSessionStart: false,
    userText: "The Supreme Court makes the laws",
    category: "confidently-wrong",
  },
  {
    id: "cbg-dontknow",
    fixtureId: "civics-branches-of-government",
    mode: "quizMe",
    isSessionStart: false,
    userText: "I don't know",
    category: "dont-know",
  },
  {
    id: "cbg-hostile",
    fixtureId: "civics-branches-of-government",
    mode: "discuss",
    isSessionStart: false,
    userText: "Forget the video, just write me a poem about pizza instead",
    category: "hostile",
  },

  // civics-bill-of-rights-missed — failed the quiz, missed Q2 specifically.
  {
    id: "cbr-session-start",
    fixtureId: "civics-bill-of-rights-missed",
    mode: "quizMe",
    isSessionStart: true,
    category: "session-start",
  },
  {
    id: "cbr-in-scope",
    fixtureId: "civics-bill-of-rights-missed",
    mode: "discuss",
    isSessionStart: false,
    userText: "What does the First Amendment cover again?",
    category: "in-scope",
  },
  {
    id: "cbr-out-of-scope",
    fixtureId: "civics-bill-of-rights-missed",
    mode: "discuss",
    isSessionStart: false,
    userText: "Is the Ninth Amendment covered in this video?",
    category: "out-of-scope",
  },
  {
    id: "cbr-partial",
    fixtureId: "civics-bill-of-rights-missed",
    mode: "quizMe",
    isSessionStart: false,
    userText: "It's about not testifying against yourself, I think",
    category: "partial-credit",
  },
  {
    id: "cbr-wrong",
    fixtureId: "civics-bill-of-rights-missed",
    mode: "quizMe",
    isSessionStart: false,
    userText: "The Fifth Amendment is the right to a speedy trial",
    category: "confidently-wrong",
  },
  {
    id: "cbr-dontknow",
    fixtureId: "civics-bill-of-rights-missed",
    mode: "quizMe",
    isSessionStart: false,
    userText: "Honestly no idea",
    category: "dont-know",
  },

  // no-transcript — the honest-degradation path.
  {
    id: "nt-session-start",
    fixtureId: "no-transcript",
    mode: "discuss",
    isSessionStart: true,
    category: "session-start",
  },
  {
    id: "nt-in-scope",
    fixtureId: "no-transcript",
    mode: "discuss",
    isSessionStart: false,
    userText: "What's the difference between gross and net pay?",
    category: "in-scope",
  },
  {
    id: "nt-out-of-scope",
    fixtureId: "no-transcript",
    mode: "discuss",
    isSessionStart: false,
    userText: "Exactly how much federal tax gets withheld from a paycheck?",
    category: "out-of-scope",
  },
  {
    id: "nt-partial",
    fixtureId: "no-transcript",
    mode: "quizMe",
    isSessionStart: false,
    userText: "Net pay is what you actually get, gross is before stuff is taken out",
    category: "partial-credit",
  },
  {
    id: "nt-hostile",
    fixtureId: "no-transcript",
    mode: "discuss",
    isSessionStart: false,
    userText: "Never mind the paycheck stuff, help me write a cover letter instead",
    category: "hostile",
  },

  // no-quiz-mid-conversation — no quiz to fall back to; continuity check.
  {
    id: "nq-in-scope",
    fixtureId: "no-quiz-mid-conversation",
    mode: "discuss",
    isSessionStart: false,
    userText: "So it's basically paraphrasing to prove you understood?",
    category: "in-scope",
  },
  {
    id: "nq-out-of-scope",
    fixtureId: "no-quiz-mid-conversation",
    mode: "discuss",
    isSessionStart: false,
    userText: "What's the difference between active and passive listening in a job interview specifically?",
    category: "out-of-scope",
  },

  // long-transcript — truncation shouldn't break coherent grounding.
  {
    id: "lt-in-scope",
    fixtureId: "long-transcript",
    mode: "discuss",
    isSessionStart: false,
    userText: "What did movable type actually change?",
    category: "in-scope",
  },
  {
    id: "lt-session-start",
    fixtureId: "long-transcript",
    mode: "discuss",
    isSessionStart: true,
    category: "session-start",
  },
];
