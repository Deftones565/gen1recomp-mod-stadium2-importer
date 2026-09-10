#!/usr/bin/env python3
"""Convert CC0 Nature Kit OBJ meshes, rounding tree crowns with Loop subdivision."""
import argparse
import math
import pathlib
import shutil
from collections import defaultdict


def subdivide(points, faces):
    neighbors = defaultdict(set)
    edges = defaultdict(list)
    for a, b, c in faces:
        for u, v, opposite in ((a, b, c), (b, c, a), (c, a, b)):
            neighbors[u].add(v)
            neighbors[v].add(u)
            edges[tuple(sorted((u, v)))].append(opposite)
    refined = []
    for i, point in enumerate(points):
        adjacent = neighbors[i]
        n = len(adjacent)
        boundary = [j for j in adjacent if len(edges[tuple(sorted((i, j)))]) == 1]
        if len(boundary) == 2:
            refined.append([.75 * point[k] + .125 * sum(points[j][k] for j in boundary) for k in range(3)])
        else:
            beta = 3 / 16 if n == 3 else 3 / (8 * n)
            refined.append([(1 - n * beta) * point[k] + beta * sum(points[j][k] for j in adjacent) for k in range(3)])
    indices = {}
    for (a, b), opposite in edges.items():
        indices[(a, b)] = len(refined)
        if len(opposite) == 2:
            refined.append([.375 * (points[a][k] + points[b][k]) + .125 * sum(points[j][k] for j in opposite) for k in range(3)])
        else:
            refined.append([.5 * (points[a][k] + points[b][k]) for k in range(3)])
    triangles = []
    for a, b, c in faces:
        ab, bc, ca = (indices[tuple(sorted(edge))] for edge in ((a, b), (b, c), (c, a)))
        triangles.extend(((a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)))
    return refined, triangles


def smooth_tree(rows, round_crown):
    """Weld each material, round separate crowns, then rebuild smooth normals."""
    points, faces, welded = [], [], {}
    for triangle in rows:
        face = []
        for position, _ in triangle:
            key = tuple(round(v, 6) for v in position)
            if key not in welded:
                welded[key] = len(points)
                points.append(list(position))
            face.append(welded[key])
        faces.append(face)
    # Preserve each foliage cluster's authored bounds during smoothing.
    adjacency = defaultdict(set)
    for face in faces:
        for i in face:
            adjacency[i].update(face)
    unseen = set(range(len(points)))
    result = []
    while unseen:
        todo = [min(unseen)]
        component = set()
        while todo:
            i = todo.pop()
            if i in component:
                continue
            component.add(i)
            todo.extend(adjacency[i] - component)
        unseen -= component
        order = sorted(component)
        local = {old: i for i, old in enumerate(order)}
        verts = [points[i] for i in order]
        tris = [[local[i] for i in f] for f in faces if f[0] in component]
        bounds = [(min(v[k] for v in verts), max(v[k] for v in verts)) for k in range(3)]
        if round_crown:
            for _ in range(2):
                verts, tris = subdivide(verts, tris)
            for k, (lo, hi) in enumerate(bounds):
                new_lo, new_hi = min(v[k] for v in verts), max(v[k] for v in verts)
                if new_hi - new_lo > 1e-8:
                    for v in verts:
                        v[k] = lo + (v[k] - new_lo) * (hi - lo) / (new_hi - new_lo)
        if round_crown:
            # Replace the inherited cuboid profile with an organic ellipsoid.
            # Subdivision supplies topology; radial lobes break the perfect ball.
            center = [(lo + hi) * .5 for lo, hi in bounds]
            radii = [max((hi - lo) * .5, 1e-6) for lo, hi in bounds]
            for point in verts:
                direction = [(point[k] - center[k]) / radii[k] for k in range(3)]
                length = math.sqrt(sum(v*v for v in direction)) or 1
                direction = [v / length for v in direction]
                x, y, z = direction
                lobe = 1 + .075 * math.sin(x*7 + z*4 + center[1]*19) * math.sin(y*6-z*3)
                for k in range(3):
                    point[k] = center[k] + radii[k] * direction[k] * lobe
        normals = [[0., 0., 0.] for _ in verts]
        for a, b, c in tris:
            u = [verts[b][k] - verts[a][k] for k in range(3)]
            v = [verts[c][k] - verts[a][k] for k in range(3)]
            normal = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
            for i in (a, b, c):
                for k in range(3):
                    normals[i][k] += normal[k]
        for n in normals:
            length = math.sqrt(sum(v*v for v in n)) or 1
            for k in range(3):
                n[k] /= length
        result.extend([[ (verts[i], normals[i]) for i in f] for f in tris])
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('pack', type=pathlib.Path)
    args = parser.parse_args()
    out = pathlib.Path(__file__).resolve().parents[1] / 'assets/kenney_nature'
    out.mkdir(parents=True, exist_ok=True)
    names = ['tree_oak', 'tree_detailed', 'tree_fat', 'plant_bush', 'grass_leafs', 'grass',
             'flower_yellowA', 'flower_purpleA', 'rock_smallA', 'structure-roof']
    lines = ['-- Generated by tools/build_kenney_grass.py; Kenney Nature Kit 2.1 (CC0).', 'return {']
    for name in names:
        base = (args.pack.parent / 'Survival Kit' if name == 'structure-roof' else args.pack) / 'Models/OBJ format'
        colors = {}
        material = None
        for line in (base / (name + '.mtl')).read_text().splitlines():
            f = line.split()
            if not f:
                continue
            if f[0] == 'newmtl':
                material = f[1]
            if f[0] == 'Kd':
                colors[material] = list(map(float, f[1:4]))
        verts, normals, materials = [], [], defaultdict(list)
        for line in (base / (name + '.obj')).read_text().splitlines():
            f = line.split()
            if not f:
                continue
            if f[0] == 'v':
                verts.append(list(map(float, f[1:4])))
            elif f[0] == 'vn':
                normals.append(list(map(float, f[1:4])))
            elif f[0] == 'usemtl':
                material = f[1]
            elif f[0] == 'f':
                face = [v.split('/') for v in f[1:]]
                for i in range(1, len(face)-1):
                    materials[material].append([(verts[int(v[0])-1], normals[int(v[2])-1])
                                                for v in (face[0], face[i], face[i+1])])
        rows = []
        for material, triangles in materials.items():
            color = colors[material]
            foliage = 'leaf' in material.lower() or 'grass' in material.lower()
            if foliage:
                color = [.31, .62, .20]
            elif 'wood' in material.lower():
                color = [.40, .29, .17]
            elif name.startswith('rock_') and material == 'dirt':
                color = [.48, .52, .43]
            surface = 1 if foliage else 2 if 'wood' in material.lower() else 3 if name.startswith('rock_') else 4
            if name == 'structure-roof':
                surface, color = 2, [.48, .35, .22]
            if name.startswith('tree_'):
                triangles = smooth_tree(triangles, foliage)
            for triangle in triangles:
                for position, normal in triangle:
                    rows.append('{' + ','.join(format(v, '.5g') for v in position + normal + color + [surface]) + '},')
        lines += ['["' + name + '"]={'] + rows + ['},']
        print(name, len(rows)//3, 'triangles')
    lines += ['}']
    (out / 'models.lua').write_text('\n'.join(lines) + '\n')
    shutil.copyfile(args.pack / 'License.txt', out / 'License.txt')
    shutil.copyfile(args.pack.parent / 'Survival Kit/License.txt', out / 'Survival-Kit-License.txt')


if __name__ == '__main__':
    main()
