#!/usr/bin/env bash
#
# build.sh - build the Xiaomi veux (SM6375) kernel, Linux 5.4.302
#
#   ./build.sh                 # configure if needed, then build Image.gz + DTBs
#   ./build.sh -j8             # limit parallelism (default: nproc)
#   ./build.sh --all           # build the default goal instead (vmlinux, Image, ...)
#   ./build.sh --modules       # also build loadable modules
#   ./build.sh --menuconfig    # run menuconfig against the existing out/.config
#   ./build.sh --config-only   # stop after configure (useful to sanity-check the toolchain)
#   ./build.sh --reconfig      # drop out/.config and regenerate it, keeping objects
#   ./build.sh --clean         # delete out/ and build from scratch
#
# Environment overrides:
#   TOOLCHAIN_DIR  clang toolchain root      (default: /home/bossku/toolchains/clang-r614150)
#   OUT_DIR        build output directory    (default: <repo>/out)
#   DEFCONFIG      defconfig name            (default: veux_defconfig)
#   JOBS           parallelism               (default: nproc)
#   LOG_FILE       build log / error log      (default: <repo>/error.log)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

TOOLCHAIN_DIR="${TOOLCHAIN_DIR:-/home/bossku/toolchains/clang-r614150}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out}"
DEFCONFIG="${DEFCONFIG:-veux_defconfig}"
JOBS="${JOBS:-$(nproc)}"
LOG_FILE="${LOG_FILE:-$ROOT_DIR/error.log}"

DO_CLEAN=0
DO_RECONFIG=0
DO_MENUCONFIG=0
DO_CONFIG_ONLY=0
BUILD_MODULES=0
BUILD_DEFAULT_GOAL=0
TARGETS=(Image.gz dtbs)

usage() {
	awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print; next } exit }' "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
	case "$1" in
	-j*)        JOBS="${1#-j}"; shift ;;
	-j)         JOBS="$2"; shift 2 ;;
	--all)      BUILD_DEFAULT_GOAL=1; shift ;;
	--modules)  BUILD_MODULES=1; shift ;;
	--config-only) DO_CONFIG_ONLY=1; shift ;;
	--clean)    DO_CLEAN=1; shift ;;
	--reconfig) DO_RECONFIG=1; shift ;;
	--menuconfig) DO_MENUCONFIG=1; shift ;;
	-h|--help)  usage; exit 0 ;;
	*)          echo "error: unknown option '$1' (try --help)" >&2; exit 2 ;;
	esac
done

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# --- toolchain -------------------------------------------------------------
[ -x "$TOOLCHAIN_DIR/bin/clang" ] || die "clang not found in '$TOOLCHAIN_DIR/bin'
Set TOOLCHAIN_DIR to your clang-rXXXXXX directory."
export PATH="$TOOLCHAIN_DIR/bin:$PATH"

missing=()
for tool in clang ld.lld llvm-ar llvm-nm llvm-objcopy llvm-objdump llvm-strip \
            make bc flex bison python3 perl; do
	command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
[ ${#missing[@]} -eq 0 ] || die "missing required tools: ${missing[*]}"

# A stale CROSS_COMPILE from the environment would pick up host gnu tools.
if [ -n "${CROSS_COMPILE:-}" ]; then
	log "ignoring inherited CROSS_COMPILE='$CROSS_COMPILE'"
	unset CROSS_COMPILE
fi

log "clang:     $("$TOOLCHAIN_DIR/bin/clang" --version | head -1)"
log "output:    $OUT_DIR"
log "defconfig: $DEFCONFIG (jobs: $JOBS)"

if [ "$DO_CLEAN" -eq 1 ]; then
	[ "$OUT_DIR" != "/" ] || die "refusing to clean '/'"
	log "removing $OUT_DIR"
	rm -rf "$OUT_DIR"
fi

mkdir -p "$OUT_DIR"

MAKE_ARGS=(O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1)

# Every make run is teed to $LOG_FILE so failures can be inspected afterwards.
# 'set -o pipefail' keeps make's exit status intact through the pipe.
kmake() { make "${MAKE_ARGS[@]}" "$@" 2>&1 | tee -a "$LOG_FILE"; }

: > "$LOG_FILE"
log "build log: $LOG_FILE"

# --- configure -------------------------------------------------------------
# --reconfig discards only out/.config, so edits to $DEFCONFIG are picked up
# without throwing away the compiled objects the way --clean does.
if [ "$DO_RECONFIG" -eq 1 ] && [ -f "$OUT_DIR/.config" ]; then
	log "--reconfig: discarding $OUT_DIR/.config"
	rm -f "$OUT_DIR/.config"
fi

if [ ! -f "$OUT_DIR/.config" ]; then
	log "generating $DEFCONFIG"
	kmake "$DEFCONFIG"
	kmake olddefconfig
else
	log "using existing $OUT_DIR/.config"
fi

if [ "${DO_MENUCONFIG:-0}" -eq 1 ]; then
	kmake menuconfig
fi

if [ "$DO_CONFIG_ONLY" -eq 1 ]; then
	log "configure only - full log: $LOG_FILE"
	exit 0
fi

# --- build -----------------------------------------------------------------
if [ "$BUILD_DEFAULT_GOAL" -eq 1 ]; then
	log "building default goal"
	kmake -j"$JOBS"
else
	log "building ${TARGETS[*]}"
	kmake -j"$JOBS" "${TARGETS[@]}"
fi

if [ "$BUILD_MODULES" -eq 1 ]; then
	log "building modules"
	kmake -j"$JOBS" modules
fi

# --- report ----------------------------------------------------------------
echo
log "artifacts"
for f in "$OUT_DIR/arch/arm64/boot/Image" \
         "$OUT_DIR/arch/arm64/boot/Image.gz" ; do
	[ -f "$f" ] && printf '  %-60s %s\n' "${f#"$ROOT_DIR"/}" "$(du -h "$f" | cut -f1)"
done
count=$(find "$OUT_DIR/arch/arm64/boot/dts" -name '*.dtb' 2>/dev/null | wc -l)
printf '  %-60s %s file(s)\n' "${OUT_DIR#"$ROOT_DIR"/}/arch/arm64/boot/dts/**/*.dtb" "$count"
log "full log: $LOG_FILE"
