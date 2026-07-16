#!/usr/bin/env python3
"""Placeholder family icons for mod-setting-name prefixes (settings.lua §order rework).

Five small flat glyphs, one per settings family — feed (flame), collect
(inbox arrow), appearance (eye), watchdog (shield), other (gear) — good
enough to see the [img=utility/lbf-<family>] prefixes working until real
art replaces them. Rendered at 4x supersample then downscaled, matching
the approach in make_banner_placeholder.py. Output: 32x32 RGBA PNGs in
graphics/icons/family/, referenced at scale=0.5 (16px effective) like
core's own utility-sprites (e.g. check_mark).
"""

import math

from PIL import Image, ImageChops, ImageDraw

OUT_DIR = '/home/gabri/Desktop/Factorio_2.1.x/mods/dev/lazy-bastards-friend/graphics/icons/family'

S = 32 * 4  # work-scale px, downscaled to 32 at the end
OUTLINE = (20, 14, 6, 255)


def new_canvas():
    return Image.new('RGBA', (S, S), (0, 0, 0, 0))


def save(canvas, name):
    canvas = canvas.resize((32, 32), Image.LANCZOS)
    canvas.save(f'{OUT_DIR}/lbf-family-{name}.png')
    print(f'wrote lbf-family-{name}.png')


def flame(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    pts = [
        (cx, S * 0.08),
        (cx + S * 0.26, S * 0.42),
        (cx + S * 0.20, S * 0.5),
        (cx + S * 0.34, S * 0.72),
        (cx, S * 0.94),
        (cx - S * 0.34, S * 0.72),
        (cx - S * 0.20, S * 0.5),
        (cx - S * 0.26, S * 0.42),
    ]
    d.polygon(pts, fill=dark + (255,), outline=OUTLINE, width=int(S * 0.02))
    inner = [
        (cx, S * 0.32),
        (cx + S * 0.14, S * 0.55),
        (cx + S * 0.10, S * 0.6),
        (cx + S * 0.16, S * 0.74),
        (cx, S * 0.86),
        (cx - S * 0.16, S * 0.74),
        (cx - S * 0.10, S * 0.6),
        (cx - S * 0.14, S * 0.55),
    ]
    d.polygon(inner, fill=color + (255,))
    return canvas


def collect(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    box = [S * 0.14, S * 0.5, S * 0.86, S * 0.9]
    d.rectangle(box, fill=dark + (255,), outline=OUTLINE, width=int(S * 0.02))
    d.rectangle([S * 0.14, S * 0.5, S * 0.86, S * 0.62], fill=color + (255,), outline=OUTLINE, width=int(S * 0.02))
    cx = S / 2
    w = int(S * 0.05)
    d.line([(cx, S * 0.5), (cx, S * 0.14)], fill=color + (255,), width=w)
    d.polygon(
        [(cx - S * 0.16, S * 0.28), (cx + S * 0.16, S * 0.28), (cx, S * 0.06)],
        fill=color + (255,),
        outline=OUTLINE,
    )
    return canvas


def eye(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx, cy = S / 2, S / 2
    d.polygon(
        [(cx - S * 0.42, cy), (cx, cy - S * 0.3), (cx + S * 0.42, cy), (cx, cy + S * 0.3)],
        fill=color + (255,),
        outline=OUTLINE,
        width=int(S * 0.02),
    )
    r = S * 0.16
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=dark + (255,), outline=OUTLINE, width=int(S * 0.02))
    r2 = S * 0.07
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=(20, 14, 6, 255))
    return canvas


def shield(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    pts = [
        (cx, S * 0.06),
        (cx + S * 0.38, S * 0.18),
        (cx + S * 0.38, S * 0.55),
        (cx, S * 0.94),
        (cx - S * 0.38, S * 0.55),
        (cx - S * 0.38, S * 0.18),
    ]
    d.polygon(pts, fill=dark + (255,), outline=OUTLINE, width=int(S * 0.02))
    r = S * 0.14
    cy = S * 0.42
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))
    d.polygon([(cx - r * 0.8, cy + r * 0.3), (cx + r * 0.8, cy + r * 0.3), (cx, cy + r * 1.8)], fill=color + (255,))
    return canvas


def gear(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx, cy = S / 2, S / 2
    r_out, r_in = S * 0.4, S * 0.24
    teeth = 8
    tooth_w = S * 0.12
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        x0 = cx + r_in * 0.9 * math.cos(a)
        y0 = cy + r_in * 0.9 * math.sin(a)
        x1 = cx + r_out * math.cos(a)
        y1 = cy + r_out * math.sin(a)
        dx = math.cos(a + math.pi / 2) * tooth_w / 2
        dy = math.sin(a + math.pi / 2) * tooth_w / 2
        d.polygon([(x0 - dx, y0 - dy), (x0 + dx, y0 + dy), (x1 + dx, y1 + dy), (x1 - dx, y1 - dy)], fill=dark + (255,))
    d.ellipse([cx - r_in, cy - r_in, cx + r_in, cy + r_in], fill=dark + (255,), outline=OUTLINE, width=int(S * 0.02))
    r_hub = S * 0.1
    d.ellipse([cx - r_hub, cy - r_hub, cx + r_hub, cy + r_hub], fill=color + (255,))
    return canvas


def filters(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    w = int(S * 0.02)
    funnel = [
        (S * 0.1, S * 0.14),
        (S * 0.9, S * 0.14),
        (cx + S * 0.14, S * 0.5),
        (cx + S * 0.14, S * 0.86),
        (cx - S * 0.14, S * 0.86),
        (cx - S * 0.14, S * 0.5),
    ]
    d.polygon(funnel, fill=dark + (255,), outline=OUTLINE, width=w)
    for i, ty in enumerate((S * 0.28, S * 0.4)):
        hw = S * (0.28 - i * 0.1)
        d.line([(cx - hw, ty), (cx + hw, ty)], fill=color + (255,), width=w)
    return canvas


def behavior():
    """Composite of feed (top-left) and collect (bottom-right), split by the
    anti-diagonal — the Behavior section covers both channels, so its title
    icon is a mashup of the two rather than a new glyph. Both halves are hard
    -clipped to their triangle (not just each icon's own alpha shape) so the
    divider line actually matches the visible cut."""
    feed_canvas = flame((250, 180, 60), (196, 96, 20))
    collect_canvas = collect((120, 210, 190), (40, 130, 120))
    tl_triangle = Image.new('L', (S, S), 0)
    ImageDraw.Draw(tl_triangle).polygon([(0, 0), (S, 0), (0, S)], fill=255)
    br_triangle = Image.new('L', (S, S), 0)
    ImageDraw.Draw(br_triangle).polygon([(S, 0), (S, S), (0, S)], fill=255)
    feed_mask = ImageChops.multiply(tl_triangle, feed_canvas.split()[-1])
    collect_mask = ImageChops.multiply(br_triangle, collect_canvas.split()[-1])
    canvas = new_canvas()
    canvas.paste(collect_canvas, (0, 0), collect_mask)
    canvas.paste(feed_canvas, (0, 0), feed_mask)
    ImageDraw.Draw(canvas).line([(S, 0), (0, S)], fill=OUTLINE, width=int(S * 0.03))
    return canvas


def main():
    save(flame((250, 180, 60), (196, 96, 20)), 'feed')
    save(collect((120, 210, 190), (40, 130, 120)), 'collect')
    save(eye((190, 150, 230), (110, 70, 160)), 'appearance')
    save(shield((235, 90, 80), (150, 40, 40)), 'watchdog')
    save(gear((200, 200, 205), (110, 110, 116)), 'other')
    save(filters((235, 200, 90), (150, 120, 30)), 'filters')
    save(behavior(), 'behavior')


if __name__ == '__main__':
    main()
