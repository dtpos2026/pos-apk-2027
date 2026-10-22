"""Splash screen and Play Store feature graphic for DT Food POS.

Usage: python3 -I generate_brand_assets.py <logo.jpg> <repo_root>
Needs branding/icon/art_foreground_2048.png (run vector/build_vector.py + render.mjs first) and the Inter font.
"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC, ROOT = sys.argv[1], sys.argv[2]
OUT = os.path.join(ROOT, "branding/screens")
FONT = "/usr/share/fonts/opentype/inter/Inter-{}.otf"
LAV, AMBER = (205, 180, 240), (255, 181, 71)

a = np.asarray(Image.open(SRC).convert("RGB")).astype(float)
lum = a.mean(axis=2); lo = lum[:200, :200].mean()
m = np.clip((lum - lo) / (255 - lo), 0, 1); m[:, 540:] = 0
ys, xs = np.where(m > 0.5)
MARK = Image.fromarray((m[ys.min() - 2:ys.max() + 3, xs.min() - 2:xs.max() + 3] * 255).astype("uint8"))

def mark(h, color=(255, 255, 255), opacity=1.0):
    mk = MARK.resize((round(MARK.width * h / MARK.height), h), Image.LANCZOS)
    mk = mk.point(lambda v: int(v * opacity))
    l = Image.new("RGBA", mk.size, color + (255,)); l.putalpha(mk); return l

def gradient(w, h):
    y, x = np.mgrid[0:h, 0:w]; x = x / w; y = y / h
    t = np.clip(x * 0.35 + y * 0.65, 0, 1)[..., None]
    c1, c2 = np.array([0x6A, 0x22, 0xB0]), np.array([0x2A, 0x04, 0x4D])
    glow = np.clip(1 - np.hypot(x - 0.3, y - 0.2) * 1.2, 0, 1)[..., None]
    img = (c1 * (1 - t) + c2 * t) * 0.85 + np.array([0x7A, 0x38, 0xC8]) * 0.3 * glow
    return Image.fromarray(np.clip(img, 0, 255).astype("uint8")).convert("RGBA")

fg = Image.open(os.path.join(ROOT, "branding/icon/art_foreground_2048.png")).convert("RGBA")
l, t, r, b = fg.getbbox()
half = max(fg.width // 2 - l, r - fg.width // 2)   # symmetric crop keeps the receipt centred
ART = fg.crop((fg.width // 2 - half, t, fg.width // 2 + half, b))   # splash: receipt centred
ART_TIGHT = fg.crop(fg.getbbox())                                  # feature graphic: art sits left of the text

def text_c(d, cx, y, s, font, fill, spacing=0):
    w = d.textlength(s, font=font) + spacing * (len(s) - 1)
    x = cx - w / 2
    for ch in s:
        d.text((x, y), ch, font=font, fill=fill); x += d.textlength(ch, font=font) + spacing

# ---------- splash 1080x1920 ----------
W, H = 1080, 1920
sp = gradient(W, H)
big = mark(1500, (255, 255, 255), 0.05); sp.alpha_composite(big, (W - big.width // 2 - 150, -260))
art = ART.resize((round(ART.width * 640 / ART.height), 640), Image.LANCZOS)
sp.alpha_composite(art, ((W - art.width) // 2, 400))
d = ImageDraw.Draw(sp)
text_c(d, W // 2, 1110, "DT Food POS", ImageFont.truetype(FONT.format("ExtraBold"), 118), (255, 255, 255), -2)
text_c(d, W // 2, 1262, "Offline-first restaurant POS", ImageFont.truetype(FONT.format("Medium"), 40), LAV)
for i, c in enumerate([(255, 255, 255), LAV, (150, 110, 205)]):
    d.ellipse((W // 2 - 60 + i * 60 - 10, 1420, W // 2 - 60 + i * 60 + 10, 1440), fill=c)
f = ImageFont.truetype(FONT.format("SemiBold"), 34)
txt = "Powered by Digital Target"
tw = d.textlength(txt, font=f) + 2 * (len(txt) - 1)
mk = mark(46); gap = 22
x0 = (W - (mk.width + gap + tw)) / 2
sp.alpha_composite(mk, (round(x0), 1742))
tx = x0 + mk.width + gap
for ch in txt:
    d.text((tx, 1742 + 2), ch, font=f, fill=LAV); tx += d.textlength(ch, font=f) + 2
sp.convert("RGB").save(f"{OUT}/splash_1080x1920.png")

# ---------- Play Store feature graphic 1024x500 ----------
W, H = 1024, 500
fgimg = gradient(W, H)
big = mark(820, (255, 255, 255), 0.05); fgimg.alpha_composite(big, (W - 560, -130))
art = ART_TIGHT.resize((round(ART_TIGHT.width * 400 / ART_TIGHT.height), 400), Image.LANCZOS)
fgimg.alpha_composite(art, (70, 50))
d = ImageDraw.Draw(fgimg)
d.text((420, 150), "DT Food POS", font=ImageFont.truetype(FONT.format("ExtraBold"), 84), fill=(255, 255, 255))
d.text((424, 258), "Offline-first restaurant POS", font=ImageFont.truetype(FONT.format("Medium"), 32), fill=LAV)
d.rounded_rectangle((424, 330, 424 + 66, 336), 3, fill=AMBER)
mk = mark(32); fgimg.alpha_composite(mk, (424, 372))
d.text((424 + mk.width + 14, 372), "Powered by Digital Target", font=ImageFont.truetype(FONT.format("SemiBold"), 26), fill=LAV)
fgimg.convert("RGB").save(f"{OUT}/playstore_feature_1024x500.png")
