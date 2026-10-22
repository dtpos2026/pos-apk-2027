"""Generate DT Food POS launcher icons.

Usage: python3 -I generate_icons.py <logo.jpg> <repo_root>
The Digital Target mark is cropped from the supplied logo (never redrawn);
the receipt, burger and gradient are drawn here.
"""
import math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC, ROOT = sys.argv[1], sys.argv[2]
OUT, RES = os.path.join(ROOT, "branding/icon"), os.path.join(ROOT, "android-res")
S = 2048
PURPLE = (0x3D, 0x09, 0x6D)
WHITE, AMBER, BUN, SEED = (255, 255, 255), (255, 181, 71), (245, 165, 58), (255, 226, 168)
LAV, CHEESE, LINE = (205, 180, 240), (255, 214, 120), (214, 200, 234)

# --- Digital Target mark (alpha mask from the supplied logo) ---
_a = np.asarray(Image.open(SRC).convert("RGB")).astype(float)
_lum = _a.mean(axis=2)
_m = np.clip((_lum - _lum[:200, :200].mean()) / (255 - _lum[:200, :200].mean()), 0, 1)
_m[:, 540:] = 0
_ys, _xs = np.where(_m > 0.5)
MARK = Image.fromarray((_m[_ys.min() - 2:_ys.max() + 3, _xs.min() - 2:_xs.max() + 3] * 255).astype("uint8"))

def mark_mask(h):
    return MARK.resize((round(MARK.width * h / MARK.height), h), Image.LANCZOS)

def gradient():
    y, x = np.mgrid[0:S, 0:S] / S
    t = np.clip(x * 0.4 + y * 0.6, 0, 1)[..., None]
    c1, c2 = np.array([0x6A, 0x22, 0xB0]), np.array([0x2A, 0x04, 0x4D])
    glow = np.clip(1 - np.hypot(x - 0.3, y - 0.25) * 1.1, 0, 1)[..., None]
    img = (c1 * (1 - t) + c2 * t) * 0.85 + np.array([0x7A, 0x38, 0xC8]) * 0.3 * glow
    return Image.fromarray(np.clip(img, 0, 255).astype("uint8")).convert("RGBA")

def shadow(im, off=18, blur=22, alpha=90):
    sh = Image.new("RGBA", im.size, (10, 0, 25, 0))
    sh.putalpha(im.split()[3].point(lambda v: v * alpha // 255))
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)), (0, off))
    out.alpha_composite(im)
    return out

def build_receipt():
    """Receipt + fork/knife badge. Returns (RGBA art, mono alpha mask)."""
    w, h, r = 680, 940, 215
    ox, oy = (S - w) // 2, (S - h) // 2           # receipt itself is centred; badge overhangs
    bx, by = ox + w - 40, oy + h - 130            # badge centre

    body = Image.new("L", (S, S), 0)
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle((ox, oy, ox + w, oy + h - 50), 44, fill=255, corners=(True, True, False, False))
    n, step = 10, w / 10
    pts = [(ox, oy + h - 50)]
    for i in range(n):
        pts += [(ox + step * i + step / 2, oy + h), (ox + step * (i + 1), oy + h - 50)]
    bd.polygon(pts, fill=255)

    art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    art.paste(Image.new("RGBA", (S, S), WHITE + (255,)), mask=body)
    d = ImageDraw.Draw(art)
    cut = Image.new("L", (S, S), 0)
    cd = ImageDraw.Draw(cut)

    # DT mark (from the supplied logo)
    mk = mark_mask(260)
    layer = Image.new("RGBA", mk.size, PURPLE + (255,)); layer.putalpha(mk)
    mx, my = ox + (w - mk.width) // 2, oy + 80
    art.alpha_composite(layer, (mx, my)); cut.paste(mk, (mx, my), mk)

    # line items
    for i, y in enumerate([oy + 430 + i * 105 for i in range(4)]):
        lw = 400 if i % 2 == 0 else 310
        d.rounded_rectangle((ox + 80, y, ox + 80 + lw, y + 36), 18, fill=LINE + (255,))
        d.rounded_rectangle((ox + w - 80 - 110, y, ox + w - 80, y + 36), 18, fill=LINE + (255,))
        cd.rounded_rectangle((ox + 80, y, ox + 80 + lw, y + 36), 18, fill=255)
        cd.rounded_rectangle((ox + w - 80 - 110, y, ox + w - 80, y + 36), 18, fill=255)
    d.rounded_rectangle((ox + 80, oy + 850, ox + w - 80, oy + 868), 9, fill=PURPLE + (255,))
    cd.rounded_rectangle((ox + 80, oy + 850, ox + w - 80, oy + 868), 9, fill=255)

    # badge
    badge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(badge).ellipse((bx - r, by - r, bx + r, by + r), fill=AMBER + (255,))
    badge = shadow(badge, 14, 18, 110)
    art = shadow(art)
    art.alpha_composite(badge)

    # fork + knife glyph, as an alpha mask so it can also be cut out of the mono layer
    k = r / 250
    g = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(g)
    fx = bx - 70 * k
    for dx in (-34, 0, 34):
        gd.rounded_rectangle((fx + dx * k - 9 * k, by - 150 * k, fx + dx * k + 9 * k, by - 30 * k), 9 * k, fill=255)
    gd.pieslice((fx - 43 * k, by - 80 * k, fx + 43 * k, by + 20 * k), 0, 180, fill=255)
    gd.rectangle((fx - 43 * k, by - 60 * k, fx + 43 * k, by - 25 * k), fill=255)
    gd.rounded_rectangle((fx - 11 * k, by - 20 * k, fx + 11 * k, by + 150 * k), 11 * k, fill=255)
    kx = bx + 60 * k
    kp = [(kx, by - 150 * k)] + [(kx + 48 * k * math.sin(math.radians(t)), by - 150 * k + 130 * k * (1 - math.cos(math.radians(t)))) for t in range(0, 91, 6)] + [(kx + 48 * k, by + 20 * k), (kx, by + 20 * k)]
    gd.polygon(kp, fill=255)
    gd.rounded_rectangle((kx - 2 * k, by - 10 * k, kx + 48 * k, by + 150 * k), 24 * k, fill=255)
    gl = Image.new("RGBA", (S, S), PURPLE + (255,)); gl.putalpha(g)
    art.alpha_composite(gl)

    # monochrome: receipt (content cut out, gap ring round badge) + badge disc (glyph cut out)
    disc = Image.new("L", (S, S), 0)
    ImageDraw.Draw(disc).ellipse((bx - r, by - r, bx + r, by + r), fill=255)
    ring = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ring).ellipse((bx - r - 26, by - r - 26, bx + r + 26, by + r + 26), fill=255)
    m = np.asarray(body).astype(float) - np.asarray(cut).astype(float) - np.asarray(ring).astype(float)
    m = np.clip(m, 0, 255) + np.clip(np.asarray(disc).astype(float) - np.asarray(g).astype(float), 0, 255)
    mono_mask = Image.fromarray(np.clip(m, 0, 255).astype("uint8"))
    return art, mono_mask

FG, MONO_MASK = build_receipt()

def scaled(layer, f):
    n = round(S * f)
    return layer.resize((n, n), Image.LANCZOS)

def full_icon():
    b = gradient()
    big = FG.resize((round(S * 1.25),) * 2, Image.LANCZOS)
    b.alpha_composite(big, ((S - big.width) // 2, (S - big.height) // 2))
    return b

def mono():
    l = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    l.putalpha(MONO_MASK)
    return l

FULL, MONO = full_icon(), mono()
r1024 = lambda im: im.resize((1024, 1024), Image.LANCZOS)
r1024(FULL).convert("RGB").save(f"{OUT}/dt_food_pos_icon_1024.png")
FULL.resize((512, 512), Image.LANCZOS).convert("RGB").save(f"{OUT}/playstore_512.png")
r1024(FG).save(f"{OUT}/ic_launcher_foreground.png")
r1024(MONO).save(f"{OUT}/ic_launcher_monochrome.png")
r1024(gradient()).convert("RGB").save(f"{OUT}/ic_launcher_background.png")

def circle(im):
    big = im.resize((im.width, im.height), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big.width - 1, big.height - 1), fill=255)
    big.putalpha(mask)
    return big

for dname, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    r = f"{RES}/mipmap-{dname}"
    os.makedirs(r, exist_ok=True)
    FULL.resize((px, px), Image.LANCZOS).convert("RGB").save(f"{r}/ic_launcher.png")
    circle(FULL.resize((px * 4, px * 4), Image.LANCZOS)).resize((px, px), Image.LANCZOS).save(f"{r}/ic_launcher_round.png")
    fp = round(px * 108 / 48)
    FG.resize((fp, fp), Image.LANCZOS).save(f"{r}/ic_launcher_foreground.png")
    MONO.resize((fp, fp), Image.LANCZOS).save(f"{r}/ic_launcher_monochrome.png")
# adaptive background is a gradient bitmap, not a flat colour
for dname, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    fp = round(px * 108 / 48)
    gradient().resize((fp, fp), Image.LANCZOS).convert("RGB").save(f"{RES}/mipmap-{dname}/ic_launcher_background.png")

sheet = Image.new("RGB", (1300, 480), (236, 236, 242))
sq = FULL.convert("RGB").resize((380, 380), Image.LANCZOS)
rr = Image.new("L", (380, 380), 0); ImageDraw.Draw(rr).rounded_rectangle((0, 0, 379, 379), 90, fill=255)
ci = Image.new("L", (380, 380), 0); ImageDraw.Draw(ci).ellipse((0, 0, 379, 379), fill=255)
sheet.paste(sq, (40, 50), rr); sheet.paste(sq, (460, 50), ci)
x = 900
for s in (192, 96, 48):
    t = FULL.convert("RGB").resize((s, s), Image.LANCZOS)
    k = Image.new("L", (s, s), 0); ImageDraw.Draw(k).rounded_rectangle((0, 0, s - 1, s - 1), s // 4, fill=255)
    sheet.paste(t, (x, 50), k); x += s + 30
sheet.save(f"{OUT}/preview.png")
