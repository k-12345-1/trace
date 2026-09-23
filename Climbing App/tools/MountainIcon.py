from PIL import Image, ImageDraw
import math

S = 4096          # supersample canvas
U = 100.0         # design units
k = S / U

# The mountain, in design units. Left shoulder lower and broader, main peak
# right and higher, the way the sketch has it.
OUT = [(9, 78), (33, 41), (45, 53), (62, 20), (91, 78)]

def px(p): return (p[0]*k, p[1]*k)

def polygon_mask(pts):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.polygon([px(p) for p in pts], fill=255)
    return m

def stroke_path(layer, pts, w, closed=False):
    """Segments plus discs at the joins, so no mitre seams."""
    d = ImageDraw.Draw(layer)
    r = w*k/2
    seq = pts + [pts[0]] if closed else pts
    for a, b in zip(seq, seq[1:]):
        d.line([px(a), px(b)], fill=255, width=int(round(w*k)))
    for p in seq:
        x, y = px(p)
        d.ellipse([x-r, y-r, x+r, y+r], fill=255)

def lattice(layer, angle_deg, spacing, w):
    """Parallel lines at an angle, covering the whole canvas."""
    d = ImageDraw.Draw(layer)
    a = math.radians(angle_deg)
    dx, dy = math.cos(a), math.sin(a)
    nx, ny = -dy, dx                       # normal
    L = U*2
    n = int(U*2/spacing)
    for i in range(-n, n+1):
        cx, cy = U/2 + nx*i*spacing, U/2 + ny*i*spacing
        p1 = (cx - dx*L, cy - dy*L)
        p2 = (cx + dx*L, cy + dy*L)
        d.line([px(p1), px(p2)], fill=255, width=int(round(w*k)))

def build(spacing, angles, outline_w, mesh_w, base_closed=True):
    mask = polygon_mask(OUT)
    mesh = Image.new("L", (S, S), 0)
    for ang in angles:
        lattice(mesh, ang, spacing, mesh_w)
    mesh = Image.composite(mesh, Image.new("L", (S, S), 0), mask)

    edge = Image.new("L", (S, S), 0)
    pts = OUT if base_closed else OUT
    stroke_path(edge, pts, outline_w, closed=base_closed)

    alpha = Image.new("L", (S, S), 0)
    alpha.paste(mesh)
    alpha.paste(edge, mask=edge)
    return alpha

def render(alpha, size, fg, bg, inset=0.12):
    a = alpha.resize((size, size), Image.LANCZOS)
    inner = int(size*(1-inset*2))
    a = a.resize((inner, inner), Image.LANCZOS)
    canvas = Image.new("L", (size, size), 0)
    canvas.paste(a, (int(size*inset), int(size*inset)))
    out = Image.new("RGB", (size, size), bg)
    out.paste(Image.new("RGB", (size, size), fg), mask=canvas)
    return out

BLUE = (0x16, 0x39, 0x5E)
WHITE = (0xFF, 0xFF, 0xFF)

cands = {
    "A": build(15, (58, -58), 5.0, 3.0),
    "B": build(20, (58, -58), 6.0, 4.0),
    "C": build(13, (62,), 5.5, 3.4),
}

sizes = [200, 96, 56, 40, 29]
for name, alpha in cands.items():
    render(alpha, 1024, WHITE, BLUE).save(f"icon-{name}-1024.png")
    strip = Image.new("RGB", (sum(sizes)+20*len(sizes), 230), (0xEE, 0xF2, 0xF6))
    x = 10
    for s in sizes:
        strip.paste(render(alpha, s, WHITE, BLUE), (x, (230-s)//2))
        x += s + 20
    strip.save(f"strip-{name}.png")
print("done")
