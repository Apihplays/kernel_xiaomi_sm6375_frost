#!/usr/bin/env bash
#
# repack-kernel.sh - Repackage the built kernel (with KSU/SUSFS) into an AnyKernel3 zip
# Based on nebula-veux-20261030-1517.zip structure (excluding the kernel)
#
# Usage:
#   ./repack-kernel.sh          # default: creates nebula-ksu-susfs-20261117-0918.zip
#   ./repack-kernel.sh -o myname # output zip name (date/time appended automatically)
#   ./repack-kernel.sh -h       # help
#
# Requirements:
#   - zip utility (busybox or GNU coreutils)
#   - Python 3 (for zipfile module)
#   - Built kernel in out/arch/arm64/boot/Image.gz
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${REPO_ROOT}/out"
NEBULA_ZIP="${REPO_ROOT}/nebula-veux-20261030-1517.zip"

# Auto-generate timestamp (YYYYMMDD-HHMMSS) for easy file tracking
BUILD_DATE="$(date +%Y%m%d-%H%M%S)"

# Default output zip name (with date appended automatically)
OUT_ZIP="${REPO_ROOT}/nebula-ksu-susfs-${BUILD_DATE}.zip"

usage() {
    echo "Usage: $0 [-o output.zip]"
    echo "  -o  Output zip filename (date/time appended automatically)"
    echo "  -h  Show this help"
    echo ""
    echo "This script copies all files from the nebule zip (except the kernel)"
    echo "and adds your newly built kernel. It reads the nebule zip directly"
    echo "using Python zipfile - no extraction step required."
    exit 0
}

while getopts "ho:" opt; do
    case "$opt" in
        o) OUT_ZIP="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Append timestamp to user-provided output name (if not already present)
if [[ "$OUT_ZIP" != *.zip ]]; then
    OUT_ZIP+=".zip"
fi
if [[ ! "$OUT_ZIP" =~ ${BUILD_DATE} ]]; then
    OUT_ZIP="${OUT_ZIP%.zip}-${BUILD_DATE}.zip"
fi

# --- Sanity checks -----------------------------------------------------
# Check nebule zip exists
if [ ! -f "$NEBULA_ZIP" ]; then
    echo "ERROR: Nebule zip not found: $NEBULA_ZIP" >&2
    echo "       Run: unzip nebula-veux-20261030-1517.zip -d nebula_extract2" >&2
    exit 1
fi

# Check built kernel
if [ ! -f "${BUILD_DIR}/arch/arm64/boot/Image.gz" ]; then
    echo "ERROR: Built kernel not found: ${BUILD_DIR}/arch/arm64/boot/Image.gz" >&2
    echo "       Run: ./build.sh first" >&2
    exit 1
fi

if ! command -v zip &>/dev/null; then
    echo "ERROR: 'zip' utility not found. Install zip or use busybox zip." >&2
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "ERROR: Python 3 not found. Install python3." >&2
    exit 1
fi

# --- Build repack structure ---------------------------------------------
RM_DIR="${REPO_ROOT}/ak3_repack"
rm -rf "$RM_DIR"
mkdir -p "$RM_DIR"

# --- Copy our newly built kernel ---------------------------------------------
# Use uncompressed Image for AnyKernel3 (flashable kernel image)
cp "${BUILD_DIR}/arch/arm64/boot/Image" "${RM_DIR}/Image"

# Also copy compressed Image.gz for reference
cp "${BUILD_DIR}/arch/arm64/boot/Image.gz" "${RM_DIR}/Image.gz"

# Update anykernel.sh with device names from nebule file
cat > "$RM_DIR/anykernel.sh" << 'EOF'
### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() {
kernel.string=nebula kernel by frost
do.devicecheck=1
do.cleanup=1
# Device names as per nebula-veux-20261030-1517.zip reference
device.name1=veux
device.name2=peux
'; } # end properties


### AnyKernel install
# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;
NO_BLOCK_DISPLAY=1;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;
. tools/ak3-custom.sh;

# boot install
split_boot;

flash_boot;
## end boot install


# vendor_boot shell variables
BLOCK=vendor_boot;

# reset for vendor_boot patching
reset_ak;

# vendor_boot install
split_boot;

check_cmdline;
check_vendor_hals;

flash_boot;
## end vendor_boot install


# dtbo install
erase_dtbo;
## end of dtbo install
EOF
chmod +x "$RM_DIR/anykernel.sh"

# --- Create zip using Python zipfile (no extraction needed) ------------
echo "==> Creating $OUT_ZIP..."

# Change to the repack directory so relative paths work correctly
cd "$RM_DIR"

# Copy nebule zip contents + built kernel into output zip using Python
python3 - << PYEOF
import zipfile
import os
import sys
import shutil

# Paths - these are passed via environment
nebula_zip = "$NEBULA_ZIP"
output_zip = "$RM_DIR/output_tmp.zip"
final_output = "$OUT_ZIP"

# Files to copy from nebule zip (everything except the kernel Image)
NEBULE_FILES = [
    "cmdline",
    "dtb",
    "banner",
    "LICENSE",
    "tools/ak3-core.sh",
    "tools/ak3-custom.sh",
    "tools/busybox",
    "tools/fdtput",
    "tools/magiskboot",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
    "anykernel.sh",
]

# Directory entries needed in the zip
ZIP_DIRS = [
    "META-INF/",
    "META-INF/com/",
    "META-INF/com/google/",
    "META-INF/com/google/android/",
    "tools/",
]

# Create output zip
zf = zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED)

# Copy nebule files
neb = zipfile.ZipFile(nebula_zip, "r")
for name in NEBULE_FILES:
    try:
        data = neb.read(name)
        # Set executable permissions on scripts (like the nebule zip)
        if name.endswith(".sh") or name.endswith("/update-binary") or name == "tools/busybox" or name == "tools/ak3-core.sh" or name == "tools/fdtput" or name == "tools/magiskboot":
            perm = 0o100775
        else:
            perm = 0o100664
        zf.writestr(zipfile.ZipInfo(name), data, compress_type=zipfile.ZIP_DEFLATED)
        # Set permissions
        if not name.endswith("/"):
            zf.getinfo(name).external_attr = perm << 16
        print("  Copy: " + name)
    except KeyError as e:
        print("  Warning: missing in nebule zip: " + str(e))

# Add directory entries (like the nebule zip)
for d in ZIP_DIRS:
    info = zipfile.ZipInfo(d)
    info.external_attr = 0o40775 << 16
    zf.writestr(info, b"")

neb.close()

# Append built kernel
zf.write("Image", "Image")
zf.close()

# Rename to final output
os.rename(output_zip, final_output)

print("")
print("==> Done. Output: " + final_output)
print("   Size: " + str(os.path.getsize(final_output)) + " bytes")
PYEOF

echo ""
echo "==> Done. Output: $OUT_ZIP"
ls -la "$OUT_ZIP"
