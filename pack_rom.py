"""
pack_rom.py - Build the HarpMudd Zaxxon Pocket core's data files (multi-game).

One bitstream runs the Sega Zaxxon-hardware family the MiSTer core supports:
    variant 0 = Zaxxon        (mod_zaxxon)
    variant 1 = Super Zaxxon  (mod_superzaxxon - encrypted CPU ROMs, RTL decrypts)
    variant 2 = Future Spy    (mod_futurespy - encrypted CPU ROMs, RTL decrypts)
A VARIANT BYTE stamped at 0x24200 is snooped by core_top.v -> mod_superzaxxon/
mod_futurespy. The cpu/gfx/map ROM image is otherwise identical in layout; the
loader forward is gated to dn_addr < 0x24200 so the byte never reaches zaxxon.vhd.

Per game we emit two files into dist/Assets/zaxxon/common/:
  <game>.rom          - game ROM image (0x24200 data + variant byte, padded 0x24400)
  <game>_samples.bin  - ~782 KB WAV blob (-> SDRAM), extracted from the .mra index=2

ROMs and samples are copyrighted -> both gitignored, never committed. Users build
them locally from their own MAME romset + MiSTer .mra.

Usage:
  python pack_rom.py [game]    # game = zaxxon szaxxon futspy
  python pack_rom.py all
"""

import sys, os, re, zipfile, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
# Romsets: prefer the shared dev artifacts dir if it exists, otherwise this
# repo folder -- a cloned user just drops their MAME .zip files next to this script.
_DEV_ARTIFACTS = r"C:\Projects\Downloaded_Artifacts"
DEFAULT_ZIP_DIR = _DEV_ARTIFACTS if os.path.isdir(_DEV_ARTIFACTS) else HERE
ASSETS_DIR      = os.path.join(HERE, "dist", "Assets", "zaxxon", "common")
_DEV_MRA        = r"C:\Projects\Downloaded_Artifacts\Arcade-Zaxxon_MiSTer-master\releases"
MRA_DIR         = _DEV_MRA if os.path.isdir(_DEV_MRA) else HERE

VARIANT_OFFSET = 0x24200
ROM_IMAGE_SIZE = 0x24400          # 0x24200 data + variant byte + generous pad

# (CRC32, size, desc, offset). Order/offsets/repeats = MiSTer dl layout.
ZAXXON_ROM_DEFS = [
    (0x6e2b4a30, 8192, "rom3d.u27 (CPU prog 0, enc)",   0x00000),
    (0x1c9ea398, 8192, "rom2d.u28 (CPU prog 1, enc)",   0x02000),
    (0x1c123ef9, 4096, "rom1d.u29 (CPU prog 2, enc)",   0x04000),
    (0x07bf8c52, 2048, "rom14.u68 (char bits 1)",       0x05000),
    (0xc215edcb, 2048, "rom15.u69 (char bits 2)",       0x05800),
    (0x6e07bb68, 8192, "rom6.u113 (bg bits 1)",         0x06000),
    (0x0a5bce6a, 8192, "rom5.u112 (bg bits 2)",         0x08000),
    (0xa5bf1465, 8192, "rom4.u111 (bg bits 3)",         0x0A000),
    (0xeaf0dd4b, 8192, "rom11.u77 (sp bits 1 #0)",      0x0C000),
    (0xeaf0dd4b, 8192, "rom11.u77 (sp bits 1 #1)",      0x0E000),
    (0x1c5369c7, 8192, "rom12.u78 (sp bits 2 #0)",      0x10000),
    (0x1c5369c7, 8192, "rom12.u78 (sp bits 2 #1)",      0x12000),
    (0xab4e8a9a, 8192, "rom13.u79 (sp bits 3 #0)",      0x14000),
    (0xab4e8a9a, 8192, "rom13.u79 (sp bits 3 #1)",      0x16000),
    (0xab4e8a9a, 8192, "rom13.u79 (sp bits 3 #2)",      0x18000),
    (0xab4e8a9a, 8192, "rom13.u79 (sp bits 3 #3)",      0x1A000),
    (0x28d65063, 8192, "rom8.u91  (map 1 lo)",          0x1C000),
    (0x6284c200, 8192, "rom7.u90  (map 1 hi)",          0x1E000),
    (0xa95e61fd, 8192, "rom10.u93 (map 2 lo)",          0x20000),
    (0x7e42691f, 8192, "rom9.u92  (map 2 hi)",          0x22000),
    (0x6cc6695b,  256, "mro16.u76 (palette)",           0x24000),
    (0xdeaa21f7,  256, "zaxxon.u72 (char color)",       0x24100),
]

# Super Zaxxon: same layout, szaxxon CPU/gfx/map ROMs (encrypted CPU). Sprite ROMs
# doubled/quadrupled into the same slots as Zaxxon. Validated vs the MiSTer .mra.
SZAXXON_ROM_DEFS = [
    (0xaf7221da, 8192, "1804e.u27 (CPU prog 0, enc)",   0x00000),
    (0x1b90fb2a, 8192, "1803e.u28 (CPU prog 1, enc)",   0x02000),
    (0x07258b4a, 4096, "1802e.u29 (CPU prog 2, enc)",   0x04000),
    (0xbccf560c, 2048, "1815b.u68 (char bits 1)",       0x05000),
    (0xd28c628b, 2048, "1816b.u69 (char bits 2)",       0x05800),
    (0xf51af375, 8192, "1807b.u113 (bg bits 1)",        0x06000),
    (0xa7de021d, 8192, "1806b.u112 (bg bits 2)",        0x08000),
    (0x5bfb3b04, 8192, "1805b.u111 (bg bits 3)",        0x0A000),
    (0x1503ae41, 8192, "1812e.u77 (sp bits 1 #0)",      0x0C000),
    (0x1503ae41, 8192, "1812e.u77 (sp bits 1 #1)",      0x0E000),
    (0x3b53d83f, 8192, "1813e.u78 (sp bits 2 #0)",      0x10000),
    (0x3b53d83f, 8192, "1813e.u78 (sp bits 2 #1)",      0x12000),
    (0x581e8793, 8192, "1814e.u79 (sp bits 3 #0)",      0x14000),
    (0x581e8793, 8192, "1814e.u79 (sp bits 3 #1)",      0x16000),
    (0x581e8793, 8192, "1814e.u79 (sp bits 3 #2)",      0x18000),
    (0x581e8793, 8192, "1814e.u79 (sp bits 3 #3)",      0x1A000),
    (0xdd1b52df, 8192, "1809b.u91 (map 1 lo)",          0x1C000),
    (0xb5bc07f0, 8192, "1808b.u90 (map 1 hi)",          0x1E000),
    (0x68e84174, 8192, "1811b.u93 (map 2 lo)",          0x20000),
    (0xa509994b, 8192, "1810b.u92 (map 2 hi)",          0x22000),
    (0x15727a9f,  256, "pr-5168.u98 (palette)",         0x24000),
    (0xdeaa21f7,  256, "pr-5167.u72 (char color)",      0x24100),
]

# Future Spy: encrypted CPU (315-5061, RTL decrypts). Same region bases, but its
# sprite ROMs are 16K each (u77/u78/u79) and u79 is repeated once to fill the same
# 64K sprite region (per the MiSTer .mra), vs Zaxxon's 8K ROMs doubled/quadrupled.
FUTSPY_ROM_DEFS = [
    (0x7578fe7f,  8192, "fs_snd.u27 (CPU prog 0, enc)",  0x00000),
    (0x8ade203c,  8192, "fs_snd.u28 (CPU prog 1, enc)",  0x02000),
    (0x734299c3,  4096, "fs_snd.u29 (CPU prog 2, enc)",  0x04000),
    (0x305fae2d,  2048, "fs_snd.u68 (char bits 1)",      0x05000),
    (0x3c5658c0,  2048, "fs_snd.u69 (char bits 2)",      0x05800),
    (0x36d2bdf6,  8192, "fs_vid.u113 (bg bits 1)",       0x06000),
    (0x3740946a,  8192, "fs_vid.u112 (bg bits 2)",       0x08000),
    (0x4cd4df98,  8192, "fs_vid.u111 (bg bits 3)",       0x0A000),
    (0x1b93c9ec, 16384, "fs_vid.u77 (sp bits 1)",        0x0C000),
    (0x50e55262, 16384, "fs_vid.u78 (sp bits 2)",        0x10000),
    (0xbfb02e3e, 16384, "fs_vid.u79 (sp bits 3 #0)",     0x14000),
    (0xbfb02e3e, 16384, "fs_vid.u79 (sp bits 3 #1)",     0x18000),
    (0x86da01f4,  8192, "fs_vid.u91 (map 1 lo)",         0x1C000),
    (0x2bd41d2d,  8192, "fs_vid.u90 (map 1 hi)",         0x1E000),
    (0xb82b4997,  8192, "fs_vid.u93 (map 2 lo)",         0x20000),
    (0xaf4015af,  8192, "fs_vid.u92 (map 2 hi)",         0x22000),
    (0x9ba2acaa,   256, "futrprom.u98 (palette)",        0x24000),
    (0xf9e26790,   256, "futrprom.u72 (char color)",     0x24100),
]

GAMES = {
    "zaxxon":  (0, "Zaxxon (Set 1, Rev D)",   "Zaxxon (Set 1, Rev D).mra",   ZAXXON_ROM_DEFS),
    "szaxxon": (1, "Super Zaxxon (315-5013)", "Super Zaxxon (315-5013).mra", SZAXXON_ROM_DEFS),
    "futspy":  (2, "Future Spy (315-5061)",   "Future Spy (315-5061).mra",   FUTSPY_ROM_DEFS),
}


def crc32_of(b): return zlib.crc32(b) & 0xFFFFFFFF


def load_dir_by_crc(zip_dir):
    found = {}
    for z in sorted(f for f in os.listdir(zip_dir) if f.lower().endswith('.zip')):
        try:
            with zipfile.ZipFile(os.path.join(zip_dir, z)) as zf:
                for inf in zf.infolist():
                    if not inf.is_dir():
                        found[crc32_of(zf.read(inf.filename))] = zf.read(inf.filename)
        except Exception as e:
            print(f"  WARNING: {z}: {e}")
    return found


def mra_index(path, idx):
    txt = open(path, encoding="utf-8", errors="ignore").read()
    m = re.search(rf'<rom index="{idx}"[^>]*>(.*?)</rom>', txt, re.DOTALL)
    return m.group(1) if m else None


def assemble_mra_rom(path, found):
    """Assemble the .mra index-0 ROM (parts by CRC + repeat-fills) for validation."""
    body = mra_index(path, 0)
    out = bytearray()
    for m in re.finditer(r'<part\b([^>]*)>([^<]*)</part>', body):
        attrs, inner = m.group(1), m.group(2)
        crcm = re.search(r'crc="([0-9a-fA-F]+)"', attrs)
        rep  = re.search(r'repeat="([^"]+)"', attrs)
        if crcm:
            out += found.get(int(crcm.group(1), 16), b'')
        elif rep:
            out += bytes([int(inner.strip(), 16)]) * int(rep.group(1), 0)
    return bytes(out)


def build(game, found):
    variant, desc, mra_name, defs = GAMES[game]
    mra = os.path.join(MRA_DIR, mra_name)
    print(f"\n=== {desc}  (variant {variant}) ===")

    image = bytearray(ROM_IMAGE_SIZE)
    errs = []
    for (crc, size, d, off) in defs:
        if crc in found and len(found[crc]) == size:
            image[off:off+size] = found[crc]
        elif crc in found:
            errs.append(f"  WRONG SIZE {d}: want {size}, got {len(found[crc])}")
        else:
            errs.append(f"  MISSING    {d} (crc {crc:08x})")
    if errs:
        print("\n".join(["  ROM ERRORS:"] + errs)); return False
    image[VARIANT_OFFSET] = variant
    # NOTE: do NOT compare to the .mra index-0 -- that's the raw romset (sprites
    # listed once); the dl image zaxxon.vhd expects has the sprite ROMs doubled/
    # quadrupled (MiSTer's loader remap), which *_ROM_DEFS already bake in. The
    # remap is mod-independent, so szaxxon mirrors zaxxon's sprite doubling.

    with open(os.path.join(ASSETS_DIR, game + ".rom"), "wb") as f:
        f.write(image)
    print(f"  ROM     {len(image)} bytes (0x{len(image):X}), variant {variant}  [MiSTer dl layout]")

    # samples (-> SDRAM)
    hexb = re.findall(r'[0-9A-Fa-f]{2}', mra_index(mra, 2) or "")
    samples = bytes(int(b, 16) for b in hexb)
    if not samples or samples[:4] != b"RIFF":
        print("  !! samples missing / not RIFF"); return False
    with open(os.path.join(ASSETS_DIR, game + "_samples.bin"), "wb") as f:
        f.write(samples)
    print(f"  SAMPLES {len(samples)} bytes (RIFF/WAVE) -> {game}_samples.bin")
    return True


def main():
    os.makedirs(ASSETS_DIR, exist_ok=True)
    arg = (sys.argv[1].lower() if len(sys.argv) > 1 else "zaxxon")
    targets = list(GAMES) if arg == "all" else [arg]
    for t in targets:
        if t not in GAMES:
            print(f"ERROR: unknown game '{t}'. Choose: {', '.join(GAMES)}, or 'all'"); sys.exit(1)
    found = load_dir_by_crc(DEFAULT_ZIP_DIR)
    ok = all(build(t, found) for t in targets)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
