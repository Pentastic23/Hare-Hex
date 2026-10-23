"""The other 55 AZTactics units as animals, built with kit.py. Same file naming as units.py:
<unit>_<animal>_<n>star. Order follows docs/units.md (by cost)."""
import math
import numpy as np

from kit import Spec, build, shade, mix
from units import WHITE, BLACK, GILT, GOLD, RUBY, SAPPHIRE, EMERALD
from vox import PID


# ---------------------------------------------------------------- small custom pieces

def frog_eyes(c, tier):
    m = c.m
    m.part = 'head'
    for sgn in (-1, 1):
        ex = c.cx + sgn * 3.6
        m.ell(ex, c.face_y - 2.5, c.top - 0.5, 2.0, 2.0, 2.0, c.s.fur)
        m.ell(ex, c.face_y - 1.4, c.top - 0.3, 1.3, 1.0, 1.3, WHITE)
        m.v(round(ex - 0.3), round(c.face_y - 0.4), round(c.top - 0.3), BLACK)
        m.v(round(ex - 0.3), round(c.face_y - 0.4), round(c.top - 1.3), BLACK)


def buck_teeth(c, tier):
    c.m.part = 'head'
    c.m.front(round(c.cx) - 1, round(c.hz - 4), WHITE)
    c.m.front(round(c.cx), round(c.hz - 4), WHITE)
    c.m.front(round(c.cx) - 1, round(c.hz - 5), WHITE)
    c.m.front(round(c.cx), round(c.hz - 5), WHITE)


def big_nose(col):
    def f(c, tier):
        c.m.part = 'head'
        c.m.ell(c.cx, c.face_y - 0.2, c.hz - 2.2, 1.6, 1.2, 2.2, col)
    return f


def nose_ring(c, tier):
    c.m.part = 'head'
    for dz, dy in ((0, 0), (-1, 0.6), (-1, -0.6)):
        c.m.v(round(c.cx) - 1, round(c.face_y + 1.6 + dy), round(c.hz - 4 + dz), GILT)


def moss(col):
    def f(c, tier):
        m = c.m
        for xx, yy, zz in np.argwhere((m.g > 0) & ((m.p == PID['body']) | (m.p == PID['head']))):
            if zz > 10 and m.rng.random() < 0.06:
                m.g[xx, yy, zz] = m.c(col)
    return f


def lava_cracks(c, tier):
    m = c.m
    m.glow.add('#ff9a3c')
    for xx, yy, zz in np.argwhere((m.g == m.c(c.s.fur))):
        if m.rng.random() < 0.07:
            m.g[xx, yy, zz] = m.c('#ff9a3c')


def ermine_cape(c, tier):
    m = c.m
    m.part = 'body'
    m.box(round(c.cx) - 6, round(c.cx) + 5, 5, 6, 2, 13, WHITE)
    for zz in range(3, 13, 3):
        for xx in range(round(c.cx) - 5, round(c.cx) + 5, 3):
            m.v(xx + (zz // 3) % 2, 5, zz, BLACK)
    m.ell(c.cx, 11.5, 13.6, 7.2, 5.8, 1.8, WHITE)


def gold_collar(c, tier):
    m = c.m
    m.part = 'body'
    m.ell(c.cx, 11.5, 13.4, 7.0, 5.6, 1.7, GILT)
    for xx in range(round(c.cx) - 5, round(c.cx) + 5, 2):
        m.front(xx, 13, SAPPHIRE)


def fuzz(col):
    def f(c, tier):
        m = c.m
        m.part = 'body'
        m.ell(c.cx, 11.5, 13.6, 7.4, 6.0, 2.4, col)
    return f


def flower_crown(c, tier):
    m = c.m
    m.part = 'head'
    for i, sgn in enumerate((-4, -2, 0, 2, 4)):
        m.v(round(c.cx + sgn), 14, round(c.top) - (1 if abs(sgn) == 4 else 0), ['#ff9ef0', '#ffd23a', '#9fe8ff', '#ffd23a', '#ff9ef0'][i])
        m.v(round(c.cx + sgn), 13, round(c.top) - (1 if abs(sgn) == 4 else 0), '#5cc27a')


def chest_fur(col):
    def f(c, tier):
        c.m.part = 'body'
        c.m.ell(c.cx, 14.5, 10.0, 4.2, 1.8, 4.0, col)
    return f


def wattle_ruff(col):
    def f(c, tier):
        c.m.part = 'head'
        c.m.ell(c.cx, c.face_y - 1, c.hz - 6, 2.0, 1.2, 1.6, col)
    return f


def flame_crest(c, tier):
    m = c.m
    m.part = 'head'
    for i, (dx, col) in enumerate(((-1.5, '#ff5a2a'), (0, '#ffd23a'), (1.5, '#ff9a3c'))):
        b = (c.cx + dx * 0.5, 13, c.top - 1)
        m.line(b, (c.cx + dx, 8, c.top + 3 + (1 if dx == 0 else 0)), col, r=0.6)
        m.line((c.cx + dx, 8, c.top + 3), (c.cx + dx * 1.3, 4.5, c.top + 2), col, r=0.4)
    m.glow |= {'#ffd23a', '#ff9a3c'}


def spade_tail(c, tier):
    m = c.m
    m.part = 'tail'
    pts = [(c.cx, 6, 4), (c.cx + 1, 2, 4), (c.cx + 3, 0.5, 7), (c.cx + 4, 1, 10)]
    for i in range(len(pts) - 1):
        m.line(pts[i], pts[i + 1], c.s.fur, r=0.4)
    m.box(round(c.cx + 3), round(c.cx + 5), 1, 1, 10, 11, '#2a1418')
    m.v(round(c.cx + 4), 1, 12, '#2a1418')
    m.pivots['tail'] = (c.cx, 7, 4.5)


# ---------------------------------------------------------------- the roster

O, W, S, A, U, E, F, Y, D, I = 'Order', 'Wild', 'Shadow', 'Arcane', 'Undead', 'Ember', 'Frost', 'Fey', 'Dwarven', 'Infernal'

SPECS = [
    # ===== 1 cost
    Spec('Militia', 'militia_badger', O, 'Protector', fur='#4a4a52', light='#e8e8e8', dark='#1e1e22',
         pattern=('badger', '#1e1e22', {'stripe': '#f2f2f2'}), ears=('round', {'r': 1.6}), snout=('long', {'len': 2, 'w': 2.3}),
         weapon=('spear',), offhand=('round',), tail=('stub', '#2a2a30')),
    Spec('Scout', 'scout_hare', W, 'Ranger', fur='#c49a6c', light='#f1e3cf', dark='#e09aa8',
         ears=('long', {'h': 9}), snout=('flat',), tail=('stub', '#ffffff'), weapon=('bow',), Z=40,
         extras=[('whiskers', '#f1e3cf')]),
    Spec('Acolyte', 'acolyte_mouse', O, 'Healer', fur='#9e9aa3', light='#efe6ea', dark='#e8a0b4',
         ears=('big', {'r': 3.2, 'dz': 4}), snout=('muzzle', {'w': 2.2, 'd': 1.6, 'h': 1.6}), eyes='big',
         tail=('thin', '#e8a0b4', {'r': 0.4}), weapon=('crossstaff',), extras=[('whiskers', '#5a5560')]),
    Spec('Apprentice', 'apprentice_frog', A, 'Caster', fur='#5cae4a', light='#d9e8a0', dark='#2a4a22',
         snout=('flat', {'mouth': '#2a4a22'}), eyes='sleepy', weapon=('wand',), offhand=('book',),
         extras=[(frog_eyes,)]),
    Spec('Skeleton', 'skeleton_rat', U, 'Warrior', fur='#e8e2d0', fur2='#d6cfba', light='#f5f0e2', dark='#2b2f2a',
         eyes='glow', eye_color='#7dff9b', ears=('round', {'r': 1.6}), snout=('long', {'len': 3, 'w': 2.0}),
         tail=('thin', '#d6cfba', {'r': 0.35}), outfit='Plain', weapon=('sword',), offhand=('buckler',),
         extras=[('bones', '#8a8270'), ('glow_eyes', '#7dff9b')]),
    Spec('Imp', 'imp_bat', I, 'Rogue', fur='#5a2430', light='#c45a5a', dark='#2a1418', eyes='narrow', eye_color='#ffcf3f',
         ears=('pointy', {'h': 5, 'w': 4, 'spread': 5.5}), snout=('flat',), horns=('small', '#2a1418'),
         wings=('bat', '#3a1820', '#2a1014', {'span': 8, 'z': 8}), weapon=('dagger',), extras=[(spade_tail,)]),
    Spec('Sprite', 'sprite_squirrel', Y, 'Caster', fur='#c0703a', light='#f3d9b8', dark='#5a2a1a',
         ears=('pointy', {'h': 3, 'w': 3, 'spread': 5}), snout=('muzzle', {'w': 2.3, 'd': 1.5, 'h': 1.6}), eyes='big',
         tail=('squirrel', '#f3d9b8'), wings=('fairy', '#ffd6f1', '#9fe8ff', {'z': 10, 'span': 6}), weapon=('orbstaff',)),
    Spec('Firebrand', 'firebrand_redpanda', E, 'Warrior', fur='#c4542a', light='#f4e6d6', dark='#3a1a12',
         ears=('round', {'r': 2.0}, '#f4e6d6'), snout=('muzzle', {'w': 2.8}), pattern=('lower', '#f4e6d6', {'dz': 0.5, 'depth': 3}),
         tail=('thin', '#c4542a', {'r': 1.3, 'ring': '#5a2418'}), weapon=('sword', 'r', {'flame': True})),
    Spec('Frostling', 'frostling_penguin', F, 'Ranger', fur='#2a2d3a', light='#f4f6fa', dark='#f2a13a',
         pattern=('face', '#f4f6fa', {'w': 4.5, 'h': 4.0}), snout=('beak', {'len': 2, 'color': '#f2a13a'}),
         legs='#f2a13a', hands='#2a2d3a', tail=('feather', '#2a2d3a'), weapon=('crossbow', 'l'), outfit='Ranger'),
    Spec('Miner', 'miner_mole', D, 'Warrior', fur='#4a3f4a', light='#e3a8b6', dark='#e3a8b6', eyes='beady',
         snout=('long', {'len': 2, 'w': 1.6, 'top_fur': False}), hands='#e3a8b6', hat=('lamp',), weapon=('pickaxe',),
         outfit='Ranger', pal={'cloth': '#7a5a3a', 'cloth2': '#5a4632'}),
    Spec('Initiate', 'initiate_monkey', W, 'Monk', fur='#7a5232', light='#e8c9a0', dark='#3a2418',
         pattern=('face', '#e8c9a0', {'w': 5.0, 'h': 4.5}), ears=('big', {'r': 2.2, 'dz': 0}, '#e8c9a0'), snout=('flat', {'mouth': '#3a2418'}),
         tail=('thin', '#7a5232', {'r': 0.6, 'pts': [(12.5, 6, 4), (13.5, 2, 4), (15.5, 0.5, 7), (16.5, 1, 11), (15, 2.5, 13), (14, 2, 11.5)]}),
         hat=('headband', '#c0303a'), weapon=('fist',)),
    # ===== 2 cost
    Spec('Bard', 'bard_robin', Y, 'Bard', fur='#7a5a3c', light='#e66a3a', dark='#3b2716',
         pattern=('lower', '#e66a3a', {'dz': 1, 'depth': 5}), snout=('beak', {'len': 1, 'color': '#3b2716'}), eyes='small',
         hat=('cap', '#4fb3a5'), tail=('feather', '#5a4030', '#7a5a3c'), offhand=('lute',)),
    Spec('Alchemist', 'alchemist_beaver', D, 'Alchemist', fur='#8a5a34', light='#d9b48a', dark='#2a1a12',
         ears=('round', {'r': 1.4}), snout=('muzzle', {'w': 2.8}), tail=('paddle', '#5a3c26'), weapon=('flask',),
         extras=[(buck_teeth,)]),
    Spec('Necromancer', 'necromancer_raven', U, 'Summoner', fur='#2e2a38', fur2='#36313f', light='#4a4656', dark='#3a3a44',
         snout=('beak', {'len': 3, 'color': '#9a96a6', 'hook': True}), pal={'cloth': '#3a4a36', 'cloth2': '#4a3a62'}, eyes='glow', eye_color='#7dff9b',
         tail=('feather', '#26232e', '#3a3646'), weapon=('skullstaff',), offhand=('book',), extras=[('glow_eyes', '#7dff9b')]),
    Spec('Ghoul', 'ghoul_hyena', U, 'Rogue', fur='#b8b48a', light='#d8d6b8', dark='#2a2a1e', eyes='glow', eye_color='#b6ff7d',
         pattern=('spots', '#6b6a4a', {'p': 0.1}), ears=('round', {'r': 2.2}), snout=('long', {'len': 3}),
         tail=('bushy', '#6b6a4a', '#3a3a28'), weapon=('claws',), offhand=('claws',),
         style={'attack': 'dual'}, extras=[('mane', '#5a5a3a'), ('glow_eyes', '#b6ff7d')]),
    Spec('Sparkcaller', 'sparkcaller_salamander', E, 'Caster', fur='#d9522a', light='#ffb13b', dark='#2a1a12',
         pattern=('spots', '#2a1a12', {'p': 0.12}), snout=('flat', {'mouth': '#2a1a12'}), eyes='big', head_r=(7.8, 6.5, 5.8),
         tail=('thin', '#d9522a', {'r': 1.1}), weapon=('flamestaff',)),
    Spec('Frost Archer', 'frostarcher_lynx', F, 'Ranger', fur='#e8e6e0', fur2='#d2cfc6', light='#ffffff', dark='#3a3a40',
         pattern=('spots', '#9a9aa0', {'p': 0.08}), ears=('pointy', {'h': 5, 'w': 4, 'tip': '#1e1e22'}),
         snout=('muzzle', {'w': 3.0}), eyes='narrow', eye_color='#3a8ab0', tail=('stub', '#1e1e22'), weapon=('bow',),
         extras=[('whiskers', '#ffffff')]),
    Spec('Ironbeard', 'ironbeard_goat', D, 'Protector', fur='#f1ede2', light='#ffffff', dark='#3a3a3a', eyes='narrow', eye_color='#8a6a1a',
         ears=('side', {'len': 3}), snout=('long', {'len': 2, 'w': 2.2}), horns=('swept', '#4a4a4a'),
         weapon=('hammer',), offhand=('round',), extras=[('beard', '#e0dccc')]),
    Spec('Druid', 'druid_stag', W, 'Healer', fur='#a0673a', light='#ead8bc', dark='#2a1a12',
         pattern=('spots', '#ead8bc', {'p': 0.06}), ears=('side', {'len': 3}), snout=('long', {'len': 2, 'w': 2.2}),
         horns=('antlers', '#d9c8a0', {'leaves': '#5cc27a'}), tail=('stub', '#ffffff'), weapon=('leafstaff',), Z=40),
    Spec('Monk', 'monk_panda', O, 'Monk', fur='#f3f1ec', light='#ffffff', dark='#1e1e24',
         pattern=('panda', '#1e1e24'), ears=('round', {'r': 2.0, 'col': '#1e1e24'}, '#1e1e24'), snout=('muzzle', {'w': 2.8}),
         legs='#1e1e24', hands='#1e1e24', weapon=('fist',)),
    Spec('Cultist', 'cultist_ferret', I, 'Summoner', fur='#d9c8a8', light='#f4ece0', dark='#3a2a20',
         pattern=('mask', '#5a4232'), ears=('round', {'r': 1.4}), snout=('muzzle', {'w': 2.4, 'd': 1.8}),
         tail=('thin', '#5a4232', {'r': 0.9}), weapon=('book', 'r', {'float_orb': True})),
    Spec('Nightblade', 'nightblade_panther', S, 'Warrior', fur='#232027', fur2='#2e2a33', light='#3a3540', dark='#111014',
         eyes='narrow', eye_color='#ffd23a', ears=('pointy', {'h': 3, 'w': 3}), snout=('muzzle', {'w': 2.8}),
         tail=('thin', '#232027', {'r': 0.7}), weapon=('sword', 'r', {'extra': 2}), extras=[('whiskers', '#8a8a96')]),
    # ===== 3 cost
    Spec('Pyromancer', 'pyromancer_meerkat', E, 'Caster', fur='#c9a77a', light='#efe0c4', dark='#3a2a1e',
         pattern=('panda', '#5a4232'), ears=('small',), snout=('muzzle', {'w': 2.2, 'd': 1.6}), tail=('thin', '#c9a77a', {'r': 0.6, 'tip': '#3a2a1e'}),
         hat=('wizard', '#b8392b'), weapon=('flamestaff',)),
    Spec('Paladin', 'paladin_retriever', O, 'Healer', fur='#d9a04a', light='#f0d29a', dark='#2a1a12',
         ears=('floppy', {'len': 6}), snout=('long', {'len': 2.5}), outfit='Warrior', weapon=('hammer', 'r', {'head': '#f2c14e'}),
         offhand=('heater',), tail=('bushy', '#d9a04a', '#f0d29a')),
    Spec('Ice Mage', 'icemage_walrus', F, 'Caster', fur='#a87a62', light='#d9b8a0', dark='#3a2a22', eyes='small',
         snout=('muzzle', {'w': 3.8, 'h': 2.4}), horns=('tusks', '#f3ecd8', {'len': 5, 'down': True}),
         hat=('wizard', '#5aa6d6'), weapon=('icestaff',), stout=1),
    Spec('Dryad', 'dryad_koala', Y, 'Healer', fur='#9a9aa4', light='#e4e2e8', dark='#2a2a30',
         ears=('round', {'r': 3.0}, '#e4e2e8'), snout=('flat',), weapon=('leafstaff',),
         extras=[(big_nose('#2a2a30'),), (flower_crown,)]),
    Spec('Minstrel', 'minstrel_otter', Y, 'Bard', fur='#7a5238', light='#d9b896', dark='#2a1a12',
         ears=('round', {'r': 1.3}), snout=('muzzle', {'w': 3.0}), tail=('thin', '#7a5238', {'r': 1.1}), weapon=('flute',),
         hat=('beret', '#c45fa6'), extras=[('whiskers', '#d9b896')]),
    Spec('Skald', 'skald_boar', D, 'Bard', fur='#6a4a3a', light='#b08a70', dark='#3a2418', eyes='small',
         ears=('pointy', {'h': 3, 'w': 3}), snout=('pig', {'r': 2.2}), horns=('tusks', '#efe4c9', {'len': 3}),
         hat=('horned_helm',), weapon=('axe',), offhand=('horn',), tail=('curly', '#6a4a3a'), extras=[('beard', '#3a2a20')]),
    Spec('Plague Doctor', 'plaguedoctor_vulture', U, 'Alchemist', fur='#3a3236', light='#efe8e0', dark='#2a2420', head_col='#4a4246',
         snout=('beak', {'len': 5, 'color': '#d9c8a0', 'hook': True}), eyes='big', eye_color='#c0303a', hat=('plague',),
         weapon=('flask', 'r', {'liquid': '#9bff6b'}), extras=[('neck_ruff', '#efe8e0')]),
    Spec('Runesmith', 'runesmith_armadillo', D, 'Alchemist', fur='#b09a8a', light='#d9c8b8', dark='#3a2a22',
         ears=('small',), snout=('long', {'len': 3, 'w': 2.0}), weapon=('runestaff', 'r', {'gem': '#ffcf6b'}),
         tail=('thin', '#8a7a6a', {'r': 0.9}), extras=[('shell', '#8a7a6a', '#6a5a4a')]),
    Spec('Shadowfist', 'shadowfist_skunk', S, 'Monk', fur='#1f1d24', light='#3a3640', dark='#111014',
         pattern=('skunk', WHITE), ears=('round', {'r': 1.4}), snout=('muzzle', {'w': 2.4}), tail=('skunk', '#1f1d24'),
         weapon=('fist',), style={'skill': 'shadowstep'}),
    Spec('Sunmonk', 'sunmonk_tiger', E, 'Monk', fur='#e0882a', light='#f8f0e0', dark='#2a1a12',
         pattern=[('lower', '#f8f0e0', {'dz': 1, 'depth': 3}), ('stripes', '#2a1a12')], ears=('round', {'r': 1.8}, '#f8f0e0'),
         snout=('muzzle', {'w': 3.0}), tail=('thin', '#e0882a', {'r': 0.8, 'ring': '#2a1a12'}), weapon=('fist',),
         extras=[('whiskers', '#f8f0e0')], style={'skill': 'spin'}),
    Spec('Demonologist', 'demonologist_lemur', I, 'Summoner', fur='#9a969e', light='#f0eef0', dark='#2a2a30',
         pattern=('panda', '#2a2a30'), eyes='big', eye_color='#e08a1a', ears=('pointy', {'h': 3, 'w': 3}), snout=('long', {'len': 2, 'w': 1.8}),
         tail=('thin', '#f0eef0', {'r': 0.8, 'ring': '#1e1e24', 'pts': [(12.5, 6, 4), (13, 2, 5), (14, 1, 10), (14.5, 1.5, 15), (13.5, 2.5, 19), (12.5, 3.5, 21)]}),
         weapon=('book', 'r', {'float_orb': True}), offhand=('lantern',)),
    Spec('Winter Knight', 'winterknight_polarbear', F, 'Warrior', fur='#f4f2ec', light='#ffffff', dark='#1e1e24',
         ears=('round', {'r': 1.7}), snout=('muzzle', {'w': 3.0}), hat=('helm',), weapon=('greatsword',), stout=1),
    # ===== 4 cost
    Spec('Warlord', 'warlord_rhino', O, 'Warrior', fur='#8a8a92', light='#b0b0b8', dark='#3a3a40', eyes='small',
         ears=('pointy', {'h': 3, 'w': 2, 'spread': 5}), snout=('muzzle', {'w': 3.6, 'd': 2.4, 'h': 2.4}), horns=('rhino', '#e8e2d0'),
         weapon=('halberd',), stout=1, extras=[('cape', '#a8242f', GOLD)]),
    Spec('Duelist', 'duelist_rooster', Y, 'Rogue', fur='#d9692a', light='#f2c14e', dark='#3b2716', head_col='#e8a040',
         snout=('beak', {'len': 2, 'color': '#f2c14e'}), eyes='small', tail=('fan', '#2f6b4f', None, {'cols': ['#2f6b4f', '#1f4a3a', '#3c8462']}),
         weapon=('sword', 'r', {'extra': 1}), extras=[('crest', '#e0303a', 4, True)]),
    Spec('Nightstalker', 'nightstalker_coyote', S, 'Ranger', fur='#8a7a6a', light='#d9cbb6', dark='#1e1a16', eyes='narrow', eye_color='#b47cff',
         ears=('pointy', {'h': 6, 'w': 4}), snout=('long', {'len': 3}), tail=('bushy', '#8a7a6a', '#2a2420'), weapon=('bow',),
         extras=[('glow_eyes', '#b47cff')], Z=40),
    Spec('Lich', 'lich_crocodile', U, 'Caster', fur='#5a6a4a', light='#c8c8a0', dark='#1e2418', eyes='glow', eye_color='#7dff9b',
         snout=('croc', {'len': 6}), tail=('croc', '#5a6a4a'), hat=('hood', '#2b2f2a'), weapon=('skullstaff',),
         extras=[('glow_eyes', '#7dff9b')]),
    Spec('Magma Guard', 'magmaguard_hippo', E, 'Protector', fur='#7a6a7a', light='#c89aa0', dark='#3a2a30', eyes='small',
         ears=('small',), snout=('pig', {'r': 3.0}), weapon=('mace',), offhand=('tower',), stout=1, extras=[(lava_cracks,)]),
    Spec('Frost Giant', 'frostgiant_mammoth', F, 'Protector', fur='#7a5a44', light='#a88466', dark='#2a1a12', eyes='small',
         ears=('big', {'r': 3.2, 'dz': 0}), snout=('trunk',), horns=('tusks', '#f6f0e0', {'len': 5}), weapon=('hammer',), offhand=('tower',),
         stout=1, extras=[('chest', '#5a4030')]),
    Spec('Dwarf Gunner', 'dwarfgunner_hedgehog', D, 'Ranger', fur='#c9a982', light='#efe0c4', dark='#2a1a12', eyes='beady',
         ears=('small',), snout=('long', {'len': 2, 'w': 1.6}), weapon=('musket', 'l'), extras=[('spikes', '#5a4232', '#efe0c4'), ('beard', '#8a5a34')]),
    Spec('Archmage', 'archmage_peacock', A, 'Caster', fur='#2a5fae', light='#5cc2c2', dark='#1e2766',
         snout=('beak', {'len': 2, 'color': '#d9c8a0'}), eyes='small', tail=('fan', '#2f8a7a'), weapon=('orbstaff',),
         extras=[('plume', '#2a5fae', '#5cc2c2')]),
    Spec('Herald', 'herald_eagle', O, 'Bard', fur='#5a3a26', light='#f4f2ec', dark='#3b2716', head_col='#f4f2ec',
         snout=('beak', {'len': 3, 'color': '#f2c14e', 'hook': True}), eyes='narrow', eye_color='#8a6a1a', weapon=('banner',),
         offhand=('horn',), tail=('feather', '#f4f2ec', '#e8e2d0')),
    Spec('Hellknight', 'hellknight_bull', I, 'Warrior', fur='#3a2a2a', light='#6a4a4a', dark='#1e1414', eyes='glow', eye_color='#ff5a2a',
         ears=('side', {'len': 2}), snout=('muzzle', {'w': 3.4, 'd': 2.2}), horns=('bull', '#e8dccc', {'tip': '#2a1e1e'}),
         weapon=('axe',), stout=1, extras=[(nose_ring,), ('glow_eyes', '#ff5a2a')]),
    Spec('Beastmaster', 'beastmaster_gorilla', W, 'Summoner', fur='#3a3a40', light='#7a7480', dark='#1e1e22',
         pattern=('face', '#7a7480', {'w': 4.5, 'h': 4.2}), ears=('small',), snout=('flat', {'mouth': '#1e1e22'}), stout=1,
         outfit='Plain', weapon=('totem',), extras=[('neck_ruff', '#8a6a4a'), (chest_fur('#5a5a62'),)]),
    Spec('Zen Master', 'zenmaster_crane', A, 'Monk', fur='#f4f2ec', light='#ffffff', dark='#1e1e24',
         snout=('beak', {'len': 4, 'color': '#5a5a5a'}), eyes='small', pattern=('cap', '#e0303a', {'dz': 4.5}),
         tail=('feather', '#1e1e24', '#2a2a30'), weapon=('fist',), legs='#3a3a3a', style={'skill': 'spin'}),
    # ===== 5 cost
    Spec('Seraph', 'seraph_pegasus', O, 'Healer', fur='#f6f4ef', light='#ffffff', dark='#8a8aa0',
         snout=('horse', {'len': 4}), ears=('pointy', {'h': 3, 'w': 2, 'spread': 4.5}), wings=('angel', '#ffffff', '#e8d79a', {'span': 8}),
         weapon=('crossstaff',), tail=('horse', '#f2c14e', '#f2c14e'), stout=1, extras=[('mane', '#f2c14e')]),
    Spec('Deathlord', 'deathlord_jackal', U, 'Warrior', fur='#1e1c22', light='#2e2a33', dark='#0e0d10', eyes='glow', eye_color='#7dff9b',
         ears=('pointy', {'h': 7, 'w': 4, 'spread': 4.5}, '#f2c14e'), snout=('long', {'len': 4}), weapon=('scythe',), stout=1,
         extras=[(gold_collar,), ('glow_eyes', '#7dff9b')], Z=42),
    Spec('Titan', 'titan_elephant', D, 'Protector', fur='#8a8a96', light='#a8a8b4', dark='#3a3a40', eyes='small',
         ears=('big', {'r': 4.5, 'dz': 0}), snout=('trunk',), horns=('tusks', '#f6f0e0', {'len': 4}), weapon=('hammer',), offhand=('tower',),
         stout=1),
    Spec('Phoenix', 'phoenix_firebird', E, 'Summoner', fur='#e0442a', light='#ffd23a', dark='#5a1a10',
         snout=('beak', {'len': 2, 'color': '#ffd23a', 'hook': True}), eyes='narrow', eye_color='#ffd23a',
         wings=('flame', '#ff5a2a', '#b8241a', {'span': 9, 'z': 8, 'hot': '#ffd23a'}), tail=('fire', '#ff9a3c'), outfit='Plain', weapon=('fist',),
         extras=[(flame_crest,), ('flames', '#ffb13b')]),
    Spec('Archdemon', 'archdemon_ram', I, 'Caster', fur='#2a1e22', light='#5a3a3a', dark='#140e10', eyes='glow', eye_color='#ff7a2a',
         snout=('long', {'len': 2, 'w': 2.4}), horns=('ram', '#d9c8a8', {'tip': '#8a7a60'}), wings=('bat', '#3a1418', '#1e0a0c', {'span': 9}),
         weapon=('flamestaff',), stout=1, extras=[('glow_eyes', '#ff7a2a')]),
    Spec('Frost Queen', 'frostqueen_ermine', F, 'Caster', fur='#f8f8f6', light='#ffffff', dark='#1e1e24',
         ears=('round', {'r': 1.5}), snout=('muzzle', {'w': 2.3, 'd': 1.6}), tail=('thin', '#f8f8f6', {'r': 1.0, 'tip': '#1e1e24'}),
         hat=('circlet',), weapon=('icestaff',), extras=[(ermine_cape,)]),
    Spec('Faerie Queen', 'faeriequeen_moth', Y, 'Bard', fur='#d8f0c8', light='#f6fbe8', dark='#3b2a4a', eyes='bug', eye_color='#3b2a4a',
         ears=('antennae', {'color': '#e8d7a0', 'feathery': True}), snout=('none',), wings=('moth', '#bfe8a0', '#8fc878', {'span': 9, 'eye': '#ff9ef0', 'z': 9}),
         hat=('circlet',), offhand=('lute',), extras=[(fuzz('#f6fbe8'),)]),
    Spec('Reaper', 'reaper_mantis', S, 'Rogue', fur='#3f6a3a', light='#8fc878', dark='#1e2a1a', eyes='bug', eye_color='#2a1e3a',
         ears=('antennae', {'color': '#3f6a3a', 'tip': '#b47cff'}), snout=('mandible',), head_r=(7.0, 6.0, 5.6),
         wings=('fairy', '#a8d8a0', '#6aa060', {'z': 9, 'span': 6}), weapon=('scythe',), outfit='Rogue'),
    Spec('Treant', 'treant_moose', W, 'Protector', fur='#5a4030', light='#8a6a50', dark='#1e1410',
         ears=('side', {'len': 2}), snout=('horse', {'len': 3}), horns=('antlers', '#c8b088', {'big': 1.4, 'leaves': '#5cc27a', 'palm': True}),
         weapon=('hammer', 'r', {'head': '#6b4a2a'}), offhand=('round',), stout=1,
         extras=[('beard', '#3a2a20'), (moss('#5cc27a'),)], Z=44),
]

NAMES = {s.cls: s for s in SPECS}


def make(cls):
    s = NAMES[cls]
    return lambda tier=1: build(s, tier)


UNITS2 = [(s.cls, make(s.cls)) for s in SPECS]
