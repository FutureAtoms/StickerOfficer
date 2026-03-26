"""Photo processing: background removal and emotion tagging."""

import io
from pathlib import Path
from PIL import Image
from rembg import remove
from config import STICKER_SIZE, THUMB_SIZE, WEBP_QUALITY

# Lazy-loaded CLIP model
_clip_model = None
_clip_preprocess = None
_clip_tokenizer = None


def process_photo(input_path: Path, output_dir: Path) -> dict | None:
    """Process a single photo: bg removal -> resize -> save WebP + thumbnail.

    Returns metadata dict or None on failure.
    """
    try:
        # Load and remove background
        input_bytes = input_path.read_bytes()
        output_bytes = remove(input_bytes)
        img = Image.open(io.BytesIO(output_bytes)).convert("RGBA")

        # Resize to 512x512 (fit within, pad with transparent)
        sticker = _fit_and_pad(img, STICKER_SIZE)
        thumb = _fit_and_pad(img, THUMB_SIZE)

        # Save sticker
        sticker_name = f"{input_path.stem}.webp"
        sticker_path = output_dir / sticker_name
        sticker.save(sticker_path, "WEBP", quality=WEBP_QUALITY)

        # Save thumbnail
        thumb_name = f"{input_path.stem}_thumb.webp"
        thumb_path = output_dir / thumb_name
        thumb.save(thumb_path, "WEBP", quality=70)

        # Emotion tagging
        emojis = classify_emotion(img)

        return {
            "sticker_path": sticker_path,
            "thumb_path": thumb_path,
            "emojis": emojis,
            "size_kb": sticker_path.stat().st_size / 1024,
        }
    except Exception as e:
        print(f"  Failed to process {input_path.name}: {e}")
        return None


def classify_emotion(img: Image.Image) -> list[str]:
    """Classify the dominant emotion in an image using CLIP zero-shot."""
    import torch
    import open_clip

    global _clip_model, _clip_preprocess, _clip_tokenizer

    if _clip_model is None:
        _clip_model, _, _clip_preprocess = open_clip.create_model_and_transforms(
            "ViT-B-32", pretrained="laion2b_s34b_b79k"
        )
        _clip_tokenizer = open_clip.get_tokenizer("ViT-B-32")
        _clip_model.eval()

    emotion_labels = {
        "a happy smiling person": "\U0001f60a",
        "a person laughing hard": "\U0001f602",
        "a sad or crying person": "\U0001f622",
        "an angry furious person": "\U0001f620",
        "a person in love, romantic": "\U0001f60d",
        "a cute adorable person": "\U0001f970",
        "a cool confident person": "\U0001f60e",
        "a confused thinking person": "\U0001f914",
        "a scared surprised person": "\U0001f631",
        "a person celebrating, excited": "\U0001f973",
        "a tired sleepy person": "\U0001f634",
        "a silly goofy person": "\U0001f92a",
    }

    # Convert RGBA to RGB for CLIP
    rgb_img = img.convert("RGB")
    image_input = _clip_preprocess(rgb_img).unsqueeze(0)
    text_inputs = _clip_tokenizer(list(emotion_labels.keys()))

    with torch.no_grad():
        image_features = _clip_model.encode_image(image_input)
        text_features = _clip_model.encode_text(text_inputs)
        image_features /= image_features.norm(dim=-1, keepdim=True)
        text_features /= text_features.norm(dim=-1, keepdim=True)
        similarity = (image_features @ text_features.T).squeeze(0)
        probs = similarity.softmax(dim=0)

    # Top 2 emotions above threshold
    emoji_list = list(emotion_labels.values())
    sorted_indices = probs.argsort(descending=True)
    result = []
    for idx in sorted_indices[:2]:
        if probs[idx] > 0.05:
            result.append(emoji_list[idx])

    return result if result else ["\U0001f60a"]  # Default to happy


def _fit_and_pad(img: Image.Image, size: int) -> Image.Image:
    """Resize image to fit within size x size, pad with transparent pixels."""
    img.thumbnail((size, size), Image.LANCZOS)
    padded = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset_x = (size - img.width) // 2
    offset_y = (size - img.height) // 2
    padded.paste(img, (offset_x, offset_y))
    return padded
