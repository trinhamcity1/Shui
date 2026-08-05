import { countedState } from "./onTopicWritten";

const publicTopic = { visibility: "public", isDeleted: false, categoryId: "skills" };

describe("countedState", () => {
  it("counts a public, non-deleted topic", () => {
    expect(countedState(publicTopic)).toEqual({ categoryId: "skills" });
  });

  it("does not count a private topic", () => {
    expect(countedState({ ...publicTopic, visibility: "private" })).toBeNull();
  });

  it("does not count a soft-deleted topic even if public", () => {
    expect(countedState({ ...publicTopic, isDeleted: true })).toBeNull();
  });

  it("does not count a missing document", () => {
    expect(countedState(undefined)).toBeNull();
  });
});
