// Concept (not in the game): a black crow sorceress, an evil boss, in the menagerie units' style (chibi body,
// big head, voxel grid, front = +y). Writes crow_sorceress.vox and preview PNGs to the folder given.
//   node crow_sorceress.js <out dir>
const path = require("path");
const fs = require("fs");
const { Model, Image } = require("./voxkit");

const out = process.argv[2] || ".";
fs.mkdirSync(out, { recursive: true });

// palette
const BLACK = "#1e1a26", BLACK2 = "#282331", BLACK3 = "#15121b";      // garments and feathers
const SHEEN = "#3a3350", SHEEN_L = "#4a4166";                                                // blue-black sheen on the feathers
const PURPLE = "#6b2fb3", PURPLE_L = "#8e4ce0", PURPLE_D = "#4a1f80";  // hems
const BEAK = "#77718a", BEAK_D = "#4b4659", BEAK_L = "#9a94ad";
const TALON = "#2c2833", CLAW = "#a39db3";
const EYE = "#c86bff", EYE_CORE = "#f7e2ff";
const BROW = "#5b2a8f";
const WOOD = "#6b4423", WOOD_D = "#4e3018", WOOD_L = "#7f5530";
const GOLD = "#f2c14e", GOLD_D = "#c48f2a", GILT_L = "#fff0b3";
const GEM = "#a24dff", GEM_L = "#e6c8ff", GEM_D = "#6f22c9";
const MOTE = "#b56cff";

const m = new Model("crow_sorceress", 32, 30, 50, 1313);
const cx = m.cx, cy = 13;   // the body's centre column (front is +y)
const mx = x => m.mirrorX(x);

// --- the gown: floor length and flared, a tattered purple hem, purple trim down the front opening ---
for (let z = 0; z <= 11; z++) {
  const r = 7.8 - z * 0.42;   // flares out from a narrow waist
  m.cyl(cx, cy, z, z, r, BLACK, r * 0.86);
}
m.cyl(cx, cy, 0, 1, 7.8, PURPLE, 6.8, { only: BLACK });
m.cyl(cx, cy, 2, 2, 7.6, PURPLE_D, 6.6, { only: BLACK });
for (let x = 0; x < m.X; x++) for (let y = 0; y < m.Y; y++) {   // ragged: bites out of the hem
  const a = Math.atan2(y - cy, x - cx), d = Math.hypot((x - cx) / 7.8, (y - cy) / 6.8);
  if (d > 0.82 && Math.floor((a + Math.PI) * 4.2) % 3 === 0) { m.v(x, y, 0, null); if (Math.floor((a + Math.PI) * 4.2) % 2 === 0) m.v(x, y, 1, null); }
}
for (let z = 2; z <= 11; z++) { m.front(Math.floor(cx), z, z < 3 ? PURPLE_L : PURPLE); m.front(Math.ceil(cx), z, z < 3 ? PURPLE_L : PURPLE); }
m.texture(BLACK, [BLACK2], 0.18);

// --- bodice, sash, the soul-gem brooch ---
m.ell(cx, cy, 13, 4.6, 4.0, 4.2, BLACK);
m.cyl(cx, cy, 10, 10, 5.0, PURPLE, 4.4, { only: "filled" });
m.front(Math.floor(cx), 13, GEM); m.front(Math.ceil(cx), 13, GEM); m.front(Math.floor(cx), 12, GEM_D); m.front(Math.ceil(cx), 12, GEM_D);
m.front(Math.floor(cx), 14, GOLD); m.front(Math.ceil(cx), 14, GOLD);
m.glow.add(GEM);

m.cyl(cx, cy, 16, 16, 5.6, PURPLE, 4.8);
m.cyl(cx, cy, 17, 17, 5.0, PURPLE_D, 4.3, { keep: true });
for (let k = 0; k < 10; k++) { const a = k * Math.PI / 5; m.v(cx + 6 * Math.cos(a), cy + 5.2 * Math.sin(a), 16, PURPLE_L); }   // its points
for (const [x, z] of [[13, 15], [14, 14], [15, 13], [16, 14], [17, 15]]) m.front(x, z, PURPLE_L);   // a V neckline
// --- a high collar of black feather spikes behind the head, lined in purple ---
for (let k = -6; k <= 6; k++) {
  const a = Math.PI / 2 + k * 0.24;   // round the back (-y)
  const px = cx + 6.4 * Math.cos(a) * (k < 0 ? 1 : 1), py = cy - 5.2 * Math.sin(a);
  const tall = 20 + Math.round(3 - Math.abs(k) * 0.45);
  for (let z = 15; z <= tall; z++) m.v(px, py, z, z === tall ? SHEEN : BLACK);
  for (let z = 15; z <= tall - 2; z++) m.v(px + (cx - px) * 0.18, py + (cy - py) * 0.18, z, PURPLE_D);   // the lining, facing in
}

// --- the cape: tattered black feathers down her back ---
for (let x = Math.round(cx - 5); x <= Math.round(cx + 5); x++) {
  const top = 16 - Math.round(Math.abs(x - cx) * 0.5);
  const bottom = (x * 7) % 3;
  const y = cy - 6 - (Math.abs(x - cx) < 3 ? 1 : 0);
  for (let z = bottom; z <= top; z++) m.v(x, y, z, (z + x) % 4 === 0 ? SHEEN : BLACK);
  m.v(x, y, bottom, PURPLE);   // the train is hemmed too
}

// --- arms: bell sleeves with purple cuffs, crow talons for hands ---
const ax = cx - 5.2 - 1.3;
for (const side of [0, 1]) {
  const x = side ? mx(ax) : ax;
  m.ell(x, cy + 0.5, 12, 2.2, 2.2, 3.8, BLACK);
  m.cyl(x, cy + 1, 8, 9, 2.9, PURPLE, 2.6);
  m.cyl(x, cy + 1, 8, 8, 2.9, PURPLE_L, 2.6, { only: PURPLE });
  m.ell(x, cy + 2, 6.5, 1.5, 1.5, 1.6, TALON);
  for (const dx of [-1, 0, 1]) m.v(x + dx, cy + 3, 5, CLAW);   // claws curling under
}

// --- the head: glossy black, a long hooked beak, glowing violet eyes under an angry brow ---
const hz = 22;
m.ell(cx, cy, hz, 7.4, 6.4, 6.4, BLACK);
m.texture(BLACK, [BLACK2, SHEEN, BLACK3], 0.22);
m.ell(cx, cy + 2, hz + 3, 5.5, 4.5, 3, SHEEN, { only: BLACK });
m.ell(cx, cy + 2, hz + 3, 5.5, 4.5, 3, SHEEN_L, { only: BLACK2 });
const face = cy + 6;   // its front surface, roughly
m.box(Math.floor(cx) - 1, Math.ceil(cx) + 1, face, face + 1, hz - 3, hz - 1, BEAK);
m.box(Math.floor(cx), Math.ceil(cx), face + 2, face + 3, hz - 3, hz - 1, BEAK);
m.box(Math.floor(cx), Math.ceil(cx), face + 4, face + 4, hz - 3, hz - 2, BEAK_D);
m.box(Math.floor(cx), Math.ceil(cx), face + 5, face + 5, hz - 4, hz - 3, BEAK_D);   // the hook
m.box(Math.floor(cx) - 1, Math.ceil(cx) + 1, face, face + 2, hz - 1, hz - 1, BEAK_L);   // the beak's ridge, lit
const eyes = [[9, 23, EYE], [10, 23, EYE], [11, 23, EYE], [12, 23, EYE], [9, 22, EYE], [10, 22, EYE_CORE], [11, 22, EYE_CORE], [12, 22, EYE], [10, 21, EYE], [11, 21, EYE]];
for (const [x, z, c] of eyes) { m.front(x, z, c); m.front(mx(x), z, c); }
m.glow.add(EYE); m.glow.add(EYE_CORE);
for (const [x, z] of [[8, 26], [9, 25], [10, 25], [11, 24], [12, 24], [13, 24]]) { m.front(x, z, BROW); m.front(mx(x), z, BROW); }   // brows slanting down to the beak

// --- the hat: a wide brim with a purple hem, a purple band with a glowing crescent, a tall crooked cone ---
const bz = 29;
m.cyl(cx, cy, bz, bz, 9.6, BLACK, 8.6);
m.cyl(cx, cy, bz, bz, 9.6, PURPLE, 8.6, { only: BLACK });
m.cyl(cx, cy, bz, bz, 8.3, BLACK, 7.3, { only: PURPLE });
m.cyl(cx, cy, bz - 1, bz - 1, 9.8, PURPLE_D, 8.8, { keep: true });   // the hem turned down a little
m.cyl(cx, cy, bz - 1, bz - 1, 8.6, null, 7.6);                         // (only the rim)
m.cyl(cx, cy, bz - 1, bz - 1, 7.4, BLACK, 6.4, { keep: true });       // so the head meets the brim
const coneH = 16;
for (let i = 0; i < coneH; i++) {
  const z = bz + 1 + i;
  const r = Math.max(6.0 - i * (5.4 / coneH), 0.7);
  const back = i > 5 ? (i - 5) * 0.55 : 0, side = i > 9 ? (i - 9) * 0.6 : 0;   // bends back, then over to one side
  m.cyl(cx + side, cy - back, z, z, r, BLACK, Math.max(r * 0.9, 0.7));
}
m.cyl(cx, cy, bz + 1, bz + 2, 6.4, PURPLE, 5.8, { only: "filled" });
m.cyl(cx, cy, bz + 1, bz + 1, 6.4, PURPLE_L, 5.8, { only: PURPLE });
for (const [x, z] of [[14, bz + 3], [14, bz + 4], [15, bz + 4], [16, bz + 4], [14, bz + 5], [15, bz + 6], [16, bz + 6], [15, bz + 5]]) m.front(x, z, EYE);   // a crescent moon
m.texture(BLACK, [BLACK2], 0.12);

// --- the staff in her left hand: dark brown, gold claws holding a big glowing purple jewel ---
const sx = Math.round(mx(ax)) + 2, sy = cy + 3, top = 31;
m.box(sx, sx, sy, sy, 0, top, WOOD);
m.texture(WOOD, [WOOD_D, WOOD_L], 0.3);
for (const [x, z] of [[sx - 1, 4], [sx + 1, 9], [sx - 1, 15], [sx + 1, 21]]) m.v(x, sy, z, WOOD_D);   // knots
m.box(sx - 1, sx + 1, sy - 1, sy + 1, top, top + 1, GOLD);
m.box(sx - 1, sx + 1, sy - 1, sy + 1, top, top, GOLD_D);
for (const [dx, dy] of [[-2, 0], [2, 0], [0, -2], [0, 2]]) {   // four gold claws curling round the jewel
  for (let z = top + 2; z <= top + 4; z++) m.v(sx + dx, sy + dy, z, z === top + 4 ? GILT_L : GOLD);
  m.v(sx + Math.sign(dx) * 2, sy + Math.sign(dy) * 2, top + 5, GILT_L);
}
m.ell(sx, sy, top + 5.5, 1.7, 1.7, 3.2, GEM);   // a big jewel rising out of the claws
m.v(sx, sy + 1, top + 6, GEM_L); m.v(sx, sy, top + 8, GEM_L); m.v(sx + 1, sy + 1, top + 7, GEM_L); m.v(sx, sy + 1, top + 4, GEM_D); m.v(sx - 1, sy, top + 4, GEM_D);
m.glow.add(GEM); m.glow.add(GEM_L);
for (const [x, y, z] of [[sx - 3, sy, top + 10], [sx + 3, sy + 1, top + 7], [sx, sy - 3, top + 11], [sx + 2, sy + 3, top + 3]]) m.v(x, y, z, GEM_L);   // shards in its light

// --- a boss's aura: violet motes drifting round her ---
for (const [x, y, z] of [[2, cy + 2, 6], [4, cy + 6, 14], [1, cy - 2, 20], [29, cy - 4, 9], [27, cy + 5, 18], [6, cy - 6, 27], [30, cy + 1, 25], [3, cy + 8, 3]]) m.v(x, y, z, MOTE);
m.glow.add(MOTE);

// --- write it out ---
const n = m.saveVox(path.join(out, "crow_sorceress.vox"));
const views = [[-35, "3q"], [0, "front"], [35, "3q_left"], [180, "back"]];
const imgs = views.map(([yaw]) => m.render(yaw, 28, 10));
imgs[0].savePng(path.join(out, "crow_sorceress.png"));
const W = imgs.reduce((s, i) => s + i.w, 0), H = Math.max(...imgs.map(i => i.h));
const sheet = new Image(W, H, [32, 33, 40]);
let ox = 0;
for (const i of imgs) { sheet.blit(i, ox, H - i.h); ox += i.w; }
sheet.savePng(path.join(out, "crow_sorceress_views.png"));
console.log(`${n} voxels, ${m.pal.length - 1} colours -> ${out}`);
