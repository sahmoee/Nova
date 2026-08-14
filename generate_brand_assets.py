#!/usr/bin/env python3
"""Generate Nova iOS and tvOS identity assets from the approved square master."""

from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent
SOURCE = Path(sys.argv[1] if len(sys.argv) > 1 else "Nova/Resources/Brand/Nova-AppIcon-Pastel-Master.png")
if not SOURCE.is_absolute():
    SOURCE = ROOT / SOURCE

master = Image.open(SOURCE).convert("RGB")


def save(image: Image.Image, relative: str) -> None:
    destination = ROOT / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, "PNG", optimize=True)
    print(f"Wrote {relative} [{image.width}x{image.height}]")


def pastel_background(width: int, height: int) -> Image.Image:
    y, x = np.mgrid[0:height, 0:width].astype(np.float32)
    xn = x / max(width - 1, 1)
    yn = y / max(height - 1, 1)
    left = np.array([220, 190, 218], dtype=np.float32)
    right = np.array([180, 171, 222], dtype=np.float32)
    edge = left[None, None, :] * (1 - xn[..., None]) + right[None, None, :] * xn[..., None]
    edge = edge + (np.array([248, 199, 207]) - edge) * (1 - np.abs(yn - .5) * 2)[..., None] * .32
    radius = np.sqrt(((xn - .5) / .72) ** 2 + ((yn - .48) / .92) ** 2)
    glow = np.clip(1 - radius, 0, 1)[..., None] ** 1.65
    center = np.array([255, 222, 185], dtype=np.float32)
    pixels = edge * (1 - glow) + center * glow
    return Image.fromarray(np.uint8(np.clip(pixels, 0, 255)), "RGB")


def extracted_emblem() -> Image.Image:
    rgba = master.convert("RGBA")
    rgb = np.asarray(master).astype(np.float32) / 255
    maximum = rgb.max(axis=2)
    minimum = rgb.min(axis=2)
    saturation = (maximum - minimum) / np.maximum(maximum, .001)
    luminance = .2126 * rgb[..., 0] + .7152 * rgb[..., 1] + .0722 * rgb[..., 2]
    yy, xx = np.mgrid[0:master.height, 0:master.width]
    safe = ((xx - master.width * .5) / (master.width * .43)) ** 2 + ((yy - master.height * .5) / (master.height * .44)) ** 2 < 1.55
    core = safe & ((luminance < .71) | ((saturation > .30) & (rgb[..., 2] > rgb[..., 0] * .82)))
    mask = Image.fromarray(np.uint8(core) * 255, "L").filter(ImageFilter.MaxFilter(19)).filter(ImageFilter.GaussianBlur(2.2))
    rgba.putalpha(mask)
    bounds = mask.getbbox()
    if not bounds:
        raise RuntimeError("Could not isolate the Nova emblem")
    return rgba.crop(bounds)


emblem = extracted_emblem()


def foreground(width: int, height: int, scale: float = .88) -> Image.Image:
    canvas = Image.new("RGBA", (width, height))
    target_h = int(height * scale)
    target_w = int(emblem.width * target_h / emblem.height)
    if target_w > width * .82:
        target_w = int(width * .82)
        target_h = int(emblem.height * target_w / emblem.width)
    item = emblem.resize((target_w, target_h), Image.Resampling.LANCZOS)
    canvas.alpha_composite(item, ((width - target_w) // 2, (height - target_h) // 2))
    return canvas


def shelf(width: int, height: int) -> Image.Image:
    canvas = pastel_background(width, height).convert("RGBA")
    item = foreground(width, height, .82)
    canvas.alpha_composite(item)
    return canvas.convert("RGB")


ios_root = "Nova/Resources/Assets-iOS.xcassets/AppIcon.appiconset"
square = master.resize((1024, 1024), Image.Resampling.LANCZOS)
for pixels in (20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024):
    save(square.resize((pixels, pixels), Image.Resampling.LANCZOS), f"{ios_root}/AppIcon-{pixels}.png")
save(square, "Nova/Resources/Brand/Nova-AppIcon-Master.png")

tv_root = "Nova/Resources/Assets-tvOS.xcassets/App Icon & Top Shelf Image.brandassets"
for suffix, width, height in (("1x", 400, 240), ("2x", 800, 480)):
    save(pastel_background(width, height), f"{tv_root}/App Icon.imagestack/Back.imagestacklayer/Content.imageset/tv_back_{suffix}.png")
    save(foreground(width, height), f"{tv_root}/App Icon.imagestack/Front.imagestacklayer/Content.imageset/tv_front_{suffix}.png")
save(pastel_background(1280, 768), f"{tv_root}/App Store.imagestack/Back.imagestacklayer/Content.imageset/appstore_back.png")
save(foreground(1280, 768), f"{tv_root}/App Store.imagestack/Front.imagestacklayer/Content.imageset/appstore_front.png")
save(shelf(1920, 720), f"{tv_root}/Top Shelf Image.imageset/TopShelf_1x.png")
save(shelf(3840, 1440), f"{tv_root}/Top Shelf Image.imageset/TopShelf_2x.png")
save(shelf(2320, 720), f"{tv_root}/Top Shelf Image Wide.imageset/TopShelfWide_1x.png")
save(shelf(4640, 1440), f"{tv_root}/Top Shelf Image Wide.imageset/TopShelfWide_2x.png")
save(shelf(2320, 720), "Nova/Resources/Brand/Nova-TopShelf-Master.png")
