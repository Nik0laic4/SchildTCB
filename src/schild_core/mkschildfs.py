#!/usr/bin/env python3
"""SchildFS GPT-gap image builder.

Builds the SchildFS on-disk structures that live inside the GPT free gap
(between the partition table at LBA 2..33 and the first partition, normally
LBA 2048). The kernel reads these structures at ABSOLUTE LBAs (see
schild_schild_fs.adb). Canonical layout:

    LBA 2016       Superblock A (primary)
    LBA 2017       Superblock B (backup  - A/B torn-write recovery)
    LBA 2018       Root directory A (primary)
    LBA 2019       Root directory B (backup)
    LBA 2020..2047 File data (contiguous per file; 28 blocks = 14 KiB)

The image produced here contains ONLY the gap (32 blocks). Flash it into the
internal NVMe without touching the protective MBR / GPT header / boot-log that
occupy LBA 0..2015:

    sudo dd if=schildfs_gap.img of=/dev/nvme0n1 bs=512 seek=2016 conv=notrunc
"""
import struct
import sys

MAGIC       = 0x4E564653
BLOCK_SIZE  = 512
MAX_ENTRIES = 16
ENTRY_SIZE  = 32
MAX_NAME    = 24

# SchildFS lives entirely inside the GPT free gap.
FS_BASE_LBA = 2016
FS_END_LBA  = 2048
GAP_BLOCKS  = FS_END_LBA - FS_BASE_LBA

SUPER_A_LBA = FS_BASE_LBA + 0   # 2016
SUPER_B_LBA = FS_BASE_LBA + 1   # 2017
DIR_A_LBA   = FS_BASE_LBA + 2   # 2018
DIR_B_LBA   = FS_BASE_LBA + 3   # 2019
DATA_LBA    = FS_BASE_LBA + 4   # 2020

def crc32_iso(data):
    """CRC-32/ISO-HDLC (reflected polynomial 0xEDB88320), matching the Ada side."""
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xEDB88320 if crc & 1 else crc >> 1
    return (~crc) & 0xFFFFFFFF

def _off(lba):
    """Byte offset of an absolute LBA inside the gap image."""
    return (lba - FS_BASE_LBA) * BLOCK_SIZE


def _write_superblock(img, lba, root_dir_lba, root_entries, dir_crc, generation):
    o = _off(lba)
    struct.pack_into('<I', img, o + 0,  MAGIC)
    struct.pack_into('<H', img, o + 4,  1)              # version
    struct.pack_into('<H', img, o + 6,  BLOCK_SIZE)
    struct.pack_into('<I', img, o + 8,  root_dir_lba)
    struct.pack_into('<I', img, o + 12, root_entries)
    struct.pack_into('<I', img, o + 20, dir_crc)
    struct.pack_into('<I', img, o + 24, generation)
    # Header checksum is CRC32 over bytes 0..15 (computed last).
    struct.pack_into('<I', img, o + 16, crc32_iso(img[o:o + 16]))


def _write_root_dir(img, lba, entries):
    """entries: list of (name, start_lba, size)."""
    o = _off(lba)
    for i, (name, start_lba, size) in enumerate(entries):
        eo = o + i * ENTRY_SIZE
        name_bytes = name.encode('ascii', errors='replace')[:MAX_NAME].ljust(MAX_NAME, b'\x00')
        img[eo:eo + MAX_NAME] = name_bytes
        struct.pack_into('<I', img, eo + 24, start_lba)
        struct.pack_into('<I', img, eo + 28, size)


def build_gap(files, output_path):
    if len(files) > MAX_ENTRIES:
        print(f"Too many files: {len(files)} > {MAX_ENTRIES}")
        sys.exit(1)

    # Allocate contiguous data blocks for each file (absolute LBAs).
    dir_entries = []
    next_lba = DATA_LBA
    for name, data in files:
        blocks = (len(data) + BLOCK_SIZE - 1) // BLOCK_SIZE
        dir_entries.append((name, next_lba, len(data)))
        next_lba += blocks
    if next_lba > FS_END_LBA:
        print(f"Data exceeds the GPT gap: need LBA {next_lba} > {FS_END_LBA}")
        sys.exit(1)

    img = bytearray(GAP_BLOCKS * BLOCK_SIZE)

    # Root directory (primary at DIR_A_LBA, backup at DIR_B_LBA - identical).
    _write_root_dir(img, DIR_A_LBA, dir_entries)
    _write_root_dir(img, DIR_B_LBA, dir_entries)
    dir_crc = crc32_iso(img[_off(DIR_A_LBA):_off(DIR_A_LBA) + BLOCK_SIZE])

    # Superblocks A and B: both point at the primary directory, generation 0.
    _write_superblock(img, SUPER_A_LBA, DIR_A_LBA, len(files), dir_crc, 0)
    _write_superblock(img, SUPER_B_LBA, DIR_A_LBA, len(files), dir_crc, 0)

    # File data at their absolute LBAs.
    for i, (name, start_lba, size) in enumerate(dir_entries):
        _, data = files[i]
        img[_off(start_lba):_off(start_lba) + len(data)] = data

    with open(output_path, 'wb') as f:
        f.write(img)

    print(f"[+] {output_path}: {GAP_BLOCKS} gap blocks, {len(files)} files")
    for name, lba, size in dir_entries:
        print(f"    /{name}: LBA {lba}, {size} bytes")

if __name__ == '__main__':
    index_html = (
        b"<!DOCTYPE html><html lang=en><head><meta charset=UTF-8>"
        b"<title>Schild TCB - high-assurance research prototype</title>"
        b"<style>"
        b"body{font-family:sans-serif;max-width:800px;margin:40px auto;padding:0 20px;"
        b"background:#0a1628;color:#e0e8f0}"
        b"h1{color:#4da6ff;border-bottom:2px solid #1a3355;padding-bottom:10px}"
        b".card{background:#112240;border-radius:8px;padding:20px;margin:20px 0;"
        b"border:1px solid #1a3355}"
        b".pass{color:#4caf50;font-weight:bold}"
        b"table{width:100%;border-collapse:collapse;margin:10px 0}"
        b"td,th{border:1px solid #1a3355;padding:8px 12px;text-align:left}"
        b"th{background:#0d1b33}"
        b".footer{margin-top:40px;font-size:12px;color:#556}"
        b"</style></head><body>"
        b"<h1>Schild TCB v1.0.0-pre</h1>"
        b"<p>High-assurance research prototype on seL4 + Ada/SPARK. MLS policy formally verified; drivers and crypto validated by tests.</p>"
        b"<div class=card><h2>Subsystem Status</h2><table>"
        b"<tr><th>Subsystem</th><th>Status</th><th>Details</th></tr>"
        b"<tr><td>NVMe Driver</td><td class=pass>PASS</td><td>Identify+Read+Write+Verify</td></tr>"
        b"<tr><td>e1000e Network</td><td class=pass>PASS</td><td>TX(DD-bit); RX needs real backend</td></tr>"
        b"<tr><td>SMP</td><td class=pass>PASS</td><td>BSP+AP cores</td></tr>"
        b"<tr><td>SchildFS</td><td class=pass>PASS</td><td>A/B superblock, create+write+read</td></tr>"
        b"<tr><td>MLS Policy</td><td class=pass>PASS</td><td>Bell-LaPadula, 5 levels</td></tr>"
        b"<tr><td>HMAC-SHA256</td><td class=pass>PASS</td><td>FIPS 198-1, 64 rounds</td></tr>"
        b"<tr><td>SPARK Verification</td><td class=pass>PASS</td><td>MLS policy formally verified via SPARK Level 4</td></tr>"
        b"<tr><td>HTTP Server</td><td class=pass>PASS</td><td>HTTP/1.0, TCP/IP on e1000e</td></tr>"
        b"</table></div>"
        b"<div class=card><h2>Technical Metrics</h2><table>"
        b"<tr><td>Microkernel</td><td>seL4 core (with standalone local object-zeroing patch)</td></tr>"
        b"<tr><td>Language</td><td>Ada/SPARK 2022 + C + ASM</td></tr>"
        b"<tr><td>Build</td><td>175 Ada objects, 0 errors</td></tr>"
        b"<tr><td>ELF Size</td><td>566 KB baseline size</td></tr>"
        b"<tr><td>Architecture</td><td>x86_64, QEMU / ThinkPad T580</td></tr>"
        b"<tr><td>MLS Levels</td><td>5 (Public..Top_Secret)</td></tr>"
        b"<tr><td>Network</td><td>e1000e + ARP + IPv4 + ICMP + TCP + HTTP</td></tr>"
        b"</table></div>"
        b"<div class=footer>Schild TCB v1.0.0-pre (Stage 10) | "
        b"\xd0\x98\xd1\x80\xd0\xb3\xd0\xb0\xd0\xbd\xd0\xbe\xd0\xb2 \xd0\x90.\xd0\x9d.</div>"
        b"</body></html>"
    )
    files = [("index.html", index_html)]
    out = sys.argv[1] if len(sys.argv) > 1 else "schildfs_gap.img"
    build_gap(files, out)

