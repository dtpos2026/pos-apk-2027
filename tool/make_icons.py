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


def receipt_mask(d, fill):
    """The paper: rounded top, zig-zag torn bottom."""
    d.rounded_rectangle([u(29), u(19), u(69), u(70)], radius=u(5), fill=fill)
    d.rectangle([u(29), u(40), u(69), u(78)], fill=fill)
    x = 29.0
    pts = [(29, 78)]
    n = 8
    w = 40 / n
    for i in range(n):
        pts.append((29 + w * (i + 0.5), 84))
        pts.append((29 + w * (i + 1), 78))
    d.polygon([(u(a), u(b)) for a, b in pts], fill=fill)


def cutlery(d, cx, cy, color):
    """Fork and knife, centred on (cx, cy)."""
    # fork (left): three tines + neck + handle
    fx = cx - 4.6
    for dx in (-2.4, 0, 2.4):
        d.rounded_rectangle([u(fx + dx - 0.55), u(cy - 8), u(fx + dx + 0.55), u(cy - 1.5)], radius=u(0.5), fill=color)
    d.rounded_rectangle([u(fx - 3), u(cy - 3.2), u(fx + 3), u(cy - 0.2)], radius=u(1.4), fill=color)
    d.rounded_rectangle([u(fx - 0.75), u(cy - 2), u(fx + 0.75), u(cy + 8)], radius=u(0.7), fill=color)
    # knife (right): blade + handle
    kx = cx + 4.6
    d.rounded_rectangle([u(kx - 1.6), u(cy - 8), u(kx + 1.4), u(cy + 0.5)], radius=u(1.4), fill=color)
    d.rounded_rectangle([u(kx - 0.75), u(cy - 1), u(kx + 1.4), u(cy + 8)], radius=u(0.7), fill=color)


def foreground(mono=False):
    im = Image.new('RGBA', (u(108), u(108)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if mono:
        receipt_mask(d, (0, 0, 0, 255))
        # details are cut out so the themed icon still reads as a receipt
        im.paste((0, 0, 0, 0), (u(39), u(23)), mark_mask(20))
        for y0, y1, x1 in ((46, 48.4, 62), (52.5, 54.9, 53)):
            d.rounded_rectangle([u(35), u(y0), u(x1), u(y1)], radius=u(1), fill=(0, 0, 0, 0))
        d.ellipse([u(57), u(55), u(87), u(85)], fill=(0, 0, 0, 0))
        d.ellipse([u(59), u(57), u(85), u(83)], fill=(0, 0, 0, 255))
        cutlery(d, 72, 70, (0, 0, 0, 0))
        return im
    # soft shadow under the paper and the coin
    sh = Image.new('RGBA', im.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    receipt_mask(sd, (0, 0, 0, 70))
    sh = sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -u(1.2)))
    im.alpha_composite(sh)
    receipt_mask(d, WHITE)
    im.paste(RED, (u(39), u(23)), mark_mask(20))  # the brand mark, now in restaurant red
    for y0, x1 in ((46, 62), (52.5, 53), (59, 51)):
        d.rounded_rectangle([u(35), u(y0), u(x1), u(y0 + 2.6)], radius=u(1.3), fill=TINT)
    d.rounded_rectangle([u(35), u(65.5), u(52), u(67.9)], radius=u(1.2), fill=BLACK)
    d.ellipse([u(56), u(54), u(88), u(86)], fill=WHITE)  # white ring keeps the coin apart from the paper
    d.ellipse([u(58), u(56), u(86), u(84)], fill=GOLD)
    cutlery(d, 72, 70, BLACK)
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
