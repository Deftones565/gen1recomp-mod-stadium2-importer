#!/usr/bin/env python3
"""Convert Kenney props for the scene-kit environments (mountain, ice cave,
interior, industrial, ruins, ship, gym, league, cave water, indoor water).

Palette packs (Textures/colormap.png) are sampled from their OBJ UVs; MTL
packs use each material's diffuse colour. Every triangle gets a material ID
(lib/scene_kit.lua): 1 foliage, 2 wood, 3 stone, 4 plaster/sand, 5 cloth,
6 painted, 7 light, 9 metal. Names in MTL files are used as hints first.
"""
from pathlib import Path
import argparse
import colorsys
import shutil
from PIL import Image

MODELS = {
    # Mountain / ice (Nature Kit, MTL colours)
    'pine-a': ('Nature Kit', 'tree_pineDefaultA'), 'pine-b': ('Nature Kit', 'tree_pineRoundC'),
    'pine-tall': ('Nature Kit', 'tree_pineTallA'), 'pine-small': ('Nature Kit', 'tree_pineSmallB'),
    'rock-large-a': ('Nature Kit', 'rock_largeA'), 'rock-large-c': ('Nature Kit', 'rock_largeC'),
    'rock-tall-a': ('Nature Kit', 'rock_tallA'), 'rock-tall-e': ('Nature Kit', 'rock_tallE'),
    'stone-tall-b': ('Nature Kit', 'stone_tallB'), 'stone-large-b': ('Nature Kit', 'stone_largeB'),
    'bush-large': ('Nature Kit', 'plant_bushLarge'), 'grass-large': ('Nature Kit', 'grass_large'),
    'flower-yellow': ('Nature Kit', 'flower_yellowB'), 'log': ('Nature Kit', 'log'),
    'stump': ('Nature Kit', 'stump_roundDetailed'), 'mushroom': ('Nature Kit', 'mushroom_tanGroup'),
    # Interior (Furniture Kit, MTL colours)
    'bookcase': ('Furniture Kit', 'bookcaseOpen'), 'bookcase-wide': ('Furniture Kit', 'bookcaseClosedWide'),
    'desk': ('Furniture Kit', 'desk'), 'chair-desk': ('Furniture Kit', 'chairDesk'),
    'sofa': ('Furniture Kit', 'loungeSofa'), 'side-table': ('Furniture Kit', 'sideTable'),
    'lamp-floor': ('Furniture Kit', 'lampRoundFloor'), 'lamp-table': ('Furniture Kit', 'lampSquareTable'),
    'potted-plant': ('Furniture Kit', 'pottedPlant'), 'plant-small': ('Furniture Kit', 'plantSmall2'),
    'rug-round': ('Furniture Kit', 'rugRound'), 'rug': ('Furniture Kit', 'rugRectangle'),
    'bed': ('Furniture Kit', 'bedSingle'), 'tv': ('Furniture Kit', 'cabinetTelevision'),
    'computer': ('Furniture Kit', 'computerScreen'), 'radio': ('Furniture Kit', 'radio'),
    'books': ('Furniture Kit', 'books'), 'table-round': ('Furniture Kit', 'tableRound'),
    'chair': ('Furniture Kit', 'chair'), 'bench-cushion': ('Furniture Kit', 'benchCushion'),
    'coat-rack': ('Furniture Kit', 'coatRackStanding'), 'kitchen-fridge': ('Furniture Kit', 'kitchenFridge'),
    'box-open': ('Furniture Kit', 'cardboardBoxOpen'), 'box-closed': ('Furniture Kit', 'cardboardBoxClosed'),
    # Industrial (Factory Kit, City Kit Industrial, Space Station Kit)
    'conveyor': ('Factory Kit', 'conveyor-long'), 'hopper': ('Factory Kit', 'hopper-high-round'),
    'crane': ('Factory Kit', 'crane'), 'box-large': ('Factory Kit', 'box-large'),
    'box-wide': ('Factory Kit', 'box-wide'), 'catwalk': ('Factory Kit', 'catwalk-straight'),
    'cog': ('Factory Kit', 'cog-a'), 'cone': ('Factory Kit', 'cone'),
    'tank': ('City Kit - Industrial', 'detail-tank'), 'chimney': ('City Kit - Industrial', 'chimney-large'),
    'pipe': ('Space Station Kit', 'pipe'), 'pipe-bend': ('Space Station Kit', 'pipe-bend'),
    'container': ('Space Station Kit', 'container-tall'), 'computer-system': ('Space Station Kit', 'computer-system'),
    'display-wall': ('Space Station Kit', 'display-wall-wide'),
    # Ruins / league (Graveyard Kit, Castle Kit, Mini Arena)
    'column-large': ('Graveyard Kit', 'column-large'), 'pillar-large': ('Graveyard Kit', 'pillar-large'),
    'pillar-square': ('Graveyard Kit', 'pillar-square'), 'stone-wall': ('Graveyard Kit', 'stone-wall'),
    'stone-wall-damaged': ('Graveyard Kit', 'stone-wall-damaged'), 'stone-wall-column': ('Graveyard Kit', 'stone-wall-column'),
    'rocks-tall': ('Graveyard Kit', 'rocks-tall'), 'debris': ('Graveyard Kit', 'debris'),
    'urn': ('Graveyard Kit', 'urn-round'), 'lantern': ('Graveyard Kit', 'lantern-candle'),
    'fire-basket': ('Graveyard Kit', 'fire-basket'), 'altar': ('Graveyard Kit', 'altar-stone'),
    'pine-crooked': ('Graveyard Kit', 'pine-crooked'), 'candles': ('Graveyard Kit', 'candle-multiple'),
    'tower-arch': ('Castle Kit', 'tower-square-arch'), 'stairs-stone': ('Castle Kit', 'stairs-stone'),
    'castle-rocks': ('Castle Kit', 'rocks-large'), 'banner-long': ('Castle Kit', 'flag-banner-long'),
    'arena-banner': ('Mini Arena', 'banner'), 'arena-column': ('Mini Arena', 'column'),
    'arena-statue': ('Mini Arena', 'statue'), 'arena-trophy': ('Mini Arena', 'trophy'),
    # Ship (Pirate Kit)
    'mast': ('Pirate Kit', 'mast-ropes'), 'flag-high': ('Pirate Kit', 'flag-high'),
    'cannon': ('Pirate Kit', 'cannon'), 'barrel': ('Pirate Kit', 'barrel'), 'crate': ('Pirate Kit', 'crate'),
    'crate-bottles': ('Pirate Kit', 'crate-bottles'), 'boat-row-large': ('Pirate Kit', 'boat-row-large'),
    'railing': ('Pirate Kit', 'structure-fence'),
}

# Per-model material fixes where colour alone misleads (from -> to).
OVERRIDES = {
    'rock-large-a': {4: 3}, 'rock-large-c': {4: 3}, 'rock-tall-a': {4: 3}, 'rock-tall-e': {4: 3},
    'stone-tall-b': {4: 3}, 'stone-large-b': {4: 3}, 'flower-yellow': {7: 6}, 'mushroom': {7: 6},
    'arena-banner': {7: 5}, 'arena-column': {7: 6}, 'arena-trophy': {7: 9, 3: 9}, 'tower-arch': {7: 6},
    'cone': {7: 6}, 'box-large': {7: 6}, 'box-wide': {7: 6}, 'chimney': {7: 6}, 'container': {7: 6},
    'tank': {7: 6}, 'stairs-stone': {7: 6}, 'crane': {7: 6}, 'mast': {7: 5},
    'arena-statue': {7: 6}, 'fire-basket': {1: 9}, 'lantern': {1: 9},
}

HINTS = [
    (('leaf', 'leaves', 'plant', 'grass', 'green', 'foliage', 'tree'), 1),
    (('wood', 'bark', 'trunk', 'plank'), 2),
    (('stone', 'rock', 'brick', 'concrete', 'cliff'), 3),
    (('metal', 'steel', 'iron', 'chrome', 'silver'), 9),
    (('lamp', 'light', 'bulb', 'emission', 'glow', 'screen', 'fire', 'flame', 'candle'), 7),
    (('fabric', 'cloth', 'cushion', 'pillow', 'carpet', 'rug', 'sofa'), 5),
    (('dirt', 'sand'), 4),
]


def classify(rgb, hint=''):
    hint = hint.lower()
    for words, material in HINTS:
        if any(w in hint for w in words):
            return material
    r, g, b = (c / 255 for c in rgb)
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h *= 360
    if v > .92 and s > .35 and 20 <= h <= 60:
        return 7  # bright yellow/orange: flames and lamps
    if 70 <= h <= 170 and s > .25:
        return 1
    if s < .14 and v > .75:
        return 4  # pale plaster / marble
    if s < .24:
        return 3 if v < .75 else 4
    if 19.5 <= h <= 45 and s < .52:
        return 4
    if h <= 30 or h >= 340:
        return 2 if v < .8 or s > .5 else 6
    return 6


def load_mtl(path):
    colours, textured, current = {}, set(), None
    if not path.exists():
        return colours, textured
    for line in path.read_text().splitlines():
        f = line.split()
        if not f:
            continue
        if f[0] == 'newmtl':
            current = f[1]
        elif f[0] == 'Kd' and current:
            colours[current] = tuple(int(float(x) * 255) for x in f[1:4])
        elif f[0] == 'map_Kd' and current:
            textured.add(current)
    return colours, textured


def convert(base, source):
    obj = base / (source + '.obj')
    lines = obj.read_text().splitlines()
    mtl = None
    for line in lines:
        if line.startswith('mtllib'):
            mtl = base / line.split(maxsplit=1)[1].strip()
    colours, textured = load_mtl(mtl) if mtl else ({}, set())
    palette_path = base / 'Textures/colormap.png'
    palette = Image.open(palette_path).convert('RGB') if palette_path.exists() else None
    positions, normals, uvs, rows = [], [], [], []
    current = ''
    for line in lines:
        f = line.split()
        if not f:
            continue
        if f[0] == 'v':
            positions.append(list(map(float, f[1:4])))
        elif f[0] == 'vn':
            normals.append(list(map(float, f[1:4])))
        elif f[0] == 'vt':
            uvs.append(list(map(float, f[1:3])))
        elif f[0] == 'usemtl':
            current = f[1]
        elif f[0] == 'f':
            face = [v.split('/') for v in f[1:]]
            for i in range(1, len(face) - 1):
                triangle = (face[0], face[i], face[i + 1])
                use_palette = palette is not None and (current in textured or current not in colours) \
                    and all(len(v) > 1 and v[1] for v in triangle)
                if use_palette:
                    colors = []
                    for v in triangle:
                        u, t = uvs[int(v[1]) - 1]
                        colors.append(palette.getpixel((
                            min(palette.width - 1, max(0, int(u * palette.width))),
                            min(palette.height - 1, max(0, int((1 - t) * palette.height))))))
                    mean = tuple(sum(c[k] for c in colors) / 3 for k in range(3))
                    material = classify(mean)
                else:
                    mean = colours.get(current, (200, 200, 200))
                    material = classify(mean, current)
                pts = [positions[int(v[0]) - 1] for v in triangle]
                if all(len(v) > 2 and v[2] for v in triangle):
                    ns = [normals[int(v[2]) - 1] for v in triangle]
                else:
                    ax = [pts[1][k] - pts[0][k] for k in range(3)]
                    bx = [pts[2][k] - pts[0][k] for k in range(3)]
                    n = [ax[1] * bx[2] - ax[2] * bx[1], ax[2] * bx[0] - ax[0] * bx[2], ax[0] * bx[1] - ax[1] * bx[0]]
                    ln = max(1e-9, sum(c * c for c in n) ** .5)
                    ns = [[c / ln for c in n]] * 3
                for p, n in zip(pts, ns):
                    row = p + n + [c / 255 for c in mean] + [material]
                    rows.append('{' + ','.join(format(x, '.5g') for x in row) + '},')
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('assets', type=Path, help="the All-in-1 '3D assets' directory")
    args = parser.parse_args()
    out = Path(__file__).resolve().parents[1] / 'assets/kenney_kit'
    out.mkdir(parents=True, exist_ok=True)
    lines = ['-- Kenney 3D kits (CC0), see README.md. Generated by tools/build_kenney_kit.py.', 'return {']
    packs = set()
    for name, (pack, source) in MODELS.items():
        base = args.assets / pack / 'Models/OBJ format'
        rows = convert(base, source)
        fixes = OVERRIDES.get(name)
        if fixes:
            fixed = []
            for row in rows:
                head, material = row[:-2].rsplit(',', 1)
                material = str(fixes.get(int(float(material)), int(float(material))))
                fixed.append(head + ',' + material + '},')
            rows = fixed
        # One function per model keeps each chunk under LuaJIT's constant limit.
        lines += ['["' + name + '"]=(function() return {'] + rows + ['} end)(),']
        packs.add(pack)
        print(name, len(rows) // 3)
    (out / 'models.lua').write_text('\n'.join(lines + ['}']) + '\n')
    for pack in sorted(packs):
        licence = args.assets / pack / 'License.txt'
        if licence.exists():
            shutil.copyfile(licence, out / (pack.replace(' ', '-') + '-License.txt'))


if __name__ == '__main__':
    main()
