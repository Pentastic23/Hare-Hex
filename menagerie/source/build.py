"""Build every unit at every tier: .vox, rigged+animated .glb, preview PNGs, metadata."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from units import UNITS, TIER_SCALE
from anims import clips_for, sample
from vox import PARTS, PID

out = sys.argv[1] if len(sys.argv) > 1 else 'out2'
only = sys.argv[2:] or None
for d in ('vox', 'glb', 'png'):
    os.makedirs(os.path.join(out, d), exist_ok=True)
meta = []
for cls, fn in UNITS:
    if only and cls not in only:
        continue
    for tier in (1, 2, 3, 4):
        t0 = time.time()
        m = fn(tier)
        m.trim()
        name = f'{m.name}_{tier}star'
        bones_present = [b for b in PARTS if b in m.pivots or (m.p == PID[b]).any()]
        clips = clips_for(m, set(bones_present) | {'root'})
        m.save_vox(f'{out}/vox/{name}.vox')
        info = m.save_glb(f'{out}/glb/{name}.glb', voxel=0.05 * TIER_SCALE[tier], clips=clips)
        m.render(f'{out}/png/{name}.png', scale=8)
        meta.append(dict(cls=cls, tier=tier, file=name, voxels=int((m.g > 0).sum()), tris=info['tris'],
                         bones=info['bones'], clips={k: round(v['dur'], 2) for k, v in clips.items()},
                         height=round(m.g.shape[2] * 0.05 * TIER_SCALE[tier], 2)))
        print(f'{name:28s} {info["tris"]:5d} tris  {len(info["bones"])} bones  {info["prims"]} prims  {time.time()-t0:.1f}s', flush=True)
if not only:
    json.dump(meta, open(f'{out}/units.json', 'w'), indent=1)
