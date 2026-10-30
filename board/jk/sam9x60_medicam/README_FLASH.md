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
| Package / Vcc | TSOP-48 (`-WP`) / 3.3 V (2.7–3.6). The BGA twin `MT29F8G08ABBCAH4` is the **same die at 1.8 V** — not interchangeable (§8.5) |
| Life cycle | **obsolete** — listed in Micron's *Obsolete SLC NAND* part catalogue. The same 3.3 V die is still sold as BGA `MT29F8G08ABACAH4-IT:C` (§8.6) |

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
* UBI's EC and VID headers are **not** in the OOB: `ubi_io_read()`/`ubi_io_write()`
  address `pnum × peb_size + offset` and call `mtd_read`/`mtd_write`, so EC sits at
  page 0 of the data area and VID at `vid_hdr_offset` (page 1), LEB = PEB − 2 pages
  (verified in `drivers/mtd/ubi/io.c`). A 64-byte spare therefore does not make a
  part unusable for UBI — it only squeezes PMECC (§7, §8.5).

## 6. Changing the chip — checklist

1. From the datasheet take: page (+spare), block, planes, block count, ECC
   requirement, ONFI timing-mode support.
2. Compute `eccOffset = spare − (page/512) × 13` for 8-bit PMECC; it must be
   ≥ 2 (OOB[0..1] holds the bad-block marker), and `eccOffset..spare` is ECC.
   Free OOB = `eccOffset` − 2: 152 B on a 4096+256 part (safe), **10 B** on a
   2048+64 part (markers + on-flash BBT only, no headroom). Update §4 rows
   1, 3, 4, 5, 6.
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
9. Read the `NAND: Switch to timing mode N` line (mode 3 on the 8 Gbit test bed).
   A slower die (25–30 ns) must negotiate ≤ 3; a mode the SMC tables do not cover
   makes every read fail, so check it before trusting the first boot.

## 7. Known profiles

| Profile | page/spare/block | PMECC config | PEB / LEB | `numpebs` | UBI-region PEBs | ubi end |
|---|---|---|---|---|---|---|
| **8 Gbit (current)** | 4096+224 / 256K+14K | `4096` + `OOB_224` (eccOffset 120) | 0x40000 / 0x3e000 | 4096 | 4056 | `0x40000000` |
| **4 Gbit, 4 K page** `MT29F4G08ABAFAWP/H4`, `TC58NVG2S0H`, `MX30LF4G28AD` | 4096+256 / 256K+16K | `4096` + `OOB_256` (eccOffset 152) | 0x40000 / 0x3e000 | 2048 | 2024 | `0x20000000` |
| **2 K page class** `MT29F2G08ABAEAWP`, `MX30LF4G18AC`, `MX30LF2G28AC/AD` | 2048+64 (or +112/+128) / 128K | `2048` + `OOB_64` (eccOffset 12) | 0x20000 / 0x1f000 | 2048 (2 Gb) / 4096 (4 Gb) | 1968 / 4008 | `0x10000000` / `0x20000000` |

Notes:

* The 4 K-page profile is the **cheap** one: only the OOB scalar changes, the
  rest of the stack (page, block, PEB, LEB) stays. The scalar has been flipped
  once already (PLAN F2: upstream 256 → 224 for this board); nothing else moved.
* A 2 K-page part is a **geometry change**: bootstrap PMECC page/spare, UBI
  PEB/LEB, genimage, `flash-nand.sh` and the DTS `ubi` end all move, and it
  cannot be validated on the 8 Gbit test bed.
* Spare sizes outside `16/32/64/128/224/256` are **not selectable** in
  AT91Bootstrap (`driver/Config.in.nandflash`) — e.g. a 112-byte-spare part
  (`MX30LF4G28AC`) needs a Kconfig + `PMECC_OOB_SIZE` patch, and 2 K/64 leaves
  only 12 B (`eccOffset`), i.e. 10 B after the bad-block marker (§8.5).
* 4 Gbit 3.3 V parts with **224**-byte spare (`MT29F4G08ABAEA`) are EOL
  (Micron PCN 34679, last shipment 2023-05-18): all current 4 Gbit parts are
  4096+256. The 2 Gbit class is EOL as well (`MT29F2G08ABAEAWP-IT:E`, Octopart
  2026-10) and dearer than a live 4 Gbit part — 2 Gbit is not a cost reduction,
  see §8.2.

## 8. Chip selection for the next revision (analysis, 2026-10-30)

Trigger: the 8 Gbit 224-spare die went from commodity to 5–10× priced. Criteria
set by the owner: (1) holds rootfs + userspace with modest spare, (2) config and
layout changes for a new chip are acceptable, (3) "changes done, still will not
boot/mount" risk is not, (4) BGA preferred, TSOP acceptable, (5) newer die,
non-obsolete.

Dataset: part datasheets (page/spare/block/planes/Vcc/package/lifecycle) plus
`drivers/mtd/ubi/io.c` for the header placement; the config deltas below are
cross-checked against §4 and §7. All six parts are ONFI 1.0 (geometry is read
from the parameter page, `-IT` = industrial temp).

### 8.1 Candidates

| Part | Density | Page data+spare | Block | Blocks | `eccOffset` (free) | Package | Vcc | Life cycle | Verdict |
|---|---:|---:|---:|---:|---:|---|---|---|---|
| `MT29F2G08ABAEAWP-IT:E` | 2 Gbit | 2048+64 | 128 KiB | 2048 | **12** (10 B) | TSOP-48 | 3.3 V | **EOL** | reject |
| **`MT29F4G08ABAFAH4-IT:F`** | 4 Gbit | 4096+256 | 256 KiB | 2048 (1 plane) | **152** | VFBGA-63 9×11, 0.8 mm | 3.3 V | production | **recommended** |
| `MT29F4G08ABAFAWP-IT:F` | 4 Gbit | 4096+256 | 256 KiB | 2048 (1 plane) | 152 | TSOP-48 | 3.3 V | production | same die, TSOP twin |
| `MT29F8G08ABBCAH4-IT:C` | 8 Gbit | 4096+224 | 256 KiB | 4096 (2×2048) | 120 | VFBGA-63, 0.8 mm | **1.8 V** (1.7–1.95) | active | reject (rail) |
| `MT29F8G08ABACAH4-IT:C` | 8 Gbit | 4096+224 | 256 KiB | 4096 (2×2048) | 120 | VFBGA-63, 0.8 mm | 3.3 V | active | zero-config 1 GiB option |
| `MX30LF4G18AC-TI` | 4 Gbit | 2048+64 | 128 KiB | 4096 (2×2048) | **12** (10 B) | TSOP-48 | 3.3 V | production, ~$14 @1 | reject |

`ABAFAWP/H4` and `ABACAH4` were added by this analysis — they are the two parts
that keep the configuration. `ABAFA` is the newest die of its class (the D/E
revisions are EOL), ONFI 1.0 at 25 ns; `MX30LF4G18AC` requires 4-bit ECC per
(512+16) B, i.e. 8-bit/512 PMECC exceeds it, which is not the problem.

### 8.2 Verdict

* **Pick `MT29F4G08ABAFAH4-IT:F`** (BGA) or `MT29F4G08ABAFAWP-IT:F` (TSOP, same
  die): 4 Gbit, 3.3 V, newest die of the class, and the only class in this list
  with live second sources (`MX30LF4G28AD`, `TC58NVG2S0H`, §7). It is a *size*
  change plus one OOB scalar, not a geometry change (§8.4).
* `MT29F8G08ABACAH4-IT:C` is the fallback if 1 GiB is needed: **zero config
  change** (identical 4096+224 die as §1), BGA, 3.3 V. It inherits the 8 Gbit
  price pressure, so it likely does not solve the cost problem.
* `MT29F8G08ABBCAH4-IT:C` is the **1.8 V** twin of the current die (same
  geometry, zero config change) but needs a 1.8 V rail on `VDDNF` (the NAND I/O
  rail on the SiP, see `Curiosity vs Medicam Pinout.md`) and NAND VCC, plus it
  is slower (30 ns). Not a drop-in for a 3.3 V board.
* `MT29F2G08ABAEAWP-IT:E` and `MX30LF4G18AC-TI` are rejected: EOL / dearer, and
  both are the 2 KiB-page class = full geometry change that cannot be validated
  on the 8 Gbit test bed (§7). If a live 2 Gbit part is wanted anyway, use
  `MT29F2G08ABAGAH4-IT:G` (2048+**128** → `eccOffset` 76) and not a 64-byte-spare
  part — §8.6, §8.7, §9.

### 8.3 Capacity (`rootfs.ubifs` measured 33 MB, `/data` auto-sizes)

| Die | UBI region | usable after ~2 % BB reserve | rootfs volume | `/data` |
|---|---:|---:|---:|---:|
| 8 Gbit (today) | 1014 MiB (4056 PEB) | ~960 MiB | 300 MiB | ~660 MiB |
| 4 Gbit | 502 MiB (2024 PEB) | ~475 MiB | ~150 MiB | ~325 MiB |
| 2 Gbit | 246 MiB (1968 PEB) | ~230 MiB | 100–120 MiB | ~110–130 MiB |

4 Gbit is comfortable for the current userspace (33 MB image). 2 Gbit leaves no
room for growth and no `ubiupdatevol` slack (an update streams a second copy of
the image into the same volume).

### 8.4 Config delta for the recommended 4 Gbit 256-spare profile

Four edits, no geometry change:

1. `at91bootstrap_nand.fragment`: `CONFIG_PMECC_OOB_224` → `CONFIG_PMECC_OOB_256`
   (eccOffset 120 → 152). Verify `xxd -l 16 output-nand/images/boot.bin.pmecc`.
2. DTS `ubi@a00000`: `0x3f600000` → `0x1f600000`.
3. `genimage-nand.cfg`: `numpebs = 2048`, ubi partition `size = 0x1f600000`.
4. `flash-nand.sh`: `rootfs|…|4056|` → `2024`, and the rootfs volume size
   (`LEB=253952` stays).

Unchanged: PEB 0x40000 / LEB 0x3e000, `UBIFS_LEBSIZE`/`UBI_PEBSIZE`, ECC
strength/step, all partition offsets, `ubi.mtd=6`, `medicam-data.sh`.

### 8.5 Traps confirmed while checking

1. **README.md used to say a 4 Gbit switch is "three numbers only, OOB 224".**
   Every *live* 4 Gbit part is 4096+256, so the bootstrap OOB scalar is a fourth
   edit; skipping it makes the ROM decode page 0 with the wrong `spareSize` →
   silent no-boot (SD rescue still recovers). Fixed in README.md.
2. **`ABB` = 1.8 V.** `ABACA`/`ABAFA` are 3.3 V, `ABBCA`/`ABBFA` are 1.8 V: same
   die, same geometry, incompatible rails. Distributor descriptions get this
   wrong in both directions — read the datasheet voltage row, not the BOM title.
3. **Do not reject a 64-byte-spare part for UBI's sake** (§5: headers are in the
   data area). Reject it for `eccOffset = 12` (10 B after the marker, on-flash
   BBT needs 2–4), for losing the PMECC upgrade path, and for the geometry churn.
4. `BR2_TARGET_ROOTFS_UBIFS_MAXLEBCNT=2082` (~505 MiB) already exceeds the
   1238-LEB rootfs volume. It mounts today, but the number must never exceed the
   volume — fix it while touching this.
5. `flash-nand.sh` erases `bootstrap … 1` erase block: correct for a 256 KiB
   block, but 2 blocks on a 128 KiB-block die (2 KiB-page class) → under-erased.
6. BGA 63-ball 0.8 mm: new footprint, via fanout and X-ray, hard to rework. Keep
   the `-WP` TSOP twin as the approved alternate — it needs no config fork.
7. `/data` on 4 Gbit ≈ 325 MiB. If the product will ever store captures locally,
   decide now; the only zero-config path to 1 GiB is `MT29F8G08ABACAH4`.
8. Before the layout freeze: Micron PCN + product-longevity check for the chosen
   ordering code, and a second-source AVL. The class decides whether multi-
   sourcing is possible at all (4 KiB/256 B: Micron + Macronix + Kioxia;
   2 KiB/64 B: many, but it is a config fork).

### 8.6 Active replacements (Micron live catalogue, checked 2026-10-30)

Status evidence, not distributor hearsay: `MT29F8G08ABACAWP-IT:C` is listed
under Micron's *Obsolete SLC NAND* part catalogue, the codes below under the
live *SLC NAND* catalogue. Prices move; re-check the PCN and the catalogue
before the layout freeze.

| Profile | Orderable code | Density | Page + spare | Blocks | `eccOffset` | Package | Config delta |
|---|---|---:|---|---:|---:|---|---|
| **A — 4 KiB + 224 B** (today's geometry) | `MT29F8G08ABACAH4-IT:C` | 8 Gb | 4096+224 | 4096 | 120 | VFBGA-63 | **none** — re-layout only |
| | `MT29F16G08ADACAH4-IT:C` | 16 Gb | 4096+224 | 8192 | 120 | VFBGA-63 | density only: `numpebs` 8192, ubi end `0x80000000` |
| **B — 4 KiB + 256 B** | `MT29F4G08ABAFAH4-IT:F`, `MT29F4G08ABAFAWP-IT:F` | 4 Gb | 4096+256 | 2048 | 152 | VFBGA-63 / TSOP-48 | §8.4 (4 edits) |
| | `MX30LF4G28AD`, `TC58NVG2S0H` | 4 Gb | 4096+256 | 2048 | 152 | TSOP / BGA | as B, per part |
| **C — 2 KiB + 128 B** | `MT29F2G08ABAGAH4-IT:G`, `MT29F2G08ABAGAWP-IT:G` | 2 Gb | 2048+128 | 2048 | **76** | VFBGA-63 9×11 / TSOP-48 | §9 |
| **D — 2 KiB + 64 B** | `W29N02GV`, `W29N04GV`, `W29N08GV` (Winbond, mass production) | 2/4/8 Gb | 2048+64 | 2048/4096/8192 | **12** | BGA-63 / TSOP-48 | §9 |
| | `MX30LF2G18AC`, `MX30LF4G18AC`, `TC58NVG1S3H`, `S34ML02G2` | 2/4 Gb | 2048+64 | — | 12 | TSOP / BGA | §9 |

Notes:

* The 1.8 V twins (`ABBGA`, `ABBFA`, `ABBCA`, Winbond `W29N04GZ/W`) are the same
  dies on a different rail — never mix them into a 3.3 V BOM (§8.5, item 2).
* Profile C is the live successor of the EOL 2 Gb `MT29F2G08ABAEAWP` (2048+64)
  and is the only 2 Gbit option that keeps OOB headroom (74 B free vs 10 B).
* Winbond's whole `W29N-GV` family (1–8 Gb) is 2 KiB/64 B, so it cannot supply a
  4 KiB-page part at any density. An 8 Gb part of that family keeps the frozen
  byte layout and the `ubi` end (`0x40000000`) but still changes page/block/LEB.
* On-die-ECC default state varies per ordering code (Micron publishes an "ECC
  off" errata for the 2 Gb `ABAGA` family, Winbond advertises configurable ECC).
  The stack already issues *Disable On-Die ECC* (README, bootstrap log) — confirm
  it for the exact code, do not assume.

### 8.7 Does a 128 KiB block hurt?

No. Checked against this stack:

| Aspect | 2 KiB page / 128 KiB block vs today |
|---|---|
| UBI/UBIFS overhead | identical 3.1 % — 2 header pages per PEB, `0x1f000/0x20000` = `0x3e000/0x40000` |
| ECC strength | unchanged: 8-bit per 512 B is a per-sector property, not per-block |
| Free OOB | set by **spare**, not block: 128 B → 74 B free (fine); 64 B → **10 B**, and 12-bit PMECC needs 64 B, i.e. it becomes impossible |
| Endurance / wear | same per-block endurance, finer granularity, wear levelling unaffected |
| Speed | 2× the page commands per MB; 8 MiB kernel = 4096 page reads instead of 2048 (tens of ms) |
| Bad-block reserve | same ~2 %, expressed in twice as many PEBs |
| Cost | the whole geometry fork (§9) and no test-bed coverage |

So the block size is a non-issue; the **64-byte spare** is what to avoid. If
2 Gbit is chosen, take the 128-byte-spare `ABAGA` (profile C).

## 9. 2 KiB-page profile — the full delta list

Only if a 2 Gbit (or Winbond 8 Gbit) part is chosen. Reference numbers:

| Value | today (4 KiB) | 2 KiB page, 2 Gbit | 2 KiB page, 4 Gbit | 2 KiB page, 8 Gbit |
|---|---|---|---|---|
| page / spare | 4096+224 | 2048+128 (or +64) | 2048+64 | 2048+64 |
| block / PEB | 0x40000 | 0x20000 | 0x20000 | 0x20000 |
| LEB | 0x3e000 | 0x1f000 | 0x1f000 | 0x1f000 |
| min-I/O | 4096 | 2048 | 2048 | 2048 |
| `eccOffset` (8-bit) | 120 | 76 (or 12) | 12 | 12 |
| `numpebs` (whole die) | 4096 | 2048 | 4096 | 8192 |
| UBI-region PEBs | 4056 | 1968 | 4008 | 8184 |
| `ubi` end / size | `0x40000000` / `0x3f600000` | `0x10000000` / `0x0f600000` | `0x20000000` / `0x1f600000` | `0x40000000` / `0x3f600000` |

Edits:

1. `at91bootstrap_nand.fragment`: `CONFIG_PMECC_PAGESIZE_2048=y` plus
   `CONFIG_PMECC_OOB_128` (profile C) or `CONFIG_PMECC_OOB_64` (profile D); the
   `boot.bin.pmecc` header then carries eccOffset 76 or 12 (§6.5).
2. DTS `ubi@a00000`: `reg = <0xa00000 0x0f600000>` (2 Gbit) / `0x1f600000`
   (4 Gbit) / unchanged for 8 Gbit.
3. `genimage-nand.cfg`: `pebsize = 0x20000`, `lebsize = 0x1f000`,
   `numpebs` per the table, `minimum-io-unit-size = 0x800`, ubi `size` per the
   table.
4. `configs/sam9x60_medicam_nand_defconfig`: `UBIFS_LEBSIZE=0x1f000`,
   `UBIFS_MINIOSIZE=0x800`, `UBI_PEBSIZE=0x20000`, and `MAXLEBCNT` ≤ the rootfs
   volume LEB count (§8.5, item 4).
5. `flash-nand.sh`: `EB_KB=128`, per-partition counts in 128 KiB erase blocks
   (bootstrap 2, u-boot 6, env 1 each, dtb 4, kernel 64, rootfs 1968/4008),
   `LEB=126976`, and the rootfs volume size in LEBs.
6. Re-run §6.6–6.9 on the first board and re-freeze UBI geometry (expect PEB
   `0x20000`, LEB `0x1f000`, VID header at 2048, data at 4096 — measure, §5).

A 2 KiB-page build cannot boot the 8 Gbit test bed (different page, block and
ECC geometry), so if 8 Gbit units are already in the field, this has to be a
**second configuration**, not an edit of the current one.
