#!/usr/bin/env python3
"""Placeholder flag icons for the relative panel's sprite-button rows (GUI
refactor, DESIGN.md §4.2 sprite-button redesign). One glyph per settings-tree
flag id (plus the two non-tree prefs use-player-color/summary) — good enough
to see the [lbf-flag-<x>] sprites working until real art replaces them.
Rendered at 4x supersample then downscaled, same approach as
make_family_icons.py. Output: 32x32 RGBA PNGs in graphics/icons/flags/,
referenced at scale=0.5 (16px effective).
"""

import math

from PIL import Image, ImageDraw

OUT_DIR = '/home/gabri/Desktop/Factorio_2.1.x/mods/dev/lazy-bastards-friend/graphics/icons/flags'

S = 32 * 4  # work-scale px, downscaled to 32 at the end
OUTLINE = (20, 14, 6, 255)


def new_canvas():
    return Image.new('RGBA', (S, S), (0, 0, 0, 0))


def save(canvas, name):
    canvas = canvas.resize((32, 32), Image.LANCZOS)
    canvas.save(f'{OUT_DIR}/lbf-flag-{name}.png')
    print(f'wrote lbf-flag-{name}.png')


def fuel_drop(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    pts = [
        (cx, S * 0.12),
        (cx + S * 0.22, S * 0.5),
        (cx + S * 0.22, S * 0.72),
        (cx, S * 0.9),
        (cx - S * 0.22, S * 0.72),
        (cx - S * 0.22, S * 0.5),
    ]
    d.polygon(pts, fill=dark + (255,), outline=OUTLINE, width=int(S * 0.02))
    r = S * 0.12
    cy = S * 0.66
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))
    return canvas


def ingredients(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx, cy = S / 2, S / 2
    r_out, r_in = S * 0.34, S * 0.2
    teeth = 6
    tooth_w = S * 0.1
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
    # inward arrow through the hub
    w = int(S * 0.045)
    d.line([(cx - S * 0.06, cy), (cx + S * 0.1, cy)], fill=color + (255,), width=w)
    d.polygon(
        [(cx + S * 0.1, cy - S * 0.08), (cx + S * 0.1, cy + S * 0.08), (cx + S * 0.2, cy)],
        fill=color + (255,),
    )
    return canvas


def crosshair(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx, cy = S / 2, S / 2
    r = S * 0.3
    w = int(S * 0.035)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color + (255,), width=w)
    d.ellipse([cx - S * 0.06, cy - S * 0.06, cx + S * 0.06, cy + S * 0.06], fill=dark + (255,))
    for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
        x0 = cx + dx * (r + S * 0.02)
        y0 = cy + dy * (r + S * 0.02)
        x1 = cx + dx * (r + S * 0.14)
        y1 = cy + dy * (r + S * 0.14)
        d.line([(x0, y0), (x1, y1)], fill=color + (255,), width=w)
    return canvas


def trash(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    w = int(S * 0.025)
    d.rectangle([cx - S * 0.22, S * 0.18, cx + S * 0.22, S * 0.26], fill=dark + (255,), outline=OUTLINE, width=w)
    body = [(cx - S * 0.24, S * 0.26), (cx + S * 0.24, S * 0.26), (cx + S * 0.18, S * 0.88), (cx - S * 0.18, S * 0.88)]
    d.polygon(body, fill=dark + (255,), outline=OUTLINE, width=w)
    for lx in (cx - S * 0.08, cx, cx + S * 0.08):
        d.line([(lx, S * 0.36), (lx, S * 0.78)], fill=color + (255,), width=w)
    return canvas


def scale(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    w = int(S * 0.035)
    d.line([(cx, S * 0.12), (cx, S * 0.82)], fill=dark + (255,), width=w)
    d.polygon([(cx - S * 0.14, S * 0.9), (cx + S * 0.14, S * 0.9), (cx, S * 0.78)], fill=dark + (255,))
    beam_y = S * 0.28
    d.line([(cx - S * 0.32, beam_y), (cx + S * 0.32, beam_y)], fill=color + (255,), width=w)
    for side in (-1, 1):
        px = cx + side * S * 0.32
        d.line([(px, beam_y), (px, beam_y + S * 0.12)], fill=color + (255,), width=w)
        pan = [(px - S * 0.14, beam_y + S * 0.12), (px + S * 0.14, beam_y + S * 0.12), (px, beam_y + S * 0.24)]
        d.line(pan, fill=color + (255,), width=w, joint='curve')
    return canvas


def open_box(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    w = int(S * 0.025)
    d.rectangle([S * 0.16, S * 0.42, S * 0.84, S * 0.86], fill=dark + (255,), outline=OUTLINE, width=w)
    d.polygon([(S * 0.16, S * 0.42), (cx, S * 0.5), (S * 0.84, S * 0.42), (S * 0.84, S * 0.32), (cx, S * 0.4), (S * 0.16, S * 0.32)], fill=color + (255,), outline=OUTLINE, width=w)
    # open flaps
    d.line([(S * 0.16, S * 0.32), (S * 0.06, S * 0.14)], fill=color + (255,), width=w)
    d.line([(S * 0.84, S * 0.32), (S * 0.94, S * 0.14)], fill=color + (255,), width=w)
    return canvas


def sweep(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    w = int(S * 0.035)
    d.arc([S * 0.14, S * 0.36, S * 0.7, S * 0.92], start=200, end=340, fill=color + (255,), width=w)
    for cx, cy, r in ((S * 0.72, S * 0.3, S * 0.05), (S * 0.82, S * 0.42, S * 0.04), (S * 0.9, S * 0.56, S * 0.035)):
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=dark + (255,), outline=OUTLINE, width=int(S * 0.015))
    return canvas


def swatch(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    pts = [
        (cx, S * 0.1),
        (cx + S * 0.24, S * 0.46),
        (cx + S * 0.24, S * 0.7),
        (cx, S * 0.92),
        (cx - S * 0.24, S * 0.7),
        (cx - S * 0.24, S * 0.46),
    ]
    d.polygon(pts, fill=dark + (255,), outline=OUTLINE, width=int(S * 0.02))
    r = S * 0.13
    cy = S * 0.62
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,))
    return canvas


def two_eyes(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cy = S / 2
    for cx in (S * 0.36, S * 0.64):
        d.polygon(
            [(cx - S * 0.22, cy), (cx, cy - S * 0.16), (cx + S * 0.22, cy), (cx, cy + S * 0.16)],
            fill=color + (255,),
            outline=OUTLINE,
            width=int(S * 0.018),
        )
        r = S * 0.07
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=dark + (255,))
    return canvas


def warning(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    pts = [(cx, S * 0.08), (cx + S * 0.36, S * 0.86), (cx - S * 0.36, S * 0.86)]
    d.polygon(pts, fill=dark + (255,), outline=OUTLINE, width=int(S * 0.025))
    w = int(S * 0.06)
    d.line([(cx, S * 0.36), (cx, S * 0.64)], fill=color + (255,), width=w)
    r = S * 0.035
    d.ellipse([cx - r, S * 0.72 - r, cx + r, S * 0.72 + r], fill=color + (255,))
    return canvas


def clipboard(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = S / 2
    w = int(S * 0.025)
    d.rectangle([S * 0.18, S * 0.14, S * 0.82, S * 0.9], fill=dark + (255,), outline=OUTLINE, width=w)
    d.rectangle([cx - S * 0.12, S * 0.06, cx + S * 0.12, S * 0.2], fill=color + (255,), outline=OUTLINE, width=w)
    for ly in (S * 0.36, S * 0.52, S * 0.68):
        d.line([(S * 0.28, ly), (S * 0.72, ly)], fill=color + (255,), width=w)
    return canvas


def circle_icon(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    cx = cy = S / 2
    r = S * 0.32
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (255,), outline=OUTLINE, width=int(S * 0.02))
    return canvas


def square_icon(color, dark):
    canvas = new_canvas()
    d = ImageDraw.Draw(canvas)
    m = S * 0.18
    d.rectangle([m, m, S - m, S - m], fill=color + (255,), outline=OUTLINE, width=int(S * 0.02))
    return canvas


def main():
    save(fuel_drop((250, 180, 60), (196, 96, 20)), 'fuel')
    save(ingredients((200, 200, 205), (110, 110, 116)), 'ingredients')
    save(crosshair((235, 90, 80), (150, 40, 40)), 'combat')
    save(trash((200, 200, 205), (110, 110, 116)), 'trash')
    save(scale((235, 200, 90), (150, 120, 30)), 'rebalance')
    save(open_box((120, 210, 190), (40, 130, 120)), 'chests')
    save(sweep((120, 210, 190), (40, 130, 120)), 'ground')
    save(swatch((190, 150, 230), (110, 70, 160)), 'use-player-color')
    save(two_eyes((190, 150, 230), (110, 70, 160)), 'show-others')
    save(warning((235, 90, 80), (150, 40, 40)), 'starvation')
    save(clipboard((190, 150, 230), (110, 70, 160)), 'summary')
    save(circle_icon((190, 150, 230), (110, 70, 160)), 'circle')
    save(square_icon((190, 150, 230), (110, 70, 160)), 'square')


if __name__ == '__main__':
    main()
