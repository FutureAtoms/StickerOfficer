"""Tests for video processor."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from video_processor import _compute_segments


def test_short_video_one_segment():
    segments = _compute_segments(5.0)
    assert segments == [(0, 5.0)]


def test_medium_video_two_segments():
    segments = _compute_segments(12.0)
    assert len(segments) == 2
    assert segments[0] == (0, 6.0)
    assert segments[1] == (6.0, 12.0)


def test_long_video_multiple_segments():
    segments = _compute_segments(30.0)
    assert len(segments) >= 3
    durations = [end - start for start, end in segments]
    assert all(5 <= d <= 10 for d in durations)
    assert segments[0][0] == 0
    assert abs(segments[-1][1] - 30.0) < 0.01


def test_very_short_video():
    segments = _compute_segments(1.0)
    assert segments == [(0, 1.0)]


def test_zero_duration():
    segments = _compute_segments(0)
    assert segments == [(0, 0)]
