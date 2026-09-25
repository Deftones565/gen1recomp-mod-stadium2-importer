#!/usr/bin/env python3
"""Bake Kenney's palette UVs into vertex colors for the shared town material pass."""
from pathlib import Path
import argparse
import shutil
from PIL import Image

def main():
    parser=argparse.ArgumentParser();parser.add_argument('pack',type=Path);args=parser.parse_args()
    base=args.pack/'Models/OBJ format'
    palette=Image.open(base/'Textures/colormap.png').convert('RGB')
    out=Path(__file__).resolve().parents[1]/'assets/kenney_town';out.mkdir(parents=True,exist_ok=True)
    lines=['-- Kenney City Kit - Suburban (CC0). Generated palette-colored geometry.','return {']
    for name in ['building-type-a','building-type-b','building-type-c','building-type-f','fence','planter','lantern']:
        source_pack=args.pack.parent/'Fantasy Town Kit' if name=='lantern' else args.pack
        base=source_pack/'Models/OBJ format'
        palette=Image.open(base/'Textures/colormap.png').convert('RGB')
        positions=[];normals=[];uvs=[];rows=[]
        for line in (base/(name+'.obj')).read_text().splitlines():
            f=line.split()
            if not f:continue
            if f[0]=='v':positions.append(list(map(float,f[1:4])))
            elif f[0]=='vn':normals.append(list(map(float,f[1:4])))
            elif f[0]=='vt':uvs.append(list(map(float,f[1:3])))
            elif f[0]=='f':
                face=[v.split('/') for v in f[1:]]
                for i in range(1,len(face)-1):
                    triangle=(face[0],face[i],face[i+1])
                    colors=[]
                    for v in triangle:
                        u,t=uvs[int(v[1])-1]
                        colors.append(palette.getpixel((min(palette.width-1,max(0,int(u*palette.width))),min(palette.height-1,max(0,int((1-t)*palette.height))))))
                    # Assign one material per triangle, even at palette seams.
                    height=sum(positions[int(q[0])-1][1] for q in triangle)/3
                    r,g,b=[sum(c[k] for c in colors)/3 for k in range(3)]
                    green=g>r*1.3 and g>b*1.1
                    # In these four source houses, planted greenery ends below y=.20;
                    # the lowest roof starts above y=.32. The old .43 cutoff
                    # painted low roofs and eaves as foliage, splitting roof shells.
                    roof=green and name.startswith('building') and height>.25
                    surface=2 if name=='fence' else 5 if roof else 1 if green else 4 if min(r,g,b)>160 else 6
                    if name=='lantern':
                        surface=7 if r>190 and abs(r-g)<5 else 6
                        colors=[(224,213,174) if surface==7 else (76,84,78)]*3
                    for v,rgb in zip(triangle,colors):
                        row=positions[int(v[0])-1]+normals[int(v[2])-1]+[c/255 for c in rgb]+[surface]
                        rows.append('{'+','.join(format(x,'.6g') for x in row)+'},')
        lines+=['["'+name+'"]={']+rows+['},'];print(name,len(rows)//3)
    (out/'models.lua').write_text('\n'.join(lines+['}'])+'\n')
    shutil.copyfile(args.pack/'License.txt',out/'License.txt')
    shutil.copyfile(args.pack.parent/'Fantasy Town Kit/License.txt',out/'Fantasy-Town-License.txt')
if __name__=='__main__':main()
