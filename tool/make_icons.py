"""Builds the DT Food POS launcher icons in Restaurant Red from the approved icon design (receipt with the DT mark, lines, a gold
fork-and-knife coin on its corner). The design layers (receipt, mark, coin) were drawn once and are kept as the foreground PNGs in
res/mipmap-*; this script recolours them (the old Digital Target purple becomes restaurant red), draws a red background and rebuilds
the legacy round / square icons.

Run: python3 -I tool/make_icons.py <from-dir>   where <from-dir> holds the original purple res/ folder (default: git history copy
extracted to a temp dir by the caller). Needs Pillow.
"""
import colorsys
import glob
import os
import sys
from PIL import Image, ImageDraw

RES = os.path.join(os.path.dirname(__file__), '..', 'app', 'android', 'app', 'src', 'main', 'res')
ASSETS = os.path.join(os.path.dirname(__file__), '..', 'app', 'assets', 'brand')
RED, RED_DARK = (212, 48, 48), (140, 20, 20)
DENS = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']


def recolor_fg(im):
    """Purple ink (mark, fork and knife, bottom line) -> restaurant red; pale lavender lines -> pale pink. White and amber stay."""
    im = im.convert('RGBA')
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            H, S, V = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if S > 0.08 and 235 <= H * 360 <= 330:
                if V < 0.62:
                    v = min(0.84, max(0.52, 0.58 + (V - 0.17) * (0.26 / 0.28)))
                    s = min(0.80, 0.55 + S * 0.3)
                else:
                    v, s = V, S * 0.9
                r2, g2, b2 = colorsys.hsv_to_rgb(0.0, s, v)
                px[x, y] = (int(r2 * 255), int(g2 * 255), int(b2 * 255), a)
    return im


def background(px):
    """A red tile: lighter at the top left, darker at the bottom right, with a soft glow."""
    im = Image.new('RGB', (px, px))
    d = im.load()
    for y in range(px):
        for x in range(px):
            t = (x + y) / (2 * px)
            glow = max(0.0, 1 - ((x - px * 0.28) ** 2 + (y - px * 0.22) ** 2) ** 0.5 / (px * 0.6)) * 0.22
            d[x, y] = tuple(min(255, int(RED[i] + (RED_DARK[i] - RED[i]) * t + 40 * glow)) for i in range(3))
    return im


def main(src):
    for dens in DENS:
        sd = os.path.join(src, f'mipmap-{dens}')
        out = os.path.join(RES, f'mipmap-{dens}')
        os.makedirs(out, exist_ok=True)
        fg = recolor_fg(Image.open(os.path.join(sd, 'ic_launcher_foreground.png')))
        fg.save(os.path.join(out, 'ic_launcher_foreground.png'))
        bg = background(fg.width)
        bg.save(os.path.join(out, 'ic_launcher_background.png'))
        # the themed (monochrome) icon is a shape only: kept as drawn
        Image.open(os.path.join(sd, 'ic_launcher_monochrome.png')).save(os.path.join(out, 'ic_launcher_monochrome.png'))
        # legacy icons: the visible 72/108 window of the whole picture, rounded square and circle
        full = bg.convert('RGBA')
        full.alpha_composite(fg)
        k = fg.width / 108
        crop = full.crop((int(18 * k), int(18 * k), int(90 * k), int(90 * k)))
        icon = int(round(48 * k))
        big = crop.resize((icon * 4, icon * 4), Image.LANCZOS)
        sq = big.copy()
        m = Image.new('L', sq.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, sq.size[0] - 1, sq.size[1] - 1], radius=int(sq.size[0] * 0.22), fill=255)
        sq.putalpha(m)
        sq.resize((icon, icon), Image.LANCZOS).save(os.path.join(out, 'ic_launcher.png'))
        rd = big.copy()
        cm = Image.new('L', rd.size, 0)
        ImageDraw.Draw(cm).ellipse([0, 0, rd.size[0] - 1, rd.size[1] - 1], fill=255)
        rd.putalpha(cm)
        rd.resize((icon, icon), Image.LANCZOS).save(os.path.join(out, 'ic_launcher_round.png'))
        if dens == 'xxxhdpi':
            full.resize((512, 512), Image.LANCZOS).save(os.path.join(ASSETS, 'app_icon_512.png'))


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1])
