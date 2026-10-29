# NAND parameters and where they are tuned

Scope: the values that couple the **chip** to the **frozen flash layout**
(`README.md` → "NAND layout"). Read this before ordering or swapping a NAND
part. Everything here is *measured on hardware*, not assumed (see
`LOG_base_image.txt`, LOG 9.12–9.15).

## 1. Current chip (test bed)

| Item | Value |
|---|---|
| Part | `MT29F8G08ABACAWP-IT:C` (Micron SLC, 3.3 V, x8, ONFI 1.0, TSOP-48) |
| Density / blocks | 8 Gbit (1 GiB) / 4096 blocks (2 planes × 2048) |
| Page | 4320 B = **4096 data + 224 spare** |
| Block | 64 pages = **256 KiB** data + 14 KiB spare |
| ECC required | 8 bit per 540 B |
| ONFI timing modes | 0–4 (this build runs **mode 3**) |

## 2. Values derived from it (all of them must match the chip)

| Derived value | Current | Comes from |
|---|---|---|
| MTD `pagesize` / `oobsize` / `erasesize` | 4096 / 224 / 0x40000 | page, spare, block |
| PMECC sectors/page, ECC bytes | 8 × 13 B = 104 B | page 4096 / 512 B sectors, 8-bit correction |
| PMECC `eccOffset` | **120** (= 224 − 104) | spare − ECC bytes |
| PMECC `spareSize` | **224** | spare size |
| UBI PEB / LEB | 0x40000 / **0x3e000** (253952) | block / (block − 2 × page) |
| UBI VID hdr offset / data offset | 4096 / 8192 | page (auto, **verify**) |
| UBI minimum I/O | 4096 | page |
| `ubi` region PEB count | **4056** = 0x3f600000 / 0x40000 | layout, not the die |
| Whole-die PEB count | **4096** = 0x40000000 / 0x40000 | die size (genimage only) |

## 3. Frozen layout (offsets are byte-addressed, geometry-independent)

| Offset | Size | Partition |
|---:|---:|---|
| `0x000000` | 256 KiB | at91bootstrap (`boot.bin.pmecc`) |
| `0x040000` | 768 KiB | u-boot |
| `0x100000` | 256 KiB | env (redundant) |
| `0x140000` | 256 KiB | env (primary) |
| `0x180000` | 512 KiB | device tree |
| `0x200000` | 8 MiB | kernel (`zImage`) |
| `0xa00000` | rest of die | `ubi` → `rootfs` + `data` volumes |

## 4. Where each value is tuned

| Value | File | Symbol / line |
|---|---|---|
| PMECC page / spare / strength | `at91bootstrap_nand.fragment` | `CONFIG_PMECC_PAGESIZE_*`, `CONFIG_PMECC_OOB_*`, `CONFIG_PMECC_CORRECT_BITS_8` |
| NAND partitions, `ubi` end | `at91-sam9x60_medicam.dts` | `ubi@a00000 { reg = <0xa00000 0x3f600000>; }` |
| PEB / LEB / whole-die PEBs | `genimage-nand.cfg` | `pebsize = 0x40000`, `lebsize = 0x3e000`, `numpebs = 4096`, ubi `size = 0x3f600000` |
| UBI-region PEB count, rootfs volume | `flash-nand.sh` | table line `rootfs\|/dev/mtd6\|rootfs.ubifs\|4056\|ubi\|rootfs`, `LEB=253952` |
| UBIFS/UBI target geometry | `configs/sam9x60_medicam_nand_defconfig` | `BR2_TARGET_ROOTFS_UBIFS_LEBSIZE=0x3e000`, `…_MINIOSIZE=0x1000`, `…_MAXLEBCNT`, `BR2_TARGET_ROOTFS_UBI_PEBSIZE=0x40000` (`UBI_SUBSIZE` is inert, PLAN 2.4) |
| Kernel/DTB offsets, bootargs | `uboot-nand.fragment`, `uboot-env-nand.txt` | `bootcmd_boot=nand read … 0x800000; … 0x180000 0x20000`, `ubi.mtd=6 root=ubi0:rootfs` |
| Fastmap, bad-block handling | kernel fragment | `MTD_UBI`, `MTD_UBI_FASTMAP`, DTS `nand-on-flash-bbt` |

**Do not touch on a chip change:** `nand-ecc-strength = 8` / `nand-ecc-step-size = 512`
(class-independent), `medicam-data.sh` + `data.mount` (resolve the MTD by label
and size the `data` volume to the rest of UBI), kernel cmdline `ubi.mtd=6`
(partition *order*, not geometry), genimage offsets.

## 5. What is automatic (no edit, but verify once)

* U-Boot and Linux read page/spare/blocks over **ONFI** — the geometry in MTD is
  correct by itself (`NAND: ONFI flash detected … Page 4096, spare 224`).
* UBI derives PEB size from MTD and VID/data offsets from the **page size** —
  but the defaults are *not* what the docs claim (LOG 9.13: someone assumed
  sub-page 512 / VID 512; measured 4096 / 8192, LEB 253952). **Always measure.**
* `medicam-data.service` creates/sizes the `data` volume from whatever UBI region
  it finds → survives density changes.

## 6. Changing the chip — checklist

1. From the datasheet take: page (+spare), block, planes, block count, ECC
   requirement, ONFI timing-mode support.
2. Compute `eccOffset = spare − (page/512) × 13` for 8-bit PMECC; it must be
   ≥ 2 (OOB[0..1] holds the bad-block marker). Update §4 rows 1, 3, 4, 5, 6.
3. Any change of page/block size also changes UBI: `pebsize`, `lebsize`,
   `numpebs`, the `ubi` partition size and the UBI-region PEB count.
4. `make clean && make` in the NAND build (images are not re-derived otherwise).
5. Check `boot.bin.pmecc`: its first 208 bytes must be 52 copies of one 32-bit
   header word carrying the new `spareSize` / `eccOffset` (README → "ROM boot
   sequence"); a wrong header = silent no-boot, nothing else in the image can
   compensate.
6. Flash from the rescue SD, then on the board: `mtdinfo /dev/mtd0` must show the
   datasheet `erasesize` / `pagesize` / `oobsize`.
7. Format UBI **empty** (`ubiformat`, no `-s`/`-O`) and freeze what the kernel
   reports: `cat /sys/class/ubi/ubi0/{eraseblock_size,leb_size,vid_hdr_offset,data_offset}`.
8. Boot, then write ~50 MiB to `/data`, reboot, read back (stage 1.5 criterion).

## 7. Known profiles

| Profile | page/spare/block | PMECC config | PEB / LEB | `numpebs` | UBI-region PEBs | ubi end |
|---|---|---|---|---|---|---|
| **8 Gbit (current)** | 4096+224 / 256K+14K | `4096` + `OOB_224` (eccOffset 120) | 0x40000 / 0x3e000 | 4096 | 4056 | `0x40000000` |
| **4 Gbit, 4 K page** `MT29F4G08ABAFAWP/H4`, `TC58NVG2S0H`, `MX30LF4G28AD` | 4096+256 / 256K+16K | `4096` + `OOB_256` (eccOffset 152) | 0x40000 / 0x3e000 | 2048 | 2024 | `0x20000000` |
| **2 K page class** `MT29F2G08ABAEAWP`, `MX30LF4G18AC`, `MX30LF2G28AC/AD` | 2048+64 (or +112/+128) / 128K | `2048` + `OOB_64` (eccOffset 12) | 0x20000 / 0x1f000 | 2048 (2 Gb) / 4096 (4 Gb) | 1968 / 4008 | `0x10000000` / `0x20000000` |

Notes:

* The 4 K-page profile is the **cheap** one: only the OOB scalar changes, the
  rest of the stack (page, block, PEB, LEB) stays. Proven once already for
  224 → 256 (PLAN F2).
* A 2 K-page part is a **geometry change**: bootstrap PMECC page/spare, UBI
  PEB/LEB, genimage, `flash-nand.sh` and the DTS `ubi` end all move, and it
  cannot be validated on the 8 Gbit test bed.
* Spare sizes outside `16/32/64/128/224/256` are **not selectable** in
  AT91Bootstrap (`driver/Config.in.nandflash`) — e.g. a 112-byte-spare part
  (`MX30LF4G28AC`) needs a Kconfig + `PMECC_OOB_SIZE` patch, and 2 K/64 leaves
  only 12 B of ECC headroom.
* 4 Gbit 3.3 V parts with **224**-byte spare (`MT29F4G08ABAEA`) are EOL
  (Micron PCN 34679, last shipment 2023-05-18): all current 4 Gbit parts are
  4096+256.
