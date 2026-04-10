#\!/usr/bin/env python3
"""
从视频列表提取帧并生成序列帧图集（sprite sheet）。

用法:
  python3 extract_spritesheet.py <config_json>

config_json 格式:
{
  "videos": {
    "idle":  "/path/to/idle_video.mp4",
    "run":   "/path/to/run_video.mp4"
  },
  "output_dir": "/workspace/assets/spritesheets",
  "character_name": "knight",
  "fps": 8,
  "frame_width": 256,
  "frame_height": 256
}
"""

import subprocess
import os
import sys
import json
import math

try:
    from PIL import Image
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow", "-q"])
    from PIL import Image


def extract(config_path):
    with open(config_path, "r") as f:
        cfg = json.load(f)

    videos = cfg["videos"]
    output_dir = cfg.get("output_dir", "/workspace/assets/spritesheets")
    char_name = cfg.get("character_name", "character")
    fps = cfg.get("fps", 8)
    fw = cfg.get("frame_width", 256)
    fh = cfg.get("frame_height", 256)
    frames_tmp = cfg.get("frames_tmp", "/tmp/sprite_frames")

    os.makedirs(output_dir, exist_ok=True)
    atlas_info = {}

    for action, video_path in videos.items():
        print(f"\n=== {action} ===")
        if not os.path.exists(video_path):
            print(f"  [skip] {video_path}")
            continue

        frame_dir = os.path.join(frames_tmp, action)
        os.makedirs(frame_dir, exist_ok=True)

        # 清理旧帧
        for old in os.listdir(frame_dir):
            os.remove(os.path.join(frame_dir, old))

        cmd = [
            "ffmpeg", "-y", "-i", video_path,
            "-vf", (
                f"fps={fps},"
                f"scale={fw}:{fh}:force_original_aspect_ratio=decrease,"
                f"pad={fw}:{fh}:(ow-iw)/2:(oh-ih)/2:color=0x00000000"
            ),
            "-pix_fmt", "rgba",
            os.path.join(frame_dir, "frame_%04d.png"),
        ]
        subprocess.run(cmd, capture_output=True)

        frame_files = sorted(f for f in os.listdir(frame_dir) if f.endswith(".png"))
        n = len(frame_files)
        print(f"  {n} frames extracted")
        if n == 0:
            continue

        cols = math.ceil(math.sqrt(n))
        rows = math.ceil(n / cols)
        sw, sh = cols * fw, rows * fh

        sheet = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        for i, fname in enumerate(frame_files):
            frame = Image.open(os.path.join(frame_dir, fname)).convert("RGBA")
            sheet.paste(frame, ((i % cols) * fw, (i // cols) * fh))

        sheet_file = f"{char_name}_{action}_sheet.png"
        sheet.save(os.path.join(output_dir, sheet_file))
        print(f"  -> {sheet_file} ({sw}x{sh}, {cols}c x {rows}r, {n} frames)")

        atlas_info[action] = {
            "file": sheet_file,
            "frame_width": fw,
            "frame_height": fh,
            "columns": cols,
            "rows": rows,
            "total_frames": n,
            "sheet_width": sw,
            "sheet_height": sh,
            "fps": fps,
        }

    info_path = os.path.join(output_dir, "atlas_info.json")
    with open(info_path, "w") as f:
        json.dump(atlas_info, f, indent=2, ensure_ascii=False)
    print(f"\natlas_info -> {info_path}")
    print("Done\!")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <config.json>")
        sys.exit(1)
    extract(sys.argv[1])
