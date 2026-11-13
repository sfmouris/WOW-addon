# Generates the addon's TGA textures (white, tintable, alpha channel).
import math, struct, sys, os
out = sys.argv[1]
N = 64

def write_tga(name, px):
    # px: function(x, y) -> (r, g, b, a) with y=0 at top
    data = bytearray()
    for y in range(N - 1, -1, -1):          # bottom-up rows
        for x in range(N):
            r, g, b, a = px(x, y)
            data += bytes((b, g, r, a))
    header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 8)
    with open(os.path.join(out, name + '.tga'), 'wb') as f:
        f.write(header + data)

def ss(fn):
    # 4x4 supersampled coverage -> alpha
    def px(x, y):
        c = 0
        for i in range(4):
            for j in range(4):
                if fn(x + (i + 0.5) / 4, y + (j + 0.5) / 4):
                    c += 1
        return c / 16.0
    return px

def inside_poly(pts, x, y):
    n, ins = len(pts), False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]; xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            ins = not ins
        j = i
    return ins

def white(cov):
    def px(x, y):
        a = cov(x, y)
        return (255, 255, 255, int(a * 255))
    return px

# Arrow pointing up (north), notched tail.
arrow_pts = [(32, 4), (56, 58), (32, 44), (8, 58)]
write_tga('arrow', white(ss(lambda x, y: inside_poly(arrow_pts, x, y))))

# Check mark.
def check(x, y):
    def seg(ax, ay, bx, by, w):
        dx, dy = bx - ax, by - ay
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        px, py = ax + t * dx, ay + t * dy
        return (x - px) ** 2 + (y - py) ** 2 <= w * w
    return seg(10, 34, 26, 50, 5) or seg(26, 50, 54, 14, 5)
write_tga('check', white(ss(check)))

# Filled dot with soft edge.
write_tga('dot', white(ss(lambda x, y: (x - 32) ** 2 + (y - 32) ** 2 <= 26 ** 2)))

# Ring.
write_tga('ring', white(ss(lambda x, y: 22 ** 2 <= (x - 32) ** 2 + (y - 32) ** 2 <= 29 ** 2)))

# --- Title bar and row icons (white, tintable) ---
def seg(x, y, ax, ay, bx, by, w):
    dx, dy = bx - ax, by - ay
    t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    px, py = ax + t * dx, ay + t * dy
    return (x - px) ** 2 + (y - py) ** 2 <= w * w

# Chevron pointing down; rotate for the collapsed state.
write_tga('chevron', white(ss(lambda x, y: seg(x, y, 14, 24, 32, 42, 5) or seg(x, y, 32, 42, 50, 24, 5))))

# Minimize: bar near the bottom.
write_tga('minimize', white(ss(lambda x, y: seg(x, y, 14, 44, 50, 44, 5))))

# Close: cross.
write_tga('close', white(ss(lambda x, y: seg(x, y, 16, 16, 48, 48, 5) or seg(x, y, 48, 16, 16, 48, 5))))

# Next: triangle plus bar ("skip to next").
next_pts = [(14, 12), (14, 52), (42, 32)]
write_tga('next', white(ss(lambda x, y: inside_poly(next_pts, x, y) or (45 <= x <= 52 and 12 <= y <= 52))))

# Gear: ring with eight teeth.
def gear(x, y):
    dx, dy = x - 32, y - 32
    d = math.hypot(dx, dy)
    if d < 9:
        return False
    if d <= 19:
        return True
    if d > 27:
        return False
    a = math.atan2(dy, dx) % (math.pi / 4)
    return min(a, math.pi / 4 - a) * d <= 5.5
write_tga('gear', white(ss(gear)))

# Padlock, closed and open.
def lock_body(x, y):
    return 13 <= x <= 51 and 30 <= y <= 57

def shackle(x, y, cy, both):
    d = math.hypot(x - 32, y - cy)
    if y <= cy and 10 <= d <= 16:
        return True
    if cy <= y <= 30 and 16 <= x <= 22:
        return True
    return both and cy <= y <= 30 and 42 <= x <= 48
write_tga('lock', white(ss(lambda x, y: lock_body(x, y) or shackle(x, y, 22, True))))
write_tga('unlock', white(ss(lambda x, y: lock_body(x, y) or shackle(x, y, 17, False))))

# Coin: gold disc with darker rim.
def coin(x, y):
    cov = ss(lambda a, b: (a - 32) ** 2 + (b - 32) ** 2 <= 28 ** 2)(x, y)
    d = math.hypot(x + 0.5 - 32, y + 0.5 - 32)
    if d > 22:
        r, g, b = 184, 134, 11
    else:
        shade = 1 - d / 60
        r, g, b = int(255 * shade + 40), int(215 * shade + 20), int(40 * shade)
    return (min(r, 255), min(g, 255), b, int(cov * 255))
write_tga('coin', coin)

# Addon icon: compass rose on dark blue disc.
needle_n = [(32, 6), (39, 32), (25, 32)]
needle_s = [(32, 58), (39, 32), (25, 32)]
def icon(x, y):
    cx, cy = x + 0.5, y + 0.5
    d = math.hypot(cx - 32, cy - 32)
    if d > 31:
        return (0, 0, 0, 0)
    if inside_poly(needle_n, cx, cy):
        return (230, 60, 50, 255)
    if inside_poly(needle_s, cx, cy):
        return (235, 235, 235, 255)
    if 27 <= d <= 31:
        return (212, 175, 55, 255)
    return (20, 40, 80, 255)
write_tga('icon', icon)
print('ok')
