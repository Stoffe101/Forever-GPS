#!/usr/bin/env python3
"""Draw Forever-GPS's icons as 32-bit TGA files, from code, with the standard
library only. Every glyph is white on transparent; the addon tints it.

    python tools/make_art.py

Shapes are rasterized at 4x and box-filtered down, so edges are smooth. The
output is deterministic: same script, same bytes.
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "addons" / "ForeverGPS" / "Art"
SIZE, SS = 64, 4
W = SIZE * SS


class Canvas:
    def __init__(self) -> None:
        self.px = bytearray(W * W)

    def _set(self, x: int, y: int, on: bool) -> None:
        if 0 <= x < W and 0 <= y < W:
            self.px[y * W + x] = 1 if on else 0

    def disc(self, cx: float, cy: float, r: float, on: bool = True) -> None:
        cx, cy, r = cx * SS, cy * SS, r * SS
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                    self._set(x, y, on)

    def ring(self, cx: float, cy: float, r: float, width: float = 5, on: bool = True) -> None:
        outer, inner = (r + width / 2) * SS, (r - width / 2) * SS
        cx, cy = cx * SS, cy * SS
        for y in range(int(cy - outer) - 1, int(cy + outer) + 2):
            for x in range(int(cx - outer) - 1, int(cx + outer) + 2):
                d = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2
                if inner * inner <= d <= outer * outer:
                    self._set(x, y, on)

    def poly(self, pts: list[tuple[float, float]], on: bool = True) -> None:
        pts = [(x * SS, y * SS) for x, y in pts]
        ys = [p[1] for p in pts]
        for y in range(int(min(ys)) - 1, int(max(ys)) + 2):
            yc = y + 0.5
            hits = []
            for i in range(len(pts)):
                x1, y1 = pts[i]
                x2, y2 = pts[(i + 1) % len(pts)]
                if (y1 <= yc < y2) or (y2 <= yc < y1):
                    hits.append(x1 + (yc - y1) * (x2 - x1) / (y2 - y1))
            hits.sort()
            for a, b in zip(hits[0::2], hits[1::2]):
                for x in range(int(a), int(b) + 1):
                    if a <= x + 0.5 <= b:
                        self._set(x, y, on)

    def line(self, pts: list[tuple[float, float]], width: float = 5, on: bool = True) -> None:
        for (x1, y1), (x2, y2) in zip(pts, pts[1:]):
            dx, dy = x2 - x1, y2 - y1
            n = math.hypot(dx, dy) or 1
            ox, oy = -dy / n * width / 2, dx / n * width / 2
            self.poly([(x1 + ox, y1 + oy), (x2 + ox, y2 + oy), (x2 - ox, y2 - oy), (x1 - ox, y1 - oy)], on)
            self.disc(x1, y1, width / 2, on)
            self.disc(x2, y2, width / 2, on)

    def rrect(self, x: float, y: float, w: float, h: float, r: float, on: bool = True) -> None:
        self.poly([(x + r, y), (x + w - r, y), (x + w - r, y + h), (x + r, y + h)], on)
        self.poly([(x, y + r), (x + w, y + r), (x + w, y + h - r), (x, y + h - r)], on)
        for cx, cy in ((x + r, y + r), (x + w - r, y + r), (x + r, y + h - r), (x + w - r, y + h - r)):
            self.disc(cx, cy, r, on)

    def rrect_line(self, x: float, y: float, w: float, h: float, r: float, width: float = 5) -> None:
        self.rrect(x, y, w, h, r)
        self.rrect(x + width, y + width, w - 2 * width, h - 2 * width, max(0.0, r - width), False)

    def tga(self, path: Path, size: int = SIZE) -> None:
        # Alpha by box filter; RGB stays white so tinting works on soft edges.
        ss = W // size
        rows = []
        for y in range(size - 1, -1, -1):        # bottom-up, as TGA stores it
            row = bytearray()
            for x in range(size):
                total = 0
                for j in range(y * ss, (y + 1) * ss):
                    off = j * W
                    total += sum(self.px[off + x * ss:off + (x + 1) * ss])
                alpha = round(255 * total / (ss * ss))
                row += bytes((255, 255, 255, alpha))
            rows.append(bytes(row))
        header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, size, size, 32, 8)
        path.write_bytes(header + b"".join(rows))


def icon(fn) -> Canvas:
    c = Canvas()
    fn(c)
    return c


# ---- transport -------------------------------------------------------------

def walk(c: Canvas) -> None:
    c.disc(34, 11, 6)
    c.line([(34, 21), (31, 36)], 7)
    c.line([(31, 36), (40, 46), (41, 57)], 6)
    c.line([(31, 36), (25, 47), (17, 56)], 6)
    c.line([(33, 24), (43, 32), (50, 30)], 5)
    c.line([(33, 24), (24, 28), (20, 37)], 5)


def flight(c: Canvas) -> None:
    c.poly([(8, 28), (56, 8), (40, 54), (31, 36)])
    c.poly([(31, 36), (56, 8), (35, 40)], False)
    c.line([(31, 36), (28, 50)], 4)


def boat(c: Canvas) -> None:
    c.line([(31, 8), (31, 38)], 4)
    c.poly([(35, 11), (52, 34), (35, 34)])
    c.poly([(27, 16), (27, 34), (13, 34)])
    c.poly([(7, 41), (57, 41), (49, 54), (15, 54)])


def zeppelin(c: Canvas) -> None:
    c.rrect(7, 12, 50, 26, 13)
    c.line([(25, 38), (22, 45)], 3)
    c.line([(39, 38), (42, 45)], 3)
    c.rrect(20, 44, 24, 9, 3)


def tram(c: Canvas) -> None:
    c.rrect_line(12, 7, 40, 42, 8, 5)
    c.rrect(19, 15, 26, 13, 2)
    c.disc(22, 38, 3)
    c.disc(42, 38, 3)
    c.line([(22, 49), (15, 58)], 5)
    c.line([(42, 49), (49, 58)], 5)


def portal(c: Canvas) -> None:
    c.ring(32, 32, 23, 5)
    c.ring(32, 32, 13, 4)
    c.disc(32, 32, 4)


def hearth(c: Canvas) -> None:
    c.poly([(32, 7), (54, 25), (54, 56), (10, 56), (10, 25)])
    c.poly([(24, 56), (24, 37), (40, 37), (40, 56)], False)


def lift(c: Canvas) -> None:
    c.rrect_line(13, 7, 38, 50, 5, 5)
    c.poly([(32, 15), (41, 27), (23, 27)])
    c.poly([(32, 49), (41, 37), (23, 37)])


def door(c: Canvas) -> None:
    c.rrect_line(15, 7, 34, 50, 4, 5)
    c.disc(40, 33, 3)


def corpse(c: Canvas) -> None:
    c.rrect(14, 8, 36, 34, 15)
    c.rrect(21, 36, 22, 18, 3)
    c.disc(25, 26, 5, False)
    c.disc(39, 26, 5, False)
    c.line([(27, 44), (27, 54)], 2, False)
    c.line([(37, 44), (37, 54)], 2, False)


def flag(c: Canvas) -> None:
    c.line([(16, 8), (16, 57)], 5)
    c.poly([(19, 9), (52, 14), (40, 24), (52, 34), (19, 34)])


# ---- places and services ---------------------------------------------------

def pin(c: Canvas) -> None:
    c.disc(32, 24, 18)
    c.poly([(16, 32), (48, 32), (32, 58)])
    c.disc(32, 24, 7, False)


def quest(c: Canvas) -> None:
    c.line([(32, 8), (32, 40)], 9)
    c.disc(32, 53, 5.5)


def turnin(c: Canvas) -> None:
    c.line([(18, 21), (23, 11), (41, 9), (47, 21), (32, 33), (32, 41)], 8)
    c.disc(32, 54, 5.5)


def search(c: Canvas) -> None:
    c.ring(27, 27, 17, 6)
    c.line([(40, 40), (54, 54)], 7)


def star(c: Canvas) -> None:
    pts = []
    for i in range(10):
        r = 25 if i % 2 == 0 else 11
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((32 + r * math.cos(a), 33 + r * math.sin(a)))
    c.poly(pts)


def star_line(c: Canvas) -> None:
    star(c)
    pts = []
    for i in range(10):
        r = 17 if i % 2 == 0 else 6.5
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((32 + r * math.cos(a), 33 + r * math.sin(a)))
    c.poly(pts, False)


def gear(c: Canvas) -> None:
    c.disc(32, 32, 18)
    for i in range(8):
        a = i * math.pi / 4
        ca, sa = math.cos(a), math.sin(a)
        c.line([(32 + 16 * ca, 32 + 16 * sa), (32 + 24 * ca, 32 + 24 * sa)], 8)
    c.disc(32, 32, 8, False)


def close(c: Canvas) -> None:
    c.line([(16, 16), (48, 48)], 6)
    c.line([(48, 16), (16, 48)], 6)


def chevron_down(c: Canvas) -> None:
    c.line([(14, 24), (32, 42), (50, 24)], 6)


def chevron_right(c: Canvas) -> None:
    c.line([(24, 14), (42, 32), (24, 50)], 6)


def chevron_up(c: Canvas) -> None:
    c.line([(14, 40), (32, 22), (50, 40)], 6)


def plus(c: Canvas) -> None:
    c.line([(32, 12), (32, 52)], 7)
    c.line([(12, 32), (52, 32)], 7)


def world_map(c: Canvas) -> None:
    c.poly([(8, 16), (24, 10), (40, 16), (56, 10), (56, 48), (40, 54), (24, 48), (8, 54)])
    c.line([(24, 10), (24, 48)], 3, False)
    c.line([(40, 16), (40, 54)], 3, False)


def locate(c: Canvas) -> None:
    c.ring(32, 32, 18, 5)
    c.disc(32, 32, 6)
    for a, b in (((32, 4), (32, 14)), ((32, 50), (32, 60)), ((4, 32), (14, 32)), ((50, 32), (60, 32))):
        c.line([a, b], 5)


def fit(c: Canvas) -> None:
    c.line([(10, 22), (10, 10), (22, 10)], 6)
    c.line([(42, 10), (54, 10), (54, 22)], 6)
    c.line([(54, 42), (54, 54), (42, 54)], 6)
    c.line([(22, 54), (10, 54), (10, 42)], 6)


def back(c: Canvas) -> None:
    c.line([(38, 14), (20, 32), (38, 50)], 6)


def check(c: Canvas) -> None:
    c.line([(12, 34), (26, 48), (52, 18)], 7)


def warning(c: Canvas) -> None:
    c.poly([(32, 7), (59, 54), (5, 54)])
    c.poly([(29, 22), (35, 22), (34, 39), (30, 39)], False)
    c.disc(32, 45, 3, False)


def shield(c: Canvas) -> None:
    c.poly([(32, 6), (54, 14), (54, 32), (32, 58), (10, 32), (10, 14)])
    c.poly([(32, 15), (45, 20), (45, 31), (32, 47), (19, 31), (19, 20)], False)


def clock(c: Canvas) -> None:
    c.ring(32, 32, 23, 6)
    c.line([(32, 18), (32, 33), (42, 39)], 5)


def nav_arrow(c: Canvas) -> None:
    # Points up as drawn: the addon rotates it.
    c.poly([(32, 5), (55, 58), (32, 46), (9, 58)])


def inn(c: Canvas) -> None:
    c.rrect(7, 34, 50, 14, 3)
    c.line([(10, 28), (10, 56)], 5)
    c.line([(54, 40), (54, 56)], 5)
    c.rrect(15, 22, 15, 12, 4)


def bank(c: Canvas) -> None:
    c.poly([(32, 7), (58, 23), (6, 23)])
    for x in (15, 32, 49):
        c.line([(x, 28), (x, 46)], 6)
    c.rrect(8, 49, 48, 8, 2)


def auction(c: Canvas) -> None:
    c.line([(14, 50), (34, 30)], 7)
    c.rrect(26, 9, 26, 15, 3)
    c.line([(35, 9), (50, 24)], 2, False)
    c.rrect(10, 50, 30, 7, 2)


def mail(c: Canvas) -> None:
    c.rrect_line(7, 15, 50, 36, 5, 5)
    c.line([(10, 19), (32, 36), (54, 19)], 5)


def repair(c: Canvas) -> None:
    c.line([(12, 52), (37, 27)], 8)
    c.ring(42, 22, 13, 8)
    c.poly([(42, 22), (62, 2), (62, 22)], False)


def trainer(c: Canvas) -> None:
    c.poly([(32, 11), (60, 26), (32, 41), (4, 26)])
    c.line([(16, 36), (16, 47), (32, 54), (48, 47), (48, 36)], 5)


def vendor(c: Canvas) -> None:
    c.line([(6, 12), (16, 12), (22, 40), (50, 40), (56, 18), (18, 18)], 5)
    c.disc(26, 51, 5)
    c.disc(46, 51, 5)


def ring(c: Canvas) -> None:
    c.ring(32, 32, 28, 8)


def dot(c: Canvas) -> None:
    c.disc(32, 32, 18)


def logo(c: Canvas) -> None:
    c.ring(32, 32, 26, 4)
    c.poly([(32, 11), (42, 35), (32, 30), (22, 35)])
    c.poly([(32, 53), (22, 29), (32, 34), (42, 29)])
    c.poly([(32, 53), (22, 29), (42, 29)], False)
    c.line([(32, 37), (32, 49)], 3)


GLYPHS = {
    "walk": walk, "flight": flight, "boat": boat, "zeppelin": zeppelin, "tram": tram, "portal": portal,
    "hearth": hearth, "lift": lift, "door": door, "corpse": corpse, "flag": flag, "pin": pin, "quest": quest,
    "turnin": turnin, "search": search, "star": star, "star-line": star_line, "gear": gear, "close": close,
    "chevron-down": chevron_down, "chevron-right": chevron_right, "back": back, "check": check,
    "warning": warning, "shield": shield, "clock": clock, "nav-arrow": nav_arrow, "inn": inn, "bank": bank,
    "auction": auction, "mail": mail, "repair": repair, "trainer": trainer, "vendor": vendor, "logo": logo,
    "ring": ring, "dot": dot, "chevron-up": chevron_up, "plus": plus, "map": world_map, "locate": locate,
    "fit": fit,
}


def shapes() -> None:
    # Nine-slice sources: 16 of 64 pixels are corner.
    c = Canvas()
    c.rrect(0, 0, 64, 64, 16)
    c.tga(OUT / "rounded.tga")
    c = Canvas()
    c.rrect_line(0, 0, 64, 64, 16, 2)
    c.tga(OUT / "rounded-line.tga")
    c = Canvas()
    c.disc(32, 32, 32)
    c.tga(OUT / "circle.tga")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, fn in GLYPHS.items():
        icon(fn).tga(OUT / f"{name}.tga")
    shapes()
    print(f"{len(GLYPHS) + 3} textures in {OUT}")


if __name__ == "__main__":
    main()
