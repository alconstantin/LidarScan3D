#!/usr/bin/env python3
"""Audit an exported STL for printability.

Runs the same checks used to verify the flat-base plane cut against synthetic
meshes, but on a real scan. No dependencies -- plain Python 3.

    python3 check_stl.py "MyScan 100pct flat.stl"
"""
import struct
import sys
import math
from collections import defaultdict


def read_binary_stl(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 84:
        raise SystemExit(f"{path}: too short to be a binary STL")
    if data[:5].lstrip().lower().startswith(b"solid") and len(data) < 200:
        raise SystemExit(f"{path}: looks like an ASCII STL; this tool reads binary STL")
    count = struct.unpack_from("<I", data, 80)[0]
    expected = 84 + count * 50
    if len(data) != expected:
        print(f"  note: file is {len(data)} bytes, header implies {expected} "
              f"({count} triangles) -- reading what is there")
        count = min(count, (len(data) - 84) // 50)
    tris = []
    off = 84
    for _ in range(count):
        vals = struct.unpack_from("<12f", data, off)
        tris.append((vals[3:6], vals[6:9], vals[9:12]))
        off += 50
    return tris


def audit(path, weld_microns=1):
    tris = read_binary_stl(path)
    if not tris:
        raise SystemExit(f"{path}: no triangles")

    scale = 1000.0 / weld_microns

    def key(p):
        return (round(p[0] * scale), round(p[1] * scale), round(p[2] * scale))

    verts = {}
    faces = []
    degenerate = 0
    for a, b, c in tris:
        ids = []
        for p in (a, b, c):
            k = key(p)
            if k not in verts:
                verts[k] = len(verts)
            ids.append(verts[k])
        if len(set(ids)) < 3:
            degenerate += 1
            continue
        faces.append(tuple(ids))

    # Edge use: a closed surface has every edge in exactly two triangles.
    counts = defaultdict(int)
    directed = defaultdict(int)
    for f in faces:
        for i in range(3):
            u, v = f[i], f[(i + 1) % 3]
            counts[(min(u, v), max(u, v))] += 1
            directed[(u, v)] += 1

    boundary = sum(1 for n in counts.values() if n == 1)
    excess = sum(1 for n in counts.values() if n > 2)
    flipped = sum(1 for (u, v), n in directed.items() if n > 1)

    # Signed volume and bounds.
    lo = [min(p[i] for t in tris for p in t) for i in range(3)]
    hi = [max(p[i] for t in tris for p in t) for i in range(3)]
    vol = 0.0
    area = 0.0
    for a, b, c in tris:
        vol += (a[0] * (b[1] * c[2] - b[2] * c[1])
                - a[1] * (b[0] * c[2] - b[2] * c[0])
                + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0
        ux, uy, uz = (b[i] - a[i] for i in range(3))
        vx, vy, vz = (c[i] - a[i] for i in range(3))
        cx, cy, cz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        area += math.sqrt(cx * cx + cy * cy + cz * cz) / 2.0

    # How flat is the bottom? Counts geometry sitting within 0.1mm of the lowest point.
    floor_band = [p for t in tris for p in t if p[2] - lo[2] <= 0.1]
    flat_share = len(floor_band) / (len(tris) * 3)

    print(f"\n=== {path} ===")
    print(f"  triangles           {len(tris):,}  (unique vertices {len(verts):,})")
    print(f"  bounding box        {hi[0]-lo[0]:.1f} x {hi[1]-lo[1]:.1f} x {hi[2]-lo[2]:.1f} mm")
    print(f"  sits on Z=0         {'yes' if abs(lo[2]) < 0.05 else f'no, lowest Z = {lo[2]:.3f}'}")
    print(f"  surface area        {area/100:.1f} cm^2")
    print(f"  signed volume       {vol/1000:.2f} cm^3"
          f"{'   <-- NEGATIVE: normals are inverted' if vol < 0 else ''}")
    print(f"  degenerate tris     {degenerate}")
    print(f"  boundary edges      {boundary}   (holes; must be 0 to be watertight)")
    print(f"  over-used edges     {excess}   (non-manifold; must be 0)")
    print(f"  flipped neighbours  {flipped}   (inconsistent winding; must be 0)")
    print(f"  points on the floor {flat_share*100:.1f}% of vertices within 0.1mm of the base")

    ok = boundary == 0 and excess == 0 and flipped == 0 and vol > 0
    print()
    if ok:
        print("  WATERTIGHT — a slicer should take this without repair.")
    else:
        print("  NOT WATERTIGHT — a slicer will either repair it or complain.")
        if boundary:
            print(f"    {boundary} boundary edges means the surface has holes in it.")
        if excess:
            print(f"    {excess} edges shared by 3+ triangles means self-intersecting geometry.")
        if flipped:
            print(f"    {flipped} edges traversed the same way twice means some normals disagree.")
        if vol <= 0:
            print("    Non-positive volume means the surface is inside-out.")
    print("\n  If the flat base is on, 'points on the floor' should be a visible")
    print("  percentage. Near 0% means the cut did not happen or did not cap.\n")
    return ok


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    results = [audit(p) for p in sys.argv[1:]]
    sys.exit(0 if all(results) else 1)
