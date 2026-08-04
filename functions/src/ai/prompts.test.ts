import { extractVisibleText, parseModelOutput } from "./prompts";

describe("extractVisibleText", () => {
  it("returns the whole string when no meta marker is present yet (mid-stream)", () => {
    expect(extractVisibleText("The legislative branch makes")).toBe("The legislative branch makes");
  });

  it("stops at the meta marker", () => {
    const raw = 'The legislative branch makes laws.\n<<<META>>>\n{"suggestedReplies":[]}\n<<<END_META>>>';
    expect(extractVisibleText(raw)).toBe("The legislative branch makes laws.");
  });
});

describe("parseModelOutput", () => {
  it("parses a well-formed meta block", () => {
    const raw =
      "Congress makes the laws.\n<<<META>>>\n" +
      '{"suggestedReplies": ["Tell me more", "What about the courts?"], "retentionAssessment": null}\n' +
      "<<<END_META>>>";
    const result = parseModelOutput(raw);
    expect(result.visibleText).toBe("Congress makes the laws.");
    expect(result.suggestedReplies).toEqual(["Tell me more", "What about the courts?"]);
    expect(result.retentionAssessment).toBeNull();
  });

  it("parses a retention assessment with a valid verdict", () => {
    const raw =
      "Close — that's the Fourth Amendment, not the Fifth.\n<<<META>>>\n" +
      '{"suggestedReplies": [], "retentionAssessment": {"questionIds": ["q2"], "verdict": "missed"}}\n' +
      "<<<END_META>>>";
    const result = parseModelOutput(raw);
    expect(result.retentionAssessment).toEqual({ questionIds: ["q2"], verdict: "missed" });
  });

  it("degrades to no chips / no retention update when there is no meta block at all", () => {
    const result = parseModelOutput("Just a plain response with no marker.");
    expect(result.visibleText).toBe("Just a plain response with no marker.");
    expect(result.suggestedReplies).toEqual([]);
    expect(result.retentionAssessment).toBeNull();
  });

  it("degrades gracefully when the meta block is malformed JSON, without throwing", () => {
    const raw = "Here's my answer.\n<<<META>>>\nnot valid json at all\n<<<END_META>>>";
    expect(() => parseModelOutput(raw)).not.toThrow();
    const result = parseModelOutput(raw);
    expect(result.visibleText).toBe("Here's my answer.");
    expect(result.suggestedReplies).toEqual([]);
    expect(result.retentionAssessment).toBeNull();
  });

  it("rejects an invalid verdict string rather than passing it through", () => {
    const raw =
      "Answer text.\n<<<META>>>\n" +
      '{"suggestedReplies": [], "retentionAssessment": {"questionIds": ["q1"], "verdict": "kind-of-right"}}\n' +
      "<<<END_META>>>";
    const result = parseModelOutput(raw);
    expect(result.retentionAssessment).toBeNull();
  });

  it("caps suggestedReplies at 3 even if the model returns more", () => {
    const raw =
      "Answer.\n<<<META>>>\n" +
      '{"suggestedReplies": ["a", "b", "c", "d", "e"], "retentionAssessment": null}\n' +
      "<<<END_META>>>";
    const result = parseModelOutput(raw);
    expect(result.suggestedReplies).toHaveLength(3);
  });
});
