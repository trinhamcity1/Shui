import { defineString } from "firebase-functions/params";

/**
 * GolpoAI always renders clean (phase-07 §2) — Shui burns its own watermark
 * as a post-process rather than relying on GolpoAI's `custom_logo` param, so
 * that one render is safely cacheable and reusable across every tier, and a
 * tier upgrade retroactively unlocks clean downloads of past lessons for
 * free (both master and watermarked copies already exist once a lesson is
 * ready).
 *
 * NOT VERIFIED against a real ffmpeg binary or a real GolpoAI-rendered
 * video in this environment — this sandbox has no ffmpeg installed, so the
 * command below is written to the documented ffmpeg overlay-filter syntax
 * and reviewed, not executed. Confirm with a real sample before trusting it
 * in production, same caveat as everything else in this phase waiting on
 * real GolpoAI access.
 */
export const watermarkLogoUrl = defineString("WATERMARK_LOGO_URL");

export interface WatermarkResult {
  watermarkedUrl: string;
}

export interface WatermarkProcessor {
  /** Downloads the clean master, burns the fixed top-right logo, uploads the result, returns its public URL. */
  applyWatermark(cleanVideoUrl: string, r2KeyPrefix: string): Promise<WatermarkResult>;
}

/**
 * The real ffmpeg invocation this needs — documented here, run from a Cloud
 * Run job rather than a bare Cloud Function if a 2-minute clip pushes past
 * Function execution/memory limits (phase-07 §4's own note). `overlay` with
 * `main_w-overlay_w-24:24` pins the logo 24px from the top-right corner
 * regardless of the source video's resolution; `-c:a copy` re-encodes only
 * video, since the overlay never touches audio.
 */
export function ffmpegWatermarkArgs(inputPath: string, logoPath: string, outputPath: string): string[] {
  return [
    "-i", inputPath,
    "-i", logoPath,
    "-filter_complex", "[0:v][1:v]overlay=main_w-overlay_w-24:24",
    "-c:a", "copy",
    "-y", outputPath,
  ];
}

/** Scripted for tests and for any environment without a real processor wired up yet. */
export class FakeWatermarkProcessor implements WatermarkProcessor {
  async applyWatermark(cleanVideoUrl: string, _r2KeyPrefix: string): Promise<WatermarkResult> {
    return { watermarkedUrl: `${cleanVideoUrl.replace(/\.mp4$/, "")}-watermarked.mp4` };
  }
}
