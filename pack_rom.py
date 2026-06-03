"""
pack_rom.py - Build the HarpMudd Zaxxon Pocket core's data files.

Zaxxon (Sega, 1982) runs on a Z80 with Sega-encrypted CPU ROMs. zaxxon.vhd is
self-contained: it takes dl_addr/dl_data/dl_wr and loads every ROM region into
internal dpram (CPU / char / bg / sprite / map / palette). core_top forwards
the loader bus, so the game image must match MiSTer's dl layout byte-for-byte.

Zaxxon's sound is DIGITIZED SAMPLES (no PSG). MiSTer stores them in SDRAM and
zaxxon.vhd reads them via wave_addr/wave_rd/wave_data. The samples are an
~782 KB WAV blob embedded in the .mra (index=2). We extract it verbatim and
load it into the Pocket's SDRAM via a 2nd data slot.

Outputs:
  dist/Assets/zaxxon/common/zaxxon.rom          - game ROM (0x24200, -> BRAM via dl)
  dist/Assets/zaxxon/common/zaxxon_samples.bin  - sample WAV blob (-> SDRAM)

Usage:
  python pack_rom.py
"""

import sys
import os
import re
import zipfile
import zlib

DEFAULT_ZIP_DIR = r"C:\Projects\Downloaded_Artifacts"
ASSETS_DIR      = r"C:\Projects\HarpMudd.zaxxon\dist\Assets\zaxxon\common"
MRA_PATH        = r"C:\Projects\Downloaded_Artifacts\Arcade-Zaxxon_MiSTer-master\releases\Zaxxon (Set 1, Rev D).mra"

ROM_IMAGE_SIZE = 0x24200

# (CRC32, expected_size, description, offset) -- order/offsets = MiSTer dl layout.
# Repeats (.mra repeat="N") listed as explicit placements.
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

OUT_ROM     = "zaxxon.rom"
OUT_SAMPLES = "zaxxon_samples.bin"


def crc32_of(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def load_dir_by_crc(zip_dir):
    found = {}
    for zname in sorted(f for f in os.listdir(zip_dir) if f.lower().endswith('.zip')):
        try:
            with zipfile.ZipFile(os.path.join(zip_dir, zname)) as zf:
                for inf in zf.infolist():
                    if not inf.is_dir():
                        found[crc32_of(zf.read(inf.filename))] = zf.read(inf.filename)
        except Exception as e:
            print(f"  WARNING: {zname}: {e}")
    return found


def extract_samples(mra_path):
    """Pull the inline WAV blob from the .mra <rom index='2'>."""
    txt = open(mra_path, encoding="utf-8", errors="ignore").read()
    m = re.search(r'<rom index="2"[^>]*>(.*?)</rom>', txt, re.DOTALL)
    if not m:
        return None
    hexb = re.findall(r'[0-9A-Fa-f]{2}', m.group(1))
    return bytes(int(b, 16) for b in hexb)


def main():
    os.makedirs(ASSETS_DIR, exist_ok=True)
    print("ROM packer - Zaxxon (Sega, 1982)\n")
    found = load_dir_by_crc(DEFAULT_ZIP_DIR)

    # --- game ROM ---
    image = bytearray(ROM_IMAGE_SIZE)
    errors = []
    for (crc, size, d, off) in ZAXXON_ROM_DEFS:
        if crc in found and len(found[crc]) == size:
            image[off:off+size] = found[crc]
            print(f"  OK   {d}  @ 0x{off:05X}")
        elif crc in found:
            errors.append(f"  WRONG SIZE {d}: want {size}, got {len(found[crc])}")
        else:
            errors.append(f"  MISSING    {d}  (crc {crc:08x})")
    if errors:
        print("\n".join(["", "ROM ERRORS:"] + errors)); sys.exit(1)
    with open(os.path.join(ASSETS_DIR, OUT_ROM), "wb") as f:
        f.write(image)
    print(f"\nSUCCESS: wrote {len(image)} bytes (0x{len(image):X}) -> {OUT_ROM}")

    # --- samples (-> SDRAM via 2nd slot) ---
    samples = extract_samples(MRA_PATH)
    if not samples:
        print("\nWARNING: could not extract samples from .mra index=2"); sys.exit(1)
    with open(os.path.join(ASSETS_DIR, OUT_SAMPLES), "wb") as f:
        f.write(samples)
    riff = " (RIFF/WAVE)" if samples[:4] == b"RIFF" else ""
    print(f"SUCCESS: wrote {len(samples)} bytes (0x{len(samples):X}){riff} -> {OUT_SAMPLES}")


if __name__ == "__main__":
    main()
