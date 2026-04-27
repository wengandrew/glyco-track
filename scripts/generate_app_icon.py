#!/usr/bin/env python3
"""Generate the GlycoTrack iOS app icon at 1024×1024.

Concept
-------
GlycoTrack tracks two health metrics — Glycemic Load (GL) and Cholesterol Load (CL).
The app uses two accent colors throughout:

  • glAccent  — deep blue   (carbs / glucose / drop.fill)
  • clAccent  — crimson red (cholesterol / heart.fill)

The icon ties both metrics together:

  1. A diagonal gradient background flows from glAccent (upper-left) to clAccent
     (lower-right), so the very canvas itself reads as "two metrics, one axis".
  2. A white circular badge sits centered, providing a clean stage for the glyph.
  3. Inside the badge, two stacked icons:
       • Top:    a chunky blue water droplet (GL — glucose)
       • Bottom: a chunky crimson heart       (CL — cholesterol)
     Their stacked layout mirrors the app's vertical layout where the GL section
     is rendered above the CL section.

Output
------
Writes a single 1024×1024 PNG. Xcode's modern AppIcon.appiconset references this
one image; the Asset Catalog compiler synthesizes all required sizes at build time.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

# Canvas
W = 1024

# Brand colors (sourced from glAccent / clAccent in HomeTabView.swift)
GL_BLUE  = (0x2A, 0x6B, 0xD1)   # deep blue  — RGB(42, 107, 209)
CL_RED   = (0xD4, 0x38, 0x59)   # crimson    — RGB(212, 56,  89)

# A small color shift toward purple at the midpoint smooths the diagonal blend
# (without it, the middle band looks muddy brown where R, G, B all average out).
MID = (0x6E, 0x4E, 0x9C)


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        int(round(a[0] + (b[0] - a[0]) * t)),
        int(round(a[1] + (b[1] - a[1]) * t)),
        int(round(a[2] + (b[2] - a[2]) * t)),
    )


def gradient_color(t: float) -> tuple[int, int, int]:
    """Three-stop blend: GL_BLUE → MID → CL_RED, smoothed by a cosine-eased t."""
    # Cosine ease for a more pleasing s-curve than linear.
    et = 0.5 - 0.5 * math.cos(math.pi * t)
    if et < 0.5:
        return lerp(GL_BLUE, MID, et * 2)
    else:
        return lerp(MID, CL_RED, (et - 0.5) * 2)


def render_background(img: Image.Image) -> None:
    """Diagonal gradient from upper-left (GL_BLUE) to lower-right (CL_RED)."""
    px = img.load()
    diag = (W - 1) * math.sqrt(2)
    for y in range(W):
        for x in range(W):
            # distance along the upper-left → lower-right diagonal, normalized
            t = (x + y) / (2 * (W - 1))
            px[x, y] = gradient_color(t)


def draw_droplet(draw: ImageDraw.ImageDraw, cx: float, cy: float, height: float, color: tuple[int, int, int]) -> None:
    """Classic teardrop: a circle with a triangular peak.

    Geometry:
      • The droplet is `height` points tall; width is ~70% of height.
      • The lower 60% is a circle; the upper 40% is a triangular peak that
        merges smoothly into the circle's tangent.
    """
    # circle radius: chosen so circle diameter ≈ 70% of droplet height
    r = height * 0.36
    circle_cy = cy + height * 0.5 - r           # bottom of droplet at cy + h/2
    apex = (cx, cy - height * 0.5)              # tip of teardrop

    # Tangent points where the triangle meets the circle: choose an angle so the
    # triangle's sides are tangent to the circle. With circle center at
    # (cx, circle_cy) and apex straight above at (cx, apex_y), the tangent angle
    # from vertical is arcsin(r / d) where d = circle_cy - apex_y.
    d = circle_cy - apex[1]
    if d <= r:
        # Apex inside circle — fallback to a simple ellipse.
        draw.ellipse(
            [cx - r, circle_cy - r, cx + r, circle_cy + r],
            fill=color,
        )
        return
    alpha = math.asin(r / d)                    # half-angle of the triangle at apex
    # tangent points on the circle, mirrored across vertical axis through cx
    # (measured from the circle center; vertical-up direction is negative y)
    left_tx  = cx - r * math.cos(alpha)
    right_tx = cx + r * math.cos(alpha)
    ty       = circle_cy - r * math.sin(alpha)

    # Draw the lower circle (full disc — the polygon will cover its top half).
    draw.ellipse(
        [cx - r, circle_cy - r, cx + r, circle_cy + r],
        fill=color,
    )
    # Triangular peak from apex down to the tangent points.
    draw.polygon(
        [apex, (right_tx, ty), (left_tx, ty)],
        fill=color,
    )


def draw_heart(draw: ImageDraw.ImageDraw, cx: float, cy: float, size: float, color: tuple[int, int, int]) -> None:
    """Heart shape composed of two circles + a kite-shaped polygon.

    `size` is the full height (and approximately width) of the heart.
    The polygon spans both lobes' inner-top edges plus the V-tip below, so the
    cleavage between the two lobes is filled solid (no notch).
    """
    # Two top lobes
    lobe_r = size * 0.28
    left_cx  = cx - lobe_r
    right_cx = cx + lobe_r
    lobe_cy = cy - size * 0.18

    draw.ellipse(
        [left_cx - lobe_r, lobe_cy - lobe_r, left_cx + lobe_r, lobe_cy + lobe_r],
        fill=color,
    )
    draw.ellipse(
        [right_cx - lobe_r, lobe_cy - lobe_r, right_cx + lobe_r, lobe_cy + lobe_r],
        fill=color,
    )

    # Kite polygon: outer tangent points on the lobes (angle 45° below horizontal)
    # → up to the cleavage top (between the lobes, slightly above lobe centers)
    # → down to the tip. This fills the inverted-V plus the bridge between lobes.
    angle = math.radians(45)
    left_tangent  = (left_cx  - lobe_r * math.cos(angle), lobe_cy + lobe_r * math.sin(angle))
    right_tangent = (right_cx + lobe_r * math.cos(angle), lobe_cy + lobe_r * math.sin(angle))
    cleavage_top  = (cx, lobe_cy - lobe_r * 0.15)   # above lobe centers — push into the lobes
    tip           = (cx, cy + size * 0.50)
    draw.polygon(
        [left_tangent, cleavage_top, right_tangent, tip],
        fill=color,
    )


def render_icon(out_path: Path) -> None:
    img = Image.new("RGB", (W, W), GL_BLUE)
    render_background(img)

    # Render glyphs on a transparent overlay so we can softly drop-shadow them.
    overlay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)

    # White circular badge (with a subtle inner highlight so it doesn't look pasted on).
    badge_radius = 360
    cx = cy = W / 2
    od.ellipse(
        [cx - badge_radius, cy - badge_radius, cx + badge_radius, cy + badge_radius],
        fill=(255, 255, 255, 255),
    )
    # Soft inner shadow hint at the bottom of the badge for depth.
    inner_shade = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    isd = ImageDraw.Draw(inner_shade)
    isd.ellipse(
        [cx - badge_radius + 8, cy - badge_radius + 28, cx + badge_radius - 8, cy + badge_radius + 28],
        fill=(0, 0, 0, 14),
    )
    inner_shade = inner_shade.filter(ImageFilter.GaussianBlur(radius=8))
    overlay.alpha_composite(inner_shade)

    # Stack the glyphs vertically inside the badge:
    #   droplet on top (GL — glucose, blue)
    #   heart   on bottom (CL — cholesterol, crimson)
    glyph_height = 280
    gap = 36
    droplet_cy = cy - (glyph_height + gap) / 2 + glyph_height * 0.05
    heart_cy   = cy + (glyph_height + gap) / 2 - glyph_height * 0.05

    draw_droplet(od, cx, droplet_cy, glyph_height, GL_BLUE)
    draw_heart  (od, cx, heart_cy,   glyph_height * 0.86, CL_RED)

    # Composite overlay onto background.
    img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")

    img.save(out_path, "PNG", optimize=True)
    print(f"Wrote {out_path} ({out_path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parents[1]
    out = repo_root / "GlycoTrack" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    render_icon(out)
