"""Draws the DT Food POS launcher icon (red + white, gold and black accents) for every Android density.

Run: python3 -I tool/make_icons.py   (needs Pillow). Layers follow the adaptive-icon grid: 108 units, safe zone 66 centred.
"""
import os
from PIL import Image, ImageDraw

ASSETS = os.path.join(os.path.dirname(__file__), '..', 'app', 'assets', 'brand')
RES = os.path.join(os.path.dirname(__file__), '..', 'app', 'android', 'app', 'src', 'main', 'res')
S = 16  # supersampling: draw at 108*S, scale down
RED, RED_DARK, GOLD, BLACK, WHITE, TINT = (201, 42, 42), (150, 24, 24), (245, 179, 1), (17, 17, 17), (255, 255, 255), (243, 194, 194)
SIZES = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0}


def mark_mask(side):
    """The Digital Target mark (4 triangles) as a mask, kept from the old icon."""
    return Image.open(os.path.join(ASSETS, 'dt_mark_white.png')).convert('RGBA').split()[-1].resize((u(side), u(side)), Image.LANCZOS)


def u(v):
    return int(round(v * S))


# Everything sits inside a circle of radius 32 around the centre (54, 54), so no launcher shape (circle, squircle, the
# Android 12 splash circle) can cut any of it off. The gold fork-and-knife coin sits on the receipt's lower-right corner.
RX0, RX1, RY0, RY1, TIP = 36, 66, 28, 75, 80
COIN = (64, 70, 9.5)


def receipt_mask(d, fill):
    """The paper: rounded top, zig-zag torn bottom."""
    d.rounded_rectangle([u(RX0), u(RY0), u(RX1), u(RY1)], radius=u(4), fill=fill)
    d.rectangle([u(RX0), u(RY0 + 12), u(RX1), u(RY1 + 2)], fill=fill)
    pts = [(RX0, RY1)]
    n = 8
    w = (RX1 - RX0) / n
    for i in range(n):
        pts.append((RX0 + w * (i + 0.5), TIP))
        pts.append((RX0 + w * (i + 1), RY1))
    d.polygon([(u(a), u(b)) for a, b in pts], fill=fill)


def cutlery(d, cx, cy, color, k=0.62):
    """Fork and knife, centred on (cx, cy), scaled by k."""
    def X(v):
        return u(cx + v * k)

    def Y(v):
        return u(cy + v * k)

    fx = -4.6
    for dx in (-2.4, 0, 2.4):
        d.rounded_rectangle([X(fx + dx - 0.6), Y(-8), X(fx + dx + 0.6), Y(-1.5)], radius=u(0.35), fill=color)
    d.rounded_rectangle([X(fx - 3), Y(-3.2), X(fx + 3), Y(-0.2)], radius=u(0.9), fill=color)
    d.rounded_rectangle([X(fx - 0.8), Y(-2), X(fx + 0.8), Y(8)], radius=u(0.5), fill=color)
    kx = 4.6
    d.rounded_rectangle([X(kx - 1.7), Y(-8), X(kx + 1.5), Y(0.5)], radius=u(1.0), fill=color)
    d.rounded_rectangle([X(kx - 0.8), Y(-1), X(kx + 1.5), Y(8)], radius=u(0.5), fill=color)


def foreground(mono=False):
    im = Image.new('RGBA', (u(108), u(108)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy, r = COIN
    mx = (RX0 + RX1) / 2 - 7
    if mono:
        receipt_mask(d, (0, 0, 0, 255))
        im.paste((0, 0, 0, 0), (u(mx), u(RY0 + 4)), mark_mask(14))
        for y0, x1 in ((RY0 + 20, RX1 - 6), (RY0 + 24.5, RX1 - 13)):
            d.rounded_rectangle([u(RX0 + 6), u(y0), u(x1), u(y0 + 2)], radius=u(1), fill=(0, 0, 0, 0))
        d.ellipse([u(cx - r - 1.6), u(cy - r - 1.6), u(cx + r + 1.6), u(cy + r + 1.6)], fill=(0, 0, 0, 0))
        d.ellipse([u(cx - r), u(cy - r), u(cx + r), u(cy + r)], fill=(0, 0, 0, 255))
        cutlery(d, cx, cy, (0, 0, 0, 0))
        return im
    # soft shadow under the paper
    sh = Image.new('RGBA', im.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    receipt_mask(sd, (0, 0, 0, 80))
    sh = sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -u(1.3)))
    im.alpha_composite(sh)
    receipt_mask(d, WHITE)
    im.paste(RED, (u(mx), u(RY0 + 4)), mark_mask(14))  # the brand mark in restaurant red
    for y0, x1 in ((RY0 + 20, RX1 - 6), (RY0 + 24.5, RX1 - 13)):
        d.rounded_rectangle([u(RX0 + 6), u(y0), u(x1), u(y0 + 2)], radius=u(1), fill=TINT)
    d.ellipse([u(cx - r - 1.7), u(cy - r - 1.7), u(cx + r + 1.7), u(cy + r + 1.7)], fill=WHITE)  # ring keeps the coin apart from the paper
    # the gold coin: drop shadow, dark rim, bright face with a soft highlight, black fork and knife
    d.ellipse([u(cx - r + 0.4), u(cy - r + 1.2), u(cx + r + 0.4), u(cy + r + 1.2)], fill=(0, 0, 0, 60))
    d.ellipse([u(cx - r), u(cy - r), u(cx + r), u(cy + r)], fill=(176, 120, 0))
    d.ellipse([u(cx - r + 0.9), u(cy - r + 0.9), u(cx + r - 0.9), u(cy + r - 0.9)], fill=GOLD)
    d.ellipse([u(cx - r + 1.6), u(cy - r + 1.6), u(cx + r - 1.6), u(cy + r - 1.6)], outline=(255, 214, 90), width=u(0.35))
    cutlery(d, cx, cy, BLACK)
    return im


def background():
    im = Image.new('RGB', (u(108), u(108)), RED)
    px = ImageDraw.Draw(im)
    for y in range(u(108)):
        t = y / u(108)
        c = tuple(int(RED[i] + (RED_DARK[i] - RED[i]) * t) for i in range(3))
        px.line([(0, y), (u(108), y)], fill=c)
    return im


def save(img, name, density, px):
    folder = os.path.join(RES, f'mipmap-{density}')
    os.makedirs(folder, exist_ok=True)
    img.resize((px, px), Image.LANCZOS).save(os.path.join(folder, name))


def main():
    fg, mono, bg = foreground(), foreground(mono=True), background()
    for dens, k in SIZES.items():
        layer = int(108 * k)
        icon = int(48 * k)
        save(fg, 'ic_launcher_foreground.png', dens, layer)
        save(mono, 'ic_launcher_monochrome.png', dens, layer)
        save(bg, 'ic_launcher_background.png', dens, layer)
        # legacy icons (Android 7 and older): the whole picture, cropped to the visible 72/108 window
        full = bg.convert('RGBA')
        full.alpha_composite(fg)
        crop = full.crop((u(18), u(18), u(90), u(90)))
        sq = crop.resize((icon * 4, icon * 4), Image.LANCZOS)
        mask = Image.new('L', sq.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, sq.size[0] - 1, sq.size[1] - 1], radius=int(sq.size[0] * 0.22), fill=255)
        sq.putalpha(mask)
        rd = crop.resize((icon * 4, icon * 4), Image.LANCZOS)
        cm = Image.new('L', rd.size, 0)
        ImageDraw.Draw(cm).ellipse([0, 0, rd.size[0] - 1, rd.size[1] - 1], fill=255)
        rd.putalpha(cm)
        folder = os.path.join(RES, f'mipmap-{dens}')
        sq.resize((icon, icon), Image.LANCZOS).save(os.path.join(folder, 'ic_launcher.png'))
        rd.resize((icon, icon), Image.LANCZOS).save(os.path.join(folder, 'ic_launcher_round.png'))
    # a 512 preview for the store listing and for a quick look
    full = bg.convert('RGBA')
    full.alpha_composite(fg)
    full.resize((512, 512), Image.LANCZOS).save(os.path.join(RES, '..', '..', '..', '..', '..', 'assets', 'brand', 'app_icon_512.png'))


main()
