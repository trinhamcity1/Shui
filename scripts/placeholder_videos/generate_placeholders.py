#!/usr/bin/env python3
"""
Generates real, vertical (9:16), ~60s placeholder MP4 lesson videos with
ffmpeg — no external video source needed. These exist purely to build and
test the app's video-backed lesson infrastructure (S3 hosting, AVPlayer
playback, seeking, caching) before spending on real Golpo-generated videos.

Each placeholder shows: the app's actual whiteboard-scene canvas color, the
real lesson title (EN + VI) pulled from lessons.json, a filling top progress
bar, and a live mm:ss timer — so you can visually confirm playback position,
seeking, and duration all work correctly once wired into the app, without
needing to judge any actual content quality.

Usage: python3 scripts/placeholder_videos/generate_placeholders.py
Output: scripts/placeholder_videos/out/<lessonId>.mp4
"""
import json
import os
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LESSONS_PATH = os.path.join(ROOT, "Histudy", "Resources", "Content", "lessons.json")
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

WIDTH, HEIGHT, DURATION, FPS = 1080, 1920, 60, 30

# Matches Theme.scene tokens in Histudy/Sources/Theme/Theme.swift
CANVAS = "0xECECEC"
ACCENT_BLUE = "0x5BC5F2"
STROKE = "0x1E293B"

LESSON_IDS = ["lsn_001", "lsn_097", "lsn_066"]


def escape_text(text: str) -> str:
    return text.replace("\\", r"\\").replace(":", r"\:").replace("'", r"\'")


def build_filter(title_en: str, title_vi: str, lesson_id: str) -> str:
    title_en_esc = escape_text(title_en)
    title_vi_esc = escape_text(title_vi)
    badge = escape_text(f"PLACEHOLDER · {lesson_id}")

    return (
        f"[0:v]drawbox=x=0:y=0:w='iw*min(t/{DURATION}\\,1)':h=28:color={ACCENT_BLUE}:t=fill[bg2];"
        f"[bg2]drawtext=fontfile={FONT_BOLD}:text='{badge}':fontcolor={ACCENT_BLUE}:fontsize=40:"
        f"x=(w-text_w)/2:y=520[bg3];"
        f"[bg3]drawtext=fontfile={FONT_BOLD}:text='{title_en_esc}':fontcolor={STROKE}:fontsize=64:"
        f"x=(w-text_w)/2:y=680:line_spacing=10[bg4];"
        f"[bg4]drawtext=fontfile={FONT_REG}:text='{title_vi_esc}':fontcolor={STROKE}:fontsize=44:"
        f"x=(w-text_w)/2:y=900:line_spacing=8[bg5];"
        f"[bg5]drawtext=fontfile={FONT_REG}:text='%{{pts\\:hms}}':fontcolor={STROKE}:fontsize=52:"
        f"x=(w-text_w)/2:y=1750[vout]"
    )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    lessons = {l["id"]: l for l in json.load(open(LESSONS_PATH, encoding="utf-8"))}

    for lesson_id in LESSON_IDS:
        lesson = lessons[lesson_id]
        out_path = os.path.join(OUT_DIR, f"{lesson_id}.mp4")
        filter_complex = build_filter(lesson["titleEN"], lesson["titleVI"], lesson_id)

        cmd = [
            "ffmpeg", "-y",
            "-f", "lavfi", "-i", f"color=c={CANVAS}:s={WIDTH}x{HEIGHT}:d={DURATION}:r={FPS}",
            "-f", "lavfi", "-i", f"anullsrc=channel_layout=stereo:sample_rate=44100",
            "-filter_complex", filter_complex,
            "-map", "[vout]", "-map", "1:a",
            "-t", str(DURATION),
            "-c:v", "libx264", "-preset", "medium", "-crf", "23", "-pix_fmt", "yuv420p",
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
        print(f"wrote {out_path} ({size_mb:.2f} MB)")


if __name__ == "__main__":
    main()
