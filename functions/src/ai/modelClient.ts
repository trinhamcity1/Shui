import Anthropic from "@anthropic-ai/sdk";
import { defineSecret, defineString } from "firebase-functions/params";
import { CallUsage } from "./pricing";

/**
 * Model choice and credentials live in Function config, never in code, so
 * either can change without an app deploy — prompts/phase-04-ai-tutor.md §3.
 * `AI_MODEL` is only the eval harness's override now — the production path
 * resolves a model per-tier via tutorGuardrails.ts, not one global config
 * value.
 */
export const aiApiKey = defineSecret("AI_API_KEY");
export const aiModel = defineString("AI_MODEL", { default: "claude-sonnet-5" });

export const AI_SECRETS = [aiApiKey];

export interface ModelMessage {
  role: "user" | "assistant";
  content: string;
}

export interface StreamParams {
  system: string;
  messages: ModelMessage[];
  maxTokens: number;
  /** Called for each text delta as it arrives, in order. */
  onToken: (delta: string) => void | Promise<void>;
}

export interface StreamResult {
  text: string;
  usage: CallUsage;
}

/**
 * The one seam every real model call goes through — callables never talk
 * to Anthropic directly, so evals and unit tests can substitute
 * `FakeModelClient` and stay fast, free, and deterministic.
 */
export interface ModelClient {
  stream(params: StreamParams): Promise<StreamResult>;
}

export class AnthropicModelClient implements ModelClient {
  private readonly model: string;

  /**
   * `model` defaults to `aiModel.value()`, which only resolves correctly
   * inside the real, Firebase-managed function runtime — `defineString`
   * (unlike `defineSecret`) isn't a plain `process.env` passthrough, so a
   * bare `node` process (the eval runner) silently gets an empty string
   * back instead of the declared default. Callers running outside that
   * runtime (evals) must pass the model explicitly rather than relying on
   * this default. Production callers now always pass a tier-resolved model
   * explicitly too (tutorGuardrails.ts) — this default is effectively
   * eval-only at this point.
   */
  constructor(model?: string) {
    this.model = model ?? aiModel.value();
  }

  /**
   * Prompt caching (shared/prompt-caching.md's "robust combination for
   * agent loops"): one explicit breakpoint on the system prompt, since it's
   * stable for nearly every turn of a tutor session, and one on the last
   * message's content, since that's the end of the growing conversation
   * tail each new turn extends. Both are ordinary content-block-level
   * `cache_control` markers — not the top-level automatic-caching field —
   * so this needs no SDK feature beyond what a text/message content block
   * already supports.
   */
  async stream(params: StreamParams): Promise<StreamResult> {
    const client = new Anthropic({ apiKey: aiApiKey.value() });

    const messages = params.messages.map((m, i) => {
      const isLast = i === params.messages.length - 1;
      if (!isLast) {
        return { role: m.role, content: m.content };
      }
      return {
        role: m.role,
        content: [{ type: "text" as const, text: m.content, cache_control: { type: "ephemeral" as const } }],
      };
    });

    const stream = client.messages.stream({
      model: this.model,
      max_tokens: params.maxTokens,
      system: [{ type: "text", text: params.system, cache_control: { type: "ephemeral" } }],
      messages,
    });

    let full = "";
    // The async-iterator form (not the `.on("text", ...)` event-emitter
    // form) so each `onToken` call is awaited in order before the next
    // delta is processed — the callable batches deltas into Firestore
    // writes, and that only stays correct if writes happen in sequence.
    for await (const event of stream) {
      if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
        full += event.delta.text;
        await params.onToken(event.delta.text);
      }
    }
    const finalMessage = await stream.finalMessage();
    const usage = finalMessage.usage;
    return {
      text: full,
      usage: {
        inputTokens: usage.input_tokens,
        outputTokens: usage.output_tokens,
        cacheCreationInputTokens: usage.cache_creation_input_tokens ?? 0,
        cacheReadInputTokens: usage.cache_read_input_tokens ?? 0,
      },
    };
  }
}

/** Scripted responses for evals and unit tests — never calls a real API. */
export class FakeModelClient implements ModelClient {
  constructor(private readonly scriptedResponse: string | ((messages: ModelMessage[]) => string)) {}

  async stream(params: StreamParams): Promise<StreamResult> {
    const full =
      typeof this.scriptedResponse === "function" ? this.scriptedResponse(params.messages) : this.scriptedResponse;
    // Deliver in small chunks so streaming-consumer logic (batching,
    // partial-write behavior) gets exercised the same way it would against
    // a real stream, not just handed the whole string in one call.
    const chunkSize = 12;
    for (let i = 0; i < full.length; i += chunkSize) {
      await params.onToken(full.slice(i, i + chunkSize));
    }
    // Deterministic stand-in — there's no real API call to report real
    // usage from. ~4 chars/token, same rough estimate grounding.ts already
    // uses elsewhere for the same reason.
    const inputChars = params.system.length + params.messages.reduce((sum, m) => sum + m.content.length, 0);
    return {
      text: full,
      usage: {
        inputTokens: Math.ceil(inputChars / 4),
        outputTokens: Math.ceil(full.length / 4),
        cacheCreationInputTokens: 0,
        cacheReadInputTokens: 0,
      },
    };
  }
}
