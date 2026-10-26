"""Ten fantasy-animal autochess units as rigged chibi voxel models, with 1-3 star tiers and a secret 4 star.

Each builder takes a tier (1-4). Tier 4 is the tier-3 model transformed into an "astral" spirit form.
Bones: root, body, head, arm_r, arm_l, leg_r, leg_l, tail (+ dragon wings/legs, + aura on 4 star).
"_r" is the character's right hand side (low x, viewer's left).
"""
import math
import os
import sys
import json

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from vox import Model, PID

BLACK = '#1b1519'
WHITE = '#ffffff'
STEEL = '#c3ccd6'
STEEL_D = '#7f8b99'
STEEL_L = '#e8eef4'
BLADE = '#dfe6ee'
BLADE_D = '#a4b2c2'
GOLD = '#f2c14e'
GOLD_D = '#c48f2a'
GILT = '#ffd75e'
GILT_D = '#d9a33a'
GILT_L = '#fff0b3'
WOOD = '#8b5a2b'
WOOD_D = '#64401f'
LEATHER = '#7a5233'
LEATHER_D = '#52361f'
RUBY = '#e0303a'
SAPPHIRE = '#3b8cff'
EMERALD = '#2fd07a'

# per-tier scale for in-game size (baked into the glb)
TIER_SCALE = {1: 1.0, 2: 1.12, 3: 1.24, 4: 1.32}
if __import__("os").environ.get("UNIFORM_SCALE"):
    TIER_SCALE = {1: 1.0, 2: 1.0, 3: 1.0, 4: 1.0}   # the game scales by star itself (Unit.STAR_SIZE)


def eye(m, x0, ztop, pat, cmap):
    """Paint an eye pattern (rows top->bottom) on the head front, left eye at x0, right eye mirrored position."""
    w = len(pat[0])
    xr = m.X - 1 - x0 - (w - 1)
    for r, row in enumerate(pat):
        for c, ch in enumerate(row):
            if ch == '.':
                continue
            m.front(x0 + c, ztop - r, cmap[ch])
            m.front(xr + c, ztop - r, cmap[ch])


def biped(m, fur, legs=None, feet=None, torso=None, arms=None, hands=None,
          head_c=(19.5,), head_r=(7.5, 6.5, 6.5), torso_r=(5.5, 4.2, 5.0), stout=0):
    """Shared chibi body: short legs, round torso, big head. Sets bones + pivots."""
    cx, cy = m.cx, 11.5
    legs = legs or fur
    feet = feet or legs
    torso = torso or fur
    arms = arms or torso
    hands = hands or fur
    lx = (8 - stout, 10)
    X = m.X
    m.part = 'leg_r'
    m.box(lx[0], lx[1], 10, 12, 0, 4, legs)
    m.box(lx[0], lx[1], 10, 14, 0, 1, feet)
    m.part = 'leg_l'
    m.box(X - 1 - lx[1], X - 1 - lx[0], 10, 12, 0, 4, legs)
    m.box(X - 1 - lx[1], X - 1 - lx[0], 10, 14, 0, 1, feet)
    rx, ry, rz = torso_r
    m.part = 'body'
    m.ell(cx, cy, 8.5, rx + stout, ry, rz, torso)
    ax = cx - rx - 1.0 - stout
    m.part = 'arm_r'
    m.ell(ax, cy, 9, 1.8, 1.8, 3.5, arms)
    m.ell(ax, cy + 1.5, 6, 1.6, 1.6, 1.6, hands)
    m.part = 'arm_l'
    m.ell(X - 1 - ax, cy, 9, 1.8, 1.8, 3.5, arms)
    m.ell(X - 1 - ax, cy + 1.5, 6, 1.6, 1.6, 1.6, hands)
    hz = head_c[0]
    m.part = 'head'
    m.ell(cx, cy, hz, *head_r, fur)
    m.part = 'body'
    m.pivots.update({
        'root': (cx, cy, 0),
        'body': (cx, cy, 4.5),
        'head': (cx, cy, hz - head_r[2] + 0.5),
        'leg_r': ((lx[0] + lx[1] + 1) / 2, cy, 4.5),
        'leg_l': (X - (lx[0] + lx[1] + 1) / 2, cy, 4.5),
        'arm_r': (ax + 0.5, cy + 0.5, 12),
        'arm_l': (X - 1 - ax + 0.5, cy + 0.5, 12),
        'weapon_r': (ax + 0.5, cy + 2.0, 6.5),
        'weapon_l': (X - 1 - ax + 0.5, cy + 2.0, 6.5),
        'tail': (cx, cy - 4, 4.5),   # default; builders with a tail override it
    })
    return dict(cx=cx, cy=cy, hz=hz, head_top=hz + head_r[2],
                hand_r=(ax, cy + 1.5, 6), hand_l=(X - 1 - ax, cy + 1.5, 6))


def crown(m, z, cx=None, cy=11.5, r=3.4, gold=GILT, gem=RUBY, points=8, tall=2):
    """Gold crown sitting with its base at height z, on the head bone."""
    cx = m.cx if cx is None else cx
    prev, m.part = m.part, 'head'
    x, y, zz = np.indices(m.g.shape)
    rr = ((x + 0.5 - cx - 0.5) / r) ** 2 + ((y - cy) / (r * 0.9)) ** 2
    ring = (rr <= 1.0) & (rr >= 0.35) & (zz >= z) & (zz <= z + 1)
    m._put(ring, gold)
    for k in range(points):
        a = 2 * math.pi * k / points + math.pi / 2
        px, py = cx + r * 0.9 * math.cos(a), cy + r * 0.8 * math.sin(a)
        for h in range(tall):
            m.v(round(px), round(py), z + 2 + h, gold if h < tall - 1 else GILT_L)
    m.front(round(cx), z, gem) if False else None
    m.v(round(cx), round(cy + r * 0.85), z, gem)
    m.v(round(cx), round(cy + r * 0.85), z + 1, gem)
    m.part = prev


def cape(m, col, trim, x0=7, x1=18, y=5, z0=3, z1=13):
    prev, m.part = m.part, 'body'
    m.box(x0, x1, y, y + 1, z0, z1, col)
    m.box(x0 + 1, x1 - 1, y, y, z0 - 1, z0 - 1, col)
    m.box(x0, x1, y, y, z0, z0, trim)
    m.box(x0 + 1, x1 - 1, y, y, z0 - 1, z0 - 1, trim)
    m.part = prev


def back_wings(m, feather='#f7f7fb', shade='#d8dcea', z=8, y=5, span=7):
    """Small feathered wings on the back (body bone)."""
    prev, m.part = m.part, 'body'
    cx = m.cx
    for sgn in (-1, 1):
        for i in range(span):
            xx = cx + sgn * (3 + i)
            h0 = z + i // 2
            h1 = z + 6 + (i if i < 4 else 7 - i)
            for zz in range(int(h0), int(h1) + 1):
                m.v(round(xx), y, zz, feather if (zz - h0) % 3 else shade)
            m.v(round(xx), y - 1, int(h1), shade)
    m.part = prev


def finish(m, tier):
    m.style['tier'] = tier
    m.close_grip('l')
    m.close_grip('r')
    if tier == 4:
        m.grow(4, 4, 6)
        m.astral()
    m.compact()
    return m


# ---------------------------------------------------------------- Knight: Lion
def knight(tier=1):
    m = Model('knight_lion', 26, 24, 34, seed=11)
    m.style.update(attack='slash', skill='spin', weapon='sword')
    fur, fur2, fur3 = '#e2a843', '#cf9132', '#ecbb5c'
    mane, mane2 = '#a24c1b', '#bf5f24'
    blue = '#2f63b8'
    cx = m.cx
    m.part = 'head'
    m.ell(cx, 10.5, 19.5, 9.5, 6.5, 8.5, mane)
    a = biped(m, fur, legs=STEEL, feet=STEEL_D, torso=STEEL, arms=STEEL, hands=fur)
    for x in range(9, 17):
        for z in range(3, 12):
            m.front(x, z, blue)
    for z in range(3, 12):
        m.front(9, z, GOLD); m.front(16, z, GOLD)
    for x in range(9, 17):
        m.front(x, 3, GOLD)
    for dz, w in ((9, 0), (8, 1), (7, 1), (6, 0)):
        for x in range(12 - w, 14 + w):
            m.front(x, dz, GOLD)
    for x in range(9, 17):
        m.front(x, 7, LEATHER_D)
    m.front(12, 7, GOLD); m.front(13, 7, GOLD)
    m.part = 'arm_r'
    m.ell(6.5, 11.5, 12.5, 2.8, 2.8, 2.0, STEEL_L)
    m.part = 'arm_l'
    m.ell(m.X - 7.5, 11.5, 12.5, 2.8, 2.8, 2.0, STEEL_L)
    m.ell(6.5, 11.5, 12.0, 2.8, 2.8, 1.0, STEEL_D, only='filled')
    m.ell(m.X - 7.5, 11.5, 12.0, 2.8, 2.8, 1.0, STEEL_D, only='filled')
    m.part = 'head'
    x, y, z = np.indices(m.g.shape)
    e = ((x - cx) / 9.5) ** 2 + ((z - 19.5) / 8.5) ** 2
    m._put((e >= 0.55) & (e <= 1.0) & (y >= 10) & (y <= 15) & (m.g == 0), mane)
    m.ell(7.5, 12, 26.3, 1.6, 1.2, 1.6, fur)
    m.ell(m.X - 8.5, 12, 26.3, 1.6, 1.2, 1.6, fur)
    m.v(7, 13, 26, '#f0b9a0'); m.v(m.X - 8, 13, 26, '#f0b9a0')
    m.ell(cx, 17.2, 16.6, 3.2, 2.0, 2.0, '#f6deaa')
    m.box(12, 13, 19, 19, 17, 18, '#5a2e1c')
    m.box(12, 13, 19, 19, 16, 16, '#5a2e1c', only='filled')
    eye(m, 8, 21, ['wk', 'kk', 'kk'], {'w': WHITE, 'k': BLACK})
    m.front(9, 22, mane2); m.front(8, 22, mane2)
    m.front(m.X - 10, 22, mane2); m.front(m.X - 9, 22, mane2)
    # sword
    m.part = 'weapon_r'
    hx, hy, hz = a['hand_r']
    sx, sy = int(round(hx)), int(round(hy)) + 2
    blade_top = 22 if tier == 1 else 25
    m.box(sx, sx, sy, sy, 3, 7, WOOD_D)
    m.v(sx, sy, 2, GOLD)
    m.box(sx - 2, sx + 2, sy, sy, 8, 8, GOLD)
    m.box(sx, sx, sy - 1, sy + 1, 8, 8, GOLD)
    m.box(sx, sx, sy - 1, sy, 9, blade_top, BLADE)
    m.box(sx, sx, sy - 1, sy - 1, 9, blade_top - 1, BLADE_D)
    m.v(sx, sy, blade_top + 1, BLADE)
    if tier >= 2:
        m.v(sx - 2, sy, 9, GOLD); m.v(sx + 2, sy, 9, GOLD)
        m.v(sx, sy + 1, 8, RUBY)
    # shield
    m.part = 'weapon_l'
    X = m.X
    for z in range(2, 15):
        half = 4 if z > 5 else (z - 1)
        m.box(X - 3, X - 2, 12 - half, 12 + half, z, z, blue)
    m.box(X - 1, X - 1, 8, 16, 14, 14, GOLD)
    for z in range(2, 15):
        half = 4 if z > 5 else (z - 1)
        m.v(X - 1, 12 - half, z, GOLD); m.v(X - 1, 12 + half, z, GOLD)
    for z in (5, 6, 7, 8, 9, 10, 11):
        m.v(X - 1, 12, z, GOLD)
    m.box(X - 1, X - 1, 10, 14, 9, 9, GOLD)
    if tier >= 2:
        m.box(X - 1, X - 1, 11, 13, 8, 10, STEEL_L)
        m.v(X - 1, 12, 9, RUBY)
        cape(m, '#a8242f', GOLD)
    m.texture(fur, [fur2, fur3], 0.18)
    m.texture(mane, [mane2, '#823914'], 0.3)
    if tier >= 3:
        crown(m, 28, cy=10.5, r=3.6)
        m.recolor({STEEL: GILT, STEEL_D: GILT_D, STEEL_L: GILT_L, '#a8242f': '#5b2a91',
                   blue: '#f4f1e8', GOLD: '#3d6fd9'})
        m.recolor({BLADE: '#bdf3ff', BLADE_D: '#7fdcff'})
        m.glow |= {'#bdf3ff', '#7fdcff'}
    return finish(m, tier)


# ---------------------------------------------------------------- Archer: Fox
def archer(tier=1):
    m = Model('archer_fox', 26, 24, 34, seed=12)
    m.style.update(attack='shoot', skill='volley', weapon='bow', main='arm_l')
    fur, fur2, fur3 = '#e8792f', '#d46a24', '#f08c45'
    cream = '#f7efe3'
    green, green_d, green_l = '#3f7d46', '#2c5c33', '#4f9657'
    string = '#ece4cc'
    cx = m.cx
    m.part = 'body'
    m.box(7, 18, 6, 7, 3, 13, green_d)
    m.box(8, 17, 6, 6, 2, 2, green_d)
    a = biped(m, fur, legs='#3a2a24', feet='#2a1e1a', torso=green, arms=green, hands='#3a2a24')
    m.ell(cx, 15, 10.5, 2.6, 1.5, 2.5, cream)
    for x in range(7, 19):
        m.front(x, 6, LEATHER)
    m.front(12, 6, GOLD); m.front(13, 6, GOLD)
    for i in range(9):
        if 4 + i <= 12:
            m.front(8 + i, 4 + i, LEATHER_D)
    m.ell(cx, 11, 13.5, 7.2, 5.5, 2.2, green_l)
    m.part = 'head'
    x, y, z = np.indices(m.g.shape)
    m._put((z <= 18) & (m.g == m.c(fur)) & (y >= 14) & (m.p == PID['head']), cream)
    m.ell(cx, 18.5, 16.8, 2.4, 2.8, 1.8, cream)
    m.box(12, 13, 21, 21, 17, 17, BLACK)
    for side in (0, 1):
        for i, (w0, w1) in enumerate([(6, 10), (6, 10), (6, 9), (7, 9), (7, 8), (7, 8)]):
            zz = 25 + i
            xa, xb = (w0, w1) if side == 0 else (m.X - 1 - w1, m.X - 1 - w0)
            m.box(xa, xb, 10, 12, zz, zz, fur)
        for i, (w0, w1) in enumerate([(7, 9), (7, 9), (7, 8)]):
            zz = 25 + i
            xa, xb = (w0, w1) if side == 0 else (m.X - 1 - w1, m.X - 1 - w0)
            m.box(xa, xb, 12, 12, zz, zz, '#3b2520')
        tip = (7, 8) if side == 0 else (m.X - 9, m.X - 8)
        m.box(tip[0], tip[1], 10, 12, 30, 30, '#3b2520')
    eye(m, 8, 21, ['wk', 'kk', 'kk'], {'w': WHITE, 'k': BLACK})
    m.part = 'tail'
    m.ell(15.5, 4.5, 5.5, 3.2, 3.8, 3.2, fur)
    m.ell(17, 2.5, 8.5, 2.6, 2.6, 2.6, fur)
    m.ell(18, 1.8, 10.5, 2.0, 2.0, 2.0, cream)
    m.pivots['tail'] = (14.5, 7, 5)
    m.part = 'body'
    m.line((8.5, 5, 8), (15.5, 5, 17), LEATHER, r=1.0)
    for dx in (0, 1, 2):
        m.line((15 + dx * 0.6, 5, 18), (16 + dx, 5, 21), WOOD, r=0)
        m.v(16 + dx, 5, 22, '#d9473a'); m.v(16 + dx, 4, 22, '#f2f0e6')
    if tier >= 2:
        for dx in (-1, 3):
            m.line((15 + dx * 0.6, 5, 18), (16 + dx, 5, 21), WOOD, r=0)
            m.v(16 + dx, 5, 22, '#d9473a'); m.v(16 + dx, 4, 22, '#f2f0e6')
        for x_ in range(7, 19):
            m.front(x_, 6, GOLD_D)
    # bow
    m.part = 'weapon_l'
    X = m.X
    bx = X - 3
    span = (1, 19) if tier == 1 else (0, 21)
    L = span[1] - span[0]
    for zz in range(span[0], span[1] + 1):
        t = (zz - span[0]) / L
        yy = 13 + int(round(3.4 * math.sin(math.pi * t)))
        m.v(bx, yy, zz, WOOD)
        if 0.38 < t < 0.62:
            m.v(bx, yy, zz, LEATHER_D)
    for zz in range(span[0] + 1, span[1]):
        m.v(bx, 13, zz, string)
    m.v(bx, 13, span[0], WOOD); m.v(bx, 13, span[1], WOOD)
    if tier >= 2:
        for zz in (span[0], span[0] + 1, span[1], span[1] - 1):
            m.v(bx, 13, zz, GOLD)
            m.v(bx, 14, zz, GOLD)
    m.texture(fur, [fur2, fur3], 0.2)
    m.texture(green, [green_l], 0.12)
    if tier >= 2:
        m.recolor({green_d: '#1f4a3a', green: '#2f6b4f', green_l: '#3c8462'})
    if tier >= 3:
        # leaf circlet
        m.part = 'head'
        for k in range(-5, 6):
            xx = round(cx + k)
            zz = 25 - (1 if abs(k) > 3 else 0)
            m.front(xx, zz, '#7fc94f' if k % 2 else GILT)
        m.v(round(cx), 18, 26, EMERALD); m.v(round(cx) + 1, 18, 26, EMERALD)
        m.recolor({'#1f4a3a': '#e9eef2', '#2f6b4f': '#f7f8fa', '#3c8462': '#dfe6ec',
                   string: '#aef7ff', GOLD_D: GILT, WOOD: '#c98b3c'})
        m.glow |= {'#aef7ff'}
        m.v(bx, 12, 10, EMERALD)
    return finish(m, tier)


# ---------------------------------------------------------------- Cleric: Sheep
def cleric(tier=1):
    m = Model('cleric_sheep', 26, 24, 34, seed=13)
    m.style.update(attack='cast', skill='heal', weapon='staff')
    wool, wool2, wool3 = '#f3ede0', '#e2d9c6', '#fbf8f0'
    face = '#4a3d3e'
    robe, robe_d = '#f4f6fb', '#d6dbe8'
    trim = GOLD
    core = '#fff4b0'
    cx = m.cx
    a = biped(m, wool, legs=face, feet='#2e2627', torso=robe, arms=wool, hands=face)
    m.part = 'body'
    for zz in range(0, 9):
        r = 6.2 - zz * 0.25
        m.cyl(cx, 11.5, zz, zz, r, robe, ry=r * 0.85, keep=True)
    # robe skirt belongs to body; legs show only as feet
    sk = (m.p == PID['body'])
    m.cyl(cx, 11.5, 0, 0, 6.2, trim, ry=6.2 * 0.85, only=robe)
    for zz in range(1, 12):
        m.front(12, zz, trim); m.front(13, zz, trim)
    m.texture(robe, [robe_d], 0.08)
    m.ell(cx, 11.5, 12.5, 7.2, 5.6, 2.4, wool)
    m.part = 'head'
    m.ell(cx, 11.5, 20, 7.8, 6.6, 6.8, wool)
    m.ell(cx, 15.8, 18.2, 4.6, 3.0, 4.6, face)
    m.ell(cx, 12.5, 25.5, 5.5, 4.5, 2.6, wool)
    rng = m.rng
    W = m.c(wool)
    for x, y, z in np.argwhere(m.g == W):
        if rng.random() < 0.12:
            for dx, dy, dz in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1)):
                xx, yy, zz = x + dx, y + dy, z + dz
                if 0 <= xx < m.X and 0 <= yy < m.Y and 0 <= zz < m.Z and m.g[xx, yy, zz] == 0 and yy < 17:
                    m.g[xx, yy, zz] = m.c(wool2); m.p[xx, yy, zz] = m.p[x, y, z]
                    break
    m.texture(wool, [wool2, wool3], 0.25)
    m.box(2, 5, 12, 13, 19, 20, face)
    m.box(m.X - 6, m.X - 3, 12, 13, 19, 20, face)
    m.ell(5.5, 10.5, 22, 1.6, 1.8, 1.8, '#c9a77a')
    m.ell(m.X - 6.5, 10.5, 22, 1.6, 1.8, 1.8, '#c9a77a')
    m.v(5, 12, 22, '#a8865a'); m.v(m.X - 6, 12, 22, '#a8865a')
    eye(m, 9, 20, ['ww', 'wk'], {'w': '#fffdf5', 'k': BLACK})
    m.front(12, 16, '#d48a96'); m.front(13, 16, '#d48a96')
    m.front(12, 10, GOLD); m.front(13, 10, GOLD); m.front(12, 9, GOLD); m.front(13, 9, GOLD)
    # staff
    m.part = 'weapon_r'
    hx, hy, _ = a['hand_r']
    sx, sy = int(round(hx)), int(round(hy)) + 2
    m.box(sx, sx, sy, sy, 0, 21, WOOD)
    for zz in (5, 6, 7):
        m.v(sx, sy, zz, LEATHER_D)
    cz = 25 if tier == 1 else 26
    R = 3 if tier == 1 else 4
    for ang in range(0, 360, 8):
        m.v(sx + round(R * math.cos(math.radians(ang))), sy, cz + round(R * math.sin(math.radians(ang))), GOLD)
    for d in (-1, 0, 1):
        m.v(sx + d, sy, cz, core); m.v(sx, sy, cz + d, core)
    m.v(sx, sy, cz, WHITE)
    for xx, zz in ((sx, cz + R + 1), (sx, cz - R - 1), (sx + R + 1, cz), (sx - R - 1, cz)):
        m.v(xx, sy, zz, GOLD_D)
    m.box(sx, sx, sy, sy, 21, cz - R, GOLD)
    m.glow |= {core}
    if tier >= 2:
        # blue stole over the robe
        m.part = 'body'
        for zz in range(3, 12):
            m.front(10, zz, '#4f86d9'); m.front(15, zz, '#4f86d9')
        m.front(10, 2, GOLD); m.front(15, 2, GOLD)
        for d in (-2, 2):
            m.v(sx + d, sy, cz + d, core); m.v(sx - d, sy, cz + d, core)
    if tier >= 3:
        back_wings(m, z=7, y=6)
        m.recolor({robe_d: '#f3e3b0', '#4f86d9': '#e8b923', GOLD: GILT})
        m.recolor({core: '#fffbd8'})
        m.glow |= {'#fffbd8', GILT_L}
        m.part = 'head'
        for k in (-2, -1, 0, 1, 2):
            m.front(round(cx) + k, 24, GILT)
        m.v(round(cx), 18, 24, SAPPHIRE)
    return finish(m, tier)


# ---------------------------------------------------------------- Guardian: Tortoise
def guardian(tier=1):
    m = Model('guardian_tortoise', 26, 24, 34, seed=14)
    m.style.update(attack='bash', skill='shieldwall', weapon='mace')
    skin, skin2 = '#7fae4f', '#6c9a40'
    shell, plate, rim = '#7a5230', '#9c6d3c', '#563820'
    belly = '#e5d38e'
    iron, iron_d, iron_l = '#8d9aaa', '#5f6b7a', '#b6c1cd'
    cx = m.cx
    m.part = 'body'
    m.ell(cx, 8.8, 10.5, 8.6, 5.0, 8.0, shell)
    x, y, z = np.indices(m.g.shape)
    seam = ((np.abs(((x - cx) + 0.5) % 5 - 2.5) < 0.6) | (np.abs((z - 1) % 5 - 2.5) < 0.6))
    m._put((m.g == m.c(shell)) & ~seam, plate, only='filled')
    a = biped(m, skin, legs=skin, feet=skin2, torso=belly, arms=skin, hands=skin, stout=1,
              torso_r=(5.8, 4.4, 5.2), head_c=(20.0,), head_r=(6.8, 6.0, 6.0))
    m.ell(cx, 10.5, 8.5, 8.0, 5.2, 7.5, rim, only=shell)
    for xx in range(8, 18):
        m.front(xx, 8, '#c9b56d'); m.front(xx, 5, '#c9b56d')
    for zz in range(4, 13):
        m.front(12, zz, '#c9b56d'); m.front(13, zz, '#c9b56d')
    m.ell(cx, 11.5, 13.5, 6.6, 5.4, 1.6, iron)
    if tier >= 2:  # shell spikes
        for (sx_, sz_) in ((6, 15), (19, 15), (9, 18), (16, 18), (12.5, 19), (5, 9), (20, 9)):
            for d in range(2):
                m.v(round(sx_), 4 - d, sz_, iron_l if d else iron)
    hz = 20.0
    m.part = 'head'
    x, y, z = np.indices(m.g.shape)
    sel = (((x - cx) / 7.3) ** 2 + ((y - 11.5) / 6.5) ** 2 + ((z - hz) / 6.5) ** 2 <= 1) & (z >= 22)
    m._put(sel, iron)
    m.box(4, 21, 5, 18, 22, 22, iron_d, only=iron)
    m.box(12, 13, 9, 15, 27, 28, GOLD)
    m.box(12, 13, 10, 13, 29, 29, GOLD_D)
    if tier >= 2:
        m.box(12, 13, 8, 16, 29, 29, '#c0303a')
        m.box(12, 13, 9, 14, 30, 30, '#c0303a')
    eye(m, 9, 21, ['wk', 'kk'], {'w': WHITE, 'k': BLACK})
    m.front(12, 18, '#4d6e2c'); m.front(13, 18, '#4d6e2c')
    m.front(11, 17, '#4d6e2c'); m.front(14, 17, '#4d6e2c')
    # mace
    m.part = 'weapon_r'
    hx, hy, _ = a['hand_r']
    sx, sy = int(round(hx)), int(round(hy)) + 2
    m.box(sx, sx, sy, sy, 3, 13, WOOD)
    m.ell(sx, sy, 15.5, 2.2 + 0.4 * (tier >= 2), 2.2 + 0.4 * (tier >= 2), 2.2 + 0.4 * (tier >= 2), iron)
    m.v(sx, sy, 18 + (tier >= 2), iron_l); m.v(sx, sy + 3, 15, iron_l); m.v(sx, sy - 3, 15, iron_l)
    m.v(sx - 3, sy, 15, iron_l); m.v(sx + 3, sy, 15, iron_l)
    m.box(sx - 1, sx + 1, sy - 1, sy + 1, 13, 13, GOLD)
    # tower shield
    m.part = 'weapon_l'
    X = m.X
    z1 = 17 if tier == 1 else 19
    m.box(X - 2, X - 1, 5, 19, 1, z1, iron)
    m.box(X - 1, X - 1, 5, 19, 1, 1, GOLD); m.box(X - 1, X - 1, 5, 19, z1, z1, GOLD)
    m.box(X - 1, X - 1, 5, 5, 1, z1, GOLD); m.box(X - 1, X - 1, 19, 19, 1, z1, GOLD)
    emb = '#4e8a3a'
    for zz, (a0, a1) in zip(range(6, 13), [(11, 13), (10, 14), (9, 15), (9, 15), (9, 15), (10, 14), (11, 13)]):
        m.box(X - 1, X - 1, a0, a1, zz, zz, emb)
    m.box(X - 1, X - 1, 12, 12, 6, 12, GOLD_D)
    m.box(X - 1, X - 1, 9, 15, 9, 9, GOLD_D)
    if tier >= 2:
        for zz in (3, 15):
            for yy in (7, 17):
                m.v(X - 1, yy, zz, iron_l)
    m.texture(iron, [iron_l], 0.08)
    m.texture(skin, [skin2], 0.15)
    if tier >= 3:
        m.recolor({iron: GILT, iron_d: GILT_D, iron_l: GILT_L, GOLD: '#3b7f4a', GOLD_D: '#2a6036',
                   emb: '#5cffb0', '#c0303a': '#e9f7ff'})
        m.glow |= {'#5cffb0'}
        m.part = 'body'
        for (sx_, sz_) in ((8, 12), (17, 12), (12.5, 15)):
            m.v(round(sx_), 4, sz_, '#5cffb0')
    return finish(m, tier)


# ---------------------------------------------------------------- Thief: Raccoon
def thief(tier=1):
    m = Model('thief_raccoon', 26, 24, 34, seed=15)
    m.style.update(attack='stab', skill='backstab', weapon='dagger')
    fur, fur2 = '#8f8f97', '#7f7f88'
    light = '#d4d4d8'
    dark = '#2c2a30'
    purple, purple_d = '#5b3f7a', '#432d5c'
    vest = '#5a3d27'
    sack = '#c4a46b'
    cx = m.cx
    a = biped(m, fur, legs=dark, feet='#1f1d22', torso=vest, arms=fur, hands=dark)
    m.ell(cx, 15, 9.5, 2.6, 1.5, 3.2, light)
    for x in range(7, 19):
        m.front(x, 6, LEATHER_D)
    m.front(12, 6, '#bfc6cf'); m.front(13, 6, '#bfc6cf')
    m.ell(cx, 11.5, 13.5, 6.8, 5.4, 1.8, purple)
    m.line((15, 6, 13), (18, 4, 10), purple_d, r=0.6)
    if tier >= 3:
        cape(m, purple_d, GILT, x0=8, x1=17, y=6, z0=4, z1=12)
    m.part = 'head'
    m.ell(7.3, 11.5, 25.5, 1.8, 1.3, 1.8, fur)
    m.ell(m.X - 8.3, 11.5, 25.5, 1.8, 1.3, 1.8, fur)
    m.v(7, 13, 25, light); m.v(m.X - 8, 13, 25, light)
    x, y, z = np.indices(m.g.shape)
    F = m.c(fur)
    H = (m.p == PID['head'])
    m._put((m.g == F) & H & (z <= 18) & (y >= 13), light, only='filled')
    m._put((m.g == F) & H & (z >= 19) & (z <= 21) & (y >= 14), dark, only='filled')
    m._put((m.g == F) & H & (z == 22) & (y >= 15) & ((x <= 11) | (x >= 14)), dark, only='filled')
    m.ell(cx, 17.4, 16.7, 2.6, 1.6, 1.7, light)
    m.box(12, 13, 19, 19, 17, 17, BLACK)
    eye(m, 8, 21, ['wk', 'kk'], {'w': WHITE, 'k': '#0c0a0e'})
    eye(m, 8, 19, ['ll'], {'l': '#3e3b44'})
    m.part = 'tail'
    pts = [(15, 5, 4), (17, 3, 6), (18.5, 2, 9), (19, 2, 12)]
    for i, (px, py, pz) in enumerate(pts):
        m.ell(px, py, pz, 2.4, 2.4, 2.0, fur if i % 2 == 0 else dark)
    m.ell(19, 2, 14, 1.6, 1.6, 1.4, dark)
    m.pivots['tail'] = (14, 7, 4.5)

    def dagger(hand, gold=False, longer=0):
        hx, hy, _ = hand
        sx, sy = int(round(hx)), int(round(hy)) + 1
        m.box(sx, sx, sy, sy + 1, 6, 6, WOOD_D)
        m.box(sx, sx, sy + 2, sy + 2, 5, 7, GILT if gold else GOLD)
        m.box(sx, sx, sy + 3, sy + 7 + longer, 6, 6, BLADE)
        m.box(sx, sx, sy + 3, sy + 6 + longer, 7, 7, BLADE_D)
    m.part = 'weapon_r'
    dagger(a['hand_r'], longer=1 if tier >= 2 else 0)
    m.part = 'body'
    sz = 1.0 if tier == 1 else 1.25
    m.ell(m.X - 6, 6.5, 13.5, 3.2 * sz, 3.0 * sz, 3.5 * sz, sack)
    m.texture(sack, ['#b0915a'], 0.25)
    m.box(m.X - 7, m.X - 5, 6, 7, 17 + (tier >= 2), 17 + (tier >= 2), '#7a5c32')
    top = 18 + (tier >= 2)
    for dx, dy in ((0, 0), (-1, 1), (1, 0), (0, -1)):
        m.v(m.X - 6 + dx, 6 + dy, top, GOLD)
    if tier >= 2:
        m.v(m.X - 6, 6, top + 1, GOLD); m.v(m.X - 5, 7, top, RUBY)
        m.part = 'weapon_l'
        dagger(a['hand_l'])
    m.part = 'body'
    m.line((m.X - 6, 9, 15), (m.X - 8, 12, 13), LEATHER_D, r=0.4)
    m.texture(fur, [fur2], 0.2)
    if tier >= 3:
        # stolen crown, worn askew
        m.part = 'head'
        cr = (8.5, 11.5, 26)
        for k in range(-3, 4):
            m.v(round(cr[0] + k), 12 + (k % 2), cr[2] + (k + 3) // 3, GILT)
            m.v(round(cr[0] + k), 11, cr[2] + (k + 3) // 3, GILT)
        for k in (-3, 0, 3):
            m.v(round(cr[0] + k), 12, cr[2] + (k + 3) // 3 + 1, GILT_L)
        m.v(round(cr[0]), 13, cr[2] + 1, RUBY)
        m.recolor({BLADE: '#ffe36b', BLADE_D: GILT_D, purple: '#2f2a57', sack: '#d8b874'})
        m.glow |= {'#ffe36b'}
    return finish(m, tier)


# ---------------------------------------------------------------- Mage: Owl
def mage(tier=1):
    m = Model('mage_owl', 26, 24, 40, seed=16)
    m.style.update(attack='cast', skill='meteor', weapon='staff', main='arm_l')
    feather, feather2 = '#8a5d3b', '#7a5032'
    light = '#ead7b6'
    belly = '#f1e4c9'
    blue, blue_d = '#3f4fb6', '#2c3784'
    crystal, crystal_l = '#6fd9ff', '#e8fbff'
    cx = m.cx
    a = biped(m, feather, legs='#e3a63a', feet='#c88a22', torso=blue, arms=feather, hands=feather,
              head_r=(7.6, 6.6, 6.4))
    m.part = 'body'
    for zz in range(0, 8):
        r = 6.0 - zz * 0.2
        m.cyl(cx, 11.5, zz + 1, zz + 1, r, blue, ry=r * 0.85, keep=True)
    m.cyl(cx, 11.5, 1, 1, 6.0, GOLD, ry=5.1, only=blue)
    m.ell(cx, 15.0, 10, 2.8, 1.5, 3.0, belly)
    for xx, zz in ((12, 11), (13, 11), (11, 9), (14, 9), (12, 8), (13, 8)):
        m.front(xx, zz, '#b98d5a')
    m.texture(blue, [blue_d], 0.08)
    m.part = 'arm_r'
    m.ell(5.5, 11.5, 9.5, 2.0, 2.4, 4.0, feather)
    m.part = 'arm_l'
    m.ell(m.X - 6.5, 11.5, 9.5, 2.0, 2.4, 4.0, feather)
    m.part = 'head'
    m.ell(cx, 15.8, 19.2, 6.0, 2.6, 5.0, light)
    eye(m, 8, 21, ['ooo', 'okw', 'okk'], {'o': '#f2a13a', 'k': BLACK, 'w': WHITE})
    for xx in (8, 9, 10):
        m.front(xx, 22, '#f2a13a'); m.front(m.X - 1 - xx, 22, '#f2a13a')
    eye(m, 8, 23, ['.kk'], {'k': feather2})
    m.box(12, 13, 19, 20, 18, 18, '#e3b23c')
    m.box(12, 13, 19, 19, 17, 17, '#c99520')
    m.front(12, 16, '#c99520'); m.front(13, 16, '#c99520')
    m.box(5, 7, 11, 12, 25, 27, feather2)
    m.box(m.X - 8, m.X - 6, 11, 12, 25, 27, feather2)
    hz0 = 25
    hat_h = 11 if tier == 1 else 13
    m.cyl(cx, 11.5, hz0, hz0, 9.0, blue, ry=8.0)
    m.cyl(cx, 11.5, hz0 + 1, hz0 + 1, 5.6, GOLD, ry=5.0)
    for i, zz in enumerate(range(hz0 + 2, hz0 + hat_h)):
        r = 5.3 - i * (5.0 / hat_h)
        off = 0 if i < 4 else (i - 3) * 0.7
        m.cyl(cx + off, 11.5 - off * 0.3, zz, zz, max(r, 0.6), blue, ry=max(r * 0.9, 0.6))
    m.cyl(cx, 11.5, hz0, hz0, 9.0, blue_d, ry=8.0, only=blue)
    m.cyl(cx, 11.5, hz0, hz0, 7.0, blue, ry=6.2, only=blue_d)
    star = '#ffd34d'
    for xx, zz in ((12, 30), (13, 30), (12, 29), (13, 29), (11, 29), (14, 29), (12, 31), (12, 28), (13, 28)):
        m.front(xx, zz, star)
    if tier >= 2:
        for xx, zz in ((9, 27), (16, 32), (10, 33), (15, 27)):
            m.front(xx, zz, star)
    m.texture(feather, [feather2, '#9b6b46'], 0.25)
    # staff
    m.part = 'weapon_l'
    hx, hy, _ = a['hand_l']
    sx, sy = int(round(hx)) + 1, int(round(hy)) + 2
    top = 22 if tier == 1 else 24
    m.box(sx, sx, sy, sy, 0, top, WOOD)
    m.v(sx - 1, sy, top, WOOD); m.v(sx + 1, sy, top, WOOD); m.v(sx - 1, sy, top + 1, WOOD); m.v(sx + 1, sy, top + 1, WOOD)
    cr = 1.4 if tier == 1 else 1.9
    m.ell(sx, sy, top + 3, cr, cr, 2.4 + 0.6 * (tier >= 2), crystal)
    m.v(sx, sy, top + 3, crystal_l); m.v(sx, sy + 1, top + 4, crystal_l)
    m.glow |= {crystal, crystal_l}
    if tier >= 2:
        m.recolor({blue: '#5a3aa8', blue_d: '#3f2780'})
        crystal2, crystal2_l = '#d77bff', '#f6e3ff'
        m.recolor({crystal: crystal2, crystal_l: crystal2_l})
        m.glow = (m.glow - {crystal, crystal_l}) | {crystal2, crystal2_l}
    if tier >= 3:
        m.recolor({'#5a3aa8': '#1d2266', '#3f2780': '#141748', GOLD: GILT, star: '#fff2a0',
                   WOOD: '#e9e2d0'})
        m.glow |= {'#fff2a0'}
        # floating crystal shards over the hat brim
        m.part = 'head'
        for (dx, dz) in ((-8, 27), (8, 28)):
            m.v(round(cx + dx), 11, dz, '#d77bff'); m.v(round(cx + dx), 11, dz + 1, '#f6e3ff')
    return finish(m, tier)


# ---------------------------------------------------------------- Assassin: Black cat
def assassin(tier=1):
    m = Model('assassin_cat', 26, 24, 34, seed=17)
    m.style.update(attack='dual', skill='shadowstep', weapon='daggers')
    fur, fur2 = '#2a2630', '#36313e'
    red, red_d, red_l = '#b4283b', '#7f1b2a', '#cf3b4e'
    eyec = '#7be36b'
    cx = m.cx
    m.part = 'head'
    m.ell(cx, 10.8, 20.2, 8.3, 6.6, 7.4, red)
    a = biped(m, fur, legs=fur, feet='#1d1a22', torso='#3a2c33', arms=fur, hands=fur)
    x, y, z = np.indices(m.g.shape)
    m.part = 'head'
    m._put((m.g == m.c(red)) & (y >= 15) & (z <= 24) & (np.abs(x - cx) < 6.5), fur)
    for side in (0, 1):
        for i, (w0, w1) in enumerate([(6, 9), (6, 9), (6, 8), (7, 8)]):
            zz = 26 + i
            xa, xb = (w0, w1) if side == 0 else (m.X - 1 - w1, m.X - 1 - w0)
            m.box(xa, xb, 11, 12, zz, zz, fur)
        p = (7, 8) if side == 0 else (m.X - 9, m.X - 8)
        m.box(p[0], p[1], 12, 12, 26, 27, '#d77b8b')
    m._put(((m.g == m.c(fur)) & (m.p == PID['head']) & (z <= 18) & (z >= 14) & (y >= 14)), red_d, only='filled')
    eye(m, 8, 21, ['ggg', 'gkg'], {'g': eyec, 'k': BLACK})
    eye(m, 8, 22, ['.kk'], {'k': '#151217'})
    m.part = 'body'
    m.ell(cx, 11.5, 13.5, 6.8, 5.4, 1.8, red)
    m.line((15, 6, 13), (19, 2, 11), red_l, r=0.7)
    m.line((14, 6, 12), (17, 2, 8), red, r=0.7)
    for i in range(8):
        m.front(8 + i, 11 - i, red_d)
    for xx in range(7, 19):
        m.front(xx, 6, LEATHER_D)
    if tier >= 2:  # katana on the back
        m.line((7, 6, 4), (17, 6, 18), '#1a1620', r=0.4)
        m.line((13, 5, 13), (17, 5, 18), BLADE, r=0)
        m.box(12, 13, 5, 6, 12, 12, GOLD)
    m.part = 'tail'
    m.line((12.5, 6, 4), (12.5, 2, 6), fur, r=1.0)
    m.line((12.5, 2, 6), (13.5, 1, 11), fur, r=1.0)
    m.line((13.5, 1, 11), (15.5, 2, 13), fur, r=0.9)
    m.box(12, 13, 1, 2, 8, 8, red)
    m.pivots['tail'] = (12.5, 7, 4.5)
    blade, blade_d = BLADE, BLADE_D
    for part, hand in (('weapon_r', a['hand_r']), ('weapon_l', a['hand_l'])):
        m.part = part
        hx, hy, hz = hand
        sx, sy = int(round(hx)), int(round(hy)) + 1
        m.box(sx, sx, sy, sy, 6, 7, '#3a2c2a')
        m.v(sx, sy + 1, 5, GOLD_D)
        seg = ((2, 5), (3, 4), (4, 4), (5, 3), (6, 3)) + (((7, 2),) if tier >= 2 else ())
        for i, (dy, dz) in enumerate(seg):
            m.v(sx, sy + dy, dz, blade)
            if i < 3:
                m.v(sx, sy + dy, dz + 1, blade_d)
    m.texture(fur, [fur2], 0.18)
    m.texture(red, [red_l], 0.1)
    if tier >= 2:
        m.recolor({red: '#8e1f33', red_l: '#a8273c', red_d: '#5e1422'})
    if tier >= 3:
        m.recolor({'#8e1f33': '#3a2266', '#a8273c': '#4b2d80', '#5e1422': '#26164a',
                   eyec: '#e05cff', BLADE: '#e8a8ff', BLADE_D: '#b45cff', GOLD_D: GILT, GOLD: GILT})
        m.glow |= {'#e05cff', '#e8a8ff', '#b45cff'}
    return finish(m, tier)


# ---------------------------------------------------------------- Hunter: Wolf
def hunter(tier=1):
    m = Model('hunter_wolf', 26, 24, 36, seed=18)
    m.style.update(attack='thrust', skill='pounce', weapon='spear')
    fur, fur2 = '#7f8696', '#6d7484'
    light = '#d0d4dc'
    cloak, cloak2 = '#6b4f3a', '#7d5d44'
    cx = m.cx
    m.part = 'body'
    m.box(7, 18, 6, 7, 3, 13, cloak)
    a = biped(m, fur, legs=LEATHER_D, feet='#3b2716', torso=LEATHER, arms=fur, hands='#4c5260')
    m.part = 'body'
    m.ell(cx, 15, 10, 2.4, 1.4, 2.6, light)
    for i in range(8):
        m.front(8 + i, 4 + i, LEATHER_D)
    for xx in range(7, 19):
        m.front(xx, 5, '#3b2716')
    m.front(12, 5, STEEL); m.front(13, 5, STEEL)
    m.box(16, 17, 14, 15, 4, 6, '#9a6b3f')
    m.line((7, 14, 6), (9, 15, 4), '#efe4c9', r=0.4)
    m.ell(cx, 11, 13.5, 7.6 + 0.6 * (tier >= 2), 5.8 + 0.6 * (tier >= 2), 2.4, cloak)
    m.texture(cloak, [cloak2, '#5a4130'], 0.35)
    if tier >= 2:  # bone tooth necklace
        for k, xx in enumerate(range(9, 17)):
            m.front(xx, 12 - (1 if 10 < xx < 15 else 0), '#efe4c9' if k % 2 else '#c9a77a')
    m.part = 'head'
    x, y, z = np.indices(m.g.shape)
    F = m.c(fur)
    m._put((m.g == F) & (m.p == PID['head']) & (z <= 17) & (y >= 14), light, only='filled')
    m.ell(cx, 18.6, 16.8, 2.5, 3.0, 1.9, light)
    m.ell(cx, 18.6, 17.6, 2.3, 3.0, 1.0, fur, only=light)
    m.box(12, 13, 21, 21, 17, 18, BLACK)
    for side in (0, 1):
        for i, (w0, w1) in enumerate([(6, 10), (6, 9), (7, 9), (7, 8), (7, 8)]):
            zz = 25 + i
            xa, xb = (w0, w1) if side == 0 else (m.X - 1 - w1, m.X - 1 - w0)
            m.box(xa, xb, 10, 12, zz, zz, fur)
        p = (7, 8) if side == 0 else (m.X - 9, m.X - 8)
        m.box(p[0], p[1], 12, 12, 25, 26, '#4c5260')
    eyec = '#f0b030'
    eye(m, 8, 21, ['wa', 'ak', 'ak'], {'w': WHITE, 'a': eyec, 'k': BLACK})
    eye(m, 8, 22, ['kk'], {'k': '#4c5260'})
    m.line((17, 9, 25), (19, 7, 29), '#c94a3a', r=0.4)
    m.part = 'tail'
    m.ell(14.5, 4.5, 5, 2.6, 3.4, 2.6, fur)
    m.ell(15.5, 2.5, 7, 2.0, 2.2, 2.0, light)
    m.pivots['tail'] = (13.5, 7, 4.5)
    # spear
    m.part = 'weapon_r'
    hx, hy, _ = a['hand_r']
    sx, sy = int(round(hx)), int(round(hy)) + 2
    m.box(sx, sx, sy, sy, 0, 25, WOOD)
    for zz in (9, 10, 15, 16):
        m.v(sx, sy, zz, LEATHER_D)
    tip = BLADE if tier < 3 else '#bff7ff'
    head_h = 3 if tier == 1 else 4
    m.box(sx - 1, sx + 1, sy, sy, 26, 25 + head_h, tip)
    m.box(sx, sx, sy, sy, 26 + head_h, 28 + head_h, tip)
    m.v(sx - 1, sy, 26, BLADE_D); m.v(sx + 1, sy, 26, BLADE_D)
    m.v(sx, sy, 25, '#c94a3a')
    if tier >= 2:
        m.v(sx - 2, sy, 26, BLADE_D); m.v(sx + 2, sy, 26, BLADE_D)
    m.texture(fur, [fur2, '#8e95a4'], 0.22)
    if tier >= 3:
        m.glow |= {tip}
        m.recolor({LEATHER: '#a4b2c2', LEATHER_D: '#6c7888', '#3b2716': '#3d4656', cloak: '#efe9df',
                   cloak2: '#ffffff', '#5a4130': '#d8d0c2', eyec: '#7fe8ff'})
        m.glow |= {'#7fe8ff'}
        # crescent moon on chest + antler circlet
        m.part = 'body'
        for xx, zz in ((12, 10), (13, 10), (11, 9), (11, 8), (12, 7), (13, 7)):
            m.front(xx, zz, GILT_L)
        m.glow |= {GILT_L}
        m.part = 'head'
        for sgn in (-1, 1):
            bx = cx + sgn * 4
            m.line((bx, 12, 25), (bx + sgn * 2, 12, 29), GILT, r=0.3)
            m.line((bx + sgn * 1, 12, 27), (bx - sgn * 0.5, 12, 30), GILT, r=0.2)
    return finish(m, tier)


# ---------------------------------------------------------------- Berserker: Bear
def berserker(tier=1):
    m = Model('berserker_bear', 26, 24, 36, seed=19)
    m.style.update(attack='slash', skill='rage', weapon='axe', twohand=True)
    fur, fur2, fur3 = '#7a4a2a', '#6a3f23', '#8a5733'
    muzzle = '#d1a274'
    paint = '#3f7fd1'
    helm, helm_d = '#8d9aaa', '#5f6b7a'
    horn = '#efe4c9'
    cx = m.cx
    a = biped(m, fur, legs='#56623a', feet='#3b2716', torso=fur, arms=fur, hands=fur, stout=1,
              torso_r=(6.0, 4.6, 5.4))
    m.part = 'body'
    m.ell(cx, 15.0, 9.5, 3.6, 1.6, 3.6, muzzle)
    for i in range(9):
        m.front(7 + i, 4 + i, LEATHER_D)
        m.front(m.X - 8 - i, 4 + i, LEATHER_D)
    m.front(12, 8, STEEL); m.front(13, 8, STEEL)
    for xx in range(6, 20):
        m.front(xx, 4, '#3b2716')
    m.front(12, 4, GOLD); m.front(13, 4, GOLD)
    if tier >= 2:  # wolf-pelt cloak
        cape(m, '#9a9aa4', '#6d6d78', x0=6, x1=19, y=5, z0=3, z1=14)
        m.ell(cx, 10.5, 14, 7.6, 5.4, 1.6, '#9a9aa4')
    m.part = 'head'
    m.ell(cx, 17.5, 17.0, 3.2, 2.0, 2.2, muzzle)
    m.box(12, 13, 19, 19, 18, 18, BLACK)
    m.ell(7.4, 11.5, 25.0, 2.0, 1.4, 2.0, fur)
    m.ell(m.X - 8.4, 11.5, 25.0, 2.0, 1.4, 2.0, fur)
    m.v(7, 13, 25, muzzle); m.v(m.X - 8, 13, 25, muzzle)
    eye(m, 8, 21, ['wk', 'kk'], {'w': WHITE, 'k': BLACK})
    eye(m, 7, 22, ['bbb'], {'b': '#4a2a16'})
    eye(m, 7, 18, ['pp.', '.pp'], {'p': paint})
    if tier >= 2:
        eye(m, 7, 23, ['p.p'], {'p': paint})
        m.front(12, 22, paint); m.front(13, 22, paint)
    x, y, z = np.indices(m.g.shape)
    sel = (((x - cx) / 7.8) ** 2 + ((y - 11.5) / 6.8) ** 2 + ((z - 19.5) / 6.8) ** 2 <= 1) & (z >= 23)
    m._put(sel, helm)
    m.box(0, 25, 0, 23, 23, 23, helm_d, only=helm)
    for xx in (12, 13):
        for zz in range(23, 27):
            m.front(xx, zz, helm_d)
    hs = 1.0 if tier == 1 else 1.35
    for sgn in (-1, 1):
        bx = cx + sgn * 6.8
        p1 = (bx + sgn * 2.5 * hs, 11.5, 23.5 + 2 * hs)
        p2 = (bx + sgn * 3.0 * hs, 11.5, 23.5 + 6 * hs)
        p3 = (bx + sgn * 2.4 * hs, 11.5, 23.5 + 8 * hs)
        m.line((bx, 11.5, 23.5), p1, horn, r=0.9)
        m.line(p1, p2, horn, r=0.6)
        m.line(p2, p3, '#d8cba8', r=0.2)
    # great axe
    m.part = 'weapon_r'
    hx, hy, _ = a['hand_r']
    sx, sy = int(round(hx)), int(round(hy)) + 2
    m.box(sx, sx, sy, sy, 0, 25, WOOD)
    for zz in (6, 7, 8):
        m.v(sx, sy, zz, LEATHER_D)
    bw = 3.5 if tier == 1 else 4.5
    rune = '#6ff0ff'
    for zz in range(17, 26):
        t = (zz - 17) / 8
        w = int(round(1 + bw * math.sin(math.pi * t)))
        m.box(sx, sx, sy + 1, sy + 1 + w, zz, zz, BLADE_D)
        m.v(sx, sy + 1 + w, zz, BLADE)
        m.box(sx, sx, sy - 1 - max(w - 1, 0), sy - 1, zz, zz, BLADE_D)
        m.v(sx, sy - 1 - max(w - 1, 0), zz, BLADE)
    m.v(sx, sy, 26, STEEL_D)
    if tier >= 2:
        for zz in (19, 21, 23):
            m.v(sx, sy + 2, zz, rune); m.v(sx, sy - 2, zz, rune)
        m.glow |= {rune}
    m.texture(fur, [fur2, fur3], 0.25)
    if tier >= 3:
        m.recolor({helm: GILT, helm_d: GILT_D, horn: '#fff7e0', paint: '#58d8ff', BLADE_D: '#3b4a66',
                   '#9a9aa4': '#f2f2f5', '#6d6d78': '#c9c9d2'})
        m.glow |= {'#58d8ff'}
        m.part = 'head'
        m.v(12, 18, 25, SAPPHIRE); m.v(13, 18, 25, SAPPHIRE)
    return finish(m, tier)


# ---------------------------------------------------------------- Dragon
def dragon(tier=1):
    m = Model('dragon', 34, 34, 36, seed=20)
    m.pivot_y = 15
    m.style.update(attack='bite', skill='breath', weapon='jaws', quad=True)
    red, red2, red_d = '#c8352e', '#d9473a', '#962420'
    belly, belly2 = '#f2c46b', '#ddae55'
    wing, wing2 = '#e8704f', '#f08460'
    horn = '#f3e7c9'
    eyec = '#ffd23a'
    cx = m.cx
    m.part = 'body'
    m.ell(cx, 15, 9, 6.0, 7.5, 5.5, red)
    m.ell(cx, 18.5, 8.0, 4.0, 4.5, 4.2, belly, only='filled')
    x, y, z = np.indices(m.g.shape)
    m._put((m.g == m.c(belly)) & (z % 2 == 0), belly2, only='filled')
    legs = {}
    for fx, side in ((cx - 4.5, 'r'), (cx + 4.5, 'l')):
        for fy, end in ((20.5, 'f'), (9.5, 'b')):
            m.part = f'leg_{end}{side}'
            m.cyl(fx, fy, 0, 6, 2.0, red)
            m.box(int(fx) - 1, int(fx) + 2, int(fy) - 1, int(fy) + 2 if end == 'f' else int(fy) + 1, 0, 1, red_d)
            if end == 'f':
                for dx in (-1, 0.5, 2):
                    m.v(int(fx + dx), int(fy) + 3, 0, horn)
            m.pivots[m.part] = (fx, fy, 6)
    m.part = 'head'
    m.line((cx, 20, 12), (cx, 23, 17), red, r=2.6)
    m.ell(cx, 24.5, 20.5, 6.6, 5.8, 5.6, red)
    m.ell(cx, 29.5, 19.0, 3.6, 3.4, 2.6, red2)
    m.ell(cx, 30.0, 17.6, 3.2, 3.0, 1.4, belly, only='filled')
    m.v(15, 33, 20, red_d); m.v(18, 33, 20, red_d)
    m.front(15, 20, BLACK); m.front(18, 20, BLACK)
    m.front(14, 17, horn); m.front(19, 17, horn)
    eye(m, 11, 23, ['yw', 'yk', 'yk'], {'y': eyec, 'w': WHITE, 'k': BLACK})
    eye(m, 10, 24, ['ddd'], {'d': red_d})
    hs = 1.0 if tier == 1 else 1.3
    for sgn in (-1, 1):
        bx = cx + sgn * 3.5
        m.line((bx, 22, 25), (bx + sgn * 1.5 * hs, 22 - 4 * hs, 25 + 3 * hs), horn, r=0.8)
        m.line((bx + sgn * 1.5 * hs, 22 - 4 * hs, 25 + 3 * hs), (bx + sgn * 2.0 * hs, 22 - 7 * hs, 25 + 4 * hs), horn, r=0.4)
        m.line((cx + sgn * 6.0, 23, 20), (cx + sgn * 8.5, 21, 22), red_d, r=0.5)
    m.box(16, 17, 22, 22, 25, 26, red_d)
    m.pivots['head'] = (cx, 19.5, 12)
    m.part = 'body'
    spikes = ((19, 15), (16, 15), (13, 15), (10, 14), (7, 12))
    for sy_, sz_ in spikes:
        m.box(16, 17, sy_, sy_, sz_ - 1, sz_ + (1 if tier >= 2 else 0), horn)
    m.part = 'tail'
    pts = [(cx, 8, 8), (cx + 1, 4, 6), (cx + 4, 1.5, 5), (cx + 8, 1.5, 6), (cx + 10, 3, 8)]
    for i in range(len(pts) - 1):
        m.line(pts[i], pts[i + 1], red, r=max(2.4 - i * 0.5, 0.6))
    tx, ty, tz = pts[-1]
    tipc = horn if tier < 3 else '#ffb13b'
    for dz, w in ((0, 2), (1, 2), (2, 1), (3, 0)):
        m.box(int(tx) - w, int(tx) + w, int(ty), int(ty), int(tz) + dz, int(tz) + dz, tipc if dz else red_d)
    if tier >= 3:
        m.v(int(tx), int(ty), int(tz) + 4, '#fff1a0')
        m.glow |= {'#ffb13b', '#fff1a0'}
    m.pivots['tail'] = (cx, 9, 8)
    m.pivots['body'] = (cx, 15, 6)
    m.pivots['root'] = (cx, 15, 0)
    ws = 1.0 if tier == 1 else 1.15
    for sgn, side in ((-1, 'r'), (1, 'l')):
        m.part = f'wing_{side}'
        sh = np.array([cx + sgn * 4.5, 13, 13.0])
        tip = np.array([cx + sgn * 15.5 * ws, 13, 13 + 14 * ws])
        out = np.array([cx + sgn * 16.0 * ws, 13, 14.0])
        mid = np.array([cx + sgn * 10.5 * ws, 13, 12.0])

        def tri(P, a, b, c):
            def s(p1, p2, p3):
                return (p1[0] - p3[0]) * (p2[2] - p3[2]) - (p2[0] - p3[0]) * (p1[2] - p3[2])
            d1, d2, d3 = s(P, a, b), s(P, b, c), s(P, c, a)
            return ~(((d1 < 0) | (d2 < 0) | (d3 < 0)) & ((d1 > 0) | (d2 > 0) | (d3 > 0)))
        P = (x.astype(float), y.astype(float), z.astype(float))
        memb = (tri(P, sh, tip, out) | tri(P, sh, out, mid)) & (y == 13)
        m._put(memb, wing, keep=True)
        m.line(sh, tip, red_d, r=0.5)
        m.line(tip, (tip + out) / 2, red, r=0.3)
        m.line(sh + np.array([sgn * 3, 0, 2]), out, red, r=0.3)
        m.line(sh + np.array([sgn * 2, 0, 1]), mid + np.array([sgn * 1, 0, 0]), red, r=0.3)
        m.v(int(round(tip[0])), 13, int(tip[2]) + 1, horn)
        m.pivots[m.part] = tuple(sh)
    m.texture(red, [red2, '#b82e28'], 0.2)
    m.texture(wing, [wing2], 0.15)
    if tier >= 2:
        m.recolor({belly: '#ffd15c', belly2: '#f0b93f'})
    if tier >= 3:
        m.recolor({horn: GILT, wing: '#ff9a3c', wing2: '#ffb35a', red_d: '#6b1414', eyec: '#9ff0ff'})
        m.glow |= {'#9ff0ff'}
        crown(m, 26, cx=cx, cy=23.5, r=3.0, points=6, gem=SAPPHIRE)
    return finish(m, tier)


UNITS = [('Knight', knight), ('Archer', archer), ('Cleric', cleric), ('Guardian', guardian),
         ('Thief', thief), ('Mage', mage), ('Assassin', assassin), ('Hunter', hunter),
         ('Berserker', berserker), ('Dragon', dragon)]
