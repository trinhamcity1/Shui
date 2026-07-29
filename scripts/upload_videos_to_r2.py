#!/usr/bin/env python3
"""
Uploads Shui/Resources/Videos/*.mp4 to the shui-videos Cloudflare R2 bucket
and prints the public URL for each, so they can be pasted into
generate_content.py's videoURLString field.

R2 is S3-API-compatible, so this is a plain boto3 client pointed at the
account's R2 endpoint rather than AWS.

Setup:
    pip install boto3
    export R2_ACCOUNT_ID=3048743e93a174146cde8f4133f3be0d
    export R2_ACCESS_KEY_ID=...       # from Manage R2 API Tokens
    export R2_SECRET_ACCESS_KEY=...   # from the same token

Usage:
    python3 scripts/upload_videos_to_r2.py
"""
import os
import sys

import boto3

BUCKET = "shui-videos"
PUBLIC_BASE_URL = "https://pub-29f895ffbdcf49779204f67d1a69af9b.r2.dev"
VIDEOS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "Shui", "Resources", "Videos",
)


def main():
    account_id = os.environ.get("R2_ACCOUNT_ID")
    access_key = os.environ.get("R2_ACCESS_KEY_ID")
    secret_key = os.environ.get("R2_SECRET_ACCESS_KEY")
    if not all([account_id, access_key, secret_key]):
        print(
            "Missing R2_ACCOUNT_ID / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY "
            "environment variables. See the docstring for setup.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    client = boto3.client(
        "s3",
        endpoint_url=f"https://{account_id}.r2.cloudflarestorage.com",
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_key,
        region_name="auto",
    )

    videos = sorted(f for f in os.listdir(VIDEOS_DIR) if f.endswith(".mp4"))
    if not videos:
        print(f"No .mp4 files found in {VIDEOS_DIR}", file=sys.stderr)
        raise SystemExit(1)

    urls = {}
    for filename in videos:
        path = os.path.join(VIDEOS_DIR, filename)
        size_mb = os.path.getsize(path) / (1024 * 1024)
        print(f"Uploading {filename} ({size_mb:.2f} MB)...")
        client.upload_file(
            path, BUCKET, filename,
            ExtraArgs={"ContentType": "video/mp4"},
        )
        urls[filename] = f"{PUBLIC_BASE_URL}/{filename}"

    print(f"\nUploaded {len(urls)} videos to R2 bucket '{BUCKET}'.\n")
    print("videoURLString values (lesson_id -> url):")
    for filename, url in urls.items():
        lesson_id = filename.removesuffix(".mp4")
        print(f"  {lesson_id}: {url}")


if __name__ == "__main__":
    main()
