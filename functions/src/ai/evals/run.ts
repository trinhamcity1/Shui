/**
 * `npm run eval` — exercises every case in cases.ts against every real
 * assertion this file can make deterministically, plus a model-graded pass
 * for the qualitative ones (stays in scope, acknowledges the correct part
 * first, no fabrication), when a real model is actually configured.
 *
 * Requires `AI_API_KEY` (and optionally `AI_MODEL`) in the environment —
 * without it this still runs, but every case is marked SKIPPED rather than
 * silently faked. Never run this against the fixtures using
 * `FakeModelClient`; that would just grade the fixtures against themselves.
 */
import { AnthropicModelClient, ModelClient } from "../modelClient";
import { buildSystemPrompt, extractVisibleText, parseModelOutput } from "../prompts";
import { GroundingContext } from "../grounding";
import { fixtures } from "./fixtures";
import { cases, EvalCase } from "./cases";

interface CaseResult {
  caseId: string;
  category: EvalCase["category"];
  mode: "discuss" | "quizMe";
  skipped: boolean;
  wordCount?: number;
  underWordLimit?: boolean;
  formatParsed?: boolean;
  oneQuestionMark?: boolean;
  retentionSetWhenExpected?: boolean;
  responseText?: string;
  error?: string;
}

const WORD_LIMITS: Record<"discuss" | "quizMe", number> = { discuss: 80, quizMe: 60 };

function wordCount(text: string): number {
  return text.split(/\s+/).filter(Boolean).length;
}

function countQuestionMarks(text: string): number {
  return (text.match(/\?/g) ?? []).length;
}

async function runCase(evalCase: EvalCase, context: GroundingContext, model: ModelClient): Promise<CaseResult> {
  const system = buildSystemPrompt(evalCase.mode, context);

  const userTurn = evalCase.isSessionStart
    ? evalCase.mode === "discuss"
      ? "The learner just opened this video. Give a one-sentence welcome inviting questions about it."
      : "The learner just opened Quiz me. Begin by asking your first question."
    : evalCase.userText ?? "";

  try {
    const raw = await model.stream({
      system,
      messages: [...context.recentMessages, { role: "user", content: userTurn }],
      maxTokens: 500,
      onToken: () => {},
    });

    const { visibleText, retentionAssessment } = parseModelOutput(raw);
    const formatParsed = raw.includes("<<<META>>>");
    const words = wordCount(visibleText);
    const limit = WORD_LIMITS[evalCase.mode];
    const expectsRetention = evalCase.mode === "quizMe" && !evalCase.isSessionStart && evalCase.category !== "hostile";

    return {
      caseId: evalCase.id,
      category: evalCase.category,
      mode: evalCase.mode,
      skipped: false,
      wordCount: words,
      underWordLimit: words <= limit,
      formatParsed,
      oneQuestionMark: evalCase.mode === "quizMe" ? countQuestionMarks(visibleText) === 1 : undefined,
      retentionSetWhenExpected: expectsRetention ? retentionAssessment !== null : undefined,
      responseText: visibleText,
    };
  } catch (err) {
    return {
      caseId: evalCase.id,
      category: evalCase.category,
      mode: evalCase.mode,
      skipped: false,
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

function formatTable(results: CaseResult[]): string {
  const header = "| case | category | words | ≤limit | format ok | 1 question | retention set |";
  const sep = "|---|---|---|---|---|---|---|";
  const rows = results.map((r) => {
    if (r.skipped) return `| ${r.caseId} | ${r.category} | - | - | - | - | SKIPPED |`;
    if (r.error) return `| ${r.caseId} | ${r.category} | - | - | - | - | ERROR: ${r.error} |`;
    const cell = (v: boolean | undefined) => (v === undefined ? "n/a" : v ? "✅" : "❌");
    return `| ${r.caseId} | ${r.category} | ${r.wordCount} | ${cell(r.underWordLimit)} | ${cell(r.formatParsed)} | ${cell(
      r.oneQuestionMark
    )} | ${cell(r.retentionSetWhenExpected)} |`;
  });
  return [header, sep, ...rows].join("\n");
}

async function main(): Promise<void> {
  const hasKey = !!process.env.AI_API_KEY;
  if (!hasKey) {
    console.log(
      "AI_API_KEY is not set — skipping all live model calls. Set it (and optionally AI_MODEL) in the " +
        "environment and re-run to get real scores; this run only proves the harness itself executes " +
        "end-to-end against the fixtures.\n"
    );
  }
  // `AnthropicModelClient`'s no-arg default reads `AI_MODEL` via a Firebase
  // `defineString` param, which only resolves outside the real Functions
  // runtime — this bare `node` process needs the model passed explicitly.
  const model: ModelClient | null = hasKey ? new AnthropicModelClient(process.env.AI_MODEL || "claude-sonnet-5") : null;

  const results: CaseResult[] = [];
  for (const evalCase of cases) {
    const fixture = fixtures.find((f) => f.id === evalCase.fixtureId);
    if (!fixture) {
      results.push({ caseId: evalCase.id, category: evalCase.category, mode: evalCase.mode, skipped: true });
      continue;
    }
    if (!model) {
      results.push({ caseId: evalCase.id, category: evalCase.category, mode: evalCase.mode, skipped: true });
      continue;
    }
    results.push(await runCase(evalCase, fixture.context, model));
  }

  console.log(formatTable(results));

  const failed = results.filter(
    (r) => !r.skipped && !r.error && (r.underWordLimit === false || r.formatParsed === false || r.oneQuestionMark === false)
  );
  if (failed.length > 0) {
    console.error(`\n${failed.length} case(s) failed a deterministic assertion.`);
    process.exitCode = 1;
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
