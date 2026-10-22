"""Generate DT Food POS launcher icons.

Usage: python3 -I generate_icons.py <logo.jpg> <repo_root>
The Digital Target mark is cropped from the supplied logo (never redrawn);
only the food cloche is drawn here.
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw

SRC, ROOT = sys.argv[1], sys.argv[2]
PURPLE = (0x3D, 0x09, 0x6D)
OUT = os.path.join(ROOT, "branding/icon")
RES = os.path.join(ROOT, "android-res")

# --- Digital Target mark (alpha mask from the supplied logo) ---
a = np.asarray(Image.open(SRC).convert("RGB")).astype(float)
lum = a.mean(axis=2)
lo = lum[:200, :200].mean()
m = np.clip((lum - lo) / (255 - lo), 0, 1)
m[:, 540:] = 0
ys, xs = np.where(m > 0.5)
mark = m[ys.min() - 2:ys.max() + 3, xs.min() - 2:xs.max() + 3]

# --- Food cloche (serving dome), supersampled ---
def cloche():
    W, H = 1200, 800
    im = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(im)
    dome = Image.new("L", (W, H), 0)
    ImageDraw.Draw(dome).ellipse((100, 120, 1100, 1160), fill=255)
    ImageDraw.Draw(dome).rectangle((0, 640, W, H), fill=0)
    im.paste(255, mask=dome)
    d.ellipse((545, 20, 655, 130), fill=255)                      # knob
    d.rounded_rectangle((40, 690, 1160, 770), 40, fill=255)       # plate
    d.line((260, 560, 330, 400), fill=0, width=0)
    # soft highlight cut-out on the dome
    d.arc((190, 210, 1010, 1030), 205, 250, fill=0, width=34)
    bb = im.getbbox()
    return np.asarray(im.crop(bb)).astype(float) / 255

food = cloche()

def group():
    """Mark above cloche, as one white-on-transparent alpha mask."""
    mh, mw = mark.shape
    mw_t = 1000
    mk = Image.fromarray((mark * 255).astype("uint8")).resize((mw_t, round(mh * mw_t / mw)), Image.LANCZOS)
    fw = round(mw_t * 1.25)
    fd = Image.fromarray((food * 255).astype("uint8"))
    fd = fd.resize((fw, round(fd.height * fw / fd.width)), Image.LANCZOS)
    gap = 130
    gw, gh = fw, mk.height + gap + fd.height
    g = Image.new("L", (gw, gh), 0)
    g.paste(mk, ((gw - mk.width) // 2, 0))
    g.paste(fd, (0, mk.height + gap))
    return g

G = group()

def render(canvas, height_frac, bg=None, color=(255, 255, 255)):
    h = round(canvas * height_frac)
    g = G.resize((round(G.width * h / G.height), h), Image.LANCZOS)
    base = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0) if bg is None else bg + (255,))
    layer = Image.new("RGBA", g.size, color + (255,))
    layer.putalpha(g)
    base.alpha_composite(layer, ((canvas - g.width) // 2, (canvas - g.height) // 2))
    return base

FULL = render(1024, 0.56, PURPLE)
FG = render(1024, 0.50)          # adaptive foreground: inside 66% safe zone
MONO = render(1024, 0.50, None, (0, 0, 0))

FULL.convert("RGB").save(f"{OUT}/dt_food_pos_icon_1024.png")
FULL.convert("RGB").resize((512, 512), Image.LANCZOS).save(f"{OUT}/playstore_512.png")
FG.save(f"{OUT}/ic_launcher_foreground.png")
MONO.save(f"{OUT}/ic_launcher_monochrome.png")
Image.new("RGB", (1024, 1024), PURPLE).save(f"{OUT}/ic_launcher_background.png")

for d, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    r = f"{RES}/mipmap-{d}"
    os.makedirs(r, exist_ok=True)
    FULL.convert("RGB").resize((px, px), Image.LANCZOS).save(f"{r}/ic_launcher.png")
    big = FULL.resize((px * 4, px * 4), Image.LANCZOS)
    mask = Image.new("L", big.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, big.width - 1, big.height - 1), fill=255)
    big.putalpha(mask)
    big.resize((px, px), Image.LANCZOS).save(f"{r}/ic_launcher_round.png")
    fp = round(px * 108 / 48)
    FG.resize((fp, fp), Image.LANCZOS).save(f"{r}/ic_launcher_foreground.png")
    MONO.resize((fp, fp), Image.LANCZOS).save(f"{r}/ic_launcher_monochrome.png")

# preview: squircle, circle, small sizes
sheet = Image.new("RGB", (1300, 480), (236, 236, 242))
sq = FULL.convert("RGB").resize((380, 380), Image.LANCZOS)
rr = Image.new("L", (380, 380), 0); ImageDraw.Draw(rr).rounded_rectangle((0, 0, 379, 379), 90, fill=255)
ci = Image.new("L", (380, 380), 0); ImageDraw.Draw(ci).ellipse((0, 0, 379, 379), fill=255)
sheet.paste(sq, (40, 50), rr); sheet.paste(sq, (460, 50), ci)
x = 900
for s in (192, 96, 48):
    t = FULL.convert("RGB").resize((s, s), Image.LANCZOS)
    mk = Image.new("L", (s, s), 0); ImageDraw.Draw(mk).rounded_rectangle((0, 0, s - 1, s - 1), s // 4, fill=255)
    sheet.paste(t, (x, 50), mk); x += s + 30
sheet.save(f"{OUT}/preview.png")
