"""Build the animated splash logo (Lottie JSON) from the shared icon geometry.
Run: python3 -I build_lottie.py <repo_root>

Comp: 800x800 @ 60 fps, transparent (the gradient background and text are drawn by the app).
Sequence: receipt rises in -> DT mark triangles pop -> line items wipe in -> badge pops -> fork/knife pops.
"""
import json, math, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vector"))
import dt_art as A

U = 0.62                                     # RU -> comp px
OX, OY = 400 - A.CENTER[0] * U, 400 - A.CENTER[1] * U
FR, OP = 60, 130

def P(x, y): return [OX + x * U, OY + y * U]
def rgb(h): return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)] + [1]

# --- keyframes -------------------------------------------------------------
OUT = ((0.215, 0.61), (0.355, 1))            # easeOutCubic
BACK = ((0.34, 1.56), (0.64, 1))             # overshoot

def val(v): return v if isinstance(v, list) else [v]

def anim(keys, ease=OUT):
    ks = []
    for i, (t, v) in enumerate(keys):
        v = val(v); n = len(v)
        k = {"t": t, "s": v}
        if i < len(keys) - 1:
            k["o"] = {"x": [ease[0][0]] * n, "y": [ease[0][1]] * n}
            k["i"] = {"x": [ease[1][0]] * n, "y": [ease[1][1]] * n}
        ks.append(k)
    return {"a": 1, "k": ks}

def static(v): return {"a": 0, "k": v}

# --- shapes ----------------------------------------------------------------
def fill(hexcol): return {"ty": "fl", "c": static(rgb(hexcol)), "o": static(100), "r": 1}
def tr(): return {"ty": "tr", "p": static([0, 0]), "a": static([0, 0]), "s": static([100, 100]), "r": static(0), "o": static(100), "sk": static(0), "sa": static(0)}
def group(items, col): return {"ty": "gr", "it": items + [fill(col), tr()]}
def poly(pts):
    pts = [P(*p) for p in pts]
    z = [[0, 0]] * len(pts)
    return {"ty": "sh", "ks": static({"i": z, "o": z, "v": pts, "c": True})}
def rect(x, y, w, h, r=0):
    c = P(x + w / 2, y + h / 2)
    return {"ty": "rc", "p": static(c), "s": static([w * U, h * U]), "r": static(r * U)}
def ellipse(cx, cy, rx, ry):
    return {"ty": "el", "p": static(P(cx, cy)), "s": static([2 * rx * U, 2 * ry * U])}

layers = []
def layer(name, groups, anchor, scale=None, pos=None, opacity=None):
    a = P(*anchor)
    layers.append({
        "ddd": 0, "ind": len(layers) + 1, "ty": 4, "nm": name, "sr": 1, "ao": 0, "ip": 0, "op": OP, "st": 0, "bm": 0,
        "ks": {"o": opacity or static(100), "r": static(0), "a": static(a + [0]),
               "p": pos or static(a + [0]), "s": scale or static([100, 100, 100])},
        "shapes": groups})

def pop(start, dur, ease=BACK, axis="both"):
    end = start + dur
    lo = [0, 0, 100] if axis == "both" else [0, 100, 100]
    return anim([(start, lo), (end, [100, 100, 100])], ease)

def hidden_until(start):
    """Opacity 0 before `start`, 100 after (layers that scale from 0 still need this to avoid a 1-frame flash)."""
    return {"a": 1, "k": [{"t": 0, "s": [0], "h": 1}, {"t": start, "s": [100]}]}

# 1. receipt body: rises + fades in
body = group([poly(A.body_points())], A.WHITE)
c = A.CENTER
a = P(*c)
rise = anim([(4, [a[0], a[1] + 90, 0]), (34, [a[0], a[1], 0])], OUT)
layer("receipt", [body], c, scale=anim([(4, [90, 90, 100]), (34, [100, 100, 100])], OUT), pos=rise,
      opacity=anim([(4, 0), (22, 100)], OUT))

# 2. DT mark triangles, staggered
for i, t in enumerate(A.mark_tris()):
    cx = sum(p[0] for p in t) / 3; cy = sum(p[1] for p in t) / 3
    layer(f"mark_{i + 1}", [group([poly(t)], A.PURPLE)], (cx, cy), scale=pop(34 + i * 5, 14),
          opacity=hidden_until(34 + i * 5))

# 3. line items wipe in from the left, then the total
for i, row in enumerate(A.ROWS):
    x0, y0, _, h = row[0]
    items = [group([rect(x, y, w, h_, h_ / 2)], A.LINE) for x, y, w, h_ in row]
    st = 58 + i * 5
    layer(f"row_{i + 1}", items, (x0, y0 + h / 2), scale=pop(st, 12, OUT, "x"), opacity=hidden_until(st))
x, y, w, h = A.TOTAL
layer("total", [group([rect(x, y, w, h, h / 2)], A.PURPLE)], (x, y + h / 2), scale=pop(80, 12, OUT, "x"), opacity=hidden_until(80))

# 4. badge + glyph
cx, cy, r = A.BADGE
layer("badge", [group([ellipse(cx, cy, r, r)], A.AMBER)], (cx, cy), scale=pop(88, 18), opacity=hidden_until(88))
g = A.glyph_shapes()
gitems = [rect(x, y, w, h, rr) for x, y, w, h, rr in g["tines"]]
gitems.append(rect(*g["fork_head"]))
bcx, bcy, rx, ry = g["bowl"]
bowl = [(bcx - rx * math.cos(math.radians(t)), bcy + ry * math.sin(math.radians(t))) for t in range(0, 181, 10)]
gitems.append(poly(bowl))
gitems.append(rect(*g["fork_handle"]))
gitems.append(poly(g["knife_blade"]))
gitems.append(rect(*g["knife_handle"]))
# one group per shape: overlapping paths inside one fill group would cancel each other (non-zero winding)
layer("fork_knife", [group([it], A.PURPLE) for it in gitems], (cx, cy), scale=pop(100, 14), opacity=hidden_until(100))

layers.reverse()                              # Lottie: first layer is on top
for i, l in enumerate(layers): l["ind"] = i + 1
doc = {"v": "5.9.0", "fr": FR, "ip": 0, "op": OP, "w": 800, "h": 800, "nm": "DT Food POS splash logo", "ddd": 0, "assets": [], "layers": layers}
out = os.path.join(sys.argv[1], "branding/animation/dt_splash_logo.json")
json.dump(doc, open(out, "w"), separators=(",", ":"))
print(out, os.path.getsize(out), "bytes", len(layers), "layers")
