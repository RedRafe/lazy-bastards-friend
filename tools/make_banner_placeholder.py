#!/usr/bin/env python3
"""Placeholder wordmark banner for lazy-bastards-friend.

Renders "LAZY BASTARD'S / FRIEND" as chunky orange slab text with a fake
bevel (top-lit lighter pass), a dark drop shadow, and a brass gear standing
in for the apostrophe — good enough to wire the GUI code against until the
real AI-generated art replaces graphics/gui/lbf-banner.png.
Output: 536x180 RGBA PNG.
"""

import math

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
OUT = '/home/gabri/Desktop/Factorio_2.1.x/mods/dev/lazy-bastards-friend/graphics/gui/lbf-banner.png'

# Work at 4x the final size for clean antialiasing, then downscale.
W, H = 536 * 4, 180 * 4
MARGIN = 8 * 4  # transparent margin in the final image, in work-scale px

ORANGE = (232, 145, 42)
ORANGE_DARK = (150, 84, 18)
HIGHLIGHT = (255, 199, 199, 90)
OUTLINE = (54, 30, 8)
SHADOW = (10, 8, 5, 200)
BRASS = (196, 158, 66)
BRASS_DARK = (110, 84, 26)

SHADOW_OFF = 14
BEVEL_OFF = 5


def gear(draw, cx, cy, r, teeth=8):
    """Solid gear: toothed ring + hub hole (hole punched by caller)."""
    tooth_w = r * 0.55
    for i in range(teeth):
        a = 2 * math.pi * i / teeth
        x1 = cx + (r * 1.35) * math.cos(a)
        y1 = cy + (r * 1.35) * math.sin(a)
        half = tooth_w / 2
        dx, dy = math.cos(a + math.pi / 2) * half, math.sin(a + math.pi / 2) * half
        x0 = cx + (r * 0.6) * math.cos(a)
        y0 = cy + (r * 0.6) * math.sin(a)
        draw.polygon([(x0 - dx, y0 - dy), (x0 + dx, y0 + dy), (x1 + dx, y1 + dy), (x1 - dx, y1 - dy)], fill=255)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)


def render_mask(font1, font2):
    """Alpha mask of the whole wordmark (text + gear), plus the gear's own mask."""
    mask = Image.new('L', (W, H), 0)
    d = ImageDraw.Draw(mask)

    seg_a, seg_b = 'LAZY BASTARD', 'S'
    line2 = 'FRIEND'
    gear_r = font1.size * 0.16
    gear_gap = gear_r * 4.2

    wa = d.textlength(seg_a, font=font1)
    wb = d.textlength(seg_b, font=font1)
    w1 = wa + gear_gap + wb
    w2 = d.textlength(line2, font=font2)

    asc1, desc1 = font1.getmetrics()
    asc2, _ = font2.getmetrics()
    line_gap = font1.size * 0.28
    total_h = asc1 + desc1 * 0.3 + line_gap + asc2
    y1 = (H - total_h) / 2 - font1.size * 0.18
    y2 = y1 + asc1 + desc1 * 0.3 + line_gap

    x1 = (W - w1) / 2
    d.text((x1, y1), seg_a, font=font1, fill=255)
    d.text((x1 + wa + gear_gap, y1), seg_b, font=font1, fill=255)
    x2 = (W - w2) / 2
    d.text((x2, y2), line2, font=font2, fill=255)

    gear_mask = Image.new('L', (W, H), 0)
    gd = ImageDraw.Draw(gear_mask)
    gcx = x1 + wa + gear_gap / 2
    gcy = y1 + asc1 * 0.30
    gear(gd, gcx, gcy, gear_r)
    hub = Image.new('L', (W, H), 0)
    ImageDraw.Draw(hub).ellipse(
        [gcx - gear_r * 0.45, gcy - gear_r * 0.45, gcx + gear_r * 0.45, gcy + gear_r * 0.45], fill=255
    )
    gear_mask = Image.composite(Image.new('L', (W, H), 0), gear_mask, hub)
    return mask, gear_mask


def flat(color, mask):
    layer = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    layer.paste(Image.new('RGBA', (W, H), color + (255,)), (0, 0), mask)
    return layer


def offset(img, dx, dy):
    out = Image.new(img.mode, img.size, 0 if img.mode == 'L' else (0, 0, 0, 0))
    out.paste(img, (dx, dy))
    return out


def main():
    font1 = ImageFont.truetype(FONT, 150)
    font2 = ImageFont.truetype(FONT, 300)
    mask, gear_mask = render_mask(font1, font2)

    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))

    # Drop shadow, slightly blurred, falling down-right.
    shadow_mask = offset(mask, SHADOW_OFF, SHADOW_OFF).filter(ImageFilter.GaussianBlur(4))
    shadow = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    shadow.paste(Image.new('RGBA', (W, H), SHADOW), (0, 0), shadow_mask)
    canvas = Image.alpha_composite(canvas, shadow)

    # Dark outline pass (fattened mask) for definition against any background.
    fat = mask.filter(ImageFilter.MaxFilter(9))
    canvas = Image.alpha_composite(canvas, flat(OUTLINE, fat))

    # Fake bevel: dark tone at rest position, main tone nudged up-left.
    canvas = Image.alpha_composite(canvas, flat(ORANGE_DARK, mask))
    canvas = Image.alpha_composite(canvas, flat(ORANGE, offset(mask, -BEVEL_OFF, -BEVEL_OFF)))

    # Top-edge highlight: the sliver of the up-left pass not covered by the base.
    sliver = Image.composite(Image.new('L', (W, H), 0), offset(mask, -BEVEL_OFF * 2, -BEVEL_OFF * 2), mask)
    hl = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    hl.paste(Image.new('RGBA', (W, H), HIGHLIGHT), (0, 0), sliver)
    canvas = Image.alpha_composite(canvas, hl)

    # Brass gear on top, with its own mini shadow/bevel.
    canvas = Image.alpha_composite(canvas, flat(BRASS_DARK, gear_mask))
    canvas = Image.alpha_composite(canvas, flat(BRASS, offset(gear_mask, -BEVEL_OFF, -BEVEL_OFF)))

    # Trim to content, then fit into 536x180 with a uniform margin.
    bbox = canvas.getbbox()
    canvas = canvas.crop(bbox)
    target_w, target_h = 536, 180
    inner_w, inner_h = target_w - 2 * MARGIN // 4, target_h - 2 * MARGIN // 4
    scale = min(inner_w / canvas.width, inner_h / canvas.height)
    canvas = canvas.resize((round(canvas.width * scale), round(canvas.height * scale)), Image.LANCZOS)
    out = Image.new('RGBA', (target_w, target_h), (0, 0, 0, 0))
    out.paste(canvas, ((target_w - canvas.width) // 2, (target_h - canvas.height) // 2))
    out.save(OUT)
    print(f'wrote {OUT} ({out.size[0]}x{out.size[1]})')


if __name__ == '__main__':
    main()
