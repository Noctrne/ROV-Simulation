#!/usr/bin/env python3
"""Generate the SAUVC pool tile texture and the meshes that use it.

The pool floor and walls are boxes in the collision model, but their visuals
are meshes with UV coordinates in *world metres*. That way one seamless tile
texture (covering 1 m x 1 m) repeats at the right physical size on every
surface, including the sloped floor.

Run from the repo root:

    python3 scripts/make_pool_assets.py

Outputs (relative to models/sauvc_pool):
    materials/pool_tiles_floor.png           seamless floor albedo, 1 m x 1 m
    materials/pool_tiles_wall.png            seamless wall albedo, 1 m x 1 m
    materials/pool_tiles_wall_emissive.png   self-illumination for the walls
    materials/lane_blue.png                  solid colour for the lane markings
    meshes/floor.obj                         three floor boxes
    meshes/walls.obj                         four wall boxes
    meshes/markings.obj                      lane lines + wall stripes

Tile geometry is a parameter: TILE_X (along u) and TILE_Y (along v).
"""

import math
import os
import random

from PIL import Image, ImageDraw

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

TILE_X = 0.10          # metres along texture u
TILE_Y = 0.20          # metres along texture v
                       # (walls swap u/v, see Obj.swap_uv)
TEXTURE_M = 1.0        # the texture repeats every 1 m
RES = 1200             # pixels for that 1 m -> 1200 px/m
GROUT_M = 0.004        # 4 mm grout line

# Colours are authored in sRGB, because gz-sim treats albedo maps as sRGB.
#
# The pool water absorbs red light, so the reference photo (taken 2 m down)
# shows cyan floor tiles and deep blue walls. Gazebo 8 in this workspace has
# no fog, so the water tint is baked into the textures instead:
#
#   floor : white-cyan tiles, dark blue grout
#   wall  : blue tiles, darker blue grout
#
# Values are pre-compensated for the scene lighting; the comment below each
# pair is the colour that actually comes out of the FPV camera.
FLOOR_TILE_RGB = (42, 205, 242)      # renders ~#20B0D0
FLOOR_GROUT_RGB = (0, 100, 140)      # renders ~#005C78
WALL_TILE_RGB = (0, 150, 215)        # renders ~#0050A0 (with wall emissive)
WALL_GROUT_RGB = (0, 95, 150)
LANE_RGB = (0, 90, 160)              # renders ~#004980

# The walls get no direct sunlight, only ambient, so they need a little
# self-illumination to read as the blue seen in the photo. The emissive map
# mirrors the tile pattern (dimmer, and only in green/blue) so the grout
# lines stay visible instead of being washed out by a flat glow.
WALL_EMISSIVE_TILE_RGB = (0, 52, 134)
WALL_EMISSIVE_GROUT_RGB = (0, 32, 92)

# Slight per-tile variation, otherwise the floor looks like plastic.
TILE_VARIATION = 6

# ---------------------------------------------------------------------------
# Pool geometry (must match models/sauvc_pool/model.sdf)
# ---------------------------------------------------------------------------

POOL_W = 10.0
X0, X1 = 0.0, 1.8
X2, X3 = 19.3, 20.3
Z_SHALLOW, Z_DEEP = -1.28, -2.00
WALL_TOP = 0.3
WALL_BOTTOM = -2.3
WALL_T = 0.3
# Visual meshes overlap the walls by this much so no two faces are coplanar
# (coplanar faces z-fight). Collisions still use the exact box sizes.
VISUAL_OVERLAP = 0.05

# Four lines split the 10 m width into five 2 m sections, so no line runs
# through the middle of the gate (the gate sits in the centre section).
LANES_Y = (-3.0, -1.0, 1.0, 3.0)
LANE_W = 0.25

HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "..", "models", "sauvc_pool")
MAT = os.path.join(MODEL, "materials")
MESH = os.path.join(MODEL, "meshes")


def slope_z(x):
    """Floor z at a given x (top surface)."""
    if x <= X1:
        return Z_SHALLOW
    if x <= X2:
        return Z_SHALLOW + (x - X1) * (Z_DEEP - Z_SHALLOW) / (X2 - X1)
    return Z_DEEP


# ---------------------------------------------------------------------------
# Texture
# ---------------------------------------------------------------------------

def make_tile_texture(path, tile_rgb, grout_rgb, seed=7):
    px = RES / TEXTURE_M
    tw = TILE_X * px          # 120 px
    th = TILE_Y * px          # 240 px
    grout = max(1, round(GROUT_M * px))

    img = Image.new("RGB", (RES, RES), grout_rgb)
    draw = ImageDraw.Draw(img)
    rnd = random.Random(seed)

    n_x = int(round(TEXTURE_M / TILE_X))
    n_y = int(round(TEXTURE_M / TILE_Y))
    for iy in range(n_y):
        for ix in range(n_x):
            x0 = ix * tw
            y0 = iy * th
            d = rnd.randint(-TILE_VARIATION, TILE_VARIATION)
            col = tuple(max(0, min(255, c + d)) for c in tile_rgb)
            draw.rectangle(
                [x0 + grout, y0 + grout, x0 + tw - 1, y0 + th - 1],
                fill=col,
            )
    img.save(path)
    print("wrote", path)


def make_textures():
    make_tile_texture(os.path.join(MAT, "pool_tiles_floor.png"),
                      FLOOR_TILE_RGB, FLOOR_GROUT_RGB)
    make_tile_texture(os.path.join(MAT, "pool_tiles_wall.png"),
                      WALL_TILE_RGB, WALL_GROUT_RGB)
    make_tile_texture(os.path.join(MAT, "pool_tiles_wall_emissive.png"),
                      WALL_EMISSIVE_TILE_RGB, WALL_EMISSIVE_GROUT_RGB)

    # Solid colour used by the lane markings.
    Image.new("RGB", (16, 16), LANE_RGB).save(
        os.path.join(MAT, "lane_blue.png"))
    print("wrote", os.path.join(MAT, "lane_blue.png"))


# ---------------------------------------------------------------------------
# OBJ helpers
# ---------------------------------------------------------------------------

class Obj:
    def __init__(self, swap_uv=False):
        self.lines = []
        self.v = 0
        self.n = 0
        self.swap_uv = swap_uv

    def face(self, verts, normal):
        """verts: 4 (x,y,z) points, CCW seen from outside."""
        self.lines.append("g face")
        for vert in verts:
            self.lines.append("v %.6f %.6f %.6f" % vert)
        nx, ny, nz = normal
        # UV in world metres / texture period. Pick the two axes that are
        # not the dominant normal axis, so every face keeps the same scale.
        ax = max(range(3), key=lambda i: abs(normal[i]))
        for vert in verts:
            if ax == 0:      # face normal along x -> u=y, v=z
                u, w = vert[1], vert[2]
            elif ax == 1:    # along y -> u=x, v=z
                u, w = vert[0], vert[2]
            else:            # along z -> u=x, v=y
                u, w = vert[0], vert[1]
            if self.swap_uv:
                u, w = w, u
            self.lines.append("vt %.6f %.6f" % (u / TEXTURE_M, w / TEXTURE_M))
        self.lines.append("vn %.6f %.6f %.6f" % normal)
        a = self.v + 1
        n = self.n + 1
        self.lines.append("f %d/%d/%d %d/%d/%d %d/%d/%d %d/%d/%d" % (
            a, a, n, a + 1, a + 1, n, a + 2, a + 2, n, a + 3, a + 3, n))
        self.v += 4
        self.n += 1

    def save(self, path):
        with open(path, "w") as f:
            f.write("# generated by scripts/make_pool_assets.py\n")
            f.write("\n".join(self.lines))
            f.write("\n")
        print("wrote", path)


def box_faces(obj, cx, cy, cz, sx, sy, sz, pitch=0.0):
    """Emit a closed box, rotated about y by `pitch`."""
    def tr(lx, ly, lz):
        # rotate about y, then translate
        wx = cx + lx * math.cos(pitch) + lz * math.sin(pitch)
        wy = cy + ly
        wz = cz - lx * math.sin(pitch) + lz * math.cos(pitch)
        return (wx, wy, wz)

    def rn(n):
        # rotate a direction (no translation)
        nx, ny, nz = n
        return (nx * math.cos(pitch) + nz * math.sin(pitch),
                ny,
                -nx * math.sin(pitch) + nz * math.cos(pitch))

    hx, hy, hz = sx / 2, sy / 2, sz / 2
    p = [tr(sx_, sy_, sz_) for sx_ in (-hx, hx) for sy_ in (-hy, hy)
         for sz_ in (-hz, hz)]
    # index helper: p[i] with bits (x, y, z)
    def P(ix, iy, iz):
        return p[ix * 4 + iy * 2 + iz]

    # +z face
    obj.face([P(0, 0, 1), P(1, 0, 1), P(1, 1, 1), P(0, 1, 1)],
             rn((0, 0, 1)))
    # -z face
    obj.face([P(0, 0, 0), P(0, 1, 0), P(1, 1, 0), P(1, 0, 0)],
             rn((0, 0, -1)))
    # +x face
    obj.face([P(1, 0, 0), P(1, 1, 0), P(1, 1, 1), P(1, 0, 1)],
             rn((1, 0, 0)))
    # -x face
    obj.face([P(0, 0, 0), P(0, 0, 1), P(0, 1, 1), P(0, 1, 0)],
             rn((-1, 0, 0)))
    # +y face
    obj.face([P(0, 1, 0), P(0, 1, 1), P(1, 1, 1), P(1, 1, 0)],
             rn((0, 1, 0)))
    # -y face
    obj.face([P(0, 0, 0), P(1, 0, 0), P(1, 0, 1), P(0, 0, 1)],
             rn((0, -1, 0)))


def quad(obj, verts, normal):
    obj.face(verts, normal)


# ---------------------------------------------------------------------------
# Meshes
# ---------------------------------------------------------------------------

def make_floor():
    o = Obj()
    ov = VISUAL_OVERLAP
    wide = POOL_W + 2 * ov

    # Shallow shelf: pokes ov past x = 0 into the start wall.
    box_faces(o, (X0 - ov + X1) / 2, 0, Z_SHALLOW - 0.15,
              X1 - X0 + ov, wide, 0.3)

    # Slope: keep its ends exactly at x = 1.8 / 19.3 (extending it along the
    # slope would lift it above the neighbouring flat slabs) and only widen
    # it sideways.
    # Positive pitch tilts local +x downwards (see box_faces), which is the
    # direction the real floor takes.
    pitch = math.atan2(Z_SHALLOW - Z_DEEP, X2 - X1)
    length = math.hypot(X2 - X1, Z_DEEP - Z_SHALLOW)
    tcx = (X1 + X2) / 2
    tcz = (Z_SHALLOW + Z_DEEP) / 2
    cx = tcx - 0.15 * math.sin(pitch)
    cz = tcz - 0.15 * math.cos(pitch)
    box_faces(o, cx, 0, cz, length, wide, 0.3, pitch)

    # Deep section: pokes ov past x = 20.3 into the far wall.
    box_faces(o, (X2 + X3 + ov) / 2, 0, Z_DEEP - 0.15,
              X3 - X2 + ov, wide, 0.3)
    o.save(os.path.join(MESH, "floor.obj"))


def make_walls():
    o = Obj(swap_uv=True)
    # x = 0 wall (widened so its ends sit inside the side walls)
    box_faces(o, -WALL_T / 2, 0, (WALL_TOP + WALL_BOTTOM) / 2,
              WALL_T, POOL_W + WALL_T, WALL_TOP - WALL_BOTTOM)
    # x = 20.3 wall
    box_faces(o, X3 + WALL_T / 2, 0, (WALL_TOP + WALL_BOTTOM) / 2,
              WALL_T, POOL_W + WALL_T, WALL_TOP - WALL_BOTTOM)
    # y = +5 wall
    box_faces(o, (X0 + X3) / 2, POOL_W / 2 + WALL_T / 2,
              (WALL_TOP + WALL_BOTTOM) / 2,
              X3 - X0 + 2 * WALL_T, WALL_T, WALL_TOP - WALL_BOTTOM)
    # y = -5 wall
    box_faces(o, (X0 + X3) / 2, -POOL_W / 2 - WALL_T / 2,
              (WALL_TOP + WALL_BOTTOM) / 2,
              X3 - X0 + 2 * WALL_T, WALL_T, WALL_TOP - WALL_BOTTOM)
    o.save(os.path.join(MESH, "walls.obj"))


def make_markings():
    o = Obj()
    eps = 0.003

    # Floor lane lines, following the bottom profile.
    for y in LANES_Y:
        yl, yr = y - LANE_W / 2, y + LANE_W / 2
        quad(o, [(X0, yl, Z_SHALLOW + eps), (X1, yl, Z_SHALLOW + eps),
                 (X1, yr, Z_SHALLOW + eps), (X0, yr, Z_SHALLOW + eps)],
             (0, 0, 1))
        quad(o, [(X1, yl, slope_z(X1) + eps), (X2, yl, slope_z(X2) + eps),
                 (X2, yr, slope_z(X2) + eps), (X1, yr, slope_z(X1) + eps)],
             (0, 0, 1))
        quad(o, [(X2, yl, Z_DEEP + eps), (X3, yl, Z_DEEP + eps),
                 (X3, yr, Z_DEEP + eps), (X2, yr, Z_DEEP + eps)],
             (0, 0, 1))

    # Vertical stripes on the pool-edge wall (x = 0), from floor to surface.
    for y in LANES_Y:
        yl, yr = y - LANE_W / 2, y + LANE_W / 2
        quad(o, [(eps, yl, Z_SHALLOW), (eps, yr, Z_SHALLOW),
                 (eps, yr, 0.0), (eps, yl, 0.0)], (1, 0, 0))

    o.save(os.path.join(MESH, "markings.obj"))


if __name__ == "__main__":
    os.makedirs(MAT, exist_ok=True)
    os.makedirs(MESH, exist_ok=True)
    make_textures()
    make_floor()
    make_walls()
    make_markings()
