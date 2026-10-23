"""Parametric animal-unit kit: heads, bodies, outfits and weapons that combine into a chibi voxel unit
in the same style as the hand-built first ten (units.py). One `Spec` describes a unit; `build(spec, tier)`
returns a rigged Model with tier upgrades applied (4 star = astral form via units.finish)."""
import math
import numpy as np

from vox import Model, PID
from units import (biped, crown, cape, back_wings, finish, BLACK, WHITE, GOLD, GOLD_D, GILT, GILT_D, GILT_L,
                   WOOD, WOOD_D, LEATHER, LEATHER_D, BLADE, BLADE_D, RUBY, SAPPHIRE, EMERALD)

# ------------------------------------------------------------------ origin palettes
# cloth: main outfit colour, cloth2: secondary, trim: accent, metal/metal_d/metal_l: armour, glow: magic
ORIGINS = {
    'Order':    dict(cloth='#2f63b8', cloth2='#eef1f8', trim='#f2c14e', metal='#c3ccd6', metal_d='#7f8b99', metal_l='#e8eef4', glow='#fff1a8', gem=SAPPHIRE),
    'Wild':     dict(cloth='#3f7d46', cloth2='#8b5a2b', trim='#c9a24a', metal='#9a8f7a', metal_d='#6b6252', metal_l='#c4baa3', glow='#9be36b', gem=EMERALD),
    'Shadow':   dict(cloth='#4a3a6b', cloth2='#231e2e', trim='#9a8cff', metal='#5a5f72', metal_d='#3b3f4d', metal_l='#8a90a6', glow='#b47cff', gem='#b47cff'),
    'Arcane':   dict(cloth='#3346b5', cloth2='#1e2766', trim='#6fd9ff', metal='#b8c2e0', metal_d='#7a84a8', metal_l='#e2e8fb', glow='#6fd9ff', gem='#6fd9ff'),
    'Undead':   dict(cloth='#4e5a46', cloth2='#2b2f2a', trim='#9bd36b', metal='#7d7466', metal_d='#544e44', metal_l='#a39a8a', glow='#7dff9b', gem='#7dff9b'),
    'Ember':    dict(cloth='#b8392b', cloth2='#5a2418', trim='#ffb13b', metal='#8a6e5a', metal_d='#5e4a3c', metal_l='#b3967f', glow='#ff9a3c', gem='#ff6a2a'),
    'Frost':    dict(cloth='#5aa6d6', cloth2='#e9f4fb', trim='#bff0ff', metal='#bcd7e8', metal_d='#86a6bd', metal_l='#e6f4fd', glow='#9ff0ff', gem='#9ff0ff'),
    'Fey':      dict(cloth='#c45fa6', cloth2='#4fb3a5', trim='#ffd6f1', metal='#dcc8ea', metal_d='#a690b8', metal_l='#f4ebfa', glow='#ff9ef0', gem='#ff9ef0'),
    'Dwarven':  dict(cloth='#8a4b2a', cloth2='#5a6b7a', trim='#d9a33a', metal='#b07a3c', metal_d='#7a5224', metal_l='#d9a866', glow='#ffcf6b', gem=RUBY),
    'Infernal': dict(cloth='#8e1f2b', cloth2='#2a1418', trim='#ff5a2a', metal='#3a2f33', metal_d='#241c20', metal_l='#5c4b52', glow='#ff5a2a', gem='#ff5a2a'),
}

# Animation style per class: (attack, skill, main hand)
CLASS_STYLE = {
    'Warrior':   ('slash', 'spin', 'arm_r'),
    'Protector': ('bash', 'shieldwall', 'arm_r'),
    'Ranger':    ('shoot', 'volley', 'arm_l'),
    'Caster':    ('cast', 'meteor', 'arm_r'),
    'Rogue':     ('stab', 'backstab', 'arm_r'),
    'Healer':    ('cast', 'heal', 'arm_r'),
    'Summoner':  ('cast', 'meteor', 'arm_r'),
    'Monk':      ('dual', 'pounce', 'arm_r'),
    'Alchemist': ('cast', 'meteor', 'arm_r'),
    'Bard':      ('cast', 'heal', 'arm_r'),
}


def hx(c):
    c = c.lstrip('#')
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def shade(c, f):
    r, g, b = hx(c)
    return '#%02x%02x%02x' % tuple(max(0, min(255, int(round(v * f)))) for v in (r, g, b))


def mix(a, b, t):
    A, B = hx(a), hx(b)
    return '#%02x%02x%02x' % tuple(int(round(A[i] + (B[i] - A[i]) * t)) for i in range(3))


class Spec:
    """Everything that makes one unit. Unset fields fall back to class/origin defaults."""
    def __init__(self, cls, name, origin, klass, **kw):
        self.cls, self.name, self.origin, self.klass = cls, name, origin, klass
        self.seed = kw.pop('seed', abs(hash(name)) % 1000)
        self.fur = kw.pop('fur')                      # main body/head colour
        self.fur2 = kw.pop('fur2', shade(self.fur, 0.88))
        self.light = kw.pop('light', mix(self.fur, '#ffffff', 0.55))   # muzzle / belly
        self.dark = kw.pop('dark', '#2a1e1e')          # nose / ear insides
        self.eyes = kw.pop('eyes', 'normal')
        self.eye_color = kw.pop('eye_color', None)
        self.ears = kw.pop('ears', None)              # (kind, params)
        self.snout = kw.pop('snout', ('muzzle',))
        self.horns = kw.pop('horns', None)
        self.pattern = kw.pop('pattern', None)
        self.tail = kw.pop('tail', None)
        self.wings = kw.pop('wings', None)
        self.extras = kw.pop('extras', [])
        self.weapon = kw.pop('weapon', None)
        self.offhand = kw.pop('offhand', None)
        self.hat = kw.pop('hat', None)
        self.outfit = kw.pop('outfit', klass)
        self.stout = kw.pop('stout', 0)
        self.head_r = kw.pop('head_r', (7.5, 6.5, 6.5))
        self.legs = kw.pop('legs', None)
        self.hands = kw.pop('hands', None)
        self.pal = dict(ORIGINS[origin])
        self.pal.update(kw.pop('pal', {}))
        self.style = dict(zip(('attack', 'skill', 'main'), CLASS_STYLE[klass]))
        self.style.update(kw.pop('style', {}))
        self.head_col = kw.pop('head_col', None)
        self.Z = kw.pop('Z', 38)
        self.X = kw.pop('X', 26)
        assert not kw, 'unknown spec fields: %s' % list(kw)


# ------------------------------------------------------------------ geometry helpers

class Ctx:
    """Shared anchors for one model being built."""
    def __init__(self, m, a, spec):
        self.m, self.a, self.s = m, a, spec
        self.cx, self.cy = m.cx, 11.5
        self.hz = a['hz']
        self.hr = spec.head_r
        self.face_y = self.cy + self.hr[1]          # front of the head
        self.top = self.hz + self.hr[2]              # top of the head
        self.hat_base = int(round(self.top - 1))

    def mirror_x(self, x):
        return self.m.X - 1 - x

    def both(self, fn):
        """Call fn(sign, x_of) for the left (-1) and right (+1) side."""
        fn(-1)
        fn(1)


def eyes(c, style, color=None):
    m, cx = c.m, c.cx
    x0 = int(round(cx - 4.5))
    k = BLACK
    E = color or k
    pats = {
        'normal': (['wk', 'kk', 'kk'], {'w': WHITE, 'k': E}),
        'small': (['wk', 'kk'], {'w': WHITE, 'k': E}),
        'beady': (['k', 'k'], {'k': E}),
        'big': (['kkk', 'kwk', 'kkk'], {'w': WHITE, 'k': E}),
        'glow': (['gg', 'gg'], {'g': color or '#7dff9b'}),
        'narrow': (['wkk'], {'w': WHITE, 'k': E}),
        'bug': (['ggg', 'gwg', 'ggg'], {'g': color or '#3b2a4a', 'w': WHITE}),
        'sleepy': (['kk'], {'k': E}),
    }
    pat, cmap = pats[style]
    w = len(pat[0])
    ztop = int(round(c.hz + 1.5))
    xl = x0 - (w - 2 if w > 2 else 0)
    xr = m.X - 1 - xl - (w - 1)
    for r, row in enumerate(pat):
        for i, ch in enumerate(row):
            if ch == '.':
                continue
            m.front(xl + i, ztop - r, cmap[ch])
            m.front(xr + i, ztop - r, cmap[ch])


def ears(c, kind, fur, inner, **p):
    m, cx = c.m, c.cx
    fur = p.pop('col', fur)
    tipc = p.pop('tip', None)
    m.part = 'head'
    top = int(round(c.top)) - 1
    if kind == 'pointy':      # fox / cat / wolf style
        h, w, spread = p.get('h', 5), p.get('w', 4), p.get('spread', 5.5)
        for sgn in (-1, 1):
            for i in range(h):
                ww = max(1, round(w * (1 - i / (h + 0.5))))
                x0 = cx + sgn * spread - ww / 2
                m.box(round(x0), round(x0) + ww - 1, 10, 12, top + i, top + i, fur)
                if i < h - 2 and ww > 2:
                    m.box(round(x0) + 1, round(x0) + ww - 2, 12, 12, top + i, top + i, inner)
            if tipc:
                xt = round(cx + sgn * spread - 0.5)
                m.box(xt, xt, 10, 12, top + h, top + h + 1, tipc)
    elif kind == 'round':     # bear / mouse / koala
        r, spread = p.get('r', 2.0), p.get('spread', 5.5)
        for sgn in (-1, 1):
            ex = cx + sgn * spread
            m.ell(ex, 11.5, top + 0.5, r, r * 0.6, r, fur)
            m.ell(ex, 12.3, top + 0.3, r * 0.6, 0.5, r * 0.6, inner)
    elif kind == 'long':      # hare
        h = p.get('h', 9)
        for sgn in (-1, 1):
            ex = cx + sgn * 3.0
            lean = sgn * p.get('lean', 1.2)
            for i in range(h):
                x = round(ex + lean * i / h)
                m.box(x - 1, x + 1, 10, 12, top + i, top + i, fur)
                if 1 <= i < h - 1:
                    m.box(x, x, 12, 12, top + i, top + i, inner)
    elif kind == 'floppy':    # dog / goat
        L = p.get('len', 6)
        for sgn in (-1, 1):
            x = round(cx + sgn * (c.hr[0] + 0.5))
            m.box(min(x, x + sgn), max(x, x + sgn), 10, 13, c.hz + 3 - L, c.hz + 3, fur)
            m.box(min(x, x + sgn), max(x, x + sgn), 10, 13, c.hz + 3 - L, c.hz + 3 - L, shade(fur, 0.8))
    elif kind == 'side':      # horizontal ears (goat, deer, cow, elephant-small)
        L = p.get('len', 3)
        for sgn in (-1, 1):
            x0 = round(cx + sgn * (c.hr[0] - 0.5))
            x1 = round(cx + sgn * (c.hr[0] - 0.5 + L))
            m.box(min(x0, x1), max(x0, x1), 11, 12, c.hz + 2, c.hz + 3, fur)
            m.box(min(x0, x1), max(x0, x1), 12, 12, c.hz + 2, c.hz + 2, inner)
    elif kind == 'big':       # elephant / bat / fennec
        r = p.get('r', 4)
        for sgn in (-1, 1):
            ex = cx + sgn * (c.hr[0] + r * 0.4)
            m.ell(ex, 10.5, c.hz + p.get('dz', 1), r * 0.55, 1.0, r, fur)
            m.ell(ex, 11.4, c.hz + p.get('dz', 1), r * 0.35, 0.5, r * 0.75, inner)
    elif kind == 'small':     # nubs
        for sgn in (-1, 1):
            ex = round(cx + sgn * 5)
            m.box(ex - 1, ex, 11, 12, top, top + 1, fur)
    elif kind == 'tufts':     # owl-like feather tufts
        for sgn in (-1, 1):
            ex = round(cx + sgn * 5.5)
            m.box(ex - 1, ex + 1, 11, 12, top, top + 1, fur)
            m.box(ex + sgn, ex + sgn, 11, 11, top + 2, top + 3, fur)
    elif kind == 'antennae':  # insects
        col = p.get('color', fur)
        for sgn in (-1, 1):
            b = (cx + sgn * 2.5, 13, top)
            t = (cx + sgn * 6, 16, top + 7)
            m.line(b, t, col, r=0.2)
            if p.get('feathery'):
                for i in range(1, 6):
                    q = np.array(b) + (np.array(t) - np.array(b)) * i / 6
                    m.v(round(q[0] + sgn), round(q[1]), round(q[2]), col)
            else:
                m.ell(t[0], t[1], t[2], 0.9, 0.9, 0.9, p.get('tip', col))


def snout(c, kind, fur, light, nose, **p):
    m, cx = c.m, c.cx
    m.part = 'head'
    fy = c.face_y
    if kind == 'muzzle':      # lion / bear / most mammals
        m.ell(cx, fy - 1.3, c.hz - 2.9, p.get('w', 3.2), p.get('d', 2.0), p.get('h', 2.0), light)
        m.box(round(cx) - 1, round(cx), round(fy) + p.get('nose_y', 1), round(fy) + p.get('nose_y', 1), round(c.hz - 2), round(c.hz - 1), nose)
    elif kind == 'long':      # dog / wolf / hyena / rat / jackal
        L = p.get('len', 3)
        m.ell(cx, fy + 0.6, c.hz - 2.7, p.get('w', 2.5), L, p.get('h', 1.9), light)
        if p.get('top_fur', True):
            m.ell(cx, fy + 0.6, c.hz - 1.9, p.get('w', 2.5) - 0.2, L, 1.0, fur, only=light)
        ny = round(fy + 0.6 + L)
        m.box(round(cx) - 1, round(cx), ny, ny, round(c.hz - 2), round(c.hz - 1), nose)
    elif kind == 'beak':      # birds
        L, col = p.get('len', 2), p.get('color', '#e3b23c')
        z = round(c.hz - 1.5)
        w = p.get('w', 1)
        for i in range(L + 1):
            ww = max(0, w - (i * w) // max(L, 1))
            m.box(round(cx) - 1 - ww, round(cx) + ww, round(fy) - 1 + i, round(fy) - 1 + i, z - 1, z, col)
        if p.get('hook'):
            m.box(round(cx) - 1, round(cx), round(fy) - 1 + L, round(fy) - 1 + L, z - 2, z - 2, col)
        m.box(round(cx) - 1, round(cx), round(fy) - 1, round(fy) - 1 + max(L - 1, 0), z - 1, z - 1, shade(col, 0.8))
    elif kind == 'pig':       # boar / hippo
        r = p.get('r', 2.2)
        m.ell(cx, fy + 0.3, c.hz - 2.8, r * 1.15, 1.6, r, light)
        y = round(fy + 1.6)
        for dx in (-1, 1):
            m.v(round(cx + dx * 0.9 - 0.5), y, round(c.hz - 2.6), nose)
    elif kind == 'flat':      # cats, frogs, monkeys: no protrusion, small nose + mouth
        m.front(round(cx) - 1, round(c.hz - 2), nose)
        m.front(round(cx), round(c.hz - 2), nose)
        if p.get('mouth'):
            for dx in range(-2, 2):
                m.front(round(cx) + dx, round(c.hz - 4), p['mouth'])
    elif kind == 'trunk':     # elephant / mammoth
        m.ell(cx, fy - 0.5, c.hz - 2.5, 2.0, 1.5, 2.0, fur)
        m.line((cx, fy + 0.5, c.hz - 3), (cx, fy + 1.8, c.hz - 8), fur, r=1.0)
        m.line((cx, fy + 1.8, c.hz - 8), (cx, fy + 3.2, c.hz - 10), fur, r=0.7)
    elif kind == 'croc':      # crocodile: long flat jaws with teeth
        L = p.get('len', 6)
        m.box(round(cx) - 3, round(cx) + 2, round(fy) - 2, round(fy) + L, round(c.hz - 4), round(c.hz - 2), fur)
        m.box(round(cx) - 3, round(cx) + 2, round(fy) - 2, round(fy) + L, round(c.hz - 4), round(c.hz - 4), light)
        for i in range(0, L + 2, 2):
            m.v(round(cx) - 3, round(fy) - 1 + i, round(c.hz - 3), WHITE)
            m.v(round(cx) + 2, round(fy) - 1 + i, round(c.hz - 3), WHITE)
        m.box(round(cx) - 2, round(cx) + 1, round(fy) + L, round(fy) + L, round(c.hz - 2), round(c.hz - 2), nose)
    elif kind == 'horse':     # long horse face
        L = p.get('len', 4)
        m.ell(cx, fy + 0.8, c.hz - 2.6, 2.6, L, 2.4, fur)
        m.ell(cx, fy + 0.8 + L * 0.6, c.hz - 3.1, 2.4, L * 0.45, 1.8, light)
        ny = round(fy + 0.8 + L)
        m.v(round(cx) - 2, ny, round(c.hz - 2), nose)
        m.v(round(cx) + 1, ny, round(c.hz - 2), nose)
    elif kind == 'mandible':  # insects
        for dx in (-2, 1):
            m.box(round(cx) + dx, round(cx) + dx + 1, round(fy), round(fy) + 1, round(c.hz - 5), round(c.hz - 4), nose)
    elif kind == 'none':
        pass


def horns(c, kind, col, **p):
    m, cx = c.m, c.cx
    m.part = 'head'
    top = c.top
    tip = p.get('tip', shade(col, 0.82))
    for sgn in (-1, 1):
        if kind == 'small':          # devil / goat nubs
            b = (cx + sgn * 3.5, 11.5, top - 1)
            m.line(b, (cx + sgn * 4.5, 10.5, top + 3), col, r=0.7)
            m.v(round(cx + sgn * 4.8), 10, round(top + 4), tip)
        elif kind == 'swept':        # mountain goat / ibex: back-swept
            b = (cx + sgn * 3, 12, top - 1)
            m.line(b, (cx + sgn * 3.6, 9, top + 3), col, r=0.8)
            m.line((cx + sgn * 3.6, 9, top + 3), (cx + sgn * 4.2, 6, top + 4), col, r=0.6)
            m.v(round(cx + sgn * 4.4), 5, round(top + 4), tip)
        elif kind == 'ram':          # curled spirals at the side of the head
            ox, oz = cx + sgn * (c.hr[0] - 0.5), c.hz + 2.5
            prev = None
            for i in range(14):
                a = i / 13 * 1.7 * math.pi
                r = 3.0 - i * 0.12
                pt = (ox + sgn * (1.2 + r * math.sin(a) * 0.6), 11.5 - r * math.cos(a) * 0.5 + 0.8, oz + r * math.cos(a) * 0.9)
                if prev:
                    m.line(prev, pt, col if i % 3 else tip, r=1.0 - i * 0.04)
                prev = pt
        elif kind == 'bull':         # out then up
            b = (cx + sgn * (c.hr[0] - 1), 11.5, top - 2)
            m.line(b, (cx + sgn * (c.hr[0] + 2.5), 11.5, top - 1), col, r=0.9)
            m.line((cx + sgn * (c.hr[0] + 2.5), 11.5, top - 1), (cx + sgn * (c.hr[0] + 3.2), 11.5, top + 3), col, r=0.6)
            m.v(round(cx + sgn * (c.hr[0] + 3.2)), 11, round(top + 4), tip)
        elif kind == 'antlers':      # deer / moose / elk
            big = p.get('big', 1.0)
            b = (cx + sgn * 3, 11.5, top - 1)
            t = (cx + sgn * (5 + 3 * big), 10.5, top + 5 * big)
            m.line(b, t, col, r=0.6)
            for k in (0.35, 0.65, 0.95):
                q = np.array(b) + (np.array(t) - np.array(b)) * k
                m.line(q, q + np.array([sgn * -0.5, 0.5, 2.5 * big]), col, r=0.4)
            if p.get('leaves'):
                for k in (0.5, 1.0):
                    q = np.array(b) + (np.array(t) - np.array(b)) * k
                    m.ell(q[0], q[1], q[2] + 1.5, 1.4, 1.2, 1.2, p['leaves'])
            if p.get('palm'):        # moose palms
                m.ell(t[0] - sgn * 0.5, t[1], t[2] - 0.5, 2.0, 0.8, 1.6, col)
        elif kind == 'tusks':        # boar / walrus / mammoth: from the muzzle
            L = p.get('len', 3)
            down = p.get('down', False)
            b = (cx + sgn * 2.2, c.face_y + 0.5, c.hz - 3.5)
            e = (cx + sgn * 2.6, c.face_y + 1.5 + (0 if down else 0.8), c.hz - 3.5 + (-L if down else L * 0.7))
            m.line(b, e, col, r=0.55)
    if kind == 'rhino':
        b = (cx, c.face_y + 1.5, c.hz - 2)
        m.line(b, (cx, c.face_y + 2.6, c.hz + 2.5), col, r=0.9)
        m.line((cx, c.face_y + 2.6, c.hz + 2.5), (cx, c.face_y + 2.4, c.hz + 4.5), tip, r=0.4)
    if kind == 'unicorn':
        m.line((cx, c.face_y - 0.5, c.hz + 3), (cx, c.face_y + 2.5, c.hz + 9), col, r=0.6)


def pattern(c, kind, col, **p):
    m, cx = c.m, c.cx
    x, y, z = np.indices(m.g.shape)
    H = (m.p == PID['head']) & (m.g > 0)
    B = (m.p == PID['body']) & (m.g > 0)
    fur = m.c(c.s.fur)
    if kind == 'mask':        # raccoon/ferret band across the eyes
        m._put(H & (m.g == fur) & (z >= c.hz - 0.5) & (z <= c.hz + 2.5) & (y >= c.face_y - 4), col, only='filled')
    elif kind == 'badger':    # white stripe over the top, black sides
        m._put(H & (m.g == fur) & (np.abs(x - cx) <= 1.6), p.get('stripe', WHITE), only='filled')
        m._put(H & (m.g == fur) & (np.abs(x - cx) > 1.6) & (np.abs(x - cx) <= 3.6) & (y >= c.face_y - 5), col, only='filled')
    elif kind == 'stripes':   # tiger
        S = (H | (p.get('body', True) & B)) & (m.g == fur)
        band = ((np.abs(x - cx) > 2) & (((z + (x // 3)) % 4) == 0))
        m._put(S & band, col, only='filled')
    elif kind == 'panda':     # eye patches
        for sgn in (-1, 1):
            m.ell(cx + sgn * 3.5, c.face_y - 0.5, c.hz + 0.5, 2.2, 1.5, 2.0, col, only='filled')
    elif kind == 'skunk':     # white stripe from the nose over the head and down the back
        m._put((H | B) & (m.g == fur) & (np.abs(x - cx) <= 1.2), p.get('stripe', WHITE), only='filled')
    elif kind == 'face':      # lighter face disk (owl, monkey, koala)
        m.ell(cx, c.face_y - 1.0, c.hz - 0.2, p.get('w', 5.5), 2.0, p.get('h', 4.8), col, only='filled')
    elif kind == 'cap':       # darker top of head (penguin, bird hoods)
        m._put(H & (z >= c.hz + p.get('dz', 0.5)), col, only='filled')
    elif kind == 'lower':     # lighter lower face / throat
        m._put(H & (m.g == fur) & (z <= c.hz - p.get('dz', 1.5)) & (y >= c.face_y - p.get('depth', 4)), col, only='filled')
    elif kind == 'spots':
        rng = m.rng
        for xx, yy, zz in np.argwhere(H | B):
            if m.g[xx, yy, zz] == fur and rng.random() < p.get('p', 0.08):
                m.g[xx, yy, zz] = m.c(col)
    elif kind == 'bones':     # skeleton: ribs on the chest, dark eye sockets done by eyes
        for zz in (6, 8, 10):
            for xx in range(round(cx) - 3, round(cx) + 3):
                m.front(xx, zz, col)
        for zz in range(5, 12):
            m.front(round(cx) - 1, zz, col)
            m.front(round(cx), zz, col)


def tail(c, kind, fur, accent=None, **p):
    m, cx = c.m, c.cx
    m.part = 'tail'
    acc = accent or fur
    if kind == 'bushy':
        m.ell(cx + 3, 4.5, 5.5, 3.0, 3.6, 3.0, fur)
        m.ell(cx + 4.5, 2.5, 8.5, 2.5, 2.5, 2.5, fur)
        m.ell(cx + 5.5, 1.8, 10.5, 1.9, 1.9, 1.9, acc)
    elif kind == 'squirrel':  # big curl up the back
        m.ell(cx + 1, 3.5, 7, 3.0, 2.6, 4.0, fur)
        m.ell(cx + 1.5, 2.5, 13, 3.2, 2.6, 3.4, fur)
        m.ell(cx + 2, 4, 17, 2.6, 2.2, 2.2, acc)
    elif kind == 'thin':      # rat / monkey / lemur
        pts = p.get('pts', [(cx, 6, 4), (cx + 1, 2, 4), (cx + 3, 0.5, 7), (cx + 4, 1, 11), (cx + 3, 2, 13)])
        ring = p.get('ring')
        for i in range(len(pts) - 1):
            m.line(pts[i], pts[i + 1], (ring if ring and i % 2 else fur), r=p.get('r', 0.6))
        if p.get('tip'):
            m.ell(*pts[-1], 1.2, 1.2, 1.2, p['tip'])
    elif kind == 'stub':
        m.ell(cx, 5.5, 4.5, 1.8, 1.6, 1.6, acc)
    elif kind == 'paddle':    # beaver
        m.box(round(cx) - 2, round(cx) + 1, 0, 6, 1, 2, acc)
        m.box(round(cx) - 1, round(cx), 0, 6, 1, 1, shade(acc, 0.8))
    elif kind == 'feather':   # birds
        for i, dx in enumerate((-2, 0, 2)):
            m.line((cx + dx * 0.4, 6, 6), (cx + dx, 2, 3 - abs(dx) * 0.3), fur if i != 1 else acc, r=0.7)
    elif kind == 'fan':       # peacock
        cols = p.get('cols', ['#2f8a7a', '#3fb3a0', '#1f5f9a'])
        for i in range(9):
            a = math.pi * (0.15 + 0.7 * i / 8)
            e = (cx + 9 * math.cos(a), 3.5, 8 + 13 * math.sin(a))
            m.line((cx, 6, 7), e, cols[i % len(cols)], r=0.6)
            m.ell(e[0], e[1], e[2], 1.2, 0.6, 1.2, '#2a4fa8')
            m.v(round(e[0]), 2, round(e[2]), GILT)
    elif kind == 'fire':      # phoenix tail
        for i, dx in enumerate((-3, -1, 1, 3)):
            m.line((cx, 6, 6), (cx + dx * 1.3, 0.5, 10 + abs(dx)), ['#ff9a3c', '#ffd23a', '#ff5a2a', '#ffb13b'][i], r=0.6)
    elif kind == 'croc':
        m.line((cx, 6, 4), (cx + 1, 1, 2), fur, r=1.8)
        m.line((cx + 1, 1, 2), (cx + 4, -2, 1), fur, r=1.0)
    elif kind == 'curly':     # pig / boar
        m.line((cx, 6, 6), (cx + 1, 4.5, 7), fur, r=0.4)
        m.line((cx + 1, 4.5, 7), (cx, 4, 8.5), fur, r=0.4)
    elif kind == 'horse':
        m.line((cx, 5.5, 8), (cx + 1, 2, 4), acc, r=1.1)
        m.line((cx + 1, 2, 4), (cx + 1.5, 1.5, 1), acc, r=0.9)
    elif kind == 'skunk':
        m.ell(cx, 3.5, 8, 3.2, 2.8, 4.2, fur)
        m.ell(cx, 2.5, 13, 3.0, 2.6, 3.0, fur)
        m.ell(cx, 2.0, 13.5, 1.0, 2.7, 3.2, WHITE, only='filled')
        m.ell(cx, 3.5, 8, 1.0, 2.9, 4.2, WHITE, only='filled')
    elif kind == 'puff':      # hedgehog / pom-pom
        m.ell(cx, 5, 4.5, 1.4, 1.4, 1.4, acc)
    if kind != 'none':
        m.pivots['tail'] = (cx, 7, 4.5)


def wings(c, kind, col, col2=None, **p):
    """Wings on the back (body bone). kinds: bat, feather, fairy, moth, angel, flame."""
    m, cx = c.m, c.cx
    m.part = 'body'
    col2 = col2 or shade(col, 0.8)
    y = p.get('y', 5)
    span = p.get('span', 8)
    z0 = p.get('z', 9)
    x, yy, z = np.indices(m.g.shape)
    for sgn in (-1, 1):
        if kind in ('bat', 'flame'):
            sh = np.array([cx + sgn * 3, y, z0 + 4])
            tip = np.array([cx + sgn * (3 + span), y, z0 + 10])
            low = np.array([cx + sgn * (2 + span * 0.9), y, z0 - 1])
            def tri(a, b, d):
                def s(p1, p2, p3):
                    return (p1[0] - p3[0]) * (p2[2] - p3[2]) - (p2[0] - p3[0]) * (p1[2] - p3[2])
                P = (x.astype(float), yy.astype(float), z.astype(float))
                d1, d2, d3 = s(P, a, b), s(P, b, d), s(P, d, a)
                return ~(((d1 < 0) | (d2 < 0) | (d3 < 0)) & ((d1 > 0) | (d2 > 0) | (d3 > 0)))
            mem = tri(sh, tip, low) & (yy == y)
            if kind == 'bat':   # scalloped lower edge
                mem &= ~((z < z0 + 1) & (((x - cx) % 3) == 0))
            m._put(mem, col, keep=True)
            m.line(sh, tip, col2, r=0.4)
            m.line(sh, low, col2, r=0.3)
            if kind == 'flame':
                m._put(mem & (z > z0 + 6), p.get('hot', '#ffd23a'), only=col)
        elif kind in ('feather', 'angel', 'fairy', 'moth'):
            n = span
            for i in range(n):
                xx = cx + sgn * (3 + i)
                if kind == 'fairy':
                    h0, h1 = z0 + 2 + i // 2, z0 + 7 + (i if i < 3 else 6 - i)
                elif kind == 'moth':
                    h0, h1 = z0 - 3 + i // 3, z0 + 8 + (i if i < 4 else 7 - i)
                else:
                    h0, h1 = z0 + i // 2, z0 + 6 + (i if i < 4 else 7 - i)
                for zz in range(int(h0), int(h1) + 1):
                    c_ = col if (zz - h0) % 3 else col2
                    if kind == 'moth' and (abs(i - n * 0.55) < 1.2 and abs(zz - (h0 + h1) / 2) < 1.5):
                        c_ = p.get('eye', '#f2c14e')
                    m.v(math.floor(xx + 0.5), y, zz, c_)
                if kind in ('feather', 'angel'):
                    m.v(math.floor(xx + 0.5), y - 1, int(h1), col2)
    m.part = 'body'


def spikes(c, col, tip=None, region='back', n=36):
    """Hedgehog quills / armadillo back."""
    m, cx = c.m, c.cx
    m.part = 'body'
    rng = m.rng
    for i in range(n):
        a = rng.random() * math.pi - math.pi / 2
        zz = 4 + rng.random() * 12
        xx = cx + 6.5 * math.sin(a)
        b = (xx, 8, zz)
        e = (xx + 2.2 * math.sin(a), 4.5, zz + 1.5)
        m.line(b, e, col, r=0.35)
        if tip:
            m.v(round(e[0]), round(e[1]), round(e[2]), tip)
    # quills over the top of the head
    m.part = 'head'
    for i in range(n // 2):
        a = rng.random() * math.pi - math.pi / 2
        b = (cx + 6 * math.sin(a), 10, c.hz + 3 + rng.random() * 3)
        m.line(b, (b[0] + 2 * math.sin(a), 6.5, b[2] + 2.5), col, r=0.35)


def shell_back(c, col, seam):
    m, cx = c.m, c.cx
    m.part = 'body'
    m.ell(cx, 8.0, 10.5, 7.8, 4.4, 7.4, col, keep=True)
    x, y, z = np.indices(m.g.shape)
    S = (m.g == m.c(col))
    m._put(S & (np.abs((z - 1) % 3) == 0), seam, only='filled')


# ------------------------------------------------------------------ outfits

def outfit(c, kind, tier):
    m, s, pal, cx = c.m, c.s, c.s.pal, c.cx
    m.part = 'body'
    x, y, z = np.indices(m.g.shape)
    trim = GILT if tier >= 2 else pal['trim']
    X = m.X
    if kind in ('Warrior', 'Protector'):
        # breastplate over the torso
        m._put((m.p == PID['body']) & (m.g > 0) & (z >= 4) & (z <= 12), pal['metal'], only='filled')
        for xx in range(round(cx) - 3, round(cx) + 3):
            for zz in range(4, 11):
                m.front(xx, zz, pal['cloth'])
        for xx in range(round(cx) - 3, round(cx) + 3):
            m.front(xx, 4, trim)
        for zz in range(4, 11):
            m.front(round(cx) - 4, zz, trim)
            m.front(round(cx) + 3, zz, trim)
        m.front(round(cx) - 1, 8, trim); m.front(round(cx), 8, trim)
        m.front(round(cx) - 1, 7, trim); m.front(round(cx), 7, trim)
        # pauldrons
        for part, sgn in (('arm_r', -1), ('arm_l', 1)):
            m.part = part
            px = cx + sgn * 6.0
            m.ell(px, 11.5, 12.5, 2.8, 2.8, 2.0, pal['metal_l'])
            m.ell(px, 11.5, 12.0, 2.8, 2.8, 1.0, pal['metal_d'], only='filled')
        m.part = 'leg_r'
        m._put((m.p == PID['leg_r']) & (m.g > 0) & (z >= 2), pal['metal'], only='filled')
        m.part = 'leg_l'
        m._put((m.p == PID['leg_l']) & (m.g > 0) & (z >= 2), pal['metal'], only='filled')
        m.part = 'body'
        if kind == 'Protector':
            m.ell(cx, 11.5, 13.5, 6.6, 5.4, 1.6, pal['metal_d'])   # gorget
    elif kind in ('Caster', 'Healer', 'Summoner'):
        robe = pal['cloth'] if kind != 'Healer' else pal['cloth2']
        for zz in range(0, 9):
            r = 6.0 - zz * 0.2
            m.cyl(cx, 11.5, zz + 1, zz + 1, r, robe, ry=r * 0.85, keep=True)
        m._put((m.p == PID['body']) & (m.g > 0) & (z <= 12), robe, only='filled')
        m.cyl(cx, 11.5, 1, 1, 6.0, trim, ry=5.1, only=robe)
        for zz in range(1, 12):
            m.front(round(cx) - 1, zz, trim if kind != 'Summoner' else pal['cloth2'])
            m.front(round(cx), zz, trim if kind != 'Summoner' else pal['cloth2'])
        if kind == 'Healer':
            for zz in range(3, 12):
                m.front(round(cx) - 3, zz, pal['cloth'])
                m.front(round(cx) + 2, zz, pal['cloth'])
        if kind == 'Summoner':
            m.ell(cx, 10.8, 20.2, 8.3, 6.6, 7.4, pal['cloth2'], keep=True)   # hood shell behind head
            m.part = 'head'
            m._put((m.g == m.c(pal['cloth2'])) & (m.p == PID['body']) & (z >= 14), pal['cloth2'], only='filled')
            m.p[(m.g == m.c(pal['cloth2'])) & (z >= 14)] = PID['head']
            m.part = 'body'
        m.ell(cx, 11.5, 13.3, 6.8, 5.4, 1.6, shade(robe, 0.85))
    elif kind == 'Ranger':
        m.box(round(cx) - 5, round(cx) + 5, 6, 7, 3, 13, pal['cloth2'])            # cloak
        m._put((m.p == PID['body']) & (m.g > 0) & (z <= 12), pal['cloth'], only='filled')
        for xx in range(round(cx) - 5, round(cx) + 6):
            m.front(xx, 6, LEATHER)
        m.front(round(cx) - 1, 6, trim); m.front(round(cx), 6, trim)
        for i in range(8):
            m.front(round(cx) - 4 + i, 4 + i, LEATHER_D)
        m.ell(cx, 11, 13.5, 7.2, 5.5, 2.2, shade(pal['cloth'], 1.15))         # hood collar
        m.line((cx - 4, 5, 8), (cx + 3, 5, 17), LEATHER, r=1.0)                # quiver
        for dx in (0, 1, 2):
            m.line((cx + 2.5 + dx * 0.6, 5, 18), (cx + 3.5 + dx, 5, 21), WOOD, r=0)
            m.v(round(cx + 3.5 + dx), 5, 22, pal['trim']); m.v(round(cx + 3.5 + dx), 4, 22, '#f2f0e6')
    elif kind == 'Rogue':
        m._put((m.p == PID['body']) & (m.g > 0) & (z <= 12), pal['cloth2'], only='filled')
        m.ell(cx, 11.5, 13.5, 6.8, 5.4, 1.8, pal['cloth'])                     # scarf
        m.line((cx + 2.5, 6, 13), (cx + 5.5, 3, 10), shade(pal['cloth'], 0.8), r=0.6)
        for xx in range(round(cx) - 5, round(cx) + 6):
            m.front(xx, 6, LEATHER_D)
        m.front(round(cx) - 1, 6, trim); m.front(round(cx), 6, trim)
        for i in range(7):
            m.front(round(cx) - 4 + i, 11 - i, pal['cloth'])
    elif kind == 'Monk':
        m.ell(cx, 15, 9.5, 3.2, 1.4, 3.4, s.light)
        for xx in range(round(cx) - 5, round(cx) + 6):
            m.front(xx, 6, pal['cloth']); m.front(xx, 5, pal['cloth'])
        m.line((cx + 2, 15, 6), (cx + 3, 16, 2), pal['cloth'], r=0.5)
        m.part = 'leg_r'
        m._put((m.p == PID['leg_r']) & (m.g > 0) & (z >= 2), pal['cloth2'], only='filled')
        m.part = 'leg_l'
        m._put((m.p == PID['leg_l']) & (m.g > 0) & (z >= 2), pal['cloth2'], only='filled')
        # hand wraps
        for part in ('arm_r', 'arm_l'):
            m.part = part
            m._put((m.p == PID[part]) & (m.g > 0) & (z >= 6) & (z <= 8), '#ece4cc', only='filled')
        m.part = 'body'
        # prayer beads
        for k in range(9):
            a = math.pi * (0.1 + 0.8 * k / 8)
            m.v(round(cx + 5 * math.cos(a)), round(11.5 + 4.6 * math.sin(a) + 0.8), 13, '#8b5a2b' if k % 2 else trim)
    elif kind == 'Alchemist':
        m._put((m.p == PID['body']) & (m.g > 0) & (z <= 12), pal['cloth2'], only='filled')
        for xx in range(round(cx) - 4, round(cx) + 4):          # apron
            for zz in range(2, 12):
                m.front(xx, zz, '#d9c8a8')
        for xx in range(round(cx) - 5, round(cx) + 6):
            m.front(xx, 7, LEATHER_D)
        for i, col in enumerate(('#7dff9b', '#ff6ad5', '#6fd9ff')):   # potion belt
            m.front(round(cx) - 4 + i * 3, 6, col)
            m.front(round(cx) - 4 + i * 3, 5, col)
        m.glow |= {'#7dff9b', '#ff6ad5', '#6fd9ff'}
        m.part = 'head'                                          # goggles on the forehead
        for sgn in (-1, 1):
            m.ell(cx + sgn * 2.8, c.face_y - 0.8, c.hz + 3.8, 1.6, 1.2, 1.3, '#d9a33a')
            m.v(round(cx + sgn * 2.8 - 0.5), round(c.face_y + 0.3), round(c.hz + 3.8), '#9ff0ff')
        m.part = 'body'
    elif kind == 'Bard':
        m._put((m.p == PID['body']) & (m.g > 0) & (z <= 12), pal['cloth'], only='filled')
        for zz in range(3, 12):
            m.front(round(cx) - 1, zz, pal['cloth2']); m.front(round(cx), zz, pal['cloth2'])
        for zz in (5, 7, 9):
            m.front(round(cx) - 2, zz, trim); m.front(round(cx) + 1, zz, trim)
        m.ell(cx, 11.5, 13.5, 6.8, 5.4, 1.6, shade(pal['cloth2'], 1.1))
    elif kind == 'Plain':
        pass
    m.part = 'body'


# ------------------------------------------------------------------ hats

def hat(c, kind, tier, col=None):
    m, cx, pal = c.m, c.cx, c.s.pal
    m.part = 'head'
    col = col or pal['cloth']
    base = c.hat_base
    x, y, z = np.indices(m.g.shape)
    trim = GILT if tier >= 2 else pal['trim']
    if kind == 'wizard':
        h = 11 if tier == 1 else 13
        m.cyl(cx, 11.5, base, base, 9.0, col, ry=8.0)
        m.cyl(cx, 11.5, base + 1, base + 1, 5.6, trim, ry=5.0)
        for i, zz in enumerate(range(base + 2, base + h)):
            r = 5.3 - i * (5.0 / h)
            off = 0 if i < 4 else (i - 3) * 0.7
            m.cyl(cx + off, 11.5 - off * 0.3, zz, zz, max(r, 0.6), col, ry=max(r * 0.9, 0.6))
        for dx, dz in ((0, 4), (-1, 4), (0, 5), (0, 3)):
            m.front(round(cx) + dx, base + dz, pal['glow'])
    elif kind == 'hood':
        sel = (((x - cx) / 8.2) ** 2 + ((y - 10.8) / 6.8) ** 2 + ((z - c.hz) / 7.4) ** 2 <= 1) & (y <= c.face_y - 3.5)
        sel |= (((x - cx) / 8.2) ** 2 + ((y - 10.8) / 6.8) ** 2 + ((z - c.hz) / 7.4) ** 2 <= 1) & (z >= c.hz + 3)
        m._put(sel, col)
        m.box(round(cx) - 1, round(cx), round(c.face_y) - 4, round(c.face_y) - 2, round(c.top) + 1, round(c.top) + 1, trim)
    elif kind == 'helm':      # rounded helmet with a crest
        sel = (((x - cx) / (c.hr[0] + 0.3)) ** 2 + ((y - 11.5) / (c.hr[1] + 0.2)) ** 2 + ((z - c.hz) / (c.hr[2] + 0.2)) ** 2 <= 1) & (z >= c.hz + 2.5)
        m._put(sel, pal['metal'])
        m.box(0, m.X - 1, 0, m.Y - 1, round(c.hz + 2.5), round(c.hz + 2.5), pal['metal_d'], only=pal['metal'])
        m.box(round(cx) - 1, round(cx), 8, 15, round(c.top), round(c.top) + 1, pal['trim'] if tier == 1 else GILT)
        if tier >= 2:
            m.box(round(cx) - 1, round(cx), 7, 16, round(c.top) + 2, round(c.top) + 2, pal['cloth'])
    elif kind == 'kettle':    # wide-brim kettle hat (dwarves, militia)
        sel = (((x - cx) / (c.hr[0] - 0.5)) ** 2 + ((y - 11.5) / (c.hr[1] - 0.5)) ** 2 + ((z - c.hz - 2) / 4.5) ** 2 <= 1) & (z >= c.hz + 3)
        m._put(sel, pal['metal'])
        m.cyl(cx, 11.5, round(c.hz + 3), round(c.hz + 3), c.hr[0] + 1.8, pal['metal_d'], ry=c.hr[1] + 1.8)
    elif kind == 'cap':       # feathered bard cap
        m.ell(cx, 11, c.top - 0.5, 6.5, 5.5, 2.4, col)
        m.box(round(cx) - 6, round(cx) + 6, 15, 16, round(c.top) - 2, round(c.top) - 2, shade(col, 0.8))
        m.line((cx + 3, 10, c.top + 1), (cx + 7, 6, c.top + 6), pal['trim'] if tier == 1 else GILT, r=0.6)
    elif kind == 'headband':
        m._put((m.p == PID['head']) & (m.g > 0) & (z >= c.hz + 2) & (z <= c.hz + 3), col, only='filled')
        m.line((cx + 1, 4.5, c.hz + 2.5), (cx + 4, 2, c.hz), col, r=0.5)
    elif kind == 'lamp':      # miner's helmet with a lamp
        sel = (((x - cx) / (c.hr[0] + 0.3)) ** 2 + ((y - 11.5) / (c.hr[1] + 0.2)) ** 2 + ((z - c.hz) / (c.hr[2] + 0.2)) ** 2 <= 1) & (z >= c.hz + 3)
        m._put(sel, '#d9a33a')
        m.box(round(cx) - 1, round(cx), round(c.face_y) - 1, round(c.face_y), round(c.hz + 4), round(c.hz + 5), '#fff4b0')
        m.glow.add('#fff4b0')
    elif kind == 'horned_helm':
        sel = (((x - cx) / 7.8) ** 2 + ((y - 11.5) / 6.8) ** 2 + ((z - c.hz) / 6.8) ** 2 <= 1) & (z >= c.hz + 3)
        m._put(sel, pal['metal'])
        for sgn in (-1, 1):
            bx = cx + sgn * 6.8
            m.line((bx, 11.5, c.hz + 4), (bx + sgn * 2.5, 11.5, c.hz + 6), '#efe4c9', r=0.9)
            m.line((bx + sgn * 2.5, 11.5, c.hz + 6), (bx + sgn * 3.0, 11.5, c.hz + 10), '#efe4c9', r=0.6)
    elif kind == 'beret':
        m.ell(cx - 1, 11, c.top, 6.0, 5.0, 1.8, col)
        m.v(round(cx) - 1, 11, round(c.top) + 2, pal['trim'])
    elif kind == 'plague':    # wide hat for the plague doctor
        m.cyl(cx, 11.5, round(c.top) - 1, round(c.top) - 1, 9.5, '#2b2f2a', ry=8.5)
        m.cyl(cx, 11.5, round(c.top), round(c.top) + 4, 5.0, '#2b2f2a', ry=4.5)
        m.cyl(cx, 11.5, round(c.top) + 1, round(c.top) + 1, 5.1, pal['trim'], ry=4.6)
    elif kind == 'circlet':
        m._put((m.p == PID['head']) & (m.g > 0) & (z == round(c.hz + 3)) & (y >= 12), trim, only='filled')
        m.front(round(cx) - 1, round(c.hz + 3), pal['gem'])
        m.front(round(cx), round(c.hz + 3), pal['gem'])
    m.part = 'body'


# ------------------------------------------------------------------ weapons and held items

def _hand(c, side):
    hx_, hy_, _ = c.a['hand_r'] if side == 'r' else c.a['hand_l']
    return int(round(hx_)), int(round(hy_)) + 2


def weapon(c, kind, tier, side='r', **p):
    """Weapons sit on weapon_r / weapon_l (pivot at the hand), drawn upright (blade up)."""
    m, pal = c.m, c.s.pal
    m.part = 'weapon_' + side
    sx, sy = _hand(c, side)
    if side == 'l' and kind in ('bow', 'crossbow', 'musket'):
        sx = m.X - 3
    big = 1 if tier >= 2 else 0
    blade, blade_d = BLADE, BLADE_D
    if kind == 'sword':
        top = 21 + 3 * big + p.get('extra', 0)
        m.box(sx, sx, sy, sy, 3, 7, WOOD_D); m.v(sx, sy, 2, pal['trim'])
        m.box(sx - 2, sx + 2, sy, sy, 8, 8, pal['trim']); m.box(sx, sx, sy - 1, sy + 1, 8, 8, pal['trim'])
        m.box(sx, sx, sy - 1, sy, 9, top, blade); m.box(sx, sx, sy - 1, sy - 1, 9, top - 1, blade_d)
        m.v(sx, sy, top + 1, blade)
        if p.get('flame'):
            for zz in range(12, top + 1, 2):
                m.v(sx, sy + 1, zz, pal['glow'])
            m.glow.add(pal['glow'])
    elif kind == 'greatsword':
        top = 24 + 3 * big
        m.box(sx, sx, sy, sy, 2, 7, WOOD_D)
        m.box(sx - 3, sx + 3, sy, sy, 8, 8, pal['trim'])
        m.box(sx, sx, sy - 1, sy + 1, 9, top, blade); m.box(sx, sx, sy - 1, sy - 1, 9, top - 1, blade_d)
    elif kind == 'axe':
        m.box(sx, sx, sy, sy, 2, 18, WOOD)
        for zz in range(13, 19):
            w = int(round(1 + (3 + big) * math.sin(math.pi * (zz - 13) / 5)))
            m.box(sx, sx, sy + 1, sy + 1 + w, zz, zz, blade_d); m.v(sx, sy + 1 + w, zz, blade)
    elif kind == 'hammer':
        m.box(sx, sx, sy, sy, 2, 17, WOOD)
        m.box(sx - 1, sx + 1, sy - 2 - big, sy + 2 + big, 17, 20 + big, p.get('head', pal['metal']))
        m.box(sx - 1, sx + 1, sy - 2 - big, sy - 2 - big, 17, 20 + big, pal['metal_d'])
    elif kind == 'pickaxe':
        m.box(sx, sx, sy, sy, 2, 17, WOOD)
        m.line((sx, sy - 4 - big, 15), (sx, sy, 18), blade_d, r=0.5)
        m.line((sx, sy, 18), (sx, sy + 4 + big, 15), blade_d, r=0.5)
    elif kind == 'mace':
        m.box(sx, sx, sy, sy, 3, 13, WOOD)
        m.ell(sx, sy, 15.5, 2.2 + 0.4 * big, 2.2 + 0.4 * big, 2.2 + 0.4 * big, pal['metal'])
        for d in ((0, 3, 0), (0, -3, 0), (3, 0, 0), (-3, 0, 0), (0, 0, 3)):
            m.v(sx + d[0], sy + d[1], 15 + d[2], pal['metal_l'])
    elif kind == 'spear':
        m.box(sx, sx, sy, sy, 0, 24, WOOD)
        m.box(sx - 1, sx + 1, sy, sy, 25, 26 + big, blade); m.box(sx, sx, sy, sy, 27 + big, 29 + big, blade)
    elif kind == 'halberd':
        m.box(sx, sx, sy, sy, 0, 25, WOOD)
        for zz in range(19, 25):
            w = int(round(1 + (2 + big) * math.sin(math.pi * (zz - 19) / 6)))
            m.box(sx, sx, sy + 1, sy + w, zz, zz, blade_d)
        m.box(sx, sx, sy, sy, 26, 28, blade)
    elif kind == 'scythe':
        m.box(sx, sx, sy, sy, 0, 24, WOOD_D)
        for i in range(9 + 2 * big):
            m.v(sx, sy + 1 + i, 24 - (i * i) // 14, blade)
            m.v(sx, sy + 1 + i, 23 - (i * i) // 14, blade_d)
    elif kind == 'dagger':
        m.box(sx, sx, sy - 1, sy, 6, 6, WOOD_D)
        m.box(sx, sx, sy + 1, sy + 1, 5, 7, pal['trim'])
        m.box(sx, sx, sy + 2, sy + 6 + big, 6, 6, blade)
        m.box(sx, sx, sy + 2, sy + 5 + big, 7, 7, blade_d)
    elif kind == 'claws':
        for dz in (-1, 0, 1):
            m.line((sx, sy, 6 + dz), (sx, sy + 4 + big, 6 + dz * 1.6), blade, r=0)
    elif kind == 'bow':
        L = 18 + 2 * big
        for zz in range(0, L + 1):
            t = zz / L
            yy = 13 + int(round(3.2 * math.sin(math.pi * t)))
            m.v(sx, yy, zz + 1, WOOD if not (0.38 < t < 0.62) else LEATHER_D)
        for zz in range(2, L + 1):
            m.v(sx, 13, zz, '#ece4cc')
        if big:
            for zz in (1, 2, L, L + 1):
                m.v(sx, 13, zz, pal['trim'])
    elif kind == 'crossbow':
        m.box(sx, sx, 10, 18, 9, 9, WOOD)
        for yy in range(-4, 5):
            m.v(sx, 17 - abs(yy) // 3, 9 + yy, blade_d)
    elif kind == 'musket':
        m.box(sx, sx, 8, 13, 7, 9, WOOD)
        m.box(sx, sx, 13, 22 + big, 9, 9, pal['metal_d'])
        m.box(sx, sx, 13, 15, 8, 8, pal['metal'])
    elif kind in ('staff', 'orbstaff', 'skullstaff', 'leafstaff', 'crossstaff', 'flamestaff', 'icestaff', 'runestaff'):
        top = 22 + 2 * big
        m.box(sx, sx, sy, sy, 0, top, p.get('wood', WOOD))
        gem = p.get('gem', pal['glow'])
        if kind in ('staff', 'orbstaff'):
            m.v(sx - 1, sy, top, WOOD); m.v(sx + 1, sy, top, WOOD)
            m.ell(sx, sy, top + 2.5, 1.5 + 0.4 * big, 1.5 + 0.4 * big, 1.8 + 0.4 * big, gem)
            m.v(sx, sy + 1, top + 3, WHITE)
        elif kind == 'skullstaff':
            m.ell(sx, sy, top + 2.5, 1.8, 1.6, 1.8, '#efe4c9')
            m.v(sx - 1, sy + 2, top + 3, gem); m.v(sx + 1, sy + 2, top + 3, gem)
        elif kind == 'leafstaff':
            for d in ((0, 0, 1), (-1, 0, 2), (1, 0, 2), (0, 0, 3), (-2, 0, 3), (2, 0, 3)):
                m.v(sx + d[0], sy, top + d[2], '#5cc27a' if d[2] < 3 else '#8fe36b')
            m.v(sx, sy, top + 4, gem)
        elif kind == 'crossstaff':
            m.box(sx, sx, sy, sy, top, top + 5, pal['trim'])
            m.box(sx - 2, sx + 2, sy, sy, top + 3, top + 3, pal['trim'])
            m.v(sx, sy + 1, top + 3, gem)
        elif kind == 'flamestaff':
            m.ell(sx, sy, top + 2, 1.4, 1.4, 1.4, '#ffd23a')
            m.ell(sx, sy, top + 3.5, 1.0, 1.0, 1.6, '#ff9a3c')
            m.v(sx, sy, top + 5, '#ff5a2a')
            gem = '#ffd23a'
            m.glow |= {'#ff9a3c', '#ff5a2a'}
        elif kind == 'icestaff':
            m.line((sx, sy, top), (sx, sy, top + 5), '#bff0ff', r=0.8)
            m.line((sx - 2, sy, top + 1), (sx, sy, top + 3), '#9ff0ff', r=0.4)
            m.line((sx + 2, sy, top + 1), (sx, sy, top + 3), '#9ff0ff', r=0.4)
            m.glow |= {'#bff0ff', '#9ff0ff'}
        elif kind == 'runestaff':
            m.box(sx - 1, sx + 1, sy - 1, sy + 1, top, top + 2, pal['metal'])
            m.v(sx, sy + 2, top + 1, gem)
        m.glow.add(gem)
    elif kind == 'wand':
        m.box(sx, sx, sy, sy + 4, 7, 7, WOOD_D)
        m.v(sx, sy + 5, 7, pal['glow']); m.glow.add(pal['glow'])
    elif kind == 'book':
        m.box(sx - 1, sx + 1, sy, sy + 3, 5, 8, pal['cloth2'])
        m.box(sx - 1, sx + 1, sy + 3, sy + 3, 5, 8, '#efe4c9')
        m.v(sx, sy, 7, pal['glow']); m.glow.add(pal['glow'])
        if p.get('float_orb'):
            m.ell(sx, sy + 2, 12, 1.2, 1.2, 1.2, pal['glow'])
    elif kind == 'flask':
        m.ell(sx, sy + 1, 7, 1.6, 1.6, 1.6, p.get('liquid', '#7dff9b'))
        m.box(sx, sx, sy + 1, sy + 1, 9, 10, '#cfe8f0')
        m.v(sx, sy + 1, 11, WOOD)
        m.glow.add(p.get('liquid', '#7dff9b'))
    elif kind == 'lute':
        m.ell(sx, sy + 2, 6, 1.6, 2.4, 2.4, '#b8763a')
        m.v(sx, sy + 4, 6, '#3b2716')
        m.box(sx, sx, sy + 2, sy + 2, 8, 14, WOOD_D)
        m.box(sx - 1, sx + 1, sy + 2, sy + 2, 14, 15, '#3b2716')
    elif kind == 'horn':
        m.line((sx, sy, 6), (sx, sy + 3, 8), '#efe4c9', r=0.6)
        m.line((sx, sy + 3, 8), (sx, sy + 5, 9.5), pal['trim'], r=1.0)
    elif kind == 'flute':
        m.box(sx, sx, sy - 1, sy + 6, 7, 7, '#b8763a')
    elif kind == 'banner':
        m.box(sx, sx, sy, sy, 0, 26, WOOD)
        m.box(sx, sx, sy + 1, sy + 6, 19, 26, pal['cloth'])
        m.box(sx, sx, sy + 1, sy + 6, 19, 19, pal['trim'])
        m.v(sx, sy + 3, 23, pal['trim']); m.v(sx, sy + 4, 23, pal['trim'])
    elif kind == 'lantern':
        m.box(sx, sx, sy + 1, sy + 1, 6, 8, LEATHER_D)
        m.box(sx - 1, sx + 1, sy, sy + 2, 3, 5, pal['metal_d'])
        m.v(sx, sy + 1, 4, pal['glow']); m.glow.add(pal['glow'])
    elif kind == 'totem':
        m.box(sx, sx, sy, sy, 0, 20, WOOD_D)
        m.ell(sx, sy, 22, 1.8, 1.6, 2.2, '#efe4c9')
        m.v(sx - 1, sy + 2, 22, pal['glow']); m.v(sx + 1, sy + 2, 22, pal['glow'])
        for zz in (18, 19):
            m.v(sx - 1, sy, zz, pal['trim']); m.v(sx + 1, sy, zz, pal['trim'])
        m.glow.add(pal['glow'])
    elif kind == 'fist':
        pass
    m.part = 'body'


def shield(c, kind, tier, emblem=None):
    m, pal = c.m, c.s.pal
    m.part = 'weapon_l'
    X = m.X
    emblem = emblem or pal['trim']
    big = 1 if tier >= 2 else 0
    if kind == 'heater':
        for z in range(2, 15 + big):
            half = 4 if z > 5 else (z - 1)
            m.box(X - 3, X - 2, 12 - half, 12 + half, z, z, pal['cloth'])
            m.v(X - 1, 12 - half, z, pal['trim']); m.v(X - 1, 12 + half, z, pal['trim'])
        m.box(X - 1, X - 1, 8, 16, 14 + big, 14 + big, pal['trim'])
        m.box(X - 1, X - 1, 11, 13, 7, 10, emblem)
    elif kind == 'round':
        x, y, z = np.indices(m.g.shape)
        d = ((y - 12) ** 2 + (z - 8.5) ** 2)
        R = 6 + big
        m._put((x >= X - 3) & (x <= X - 2) & (d <= R * R), pal['metal'] if c.s.origin in ('Dwarven', 'Infernal') else pal['cloth'])
        m._put((x == X - 1) & (d <= R * R) & (d >= (R - 1) ** 2), pal['trim'])
        m._put((x == X - 1) & (d <= 2.2), emblem)
    elif kind == 'tower':
        z1 = 17 + 2 * big
        m.box(X - 2, X - 1, 5, 19, 1, z1, pal['metal'])
        m.box(X - 1, X - 1, 5, 19, 1, 1, pal['trim']); m.box(X - 1, X - 1, 5, 19, z1, z1, pal['trim'])
        m.box(X - 1, X - 1, 5, 5, 1, z1, pal['trim']); m.box(X - 1, X - 1, 19, 19, 1, z1, pal['trim'])
        m.box(X - 1, X - 1, 10, 14, 7, 11, emblem)
    elif kind == 'buckler':
        x, y, z = np.indices(m.g.shape)
        d = ((y - 12) ** 2 + (z - 8) ** 2)
        m._put((x >= X - 3) & (x <= X - 2) & (d <= 12), pal['metal'])
        m._put((x == X - 1) & (d <= 2.2), emblem)
    m.part = 'body'


# ------------------------------------------------------------------ 3 star toppers, by origin

def topper(c, origin, pal):
    m, cx = c.m, c.cx
    z = int(c.top) + (1 if not c.s.horns else 2)
    x, y, zz = np.indices(m.g.shape)
    m.part = 'head'
    if origin in ('Order', 'Dwarven', 'Ember'):
        crown(m, z, cx=cx, cy=11.0, r=3.2, gem=pal['gem'], points=6)
    elif origin == 'Infernal':      # blackened iron crown with tall spikes and ember gems
        crown(m, z, cx=cx, cy=11.0, r=3.4, gold='#2a2024', gem='#ff5a2a', points=5, tall=3)
        m.glow.add('#ff5a2a')
    elif origin == 'Undead':        # bone crown
        crown(m, z, cx=cx, cy=11.0, r=3.2, gold='#e8e2d0', gem='#7dff9b', points=7, tall=2)
    elif origin == 'Frost':         # ice spikes of uneven height
        for k in range(7):
            a = 2 * math.pi * k / 7 + 0.3
            px, py = cx + 3.0 * math.cos(a), 11.0 + 2.6 * math.sin(a)
            h = 2 + (k * 3) % 4
            m.line((px, py, z), (px, py, z + h), '#bff0ff' if k % 2 else '#e6f8ff', r=0.4)
        m.glow |= {'#bff0ff'}
    else:                           # Wild / Fey / Shadow / Arcane: a circlet around the brow with a gem
        band = {'Wild': '#5cc27a', 'Fey': '#ffd6f1', 'Shadow': '#9a8cff', 'Arcane': GILT}[origin]
        lvl = round(c.hz + 3)
        m._put((m.p == PID['head']) & (m.g > 0) & (zz == lvl), band, only='filled')
        m.front(round(cx) - 1, lvl, pal['gem']); m.front(round(cx), lvl, pal['gem'])
        m.front(round(cx) - 1, lvl + 1, pal['gem']); m.front(round(cx), lvl + 1, pal['gem'])
        if origin in ('Wild', 'Fey'):   # leaves / blossoms around the band
            for k in range(8):
                a = 2 * math.pi * k / 8
                px, py = cx + (c.hr[0] + 0.4) * math.cos(a), 11.5 + (c.hr[1] + 0.4) * math.sin(a)
                col = ('#8fe36b' if k % 2 else '#5cc27a') if origin == 'Wild' else ('#ff9ef0' if k % 2 else '#ffffff')
                m.v(math.floor(px + 0.5), math.floor(py + 0.5), lvl + 1, col)
        elif origin == 'Arcane':        # floating rune motes above the head
            for k in range(3):
                a = 2 * math.pi * k / 3
                m.v(math.floor(cx + 3 * math.cos(a) + 0.5), math.floor(11.5 + 2.5 * math.sin(a) + 0.5), z + 2, pal['glow'])
        m.glow.add(pal['gem'])


# ------------------------------------------------------------------ assemble

def build(s: Spec, tier=1):
    m = Model(s.name, s.X, 24, s.Z, seed=s.seed)
    m.style.update(s.style)
    if s.klass == 'Protector':
        m.style['main'] = 'arm_r'
    legs = s.legs or (s.pal['cloth2'] if s.klass in ('Rogue', 'Ranger', 'Bard') else shade(s.fur, 0.75))
    feet = shade(legs, 0.75)
    hands = s.hands or shade(s.fur, 0.9)
    a = biped(m, s.fur, legs=legs, feet=feet, torso=s.fur, arms=s.fur, hands=hands, stout=s.stout,
              head_r=s.head_r)
    c = Ctx(m, a, s)
    if s.head_col:
        m.g[(m.p == PID['head']) & (m.g == m.c(s.fur))] = m.c(s.head_col)
    # belly
    m.part = 'body'
    m.ell(c.cx, 15.0, 9.5, 3.0, 1.5, 3.4, s.light)
    # head features first (patterns paint onto the base fur)
    if s.pattern:
        for pt in (s.pattern if isinstance(s.pattern[0], tuple) else [s.pattern]):
            pattern(c, pt[0], *pt[1:2], **(pt[2] if len(pt) > 2 else {}))
    if s.snout:
        snout(c, s.snout[0], s.fur, s.light, s.dark, **(s.snout[1] if len(s.snout) > 1 else {}))
    eyes(c, s.eyes, s.eye_color)
    if s.ears:
        ears(c, s.ears[0], s.fur, s.dark if len(s.ears) < 3 else s.ears[2], **(s.ears[1] if len(s.ears) > 1 else {}))
    if s.horns:
        horns(c, s.horns[0], s.horns[1], **(s.horns[2] if len(s.horns) > 2 else {}))
    # body dressing
    outfit(c, s.outfit, tier)
    if s.tail:
        cols = [t for t in s.tail[1:] if isinstance(t, str)]
        params = next((t for t in s.tail[1:] if isinstance(t, dict)), {})
        tail(c, s.tail[0], cols[0] if cols else s.fur, cols[1] if len(cols) > 1 else None, **params)
    if s.wings:
        wings(c, s.wings[0], s.wings[1], *(s.wings[2:3]), **(s.wings[3] if len(s.wings) > 3 else {}))
    for ex in s.extras:
        kind = ex[0]
        if kind == 'spikes':
            spikes(c, ex[1], ex[2] if len(ex) > 2 else None)
        elif kind == 'shell':
            shell_back(c, ex[1], ex[2])
        elif kind == 'mane':
            m.part = 'head'
            col = ex[1]
            for zz in range(int(c.hz - 2), int(c.top) + 2):
                m.box(round(c.cx) - 1, round(c.cx), 4, 10, zz, zz, col, keep=True)
            m.box(round(c.cx) - 1, round(c.cx), 9, 15, int(c.top), int(c.top) + 1, col)
        elif kind == 'beard':
            m.part = 'head'
            m.ell(c.cx, c.face_y - 0.5, c.hz - 5.5, 3.0, 1.6, 2.8, ex[1])
        elif kind == 'crest':           # rooster comb / bird crest
            m.part = 'head'
            for i in range(ex[2] if len(ex) > 2 else 4):
                m.box(round(c.cx) - 1, round(c.cx), 9 + i * 2, 10 + i * 2, int(c.top), int(c.top) + 1 + (i % 2), ex[1])
            if len(ex) > 3:             # wattle
                m.box(round(c.cx) - 1, round(c.cx), round(c.face_y), round(c.face_y), int(c.hz - 5), int(c.hz - 4), ex[1])
        elif kind == 'plume':           # peacock / eagle head feathers
            m.part = 'head'
            for dx in (-1, 0, 1):
                m.line((c.cx + dx, 11, c.top), (c.cx + dx * 2.5, 10, c.top + 4), ex[1], r=0.3)
                m.v(round(c.cx + dx * 2.5), 10, int(c.top + 5), ex[2] if len(ex) > 2 else ex[1])
        elif kind == 'whiskers':
            for sgn in (-1, 1):
                for dz in (0, 1):
                    m.part = 'head'
                    m.line((c.cx + sgn * 2.5, c.face_y + 0.5, c.hz - 2.5 + dz), (c.cx + sgn * 6, c.face_y + 0.5, c.hz - 2 + dz * 1.5), ex[1], r=0)
        elif kind == 'scarf':
            m.part = 'body'
            m.ell(c.cx, 11.5, 13.5, 6.8, 5.4, 1.8, ex[1])
        elif kind == 'cape':
            cape(m, ex[1], ex[2] if len(ex) > 2 else s.pal['trim'])
        elif kind == 'chest':           # extra fur on chest (yeti/mammoth)
            m.part = 'body'
            m.ell(c.cx, 14, 10.5, 4.0, 2.0, 3.6, ex[1])
        elif kind == 'neck_ruff':
            m.part = 'body'
            m.ell(c.cx, 11.5, 13.5, 7.6, 6.0, 2.4, ex[1])
        elif kind == 'glow_eyes':
            m.glow.add(ex[1])
        elif kind == 'bones':
            pattern(c, 'bones', ex[1])
        elif kind == 'texture':
            m.texture(ex[1], ex[2], ex[3] if len(ex) > 3 else 0.2)
        elif kind == 'flames':          # flickering voxels on the body (phoenix/infernal)
            m.part = 'body'
            for xx, yy, zz in np.argwhere((m.g > 0) & (m.p == PID['body'])):
                if m.rng.random() < 0.05:
                    m.v(xx, yy, zz + 1, ex[1])
            m.glow.add(ex[1])
        elif kind == 'halo_small':
            pass
        elif callable(kind):
            kind(c, tier)
    # weapons and off-hand
    if s.weapon:
        w = s.weapon
        weapon(c, w[0], tier, w[1] if len(w) > 1 else ('l' if w[0] in ('bow', 'crossbow', 'musket') else 'r'), **(w[2] if len(w) > 2 else {}))
    if s.offhand:
        o = s.offhand
        if o[0] in ('heater', 'round', 'tower', 'buckler'):
            shield(c, o[0], tier, o[1] if len(o) > 1 else None)
        else:
            weapon(c, o[0], tier, 'l', **(o[1] if len(o) > 1 else {}))
    if s.hat:
        hat(c, s.hat[0], tier, s.hat[1] if len(s.hat) > 1 else None)
    # fur texture last so it doesn't break the paint masks above
    m.texture(s.fur, [s.fur2, shade(s.fur, 1.08)], 0.2)
    # ---------------- star upgrades
    pal = s.pal
    if tier >= 2:
        if s.klass in ('Warrior', 'Protector', 'Healer', 'Summoner') and not s.wings:
            cape(m, shade(pal['cloth'], 0.8), GILT)
        m.recolor({pal['trim']: GILT}) if pal['trim'] not in (GILT,) else None
    if tier >= 3:
        # crown or circlet on top unless a hat already sits there
        if not s.hat or s.hat[0] in ('headband', 'circlet'):
            topper(c, s.origin, pal)
        else:
            m.part = 'head'
            m.v(round(c.cx), 15, int(c.top) + 1, pal['gem'])
        m.recolor({pal['metal']: GILT, pal['metal_d']: GILT_D, pal['metal_l']: GILT_L,
                   BLADE: mix(pal['glow'], '#ffffff', 0.55), BLADE_D: pal['glow']})
        m.glow |= {mix(pal['glow'], '#ffffff', 0.55), pal['glow']}
        m.recolor({pal['cloth']: shade(pal['cloth'], 0.78)})
    return finish(m, tier)
