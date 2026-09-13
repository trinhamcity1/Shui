import { GolpoSettingsSchema } from "./golpoCapabilities";

const validCanvas = {
  engine: "golpo_canvas",
  canvasStyleVariant: "modern_minimal",
  scenePacing: "normal",
  voice: "female-1",
  musicTrack: "engaging",
};

const validSketch = {
  engine: "golpo_sketch",
  sketchStyleVariant: "classic",
  scenePacing: "fast",
  voice: "male-1",
};

describe("GolpoSettingsSchema", () => {
  test("accepts a valid Canvas configuration", () => {
    expect(GolpoSettingsSchema.safeParse(validCanvas).success).toBe(true);
  });

  test("accepts a valid Sketch configuration with music omitted", () => {
    expect(GolpoSettingsSchema.safeParse(validSketch).success).toBe(true);
  });

  test("accepts Canvas with a pen animation style", () => {
    const result = GolpoSettingsSchema.safeParse({ ...validCanvas, penAnimationStyle: "stylus" });
    expect(result.success).toBe(true);
  });

  test("rejects Canvas missing canvasStyleVariant", () => {
    const { canvasStyleVariant: _unused, ...withoutStyle } = validCanvas;
    expect(GolpoSettingsSchema.safeParse(withoutStyle).success).toBe(false);
  });

  test("rejects Sketch missing sketchStyleVariant", () => {
    const { sketchStyleVariant: _unused, ...withoutStyle } = validSketch;
    expect(GolpoSettingsSchema.safeParse(withoutStyle).success).toBe(false);
  });

  test("rejects a pen animation style on the Sketch engine", () => {
    const result = GolpoSettingsSchema.safeParse({ ...validSketch, penAnimationStyle: "marker" });
    expect(result.success).toBe(false);
  });

  test("rejects an unknown style value", () => {
    const result = GolpoSettingsSchema.safeParse({ ...validCanvas, canvasStyleVariant: "not_a_real_style" });
    expect(result.success).toBe(false);
  });

  test("rejects an unknown voice", () => {
    const result = GolpoSettingsSchema.safeParse({ ...validCanvas, voice: "robot-1" });
    expect(result.success).toBe(false);
  });
});
