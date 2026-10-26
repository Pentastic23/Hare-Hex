"""Tiny voxel modeling toolkit: build rigged voxel models on a grid, export .vox / skinned+animated .glb,
render previews.

Grid convention: g[x, y, z]; x = right (as seen by the viewer), y = toward viewer (front), z = up.
Every voxel also carries a part label (which bone it follows). Parts are rigid: each voxel is
weighted 100% to one bone, which keeps the blocky look crisp when animated.
"""
import json
import math
import random
import struct

import numpy as np
from PIL import Image, ImageDraw

PARTS = ['root', 'body', 'head', 'arm_r', 'arm_l', 'leg_r', 'leg_l', 'tail',
         'wing_r', 'wing_l', 'leg_fr', 'leg_fl', 'leg_br', 'leg_bl', 'aura', 'weapon_r', 'weapon_l']
PID = {n: i for i, n in enumerate(PARTS)}
PARENT = {'body': 'root', 'head': 'body', 'arm_r': 'body', 'arm_l': 'body', 'tail': 'body',
          'leg_r': 'root', 'leg_l': 'root', 'wing_r': 'body', 'wing_l': 'body',
          'leg_fr': 'root', 'leg_fl': 'root', 'leg_br': 'root', 'leg_bl': 'root', 'aura': 'root',
          'weapon_r': 'arm_r', 'weapon_l': 'arm_l'}


def hexrgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lum(rgb):
    return 0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]


def grad(stops, t):
    t = min(max(t, 0.0), 1.0) * (len(stops) - 1)
    i = min(int(t), len(stops) - 2)
    f = t - i
    a, b = hexrgb(stops[i]), hexrgb(stops[i + 1])
    return tuple(int(round(a[k] + (b[k] - a[k]) * f)) for k in range(3))


def quat_euler(ex, ey, ez):
    """Degrees, applied X then Y then Z (q = qz*qy*qx). Returns (x, y, z, w)."""
    def q(axis, a):
        h = math.radians(a) / 2
        v = [0.0, 0.0, 0.0]; v[axis] = math.sin(h)
        return (*v, math.cos(h))

    def mul(a, b):
        ax, ay, az, aw = a; bx, by, bz, bw = b
        return (aw * bx + ax * bw + ay * bz - az * by,
                aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw,
                aw * bw - ax * bx - ay * by - az * bz)
    return mul(q(2, ez), mul(q(1, ey), q(0, ex)))


class Model:
    def __init__(self, name, X=24, Y=24, Z=32, seed=1):
        self.name = name
        self.g = np.zeros((X, Y, Z), np.uint8)
        self.p = np.zeros((X, Y, Z), np.uint8)   # part id per voxel
        self.X, self.Y, self.Z = X, Y, Z
        self.cx = (X - 1) / 2.0
        self.pal = [(0, 0, 0)]  # index 0 = empty
        self._idx = {}
        self.rng = random.Random(seed)
        self.pivot_y = 11.5
        self.origin = None
        self.part = 'body'
        self.pivots = {}          # part -> (x, y, z) grid coords
        self.glow = set()         # hex colors that should be emissive
        self.style = {}           # animation style hints

    # ---------- palette ----------
    def c(self, col):
        if isinstance(col, (int, np.integer)):
            return int(col)
        rgb = hexrgb(col) if isinstance(col, str) else tuple(int(v) for v in col)
        if rgb not in self._idx:
            self._idx[rgb] = len(self.pal)
            self.pal.append(rgb)
        return self._idx[rgb]

    def recolor(self, mapping):
        """Swap palette colors (hex -> hex) everywhere they are used."""
        for old, new in mapping.items():
            o = hexrgb(old)
            if o in self._idx:
                i = self._idx.pop(o)
                n = hexrgb(new)
                if n in self._idx:   # merge into the existing entry
                    self.g[self.g == i] = self._idx[n]
                    self.pal[i] = (1, 2, 3)  # orphan
                else:
                    self.pal[i] = n
                    self._idx[n] = i

    def compact(self):
        used = sorted(set(np.unique(self.g).tolist()) - {0})
        remap = np.zeros(max(len(self.pal), 256), np.uint8)
        pal = [(0, 0, 0)]
        idx = {}
        for i in used:
            rgb = self.pal[i]
            if rgb not in idx:
                idx[rgb] = len(pal); pal.append(rgb)
            remap[i] = idx[rgb]
        self.g = remap[self.g]
        self.pal, self._idx = pal, idx
        assert len(pal) <= 256, f'{self.name}: too many colors ({len(pal)})'

    def close_grip(self, side):
        """Slide a hand's weapon voxels sideways until they touch the hand (arm voxels below the elbow).
        Bows, guns and shields are drawn at a fixed column near the grid's edge, which left them a voxel
        or two beside the hand: floating next to the unit in every pose. Overlapping voxels (a pauldron
        behind a shield) give way to the weapon."""
        w = (self.p == PID['weapon_' + side]) & (self.g > 0)
        hand = (self.p == PID['arm_' + side]) & (self.g > 0)
        hand[:, :, 9:] = False   # the hand is at z 4-8, the elbow above
        if not w.any() or not hand.any():
            return
        xw = np.nonzero(w.any(axis=(1, 2)))[0]
        xh = np.nonzero(hand.any(axis=(1, 2)))[0]
        gap = xw.min() - xh.max() - 1 if side == 'l' else xh.min() - xw.max() - 1
        if gap <= 0:
            return
        d = -gap if side == 'l' else gap
        idx = np.argwhere(w)
        g, p = self.g[w], self.p[w]
        self.g[w] = 0
        self.g[idx[:, 0] + d, idx[:, 1], idx[:, 2]] = g
        self.p[idx[:, 0] + d, idx[:, 1], idx[:, 2]] = p

    # ---------- primitives ----------
    def _put(self, mask, col, only=None, keep=False):
        """Apply color to mask. only: restrict to filled voxels (a paint). keep: don't overwrite filled."""
        paint = only is not None
        if only == 'filled':
            mask = mask & (self.g > 0)
        elif only is not None:  # a specific color
            mask = mask & (self.g == self.c(only))
        if keep:
            mask = mask & (self.g == 0)
        if callable(col):
            xs, ys, zs = np.nonzero(mask)
            for x, y, z in zip(xs, ys, zs):
                self.g[x, y, z] = self.c(col(x, y, z))
        else:
            self.g[mask] = 0 if col is None else self.c(col)
        if not paint and col is not None:
            self.p[mask] = PID[self.part]

    def _grid(self):
        return np.indices(self.g.shape)

    def box(self, x0, x1, y0, y1, z0, z1, col, **kw):
        m = np.zeros(self.g.shape, bool)
        xa, xb = sorted((int(x0), int(x1))); ya, yb = sorted((int(y0), int(y1))); za, zb = sorted((int(z0), int(z1)))
        xa, ya, za = max(xa, 0), max(ya, 0), max(za, 0)
        m[xa:xb + 1, ya:yb + 1, za:zb + 1] = True
        self._put(m, col, **kw)

    def ell(self, cx, cy, cz, rx, ry, rz, col, **kw):
        x, y, z = self._grid()
        m = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1.0
        self._put(m, col, **kw)

    def cyl(self, cx, cy, z0, z1, rx, col, ry=None, **kw):
        ry = ry or rx
        x, y, z = self._grid()
        m = (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0) & (z >= z0) & (z <= z1)
        self._put(m, col, **kw)

    def line(self, p0, p1, col, r=0.0, **kw):
        """Thick 3D line segment (capsule radius r)."""
        p0 = np.array(p0, float); p1 = np.array(p1, float)
        x, y, z = self._grid()
        P = np.stack([x, y, z], -1).astype(float)
        d = p1 - p0
        L2 = max(d @ d, 1e-9)
        t = np.clip(((P - p0) @ d) / L2, 0, 1)
        closest = p0 + t[..., None] * d
        dist = np.linalg.norm(P - closest, axis=-1)
        self._put(dist <= r + 0.5, col, **kw)

    def v(self, x, y, z, col):
        x, y, z = int(x), int(y), int(z)
        if 0 <= x < self.X and 0 <= y < self.Y and 0 <= z < self.Z:
            if col and self.g[x, y, z] == 0:
                self.p[x, y, z] = PID[self.part]
            self.g[x, y, z] = self.c(col) if col else 0

    def front(self, x, z, col, depth=1, inset=0):
        """Paint the frontmost filled voxel(s) in column (x, z)."""
        x, z = int(x), int(z)
        ys = np.nonzero(self.g[x, :, z])[0]
        if len(ys) == 0:
            return
        y = ys.max()
        for _ in range(inset):
            self.g[x, y, z] = 0
            y -= 1
        for d in range(depth):
            if y - d >= 0:
                self.g[x, y - d, z] = self.c(col)

    def texture(self, col, variants, p=0.25):
        ci = self.c(col)
        vi = [self.c(v) for v in variants]
        xs, ys, zs = np.nonzero(self.g == ci)
        for x, y, z in zip(xs, ys, zs):
            if self.rng.random() < p:
                self.g[x, y, z] = self.rng.choice(vi)

    def part_top(self, part):
        """(x, y, z_top) center-top of a part's voxels."""
        pts = np.argwhere((self.p == PID[part]) & (self.g > 0))
        ztop = pts[:, 2].max()
        sel = pts[pts[:, 2] >= ztop - 2]
        return sel[:, 0].mean(), sel[:, 1].mean(), int(ztop)

    def grow(self, dx=0, dy=0, dz=0):
        """Pad the grid by dx/dy on each side and dz on top, keeping everything in place."""
        self.g = np.pad(self.g, ((dx, dx), (dy, dy), (0, dz)))
        self.p = np.pad(self.p, ((dx, dx), (dy, dy), (0, dz)))
        self.X, self.Y, self.Z = self.g.shape
        self.cx += dx
        self.pivot_y += dy
        self.pivots = {k: (v[0] + dx, v[1] + dy, v[2]) for k, v in self.pivots.items()}

    # ---------- secret 4-star "astral" form ----------
    def astral(self, keep_white=True, sparkle=0.05, aura_r=None, aura_z=(4, 16)):
        body = ['#120b33', '#2a1c6e', '#4b37b4', '#7a68f0', '#b7aaff']
        gear = ['#3e5bd0', '#79c3ff', '#d6f6ff', '#ffffff']
        gearish = {hexrgb(h) for h in ['#c3ccd6', '#7f8b99', '#e8eef4', '#f2c14e', '#c48f2a', '#8b5a2b',
                                       '#64401f', '#7a5233', '#52361f', '#8d9aaa', '#5f6b7a', '#b6c1cd',
                                       '#ece4cc', '#efe4c9', '#f3e7c9', '#ffd34d', '#d8cba8', '#cfd6df',
                                       '#bfc6cf', '#fff1a8', '#fff4b0', '#e5b93c', '#ffd700', '#ffe066',
                                       '#fff6c2', '#f7e08a', '#d9a93a', '#b8860b', '#ffcf3f', '#e8b923',
                                       '#a4b2c2', '#dfe6ee', '#f6f8fb', '#9aa7b6', '#6c7888']}
        gold = {hexrgb(h) for h in ['#f2c14e', '#c48f2a', '#ffd34d', '#e5b93c', '#d9a93a', '#ffd700',
                                    '#ffe066', '#e8b923', '#ffcf3f', '#b8860b', '#f7e08a', '#fff6c2',
                                    '#ffd75e', '#d9a33a', '#fff0b3']}
        new_glow = set()
        for i in range(1, len(self.pal)):
            rgb = self.pal[i]
            L = lum(rgb) / 255.0
            hx = '#%02x%02x%02x' % rgb
            if L < 0.09:                       # eyes, noses, pupils -> glowing starlight
                n = hexrgb('#8ff7ff'); new_glow.add('#8ff7ff')
            elif keep_white and L > 0.97:
                n = (255, 255, 255); new_glow.add('#ffffff')
            elif rgb in gold:
                n = hexrgb('#ffe9a8'); new_glow.add('#ffe9a8')
            elif rgb in gearish:
                n = grad(gear, L * 1.05)
            elif hx in self.glow:
                n = hexrgb('#9ff0ff'); new_glow.add('#9ff0ff')
            else:
                n = grad(body, 0.08 + L * 0.95)
            self.pal[i] = n
        self._idx = {}
        for i in range(1, len(self.pal)):
            self._idx.setdefault(self.pal[i], i)
        self.glow = new_glow
        # sprinkle stars over the body surface
        pad = np.pad(self.g, 1)
        exposed = np.zeros_like(self.g, bool)
        for ax in range(3):
            for s in (-1, 1):
                exposed |= (np.roll(pad, s, axis=ax)[1:-1, 1:-1, 1:-1] == 0)
        cand = np.argwhere((self.g > 0) & exposed)
        star = self.c('#ffffff'); self.glow.add('#ffffff')
        star2 = self.c('#c9b8ff'); self.glow.add('#c9b8ff')
        for x, y, z in cand:
            if self.rng.random() < sparkle and lum(self.pal[self.g[x, y, z]]) < 140:
                self.g[x, y, z] = star if self.rng.random() < 0.6 else star2
        # halo above the head
        hx_, hy_, ht = self.part_top('head')
        self.part = 'head'
        x, y, z = self._grid()
        rr = ((x - hx_) / 4.6) ** 2 + ((y - hy_) / 3.4) ** 2
        ring = (rr <= 1.0) & (rr >= 0.45) & (z == ht + 3)
        self._put(ring, '#ffe9a8'); self.glow.add('#ffe9a8')
        # orbiting aura motes (own bone so they can spin)
        self.part = 'aura'
        cx, cy = self.cx, self.pivot_y
        R = aura_r or (self.X / 2.0 + 1.5)
        for k in range(10):
            a = k * 2 * math.pi / 10 + self.rng.random() * 0.3
            zz = aura_z[0] + (aura_z[1] - aura_z[0]) * ((k * 7) % 10) / 9.0
            px, py = cx + R * math.cos(a), cy + R * 0.8 * math.sin(a)
            col = ['#8ff7ff', '#ffffff', '#c9b8ff'][k % 3]
            self.glow.add(col)
            self.v(round(px), round(py), round(zz), col)
            if k % 2 == 0:
                for d in ((1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)):
                    self.v(round(px) + d[0], round(py) + d[1], round(zz) + d[2], '#7a68f0')
        self.pivots['aura'] = (cx, cy, 0)
        self.style['aura'] = True

    # ---------- export ----------
    def trim(self, pad_top=0):
        nz = np.argwhere(self.g > 0)
        lo, hi = nz.min(0), nz.max(0)
        lo[2] = 0
        self.g = self.g[lo[0]:hi[0] + 1, lo[1]:hi[1] + 1, :hi[2] + 1].copy()
        self.p = self.p[lo[0]:hi[0] + 1, lo[1]:hi[1] + 1, :hi[2] + 1].copy()
        self.X, self.Y, self.Z = self.g.shape
        self.origin = (self.cx - lo[0] + 0.5, self.pivot_y - lo[1] + 0.5)
        self.pivots = {k: (v[0] - lo[0], v[1] - lo[1], v[2]) for k, v in self.pivots.items()}
        self.cx -= lo[0]
        self.pivot_y -= lo[1]

    def save_vox(self, path):
        X, Y, Z = self.g.shape
        xs, ys, zs = np.nonzero(self.g)
        n = len(xs)
        size = b'SIZE' + struct.pack('<ii', 12, 0) + struct.pack('<iii', X, Y, Z)
        xyzi = bytearray(b'XYZI' + struct.pack('<ii', 4 + 4 * n, 0) + struct.pack('<i', n))
        for x, y, z in zip(xs, ys, zs):
            xyzi += struct.pack('<BBBB', x, Y - 1 - y, z, self.g[x, y, z])
        rgba = bytearray(b'RGBA' + struct.pack('<ii', 1024, 0))
        for i in range(1, 256):
            r, g, b = self.pal[i] if i < len(self.pal) else (0, 0, 0)
            rgba += struct.pack('<BBBB', r, g, b, 255)
        rgba += struct.pack('<BBBB', 0, 0, 0, 0)
        children = size + bytes(xyzi) + bytes(rgba)
        open(path, 'wb').write(b'VOX ' + struct.pack('<i', 150) + b'MAIN' +
                               struct.pack('<ii', 0, len(children)) + children)

    def quads(self, greedy=True):
        """Greedy-merged visible faces. A face is visible where the neighbor is empty or belongs to
        another part (so joints stay closed when parts rotate). Yields (corners[4], normal, color, part)."""
        g = self.g.astype(np.int32); p = self.p.astype(np.int32)
        key = np.where(g > 0, g + 256 * p, 0)
        out = []
        for axis in range(3):
            for sign in (-1, 1):
                pad = np.pad(key, 1)
                nb = np.roll(pad, -sign, axis=axis)[1:-1, 1:-1, 1:-1]
                vis = (key > 0) & ((nb == 0) | ((nb // 256) != (key // 256)))
                F = np.where(vis, key, 0)
                u, w = [a for a in range(3) if a != axis]
                n = np.zeros(3); n[axis] = sign
                for i in range(F.shape[axis]):
                    M = np.take(F, i, axis=axis)  # dims ordered (u, w)
                    if not M.any():
                        continue
                    used = np.zeros(M.shape, bool)
                    nu, nw = M.shape
                    for u0 in range(nu):
                        row = M[u0]
                        for w0 in range(nw):
                            k = row[w0]
                            if k == 0 or used[u0, w0]:
                                continue
                            w1 = w0 + 1
                            if greedy:
                                while w1 < nw and M[u0, w1] == k and not used[u0, w1]:
                                    w1 += 1
                            u1 = u0 + 1
                            if greedy:
                                while u1 < nu and np.all(M[u1, w0:w1] == k) and not used[u1, w0:w1].any():
                                    u1 += 1
                            used[u0:u1, w0:w1] = True
                            plane = i + (1 if sign > 0 else 0)
                            cs = []
                            for du, dw in ((u0, w0), (u1, w0), (u1, w1), (u0, w1)):
                                c = [0.0, 0.0, 0.0]
                                c[axis] = plane; c[u] = du; c[w] = dw
                                cs.append(c)
                            out.append((cs, n.copy(), int(k % 256), int(k // 256)))
        return out

    def save_glb(self, path, voxel=0.05, clips=None):
        """Skinned glTF binary: rigid per-part skinning, vertex colors, flat normals, emissive glow
        primitives, and animation clips. Meters; feet at origin; facing +Z."""
        ox, oy = self.origin or (self.X / 2.0, self.Y / 2.0)

        def tf(p):
            return [(p[0] - ox) * voxel, p[2] * voxel, (p[1] - oy) * voxel]

        def lin(c):
            c = c / 255.0
            return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

        # ----- skeleton -----
        present = {PARTS[i] for i in np.unique(self.p[self.g > 0])}
        bones = ['root'] + [b for b in PARTS[1:] if b in present or b in self.pivots]
        for b in bones:
            if b not in self.pivots:
                self.pivots[b] = (self.cx, self.pivot_y, 0)
        # ensure parents exist
        changed = True
        while changed:
            changed = False
            for b in list(bones):
                pa = PARENT.get(b)
                if pa and pa not in bones:
                    bones.append(pa); changed = True
                    self.pivots.setdefault(pa, (self.cx, self.pivot_y, 0))
        bones = [b for b in PARTS if b in bones]
        bidx = {b: i for i, b in enumerate(bones)}
        world = {b: np.array(tf(self.pivots[b])) for b in bones}

        # ----- geometry, grouped by material -----
        glow_idx = {}
        for h in self.glow:
            rgb = hexrgb(h)
            if rgb in self._idx:
                glow_idx[self._idx[rgb]] = h
        groups = {}  # material key -> lists
        for cs, n, ci, pi in self.quads():
            mk = glow_idx.get(ci, None)
            G = groups.setdefault(mk, dict(pos=[], nrm=[], col=[], jnt=[], idx=[]))
            cw = [tf(c) for c in cs]
            nn = [n[0], n[2], n[1]]
            a, b, c = (np.array(cw[i]) for i in range(3))
            if np.dot(np.cross(b - a, c - a), nn) < 0:
                cw = cw[::-1]
            rgb = self.pal[ci]
            lc = [lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1.0]
            j = bidx.get(PARTS[pi], 0)
            s = len(G['pos'])
            for pt in cw:
                G['pos'].append(pt); G['nrm'].append(nn); G['col'].append(lc); G['jnt'].append([j, 0, 0, 0])
            G['idx'] += [s, s + 1, s + 2, s, s + 2, s + 3]

        binbuf = bytearray()
        views, accs = [], []

        def add(arr, comp, typ, target=None, minmax=False):
            nonlocal binbuf
            while len(binbuf) % 4:
                binbuf += b'\0'
            off = len(binbuf)
            raw = arr.tobytes()
            binbuf += raw
            v = {"buffer": 0, "byteOffset": off, "byteLength": len(raw)}
            if target:
                v["target"] = target
            views.append(v)
            a = {"bufferView": len(views) - 1, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
            if minmax:
                a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
            accs.append(a)
            return len(accs) - 1

        materials = [{"name": "voxel", "pbrMetallicRoughness": {
            "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 1.0}}]
        prims = []
        for mk, G in sorted(groups.items(), key=lambda t: (t[0] is not None, t[0] or '')):
            P = np.array(G['pos'], np.float32); N = np.array(G['nrm'], np.float32)
            C = np.round(np.array(G['col'], np.float64) * 65535).astype(np.uint16)
            J = np.array(G['jnt'], np.uint8)
            W = np.zeros((len(P), 4), np.uint8); W[:, 0] = 255
            I = np.array(G['idx'], np.uint32 if len(P) > 65535 else np.uint16)
            attrs = {"POSITION": add(P, 5126, "VEC3", 34962, True), "NORMAL": add(N, 5126, "VEC3", 34962),
                     "COLOR_0": add(C, 5123, "VEC4", 34962), "JOINTS_0": add(J, 5121, "VEC4", 34962),
                     "WEIGHTS_0": add(W, 5121, "VEC4", 34962)}
            accs[attrs["COLOR_0"]]["normalized"] = True
            accs[attrs["WEIGHTS_0"]]["normalized"] = True
            ia = add(I, 5125 if I.dtype == np.uint32 else 5123, "SCALAR", 34963)
            mat = 0
            if mk is not None:
                rgb = hexrgb(mk)
                materials.append({"name": "glow_" + mk.lstrip('#'),
                                  "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1],
                                                           "metallicFactor": 0.0, "roughnessFactor": 1.0},
                                  "emissiveFactor": [lin(c) for c in rgb]})
                mat = len(materials) - 1
            prims.append({"attributes": attrs, "indices": ia, "material": mat})

        # ----- nodes -----
        nodes = [{"name": self.name, "mesh": 0, "skin": 0}]
        jn = {}
        for b in bones:
            jn[b] = len(nodes)
            pa = PARENT.get(b)
            local = world[b] - (world[pa] if pa else 0)
            nodes.append({"name": b, "translation": [float(v) for v in local]})
        for b in bones:
            kids = [jn[c] for c in bones if PARENT.get(c) == b]
            if kids:
                nodes[jn[b]]["children"] = kids
        ibm = []
        for b in bones:
            m = np.eye(4, dtype=np.float32); m[:3, 3] = -world[b]
            ibm.append(m.T.reshape(-1))   # column-major
        ibm_acc = add(np.array(ibm, np.float32), 5126, "MAT4")
        skins = [{"joints": [jn[b] for b in bones], "inverseBindMatrices": ibm_acc, "skeleton": jn['root']}]

        # ----- animations -----
        anims = []
        for cname, clip in (clips or {}).items():
            samplers, channels = [], []
            dur = clip['dur']
            for b in bones:
                tr = clip['tracks'].get(b, {})
                pa = PARENT.get(b)
                base = world[b] - (world[pa] if pa else 0)
                rk = tr.get('r') or [(0, (0, 0, 0)), (dur, (0, 0, 0))]
                tk = tr.get('t') or [(0, (0, 0, 0)), (dur, (0, 0, 0))]
                T = np.array([k[0] for k in rk], np.float32)
                Q = np.array([quat_euler(*k[1]) for k in rk], np.float32)
                for i in range(1, len(Q)):   # keep quaternions on one hemisphere
                    if np.dot(Q[i], Q[i - 1]) < 0:
                        Q[i] = -Q[i]
                ti = add(T[:, None], 5126, "SCALAR"); accs[ti]["min"] = [float(T.min())]; accs[ti]["max"] = [float(T.max())]
                qi = add(Q, 5126, "VEC4")
                samplers.append({"input": ti, "output": qi, "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": jn[b], "path": "rotation"}})
                T2 = np.array([k[0] for k in tk], np.float32)
                V = np.array([[base[0] + k[1][0] * voxel / 0.05, base[1] + k[1][1] * voxel / 0.05,
                               base[2] + k[1][2] * voxel / 0.05] for k in tk], np.float32)
                ti2 = add(T2[:, None], 5126, "SCALAR"); accs[ti2]["min"] = [float(T2.min())]; accs[ti2]["max"] = [float(T2.max())]
                vi = add(V, 5126, "VEC3")
                samplers.append({"input": ti2, "output": vi, "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": jn[b], "path": "translation"}})
            anims.append({"name": cname, "samplers": samplers, "channels": channels})

        gl = {"asset": {"version": "2.0", "generator": "menagerie-voxel-units"},
              "scene": 0, "scenes": [{"nodes": [0, jn['root']]}],
              "nodes": nodes, "materials": materials,
              "meshes": [{"name": self.name, "primitives": prims}],
              "skins": skins, "animations": anims,
              "buffers": [{"byteLength": len(binbuf)}], "bufferViews": views, "accessors": accs}
        if not anims:
            del gl["animations"]
        js = json.dumps(gl, separators=(',', ':')).encode()
        js += b' ' * ((4 - len(js) % 4) % 4)
        while len(binbuf) % 4:
            binbuf += b'\0'
        total = 12 + 8 + len(js) + 8 + len(binbuf)
        out = struct.pack('<III', 0x46546C67, 2, total)
        out += struct.pack('<II', len(js), 0x4E4F534A) + js
        out += struct.pack('<II', len(binbuf), 0x004E4942) + bytes(binbuf)
        open(path, 'wb').write(out)
        return dict(bones=bones, prims=len(prims), tris=sum(len(G['idx']) // 3 for G in groups.values()))

    # ---------- preview ----------
    def posed(self, pose):
        """Return a copy of the voxel grid with rigid parts rotated (pose: part -> (ex, ey, ez) degrees in
        glTF axes), for checking the rig in static renders. Nearest-voxel resampling."""
        g = self.g; out = np.zeros_like(g)
        order = ['root', 'body', 'leg_r', 'leg_l', 'leg_fr', 'leg_fl', 'leg_br', 'leg_bl',
                 'head', 'arm_r', 'arm_l', 'weapon_r', 'weapon_l', 'tail', 'wing_r', 'wing_l', 'aura']

        def R(e):
            q = quat_euler(*e); x, y, z, w = q
            return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                             [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                             [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        # grid -> gltf axis swap matrix
        S = np.array([[1, 0, 0], [0, 0, 1], [0, 1, 0]], float)
        mats = {}
        for b in order:
            if b not in self.pivots and b != 'root':
                continue
            piv = np.array(self.pivots.get(b, (self.cx, self.pivot_y, 0)), float)
            Rg = S @ R(pose.get(b, (0, 0, 0))) @ S
            loc = (Rg, piv)
            pa = PARENT.get(b)
            mats[b] = [loc] + (mats.get(pa, []) if pa else [])
        shape = np.array(g.shape)
        for pid in np.unique(self.p[g > 0]):
            b = PARTS[pid]
            pts = np.argwhere((self.p == pid) & (g > 0)).astype(float) + 0.5
            cols = g[(self.p == pid) & (g > 0)]
            for Rg, piv in mats.get(b, []):
                pts = (pts - piv) @ Rg.T + piv
            ip = np.floor(pts).astype(int)
            ok = np.all((ip >= 0) & (ip < shape), 1)
            out[ip[ok, 0], ip[ok, 1], ip[ok, 2]] = cols[ok]
        return out

    def render(self, path=None, yaw=-35, pitch=28, scale=10, bg=(32, 33, 40), grid=None):
        g = self.g if grid is None else grid
        X, Y, Z = g.shape
        cy_, sy_ = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
        light = np.array([0.45, 0.55, 0.7]); light /= np.linalg.norm(light)
        glow_i = {self._idx.get(hexrgb(h)) for h in self.glow}

        def proj(p):
            x, y, z = p[0] - X / 2, p[1] - Y / 2, p[2]
            rx = x * cy_ + y * sy_
            ry = -x * sy_ + y * cy_
            return rx, -(z * cp - ry * sp), ry * cp + z * sp

        pad = np.pad(g, 1)
        polys = []
        for axis in range(3):
            for sign in (-1, 1):
                nb = np.roll(pad, -sign, axis=axis)[1:-1, 1:-1, 1:-1]
                n = np.zeros(3); n[axis] = sign
                vy = -n[0] * sy_ + n[1] * cy_
                if vy * cp + n[2] * sp <= 0.01:
                    continue
                shade = 0.62 + 0.38 * max(0, n @ light)
                u, w = [a for a in range(3) if a != axis]
                for x, y, z in np.argwhere((g > 0) & (nb == 0)):
                    ci = g[x, y, z]
                    base = np.array([x, y, z], float)
                    if sign > 0:
                        base[axis] += 1
                    pts = []
                    for du, dw in ((0, 0), (1, 0), (1, 1), (0, 1)):
                        p = base.copy(); p[u] += du; p[w] += dw
                        pts.append(proj(p))
                    sh = 1.0 if ci in glow_i else shade
                    rgb = tuple(min(255, int(c * sh)) for c in self.pal[ci])
                    polys.append((sum(p[2] for p in pts) / 4, [(p[0], p[1]) for p in pts], rgb))
        polys.sort(key=lambda t: t[0])
        allp = [pt for _, ps, _ in polys for pt in ps]
        minx = min(p[0] for p in allp); maxx = max(p[0] for p in allp)
        miny = min(p[1] for p in allp); maxy = max(p[1] for p in allp)
        pd = 2
        W = int((maxx - minx + 2 * pd) * scale); H = int((maxy - miny + 2 * pd) * scale)
        img = Image.new('RGB', (W, H), bg)
        dr = ImageDraw.Draw(img)
        for _, ps, rgb in polys:
            pts = [((px - minx + pd) * scale, (py - miny + pd) * scale) for px, py in ps]
            dr.polygon(pts, fill=rgb, outline=tuple(int(c * 0.82) for c in rgb))
        if path:
            img.save(path)
        return img
