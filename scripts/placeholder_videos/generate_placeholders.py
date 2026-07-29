#!/usr/bin/env python3
"""
Generates real, vertical (9:16), 60s placeholder MP4 lesson videos with
ffmpeg — no external video source needed. These exist purely to build and
test the app's video-backed lesson infrastructure (cloud hosting, AVPlayer
playback, seeking, prefetch, caching) before spending on real produced
videos.

Each placeholder shows: the app's actual whiteboard-scene canvas color, the
real lesson title (EN + VI) pulled from lessons.json, a filling top progress
bar, and a live mm:ss timer — so you can visually confirm playback position,
seeking, and duration all work correctly once wired into the app, without
needing to judge any actual content quality.

Text is drawn one line per drawtext call. ffmpeg 6.x has no `text_align`
option, so a multi-line `text=` block would render left-aligned inside its
bounding box; emitting each line separately is what actually centers it.
Line content is passed via `textfile=` rather than `text=` so Vietnamese
diacritics, apostrophes, and commas need no shell/filter escaping.

Usage: python3 scripts/placeholder_videos/generate_placeholders.py
Output: scripts/placeholder_videos/out/<lessonId>.mp4
"""
import json
import os
import shutil
import subprocess
import tempfile
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LESSONS_PATH = os.path.join(ROOT, "Shui", "Resources", "Content", "lessons.json")
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

WIDTH, HEIGHT, DURATION, FPS = 1080, 1920, 60, 30

# Matches Theme.scene tokens in Shui/Sources/Theme/Theme.swift
CANVAS = "0xECECEC"
ACCENT_BLUE = "0x5BC5F2"
STROKE = "0x1E293B"

# Wrap widths chosen so the longest real title still fits 1080px wide with
# margins: DejaVu averages ~0.6em per char, so usable_px / (0.6 * fontsize).
BADGE_SIZE, EN_SIZE, VI_SIZE, TIMER_SIZE = 40, 64, 44, 52
EN_WRAP, VI_WRAP = 22, 30
EN_TOP, VI_TOP = 660, 940


def drawtext(src_label: str, out_label: str, textfile: str, font: str,
             size: int, color: str, y: int) -> str:
    """One centered line. x centers this line's own width, not a block's."""
    return (
        f"[{src_label}]drawtext=fontfile={font}:textfile='{textfile}':"
        f"fontcolor={color}:fontsize={size}:x=(w-text_w)/2:y={y}[{out_label}]"
    )


def build_filter(tmpdir: str, title_en: str, title_vi: str, lesson_id: str) -> str:
    """Progress bar + badge + wrapped EN/VI titles + live timer."""
    steps = []
    n = [0]

    def next_label():
        n[0] += 1
        return f"v{n[0]}"

    def write(name: str, content: str) -> str:
        path = os.path.join(tmpdir, name)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return path

    # Progress bar: drawbox w/x/y/h accept per-frame expressions natively.
    src = next_label()
    steps.append(
        f"[0:v]drawbox=x=0:y=0:w='iw*min(t/{DURATION}\\,1)':h=28:"
        f"color={ACCENT_BLUE}:t=fill[{src}]"
    )

    lines = [(write("badge.txt", f"PLACEHOLDER · {lesson_id}"),
              FONT_BOLD, BADGE_SIZE, ACCENT_BLUE, 520)]

    for i, line in enumerate(textwrap.wrap(title_en, EN_WRAP)):
        lines.append((write(f"en{i}.txt", line), FONT_BOLD, EN_SIZE, STROKE,
                      EN_TOP + i * (EN_SIZE + 10)))

    for i, line in enumerate(textwrap.wrap(title_vi, VI_WRAP)):
        lines.append((write(f"vi{i}.txt", line), FONT_REG, VI_SIZE, STROKE,
                      VI_TOP + i * (VI_SIZE + 8)))

    lines.append((write("timer.txt", "%{pts:hms}"), FONT_REG, TIMER_SIZE,
                  STROKE, 1750))

    for path, font, size, color, y in lines:
        dst = next_label()
        steps.append(drawtext(src, dst, path, font, size, color, y))
        src = dst

    # Rename the final label so -map can find it.
    steps[-1] = steps[-1].replace(f"[{src}]", "[vout]")
    return ";".join(steps)


def main():
    if shutil.which("ffmpeg") is None:
        raise SystemExit("ffmpeg not found on PATH")

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(LESSONS_PATH, encoding="utf-8") as f:
        lessons = json.load(f)

    for lesson in lessons:
        lesson_id = lesson["id"]
        out_path = os.path.join(OUT_DIR, f"{lesson_id}.mp4")

        with tempfile.TemporaryDirectory() as tmpdir:
            filter_complex = build_filter(
                tmpdir, lesson["titleEN"], lesson["titleVI"], lesson_id
            )
            cmd = [
                "ffmpeg", "-y",
                "-f", "lavfi",
                "-i", f"color=c={CANVAS}:s={WIDTH}x{HEIGHT}:d={DURATION}:r={FPS}",
                "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
                "-filter_complex", filter_complex,
                "-map", "[vout]", "-map", "1:a",
                "-t", str(DURATION),
                "-c:v", "libx264", "-preset", "medium", "-crf", "23",
                "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-shortest",
                "-movflags", "+faststart",
                out_path,
            ]
            result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            print(f"FAILED: {lesson_id}")
            print(result.stderr[-3000:])
            raise SystemExit(1)
        size_mb = os.path.getsize(out_path) / (1024 * 1024)
        print(f"wrote {os.path.basename(out_path)} ({size_mb:.2f} MB)")

    print(f"\n{len(lessons)} placeholders in {OUT_DIR}")


if __name__ == "__main__":
    main()
