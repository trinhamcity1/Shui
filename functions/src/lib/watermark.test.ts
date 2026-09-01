import { ffmpegWatermarkArgs, FakeWatermarkProcessor } from "./watermark";

describe("ffmpegWatermarkArgs", () => {
  test("overlays the logo pinned to the top-right corner, re-encodes video only", () => {
    const args = ffmpegWatermarkArgs("in.mp4", "logo.png", "out.mp4");
    expect(args).toContain("in.mp4");
    expect(args).toContain("logo.png");
    expect(args).toContain("out.mp4");
    expect(args.join(" ")).toContain("overlay=main_w-overlay_w-24:24");
    expect(args.join(" ")).toContain("-c:a copy");
  });
});

describe("FakeWatermarkProcessor", () => {
  test("returns a distinct URL from the clean master, deterministically", async () => {
    const processor = new FakeWatermarkProcessor();
    const result = await processor.applyWatermark("https://cdn.example/video.mp4", "videos/v1");
    expect(result.watermarkedUrl).not.toBe("https://cdn.example/video.mp4");
    expect(result.watermarkedUrl).toBe("https://cdn.example/video-watermarked.mp4");
  });
});
