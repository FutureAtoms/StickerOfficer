# Video-to-Sticker Redesign Spec

## Problem

The current video-to-sticker pipeline uses `video_thumbnail` to extract 2-8 static frame screenshots from a video (user-controlled via a slider) and passes them to the animated editor for GIF assembly. This produces choppy, low-quality stickers that don't preserve the motion essence of the source video. Users also can't choose which segment they want — the code auto-adjusts `_trimEnd` proportionally when a video exceeds 5 seconds.

## Goals

1. Instagram-style trim scrubber so users pick the exact clip they want
2. FFmpeg-powered two-pass GIF conversion for vibrant, well-dithered output
3. User-controlled quality vs. smoothness slider with real-time size estimation
4. Stay within WhatsApp animated sticker limits (512x512, 500KB)
5. Preserve existing animated editor features (text, reorder, export to pack)
6. Zero regressions in the existing manual animated sticker flow

## Non-Goals

- In-app camera recording (gallery only)
- Audio in stickers (GIF has no audio)
- Telegram-specific animated sticker format (TGS/WebM)

## Constraints

- Max clip duration: 5 seconds
- Max file size: 500KB (WhatsApp animated sticker limit)
- Output dimensions: 512x512 (square, padded if needed)
- FPS range: 8-15 (video path only; manual path stays 4-8)
- Resolution range: 320-512px (mapped to quality slider)
- Validation requirement: every implementation step must be verified on the emulator as a real user would experience it

---

## Architecture

### Dependency Changes

**Add:** `ffmpeg_kit_flutter_min_gpl` — minimal GPL variant, includes `palettegen`, `paletteuse`, `scale`, `fps` filters. Exact version to be confirmed against pub.dev at implementation time.

**Remove:** `video_thumbnail: ^0.5.3` — fully replaced by FFmpeg for frame/thumbnail extraction.

### Two-Screen Flow (Preserved)

```
VideoToStickerScreen (upgraded) --> AnimatedStickerScreen (enhanced handoff)
```

Route parameter changes from `List<String>` to a map, with backward compatibility. The **route handler** does the type dispatch and constructs `AnimatedStickerScreen` with explicit named parameters:

```dart
GoRoute(
  path: '/animated-editor',
  builder: (context, state) {
    final extra = state.extra;
    if (extra is Map<String, dynamic>) {
      // New video-to-sticker path
      return AnimatedStickerScreen(
        initialFramePaths: extra['frames'] as List<String>?,
        ffmpegGifPath: extra['gifPath'] as String?,
        initialFps: extra['fps'] as int?,
      );
    }
    // Legacy path: List<String> from manual frame add, or null from main shell
    return AnimatedStickerScreen(
      initialFramePaths: extra as List<String>?,
    );
  },
),
```

The `AnimatedStickerScreen` constructor gains two optional named parameters (`ffmpegGifPath` and `initialFps`). Existing callers that pass `List<String>?` or `null` are unaffected. Test files that construct `AnimatedStickerScreen(initialFramePaths: ...)` directly continue to work unchanged.

---

## Section 1: Instagram-Style Trim Scrubber

### Thumbnail Strip

- On video pick, FFmpeg extracts thumbnails for the visible viewport
- Command: `ffmpeg -i input.mp4 -vf "fps=2,scale=80:-1" thumb_%04d.png`
- Thumbnails arranged horizontally in a scrollable row widget
- **Lazy loading for long videos:** Only generate thumbnails for the visible window (30s at a time). As user scrolls, generate more on demand. This prevents generating 1,200+ thumbnails for a 10-minute video.
- Total strip width = thumbnail_count * thumb_width

### Draggable Handles

- Two handle widgets (start/end) overlaid on the thumbnail strip
- Selected region highlighted; excluded regions dimmed with semi-transparent overlay
- Max selection enforced at 5 seconds — dragging beyond auto-adjusts the opposite handle
- Min selection: 0.5 seconds — handles snap if dragged too close (reconciled with existing 200ms threshold, now unified at 500ms)

### Video Preview

- `VideoPlayerController` positioned above the scrubber
- Plays only the selected segment on loop
- Play/pause toggle button
- Thin playback position indicator moves across the thumbnail strip in sync

### Duration Indicator

- Below scrubber: `"2.3s selected"` updating in real-time
- Warning if < 0.5s: `"Too short for a sticker!"`

---

## Section 2: Quality & Conversion Settings

### Quality vs. Smoothness Slider

Single slider with 5 discrete stops:

| Stop | Label    | FPS | Resolution | Max Colors |
|------|----------|-----|------------|------------|
| 1    | Crispest | 8   | 512px      | 256        |
| 2    | Crisp    | 10  | 448px      | 224        |
| 3    | Balanced | 12  | 384px      | 192        |
| 4    | Smooth   | 13  | 352px      | 160        |
| 5    | Smoothest| 15  | 320px      | 128        |

Default: stop 3 (Balanced).

### Real-Time Size Estimation

The formula `(resolution^2 * frame_count * bytes_per_pixel) / compression_ratio` is approximate — GIF compression is highly content-dependent (solid colors compress 50x, noisy video 5x). The estimation serves as a rough guide; the **auto-retry mechanism (step 4 below) is the true safety net** for size compliance.

- `frame_count = duration_seconds * fps`
- `compression_ratio` starts at 10x, can be tuned after calibration against real outputs
- Displayed as:
  - Progress bar against 500KB limit
  - Color-coded: green (<350KB), orange (350-450KB), red (>450KB)
  - Text: `"~280 KB"` with contextual tip

### FFmpeg Two-Pass Pipeline

Runs when user taps "Create Animated Sticker!":

1. **Trim**: `-ss {start} -t {duration}` for precise segment extraction
2. **Pass 1 — Palette Generation**:
   ```
   ffmpeg -ss {start} -t {dur} -i input.mp4 \
     -vf "fps={fps},scale={res}:{res}:force_original_aspect_ratio=decrease,pad={res}:{res}:(ow-iw)/2:(oh-ih)/2:color=0x00000000,palettegen=max_colors={colors}:reserve_transparent=1" \
     palette.png
   ```
   Note: `reserve_transparent=1` ensures a palette slot is reserved for transparency, so non-square video padding renders as transparent (not black) in the GIF.
3. **Pass 2 — GIF Encoding**:
   ```
   ffmpeg -ss {start} -t {dur} -i input.mp4 -i palette.png \
     -lavfi "fps={fps},scale={res}:{res}:force_original_aspect_ratio=decrease,pad={res}:{res}:(ow-iw)/2:(oh-ih)/2:color=0x00000000[v];[v][1:v]paletteuse=dither=floyd_steinberg" \
     output.gif
   ```
4. **Size check**: If output > 500KB, reduce one quality stop and retry (max 2 retries)
5. **Final pad to 512x512** if resolution was lower: transparent padding to maintain WhatsApp square requirement

### Cancel Button

A cancel button is shown during conversion. Pressing it calls `FFmpegKit.cancel()` to abort the running command, cleans up temp files, and returns the user to the scrubber screen.

### Loading Overlay

Progress shown during conversion:
- `"Generating color palette..."` (Pass 1)
- `"Encoding sticker..."` (Pass 2)
- `"Optimizing size..."` (if retry needed)
- Cancel button visible throughout

---

## Section 3: Animated Editor Integration

### Enhanced Handoff

VideoToStickerScreen produces:
- A GIF file (FFmpeg output, best quality)
- Extracted frame PNGs (decoded from the GIF via `image` package)
- The FPS used during conversion

All three passed to AnimatedStickerScreen via the route extra map.

### AnimatedStickerScreen Changes

- Constructor gains two optional named parameters: `String? ffmpegGifPath` and `int? initialFps`
- `_loadInitialFrames()` checks `widget.ffmpegGifPath` to determine if this is a video-sourced sticker
- If `ffmpegGifPath != null`, store it as `_ffmpegGifPath` and set `_isVideoSourced = true`
- On export:
  - **No edits made** (no text, no reorder, no frame add/remove) -> use `_ffmpegGifPath` directly. Best quality path.
  - **Edits made** -> re-encode using Dart `image` package with the FFmpeg-extracted frames (higher quality source than old thumbnails)
- FPS slider pre-set to the value from the conversion
- **Frame count display:** For video-sourced stickers, show frame count but hide the "add frames" and "reorder" controls (75 frames can't be meaningfully reordered by hand). Text overlay still available.

### Memory Management for Video-Sourced Frames

Video-sourced stickers can have up to 75 frames (5s x 15fps). At 512x512x4 bytes each, holding all decoded frames in memory would consume ~75MB.

Strategy:
- **Frame paths stay on disk** — `_framePaths` list holds file paths (existing pattern)
- **Preview animation** — load only the current visible frame + 2 ahead into memory, evicting old frames (sliding window)
- **Export** — stream frames from disk during GIF encoding rather than loading all at once
- **Manual sticker path** — unchanged (max 8 frames, no memory concern)

### What Stays the Same

- Text overlay system (all 7 animations)
- Frame reorder via drag-and-drop (manual path only)
- Add frames from gallery (manual path only)
- Import GIF
- Save to pack dialog
- WhatsApp export flow
- Kid-safe text filter

---

## Section 4: Guardrails Updates

### Design Decision: Video-Specific Constants (Not Global Changes)

The existing `maxFrames = 8` and `maxFps = 8` are global constants used by the manual animated sticker flow, validated by 12+ test files. Changing them would break existing tests and allow nonsensical configurations in the manual flow (e.g., 75 manually-selected photos, or 15 FPS with 2 frames = 133ms animation).

**Solution:** Keep global constants unchanged. Add video-specific constants.

```dart
// Existing (UNCHANGED)
static const int maxFrames = 8;        // manual sticker flow
static const int maxFps = 8;           // manual sticker flow
static const int minFps = 4;
static const int minDurationMs = 500;
static const int maxDurationMs = 10000;

// NEW: Video-to-sticker specific
static const int videoMaxFrames = 75;  // 5s x 15fps
static const int videoMaxFps = 15;
static const int videoMinFps = 8;
static const int videoMaxDurationMs = 5000;  // 5 seconds hard cap
static const int minGifResolution = 256;
static const int maxGifResolution = 512;
static const List<int> qualityFpsStops = [8, 10, 12, 13, 15];
static const List<int> qualityResStops = [512, 448, 384, 352, 320];
static const List<int> qualityColorStops = [256, 224, 192, 160, 128];
```

### Duration Math Verification

With video-specific constants, all configurations are valid:
- Min duration: 0.5s clip at 8 FPS = 4 frames, 500ms >= minDurationMs (500ms) OK
- Max duration: 5.0s clip at 15 FPS = 75 frames, 5000ms <= videoMaxDurationMs (5000ms) OK
- Max frames: 5s x 15fps = 75 = videoMaxFrames OK

Manual flow unchanged:
- Min: 2 frames at 4 fps = 500ms = minDurationMs OK
- Max: 8 frames at 4 fps = 2000ms <= maxDurationMs OK

### New Functions

```dart
/// Validates a video-sourced animated sticker.
/// Uses video-specific limits instead of manual sticker limits.
static List<String> validateVideoSticker({
  required int frameCount,
  required int fps,
  required int sizeBytes,
  String? text,
}) -> List<String>

/// Estimates GIF file size in KB based on conversion parameters.
/// Approximate — auto-retry is the true safety net.
static double estimateGifSizeKB({
  required double durationSec,
  required int fps,
  required int resolution,
}) -> double
```

### Existing Functions — No Changes

- `validateAnimatedSticker()` — unchanged, still uses maxFrames=8 / maxFps=8
- `compressAnimatedFrames()` — unchanged, used as fallback for Dart re-encode path
- `sizeStatus()`, `sizeColor()`, `sizeTip()` — unchanged

---

## Section 5: Error Handling

### FFmpeg Failures

- 30-second timeout on each FFmpeg command
- On failure: `"Oops! Couldn't convert this video. Try a shorter clip or different video"` with retry button
- Specific error codes logged for debugging (not shown to user)
- Cancel button calls `FFmpegKit.cancel()` for user-initiated abort

### Size Overshoot

- After conversion, check GIF size against 500KB
- If over: auto-retry one quality stop lower (max 2 retries)
- If still over after retries: show result with warning and let user manually adjust slider

### Storage

- Check available space before conversion; warn if < 50MB free
- All temp files (thumbnails, palette, intermediate GIF) cleaned up in `finally` blocks

### Video Edge Cases

| Case | Handling |
|------|----------|
| Video < 1s | Use full video, skip handle adjustment |
| Video > 5 min | Lazy-load thumbnails in 30s windows as user scrolls |
| Portrait/landscape | Scale longest side, pad to square with transparent background (`reserve_transparent=1`) |
| Corrupt/unsupported codec | Catch FFmpeg error, show friendly message |
| No video track | Reject with message |
| Audio-only MP4 | After thumbnail extraction, check frame count > 0; if zero, show "This file has no video" |

---

## Section 6: Verification Plan

Every implementation step validated on emulator before proceeding:

| Step | What to verify on emulator |
|------|---------------------------|
| 0. Run existing tests | `flutter test` — all existing tests pass before any changes |
| 1. Add FFmpeg dependency, remove video_thumbnail | App builds and launches, FFmpeg kit initializes, no import errors from removed package |
| 2. Thumbnail strip | Pick video, see thumbnail row generated correctly |
| 3. Scrubber handles | Drag handles, see duration update, enforce 5s max, enforce 0.5s min |
| 4. Video preview | Preview plays only selected segment, loops correctly |
| 5. Quality slider | Move slider, see size estimation update in real-time |
| 6. FFmpeg palette gen | Run pass 1, verify palette.png created with transparency reserved |
| 7. FFmpeg GIF encode | Run pass 2, verify GIF output, check file size, verify non-square video has transparent padding (not black) |
| 8. Cancel during conversion | Tap cancel, verify FFmpeg aborts and temp files cleaned |
| 9. Size retry logic | Force a large video, verify auto-retry reduces quality |
| 10. Handoff to editor (video path) | Navigate to animated editor, verify frames load from map format |
| 11. Handoff to editor (manual path) | Navigate to animated editor via manual frame add (List<String>), verify still works |
| 12. No-edit export path | Export without editing, verify FFmpeg GIF used directly |
| 13. Edit + re-export | Add text, export, verify Dart re-encode uses quality frames |
| 14. Memory with many frames | Pick 5s video at Smoothest (75 frames), verify app doesn't OOM, preview animates smoothly |
| 15. End-to-end flow | Full flow: pick -> trim -> convert -> text -> export -> save to pack |
| 16. Edge cases | Short video (<1s), long video (>5min scroll), portrait video, audio-only file |
| 17. Temp cleanup | After flow, verify no temp files remain |
| 18. Run full test suite | `flutter test` — all tests pass, zero regressions |

---

## Files Changed

### Source Files

| File | Change |
|------|--------|
| `pubspec.yaml` | Add `ffmpeg_kit_flutter_min_gpl`, remove `video_thumbnail` |
| `lib/core/utils/sticker_guardrails.dart` | Add video-specific constants, `validateVideoSticker()`, `estimateGifSizeKB()`. Do NOT change existing maxFps/maxFrames. |
| `lib/features/editor/presentation/video_to_sticker_screen.dart` | Full rewrite: Instagram scrubber, quality slider, FFmpeg pipeline, cancel button |
| `lib/features/editor/presentation/animated_sticker_screen.dart` | Update `_loadInitialFrames()` to handle both List and Map extras, add `_ffmpegGifPath` / `_isVideoSourced`, sliding window frame loading, no-edit export path |
| `lib/core/router/app_router.dart` | Update route handler for `/animated-editor` to accept both `List<String>` and `Map<String, dynamic>` |
| `lib/core/widgets/video_trim_scrubber.dart` | New widget: thumbnail strip with draggable handles |

### Test Files (need updates or new tests)

| File | Change |
|------|--------|
| `test/unit/text_animation_rendering_test.dart` | Add video-specific guardrail tests |
| `test/unit/canvas_and_export_test.dart` | Add video GIF export tests |
| `test/unit/whatsapp_export_test.dart` | Verify video-sourced stickers export correctly |
| `test/widget/editor_screen_test.dart` | Test both List and Map handoff formats |
| `test/widget/editor_comprehensive_test.dart` | Test video-sourced editor behavior |
| `test/widget/screen_coverage_test.dart` | Add video trim screen coverage |
| `test/widget/interaction_gaps_test.dart` | No changes needed (uses global maxFrames=8, unchanged) |
| `test/unit/sticker_guardrails_test.dart` | No changes to existing tests; add new tests for video-specific constants |
| `test/unit/guardrails_comprehensive_test.dart` | No changes to existing tests; add new video validation tests |
| `integration_test/sticker_features_test.dart` | Add video-to-sticker E2E test |
