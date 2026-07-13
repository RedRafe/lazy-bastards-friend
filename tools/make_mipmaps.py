#!/usr/bin/env python3
"""Generate a Factorio mipmap strip from a (large, square) source PNG.

Factorio expects pre-baked mipmaps laid out as a horizontal strip: the base
size followed by each successive half-size appended to the right. E.g.
size=32, mips=2 -> a 48x32 file (32x32 + 16x16), declared in the prototype as:

    {
        type = 'sprite',
        name = 'my-icon',
        filename = '__my-mod__/graphics/icons/my-icon-mip.png',
        priority = 'extra-high-no-scale',
        size = 32,
        mipmap_count = 2,
        flags = { 'gui-icon' },
    }

The base game's GUI icons (data/core/graphics/icons/mip/*.png) use
size=32 with mipmap_count=2 — that's the convention for anything shown in
GUI buttons, and this script's default. Use -m 1 for a plain resize with no
strip (e.g. shortcut prototype icons, where the engine wants a flat image).

Usage:
    make_mipmaps.py INPUT.png                 # 32px + 2 mips -> INPUT-mip.png
    make_mipmaps.py INPUT.png -s 64 -m 4      # 64+32+16+8 strip
    make_mipmaps.py INPUT.png -s 64 -m 1 -o out.png   # flat 64x64 resize
"""

import argparse
import os
import sys

from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('input', help='source PNG (square, ideally much larger than --size)')
    parser.add_argument('-s', '--size', type=int, default=32, help='base sprite size (default 32, the GUI-icon standard)')
    parser.add_argument('-m', '--mips', type=int, default=2, help='mipmap count including the base level (default 2); 1 = flat resize')
    parser.add_argument('-o', '--output', help='output path (default: <input>-mip.png, or <input>-<size>.png when --mips 1)')
    args = parser.parse_args()

    if args.size & (args.size - 1):
        sys.exit(f'--size must be a power of two, got {args.size}')
    if args.mips < 1 or args.size >> (args.mips - 1) < 1:
        sys.exit(f'--mips {args.mips} is too many levels for size {args.size}')

    source = Image.open(args.input).convert('RGBA')
    if source.width != source.height:
        sys.exit(f'source must be square, got {source.width}x{source.height}')

    total_width = sum(args.size >> level for level in range(args.mips))
    strip = Image.new('RGBA', (total_width, args.size), (0, 0, 0, 0))
    x = 0
    for level in range(args.mips):
        level_size = args.size >> level
        strip.paste(source.resize((level_size, level_size), Image.LANCZOS), (x, 0))
        x += level_size

    stem, _ = os.path.splitext(args.input)
    suffix = '-mip' if args.mips > 1 else f'-{args.size}'
    output = args.output or f'{stem}{suffix}.png'
    strip.save(output)
    print(f'{output}: {strip.width}x{strip.height} '
          f'(size={args.size}, mipmap_count={args.mips})')


if __name__ == '__main__':
    main()
