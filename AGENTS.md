# AGENTS.md - Kernel Build & Repack Notes (Xiaomi veux SM6375 / Frost)

## Quick Reference

```
Project root: /home/bossku/veux/kernel_xiaomi_sm6375_frost
Kernel: 5.4.302 (QGKI/GKI 1.0), ARM64, Android
Toolchain: clang-r614150 (Android build, clang 23.0.1)
Native build:  ./build.sh -j2    (or  -j8 if RAM >= 8GB)
ThinLTO:      CONFIG_THINLTO=y in out/.config  (required for <8GB RAM)
Repacked zip: repack-kernel.sh  OR  nebula-ksu-susfs.zip
```

## Build System

- `build.sh` (top-level) wraps `make ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1`
- Output: `out/` directory (O=out)
- Defconfig: `veux_defconfig` (gki_defconfig based)
- LTO: full LTO (`-flto`) OOMs on WSL2 3.8GB; thinlto (`-flto=thin`, `CONFIG_THINLTO=y`) is the working path
- Kernel image: `out/arch/arm64/boot/Image.gz` (compressed) or `Image` (raw)
- Device tree: `out/arch/arm64/boot/dts/vendor/xiaomi/veux.dtb`

## KSU / SUSFS Integration (bakasu)

- KSU kernel patch: `003-susfs_patch_to_5.4.patch` (+ `004-susfs_fixup_5.4.patch`)
- Version: BakaSU v4.2.0-rc3, SUSFS v2.3.0
- KernelSU kmodule compiled into kernel (not a separate module)
- Inline hook: SUSFS inline hook enabled
- `KernelSU/kernel/` contains the KSU kmodule source

## Repack / Flash Workflow

- AnYKernel3 structure used: `Image.gz`, `cmdline`, `dtb`, `anykernel.sh`, `tools/`
- `anykernel.sh` (nebula style):
  - `kernel.string=nebula kernel by frost`
  - `do.devicecheck=1`, `do.cleanup=1`, `device.name1=veux`, `device.name2=peux`
  - BlocK=boot, minimal split_boot+flash_boot
- Repack script: `repack-kernel.sh` (standalone, run with `./repack-kernel.sh`)
- Output zip: `nebula-ksu-susfs-YYYYMMDD-HHMMSS.zip` (auto-appends date/time)
- Flash: `fastboot update nebula-ksu-susfs.zip`
- Uses uncompressed `Image` for flash-ready output (AnyKernel3 expects uncompressed Image)
- Also copies compressed `Image.gz` for reference
- No extraction step: reads nebule zip directly via Python `zipfile`
- Device names (from nebule anykernel.sh): `veux`, `peux` — do NOT add extra device names

## Cmdline (from nebule zip)
- `androidboot.hardware=qcom`
- `androidboot.init_fatal_reboot_target=recovery`
- `lpm_levels.sleep_disabled=1`
- `service_locator.enable=1`
- `androidboot.usbcontroller=4e00000.dwc3`
- `swiotlb=noforce`
- `loop.max_part=7`
- `iptable_raw.raw_before_defrag=1`
- `ip6table_raw.raw_before_defrag=1`
- `buildvariant=user`

## Ref Files
- Nebule zip: `nebula-veux-20261030-1517.zip`
- Nebule extracted: `nebula_extract2/` (contains Image, cmdline, dtb, anykernel.sh, tools/, etc.)
- AnyKernel3: `AnyKernel3/` (cloned from osm0sis/AnyKernel3)
- Repack output: `nebula-ksu-susfs-YYYYMMDD-HHMMSS.zip`

## WSL2 RAM Limitation

- System RAM: 3.8GB total, ~838MB usable
- WSL2 default is 50% of host RAM; no `.wslconfig` set
- Recommended for full build: set `memory=8GB` in Windows `.wslconfig`
- Build with `JOBS=2` when RAM < 4GB

## File Reference

| Path | Purpose |
|------|---------|
| `build.sh` | Kernel build wrapper |
| `out/.config` | Kernel config (LTO/thinlto enabled) |
| `out/arch/arm64/boot/Image.gz` | Built compressed kernel |
| `out/arch/arm64/boot/dts/vendor/xiaomi/veux.dtb` | Device tree blob |
| `003-susfs_patch_to_5.4.patch` | KSU/SUSFS patch to 5.4 |
| `nebula-ksu-susfs.zip` | Ready-to-flash repacked kernel |
| `repack-kernel.sh` | Standalone repack script |
| `AnyKernel3/` | AnYKernel3 repo (cloned) |
