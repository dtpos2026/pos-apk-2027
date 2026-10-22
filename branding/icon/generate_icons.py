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
    """Returns (receipt RGBA, mask of the receipt body, mask of the printed content)."""
    w, h = 760, 1040
    ox, oy = (S - w) // 2, (S - h) // 2
    body = Image.new("L", (S, S), 0)
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle((ox, oy, ox + w, oy + h - 50), 46, fill=255, corners=(True, True, False, False))
    n, step = 10, w / 10
    pts = [(ox, oy + h - 50)]
    for i in range(n):
        pts += [(ox + step * i + step / 2, oy + h), (ox + step * (i + 1), oy + h - 50)]
    bd.polygon(pts, fill=255)

    ink = Image.new("RGBA", (S, S), (0, 0, 0, 0))   # coloured content
    cut = Image.new("L", (S, S), 0)                 # content silhouette (for monochrome)
    d, cd = ImageDraw.Draw(ink), ImageDraw.Draw(cut)

    mk = mark_mask(190)
    layer = Image.new("RGBA", mk.size, PURPLE + (255,)); layer.putalpha(mk)
    ink.alpha_composite(layer, (S // 2 - mk.width // 2, oy + 70))
    cut.paste(mk, (S // 2 - mk.width // 2, oy + 70), mk)

    # burger
    cx, bw, y0 = S // 2, 520, oy + 330
    dome = Image.new("L", (S, S), 0)
    dd = ImageDraw.Draw(dome)
    dd.ellipse((cx - bw // 2, y0, cx + bw // 2, y0 + 380), fill=255)
    dd.rectangle((0, y0 + 190, S, S), fill=0)
    ink.paste(Image.new("RGBA", (S, S), BUN + (255,)), mask=dome)
    cut.paste(255, mask=dome)
    for sx, sy, r in [(-150, 60, 0), (-30, 35, 25), (95, 62, -20), (175, 110, 15), (-190, 125, -30), (20, 120, 10)]:
        e = Image.new("RGBA", (46, 24), (0, 0, 0, 0)); ImageDraw.Draw(e).ellipse((0, 0, 45, 23), fill=SEED + (255,))
        e = e.rotate(r, expand=True)
        ink.alpha_composite(e, (cx + sx - e.width // 2, y0 + sy - e.height // 2))
    wave = [(cx - bw // 2 - 24 + i, y0 + 222 + 12 * math.sin(i / 24)) for i in range(0, bw + 48, 4)]
    for px_, py_ in wave:
        d.ellipse((px_ - 17, py_ - 17, px_ + 17, py_ + 17), fill=LAV + (255,))
    d.rounded_rectangle((cx - bw // 2 - 14, y0 + 250, cx + bw // 2 + 14, y0 + 322), 36, fill=PURPLE + (255,))
    d.polygon([(cx - bw // 2 + 20, y0 + 312), (cx + bw // 2 - 20, y0 + 312), (cx + bw // 2 - 110, y0 + 362),
               (cx + bw // 2 - 190, y0 + 318), (cx + bw // 2 - 250, y0 + 366), (cx - bw // 2 + 90, y0 + 318)], fill=CHEESE + (255,))
    d.rounded_rectangle((cx - bw // 2, y0 + 330, cx + bw // 2, y0 + 410), 40, fill=BUN + (255,))
    for xy in [(cx - bw // 2 - 14, y0 + 190, cx + bw // 2 + 14, y0 + 410)]:
        cd.rounded_rectangle(xy, 40, fill=255)

    # printed lines + total
    ly = oy + 790
    d.rounded_rectangle((ox + 70, ly, ox + 70 + 330, ly + 26), 13, fill=LINE + (255,))
    d.rounded_rectangle((ox + w - 70 - 110, ly, ox + w - 70, ly + 26), 13, fill=LINE + (255,))
    d.rounded_rectangle((ox + 70, ly + 60, ox + w - 70, ly + 78), 9, fill=PURPLE + (255,))
    d.rounded_rectangle((ox + 70, ly + 110, ox + 70 + 240, ly + 136), 13, fill=PURPLE + (255,))
    d.rounded_rectangle((ox + w - 70 - 170, ly + 110, ox + w - 70, ly + 136), 13, fill=PURPLE + (255,))
    for xy in [(ox + 70, ly, ox + w - 70, ly + 136)]:
        cd.rectangle(xy, fill=255)

    rec = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rec.paste(Image.new("RGBA", (S, S), WHITE + (255,)), mask=body)
    rec.alpha_composite(ink)
    return rec, body, cut

REC, BODY, CUT = build_receipt()
FG = shadow(REC)

def scaled(layer, f):
    n = round(S * f)
    return layer.resize((n, n), Image.LANCZOS)

def full_icon():
    b = gradient()
    big = FG.resize((round(S * 1.3),) * 2, Image.LANCZOS)
    b.alpha_composite(big, ((S - big.width) // 2, (S - big.height) // 2))
    return b

def mono():
    a = np.asarray(BODY).astype(float) - np.asarray(CUT).astype(float)
    m = Image.fromarray(np.clip(a, 0, 255).astype("uint8"))
    l = Image.new("RGBA", (S, S), (0, 0, 0, 255)); l.putalpha(m)
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
