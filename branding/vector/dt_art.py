"""Shared geometry for the DT Food POS icon art (receipt + DT mark + fork/knife badge).

Everything lives in "receipt units" (RU): receipt is 680 x 940 with its top-left at (0, 0).
The DT mark polygons were traced from the supplied logo and verified against it (IoU 0.997).
"""
import math

W, H, TEETH, TOOTH = 680, 940, 10, 50
CORNER = 44
BADGE = (640, 810, 215)                    # cx, cy, r
CENTER = (W / 2, H / 2)

PURPLE, WHITE, AMBER, LINE = "#3D096D", "#FFFFFF", "#FFB547", "#D6C8EA"
BG_TOP, BG_BOTTOM, BG_GLOW = "#5A1D96", "#240341", "#7A38C8"

# DT mark: 4 right triangles in a 338 x 340 box
MARK_W, MARK_H = 338, 340
MARK_TRIS = [
    [(0, 0), (169, 0), (169, 169)],
    [(170, 0), (338, 0), (338, 169)],
    [(0, 170), (169, 170), (169, 340)],
    [(170, 170), (338, 170), (338, 340)],
]
MARK_SCALE = 260 / MARK_H
MARK_POS = ((W - MARK_W * MARK_SCALE) / 2, 80)

def mark_tris():
    """Triangles in RU."""
    return [[(MARK_POS[0] + x * MARK_SCALE, MARK_POS[1] + y * MARK_SCALE) for x, y in t] for t in MARK_TRIS]

# line items: (x, y, w, h)
ROWS = []
for i in range(4):
    y = 430 + i * 105
    ROWS.append([(80, y, 400 if i % 2 == 0 else 310, 36), (W - 80 - 110, y, 110, 36)])
TOTAL = (80, 850, W - 160, 18)

def body_points(arc_steps=10):
    """Receipt outline as a polygon (rounded top corners, zig-zag tear edge)."""
    pts = []
    for cx, cy, a0 in ((CORNER, CORNER, 180), (W - CORNER, CORNER, 270)):
        for s in range(arc_steps + 1):
            a = math.radians(a0 + 90 * s / arc_steps)
            pts.append((cx + CORNER * math.cos(a), cy + CORNER * math.sin(a)))
    pts.append((W, H - TOOTH))
    step = W / TEETH
    for i in range(TEETH - 1, -1, -1):
        pts += [(step * i + step / 2, H), (step * i, H - TOOTH)]
    return pts

def glyph_shapes():
    """Fork + knife in RU. Returns dict of primitives for svg/lottie builders."""
    cx, cy, r = BADGE
    k = r / 250
    fx, kx = cx - 70 * k, cx + 60 * k
    tines = [(fx + dx * k - 9 * k, cy - 150 * k, 18 * k, 120 * k, 9 * k) for dx in (-34, 0, 34)]
    bowl_top = cy - 60 * k
    fork_head = (fx - 43 * k, bowl_top, 86 * k, 35 * k)                 # rect joining tines
    bowl = (fx, cy - 30 * k, 43 * k, 50 * k)                            # lower half-ellipse: cx, cy, rx, ry
    fork_handle = (fx - 11 * k, cy - 20 * k, 22 * k, 170 * k, 11 * k)
    ky0 = cy - 150 * k
    knife_blade = [(kx + 48 * k * math.sin(math.radians(t)), ky0 + 130 * k * (1 - math.cos(math.radians(t)))) for t in range(0, 91, 6)]
    knife_blade = [(kx, ky0)] + knife_blade[1:] + [(kx + 48 * k, cy + 20 * k), (kx, cy + 20 * k)]
    knife_handle = (kx - 2 * k, cy - 10 * k, 50 * k, 160 * k, 24 * k)
    return dict(tines=tines, fork_head=fork_head, bowl=bowl, fork_handle=fork_handle,
                knife_blade=knife_blade, knife_handle=knife_handle, k=k)

def fmt(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")

def pts_str(pts):
    return " ".join(f"{fmt(x)},{fmt(y)}" for x, y in pts)

def glyph_svg(fill):
    g = glyph_shapes()
    out = [f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(r)}"/>' for x, y, w, h, r in g["tines"]]
    x, y, w, h = g["fork_head"]
    out.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}"/>')
    cx, cy, rx, ry = g["bowl"]
    out.append(f'<path d="M{fmt(cx - rx)} {fmt(cy)}A{fmt(rx)} {fmt(ry)} 0 0 0 {fmt(cx + rx)} {fmt(cy)}Z"/>')
    x, y, w, h, r = g["fork_handle"]
    out.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(r)}"/>')
    out.append(f'<polygon points="{pts_str(g["knife_blade"])}"/>')
    x, y, w, h, r = g["knife_handle"]
    out.append(f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(r)}"/>')
    return f'<g fill="{fill}">' + "".join(out) + "</g>"

def mark_svg(fill):
    return f'<g fill="{fill}">' + "".join(f'<polygon points="{pts_str(t)}"/>' for t in mark_tris()) + "</g>"

def mark_svg_raw(fill):
    """The mark in its own 338 x 340 box (for stand-alone exports)."""
    return f'<g fill="{fill}">' + "".join(f'<polygon points="{pts_str(t)}"/>' for t in MARK_TRIS) + "</g>"

def rows_svg(label_fill, total_fill):
    out = [f'<g fill="{label_fill}">']
    for row in ROWS:
        for x, y, w, h in row:
            out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h / 2}"/>')
    out.append("</g>")
    x, y, w, h = TOTAL
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h / 2}" fill="{total_fill}"/>')
    return "".join(out)

def art_svg(shadow=True):
    cx, cy, r = BADGE
    body = f'<polygon points="{pts_str(body_points())}" fill="{WHITE}"/>'
    receipt = body + mark_svg(PURPLE) + rows_svg(LINE, PURPLE)
    badge = f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{AMBER}"/>'
    f1 = ' filter="url(#sh)"' if shadow else ""
    f2 = ' filter="url(#sh2)"' if shadow else ""
    return f'<g{f1}>{receipt}</g><g{f2}>{badge}</g>{glyph_svg(PURPLE)}'

SHADOW_DEFS = ('<filter id="sh" x="-20%" y="-20%" width="150%" height="150%"><feDropShadow dx="0" dy="18" stdDeviation="14" flood-color="#0a0019" flood-opacity="0.38"/></filter>'
               '<filter id="sh2" x="-30%" y="-30%" width="170%" height="170%"><feDropShadow dx="0" dy="14" stdDeviation="11" flood-color="#0a0019" flood-opacity="0.42"/></filter>')

def bg_defs():
    return (f'<linearGradient id="bg" x1="0" y1="0" x2="0.769" y2="1.154"><stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_BOTTOM}"/></linearGradient>'
            f'<radialGradient id="glow" cx="0.3" cy="0.25" r="0.7"><stop offset="0" stop-color="{BG_GLOW}" stop-opacity="0.55"/><stop offset="1" stop-color="{BG_GLOW}" stop-opacity="0"/></radialGradient>')

def bg_rect(size=1024):
    return f'<rect width="{size}" height="{size}" fill="url(#bg)"/><rect width="{size}" height="{size}" fill="url(#glow)"/>'

def placed(scale):
    """Transform that puts the receipt centre at the middle of a 1024 canvas."""
    return f'translate({fmt(512 - CENTER[0] * scale)} {fmt(512 - CENTER[1] * scale)}) scale({scale})'

def svg(body, defs="", size=1024):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}"><defs>{defs}</defs>{body}</svg>'

FULL_SCALE, FG_SCALE = 0.625, 0.5          # legacy icon / adaptive foreground (inside the 66% safe zone)

def icon_svg(round_=False):
    inner = bg_rect() + f'<g transform="{placed(FULL_SCALE)}">{art_svg()}</g>'
    if round_:
        inner = f'<clipPath id="rc"><circle cx="512" cy="512" r="512"/></clipPath><g clip-path="url(#rc)">{inner}</g>'
    return svg(inner, bg_defs() + SHADOW_DEFS)

def foreground_svg():
    return svg(f'<g transform="{placed(FG_SCALE)}">{art_svg()}</g>', SHADOW_DEFS)

def background_svg():
    return svg(bg_rect(), bg_defs())

def monochrome_svg():
    cx, cy, r = BADGE
    holes = mark_svg("#000") + rows_svg("#000", "#000") + f'<circle cx="{cx}" cy="{cy}" r="{r + 26}" fill="#000"/>'
    defs = (f'<mask id="bm" maskUnits="userSpaceOnUse" x="-100" y="-100" width="{W + 400}" height="{H + 400}"><rect x="-100" y="-100" width="{W + 400}" height="{H + 400}" fill="#fff"/>{holes}</mask>'
            f'<mask id="dm" maskUnits="userSpaceOnUse" x="-100" y="-100" width="{W + 400}" height="{H + 400}"><circle cx="{cx}" cy="{cy}" r="{r}" fill="#fff"/>{glyph_svg("#000")}</mask>')
    body = (f'<g fill="#000"><polygon points="{pts_str(body_points())}" mask="url(#bm)"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r}" mask="url(#dm)"/></g>')
    return svg(f'<g transform="{placed(FG_SCALE)}">{body}</g>', defs)
