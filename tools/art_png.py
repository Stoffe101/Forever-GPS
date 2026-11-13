#!/usr/bin/env python3
"""Copies the addon's TGA art to PNG, and its fonts, for tools/ui_preview.lua."""
import shutil
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "preview"


def png(path: Path, target: Path) -> None:
    data = path.read_bytes()
    w, h = data[12] + data[13] * 256, data[14] + data[15] * 256
    px = data[18:]
    rows = []
    for y in range(h):
        row = bytearray(b"\0")
        off = (h - 1 - y) * w * 4
        for x in range(w):
            b, g, r, a = px[off + x * 4:off + x * 4 + 4]
            row += bytes((r, g, b, a))
        rows.append(bytes(row))

    def chunk(tag: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))

    target.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                       + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))


def main() -> None:
    (OUT / "art").mkdir(parents=True, exist_ok=True)
    (OUT / "fonts").mkdir(parents=True, exist_ok=True)
    for tga in (ROOT / "addons" / "ForeverGPS" / "Art").glob("*.tga"):
        png(tga, OUT / "art" / (tga.stem + ".png"))
    for font in ("Inter-Regular.ttf", "Inter-SemiBold.ttf", "Inter-Bold.ttf"):
        shutil.copyfile(ROOT / "addons" / "EasyFind" / "Fonts" / font, OUT / "fonts" / font)


if __name__ == "__main__":
    main()
