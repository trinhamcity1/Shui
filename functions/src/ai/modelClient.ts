import Anthropic from "@anthropic-ai/sdk";
import { defineSecret, defineString } from "firebase-functions/params";

/**
 * Model choice and credentials live in Function config, never in code, so
 * either can change without an app deploy — prompts/phase-04-ai-tutor.md §3.
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

/**
 * The one seam every real model call goes through — `aiTutorMessage` never
 * talks to Anthropic directly, so evals and unit tests can substitute
 * `FakeModelClient` and stay fast, free, and deterministic.
 */
export interface ModelClient {
  stream(params: StreamParams): Promise<string>;
}

export class AnthropicModelClient implements ModelClient {
  async stream(params: StreamParams): Promise<string> {
    const client = new Anthropic({ apiKey: aiApiKey.value() });
    const stream = client.messages.stream({
      model: aiModel.value(),
      max_tokens: params.maxTokens,
      system: params.system,
      messages: params.messages.map((m) => ({ role: m.role, content: m.content })),
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
    await stream.finalMessage();
    return full;
  }
}

/** Scripted responses for evals and unit tests — never calls a real API. */
export class FakeModelClient implements ModelClient {
  constructor(private readonly scriptedResponse: string | ((messages: ModelMessage[]) => string)) {}

  async stream(params: StreamParams): Promise<string> {
    const full =
      typeof this.scriptedResponse === "function" ? this.scriptedResponse(params.messages) : this.scriptedResponse;
    // Deliver in small chunks so streaming-consumer logic (batching,
    // partial-write behavior) gets exercised the same way it would against
    // a real stream, not just handed the whole string in one call.
    const chunkSize = 12;
    for (let i = 0; i < full.length; i += chunkSize) {
      await params.onToken(full.slice(i, i + chunkSize));
    }
    return full;
  }
}
