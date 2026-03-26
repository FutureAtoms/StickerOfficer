"""Video processing: smart splitting and conversion to animated stickers."""

import subprocess
import json
from pathlib import Path
from config import MAX_ANIMATED_DURATION_SEC, MAX_ANIMATED_SIZE_KB, STICKER_SIZE


def get_video_duration(video_path: Path) -> float:
    """Get video duration in seconds using ffprobe."""
    result = subprocess.run(
        [
            "ffprobe", "-v", "quiet", "-print_format", "json",
            "-show_format", str(video_path),
        ],
        capture_output=True, text=True
    )
    info = json.loads(result.stdout)
    return float(info.get("format", {}).get("duration", 0))


def process_video(input_path: Path, output_dir: Path) -> list[dict]:
    """Process a video into one or more animated sticker segments.

    Returns list of metadata dicts, one per segment.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    duration = get_video_duration(input_path)

    if duration <= 0:
        print(f"  Skipping {input_path.name}: could not determine duration")
        return []

    segments = _compute_segments(duration)
    results = []

    for i, (start, end) in enumerate(segments):
        segment_name = f"{input_path.stem}_seg{i}.webp"
        segment_path = output_dir / segment_name

        success = _extract_animated_webp(input_path, segment_path, start, end)
        if success and segment_path.exists():
            size_kb = segment_path.stat().st_size / 1024

            # If too large, reduce quality/fps
            if size_kb > MAX_ANIMATED_SIZE_KB:
                _extract_animated_webp(input_path, segment_path, start, end, low_quality=True)
                size_kb = segment_path.stat().st_size / 1024

            results.append({
                "sticker_path": segment_path,
                "thumb_path": None,
                "duration_sec": end - start,
                "size_kb": size_kb,
                "emojis": ["\U0001f3ac"],  # Movie clapper emoji
            })

    return results


def _compute_segments(duration: float) -> list[tuple[float, float]]:
    """Compute (start, end) pairs for splitting video into sticker-length segments."""
    max_dur = MAX_ANIMATED_DURATION_SEC  # 8 seconds

    if duration <= max_dur:
        return [(0, duration)]
    elif duration <= max_dur * 2:
        mid = duration / 2
        return [(0, mid), (mid, duration)]
    else:
        num_segments = max(2, int(duration / 7))
        segment_len = duration / num_segments
        return [(i * segment_len, (i + 1) * segment_len) for i in range(num_segments)]


def _extract_animated_webp(
    input_path: Path, output_path: Path, start: float, end: float,
    low_quality: bool = False,
) -> bool:
    """Extract a segment as animated WebP using ffmpeg."""
    duration = end - start
    fps = 10 if low_quality else 15
    quality = 50 if low_quality else 70
    size = STICKER_SIZE

    cmd = [
        "ffmpeg", "-y", "-ss", str(start), "-t", str(duration),
        "-i", str(input_path),
        "-vf", f"scale={size}:{size}:force_original_aspect_ratio=decrease,"
               f"pad={size}:{size}:(ow-iw)/2:(oh-ih)/2:color=0x00000000,"
               f"fps={fps}",
        "-c:v", "libwebp", "-lossless", "0", "-quality", str(quality),
        "-loop", "0", "-an",
        str(output_path),
    ]

    try:
        subprocess.run(cmd, capture_output=True, text=True, check=True, timeout=60)
        return True
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        print(f"  ffmpeg failed for {input_path.name}: {e}")
        return False
