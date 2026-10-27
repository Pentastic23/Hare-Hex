// A small Node port of menagerie/source/vox.py (Model: box / ell / cyl / v / front / texture, .vox writer,
// the 3/4-view preview renderer) so a concept unit can be made without Python. Same conventions:
// x across (low x = the character's right), y front-back (+y is the front), z up.
const fs = require("fs");
const zlib = require("zlib");

function hexrgb(h) { h = h.replace("#", ""); return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)); }

// mulberry32: the same role as Python's random.Random(seed) (not the same numbers)
function rng(seed) { let a = seed >>> 0; return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

class Model {
  constructor(name, X, Y, Z, seed = 1) {
    Object.assign(this, { name, X, Y, Z });
    this.g = new Uint8Array(X * Y * Z);
    this.cx = (X - 1) / 2;
    this.pal = [[0, 0, 0]];
    this.idx = new Map();
    this.glow = new Set();
    this.rand = rng(seed);
  }
  i(x, y, z) { return (x * this.Y + y) * this.Z + z; }
  inb(x, y, z) { return x >= 0 && y >= 0 && z >= 0 && x < this.X && y < this.Y && z < this.Z; }
  get(x, y, z) { return this.inb(x, y, z) ? this.g[this.i(x, y, z)] : 0; }
  c(col) {
    const key = col.toLowerCase();
    if (!this.idx.has(key)) { this.idx.set(key, this.pal.length); this.pal.push(hexrgb(key)); }
    return this.idx.get(key);
  }
  // put col where test(x, y, z) holds. only: a colour to paint over (or "filled"); keep: don't overwrite.
  _put(test, col, { only = null, keep = false } = {}) {
    const ci = col == null ? 0 : this.c(col);
    const oi = only && only !== "filled" ? this.c(only) : null;
    for (let x = 0; x < this.X; x++) for (let y = 0; y < this.Y; y++) for (let z = 0; z < this.Z; z++) {
      if (!test(x, y, z)) continue;
      const k = this.i(x, y, z), cur = this.g[k];
      if (only === "filled" && !cur) continue;
      if (oi !== null && cur !== oi) continue;
      if (keep && cur) continue;
      this.g[k] = ci;
    }
  }
  box(x0, x1, y0, y1, z0, z1, col, kw) {
    const [xa, xb] = [Math.min(x0, x1), Math.max(x0, x1)], [ya, yb] = [Math.min(y0, y1), Math.max(y0, y1)], [za, zb] = [Math.min(z0, z1), Math.max(z0, z1)];
    this._put((x, y, z) => x >= xa && x <= xb && y >= ya && y <= yb && z >= za && z <= zb, col, kw);
  }
  ell(cx, cy, cz, rx, ry, rz, col, kw) {
    this._put((x, y, z) => ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + ((z - cz) / rz) ** 2 <= 1, col, kw);
  }
  cyl(cx, cy, z0, z1, rx, col, ry, kw) {
    ry = ry || rx;
    this._put((x, y, z) => z >= z0 && z <= z1 && ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1, col, kw);
  }
  v(x, y, z, col) { x = Math.round(x); y = Math.round(y); z = Math.round(z); if (this.inb(x, y, z)) this.g[this.i(x, y, z)] = col ? this.c(col) : 0; }
  // paint the frontmost filled voxel in column (x, z)
  front(x, z, col, depth = 1) {
    for (let y = this.Y - 1; y >= 0; y--) if (this.get(x, y, z)) { for (let d = 0; d < depth; d++) if (y - d >= 0) this.g[this.i(x, y - d, z)] = this.c(col); return; }
  }
  texture(col, variants, p = 0.25) {
    const ci = this.c(col), vi = variants.map(v => this.c(v));
    for (let k = 0; k < this.g.length; k++) if (this.g[k] === ci && this.rand() < p) this.g[k] = vi[Math.floor(this.rand() * vi.length)];
  }
  mirrorX(x) { return this.X - 1 - x; }

  saveVox(path) {
    const vox = [];
    for (let x = 0; x < this.X; x++) for (let y = 0; y < this.Y; y++) for (let z = 0; z < this.Z; z++) { const c = this.get(x, y, z); if (c) vox.push([x, this.Y - 1 - y, z, c]); }
    const i32 = n => { const b = Buffer.alloc(4); b.writeInt32LE(n); return b; };
    const size = Buffer.concat([Buffer.from("SIZE"), i32(12), i32(0), i32(this.X), i32(this.Y), i32(this.Z)]);
    const xyzi = Buffer.concat([Buffer.from("XYZI"), i32(4 + 4 * vox.length), i32(0), i32(vox.length), Buffer.from(vox.flat())]);
    const rgba = Buffer.alloc(12 + 1024);
    rgba.write("RGBA", 0); rgba.writeInt32LE(1024, 4); rgba.writeInt32LE(0, 8);
    for (let i = 1; i < 256; i++) { const [r, g, b] = this.pal[i] || [0, 0, 0]; rgba.set([r, g, b, 255], 12 + (i - 1) * 4); }
    const children = Buffer.concat([size, xyzi, rgba]);
    fs.writeFileSync(path, Buffer.concat([Buffer.from("VOX "), i32(150), Buffer.from("MAIN"), i32(0), i32(children.length), children]));
    return vox.length;
  }

  // The preview: the same projection and face shading as vox.py's render(), painted far to near.
  render(yaw = -35, pitch = 28, scale = 10, bg = [32, 33, 40]) {
    const r = Math.PI / 180, cyw = Math.cos(yaw * r), syw = Math.sin(yaw * r), cp = Math.cos(pitch * r), sp = Math.sin(pitch * r);
    let L = [0.45, 0.55, 0.7]; const ln = Math.hypot(...L); L = L.map(v => v / ln);
    const glowI = new Set([...this.glow].map(h => this.idx.get(h.toLowerCase())));
    const X = this.X, Y = this.Y;
    const proj = p => { const x = p[0] - X / 2, y = p[1] - Y / 2, z = p[2]; const rx = x * cyw + y * syw, ry = -x * syw + y * cyw; return [rx, -(z * cp - ry * sp), ry * cp + z * sp]; };
    const polys = [];
    for (let axis = 0; axis < 3; axis++) for (const sign of [-1, 1]) {
      const n = [0, 0, 0]; n[axis] = sign;
      const vy = -n[0] * syw + n[1] * cyw;
      if (vy * cp + n[2] * sp <= 0.01) continue;
      const shade = 0.62 + 0.38 * Math.max(0, n[0] * L[0] + n[1] * L[1] + n[2] * L[2]);
      const [u, w] = [0, 1, 2].filter(a => a !== axis);
      for (let x = 0; x < X; x++) for (let y = 0; y < Y; y++) for (let z = 0; z < this.Z; z++) {
        const ci = this.get(x, y, z); if (!ci) continue;
        const nb = [x, y, z]; nb[axis] += sign; if (this.get(...nb)) continue;
        const base = [x, y, z]; if (sign > 0) base[axis] += 1;
        const pts = [[0, 0], [1, 0], [1, 1], [0, 1]].map(([du, dw]) => { const p = base.slice(); p[u] += du; p[w] += dw; return proj(p); });
        const sh = glowI.has(ci) ? 1 : shade;
        const rgb = this.pal[ci].map(c => Math.min(255, Math.floor(c * sh)));
        polys.push([pts.reduce((s, p) => s + p[2], 0) / 4, pts, rgb]);
      }
    }
    polys.sort((a, b) => a[0] - b[0]);
    let minx = 1e9, maxx = -1e9, miny = 1e9, maxy = -1e9;
    for (const [, ps] of polys) for (const p of ps) { minx = Math.min(minx, p[0]); maxx = Math.max(maxx, p[0]); miny = Math.min(miny, p[1]); maxy = Math.max(maxy, p[1]); }
    const pd = 2, W = Math.ceil((maxx - minx + 2 * pd) * scale), H = Math.ceil((maxy - miny + 2 * pd) * scale);
    const img = new Image(W, H, bg);
    for (const [, ps, rgb] of polys) {
      const pts = ps.map(p => [(p[0] - minx + pd) * scale, (p[1] - miny + pd) * scale]);
      img.poly(pts, rgb);
      img.outline(pts, rgb.map(c => Math.floor(c * 0.82)));
    }
    return img;
  }
}

class Image {
  constructor(w, h, bg = [0, 0, 0]) { this.w = w; this.h = h; this.d = Buffer.alloc(w * h * 3); for (let k = 0; k < w * h; k++) this.d.set(bg, k * 3); }
  px(x, y, c) { if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.d.set(c, (y * this.w + x) * 3); }
  // scanline fill of a convex polygon (PIL-like: pixel centres inside)
  poly(pts, c) {
    const ys = pts.map(p => p[1]); const y0 = Math.max(0, Math.floor(Math.min(...ys))), y1 = Math.min(this.h - 1, Math.ceil(Math.max(...ys)));
    for (let y = y0; y <= y1; y++) {
      const yc = y + 0.5; const xs = [];
      for (let i = 0; i < pts.length; i++) { const a = pts[i], b = pts[(i + 1) % pts.length]; if ((a[1] <= yc && b[1] > yc) || (b[1] <= yc && a[1] > yc)) xs.push(a[0] + (yc - a[1]) / (b[1] - a[1]) * (b[0] - a[0])); }
      if (xs.length < 2) continue; xs.sort((p, q) => p - q);
      for (let x = Math.ceil(xs[0] - 0.5); x <= Math.floor(xs[xs.length - 1] - 0.5); x++) this.px(x, y, c);
    }
  }
  outline(pts, c) {
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i], b = pts[(i + 1) % pts.length]; const n = Math.ceil(Math.max(Math.abs(b[0] - a[0]), Math.abs(b[1] - a[1]))) + 1;
      for (let k = 0; k <= n; k++) this.px(Math.floor(a[0] + (b[0] - a[0]) * k / n), Math.floor(a[1] + (b[1] - a[1]) * k / n), c);
    }
  }
  blit(src, ox, oy) { for (let y = 0; y < src.h; y++) for (let x = 0; x < src.w; x++) this.px(ox + x, oy + y, src.d.subarray((y * src.w + x) * 3, (y * src.w + x) * 3 + 3)); }
  savePng(path) {
    const crcT = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcT[n] = c >>> 0; }
    const crc = b => { let c = 0xffffffff; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
    const chunk = (t, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(t), data]); const cr = Buffer.alloc(4); cr.writeUInt32BE(crc(td)); return Buffer.concat([len, td, cr]); };
    const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(this.w, 0); ihdr.writeUInt32BE(this.h, 4); ihdr[8] = 8; ihdr[9] = 2;
    const raw = Buffer.alloc((this.w * 3 + 1) * this.h);
    for (let y = 0; y < this.h; y++) { raw[y * (this.w * 3 + 1)] = 0; this.d.copy(raw, y * (this.w * 3 + 1) + 1, y * this.w * 3, (y + 1) * this.w * 3); }
    fs.writeFileSync(path, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]));
  }
}

module.exports = { Model, Image };
