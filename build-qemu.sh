#!/usr/bin/env bash
#
# build-qemu v3 written by Andrea Giani
#

set -e

# ==============================
# STEP 0: Parse optional arguments
# ==============================
ENABLE_VIRTFS="--disable-virtfs"
USE_NASM=true
REUSE_DOWNLOAD=false

print_help() {
		echo "build-qemu v3 - written by Andrea Giani"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --virtfs           Enable VirtFS support (disabled by default)"
    echo "  --no-nasm          Do not use NASM as assembler (uses default system assembler)"
    echo "  --reuse-download   Reuse existing QEMU archive if already downloaded"
    echo "  --inject-alignment Injecting Cache Alignment into headers"
    echo "  --help             Show this help message and exit"
    exit 0
}

for arg in "$@"; do
    case $arg in
        --virtfs)
            ENABLE_VIRTFS="--enable-virtfs"
            echo "🔧 VirtFS ENABLED"
            ;;
        --no-nasm)
            USE_NASM=false
            echo " NASM DISABLED"
            ;;
        --reuse-download)
            REUSE_DOWNLOAD=true
            echo " Reusing existing archive if available"
            ;;
        --help)
            print_help
            ;;            
    esac
done

if $USE_NASM; then
    export AS="nasm"
fi

# ==============================
# STEP 1: Fetch latest QEMU version
# ==============================
rm -rf build/

echo "build-qemu v3 - written by Andrea Giani"
echo " Retrieving latest QEMU version..."
LATEST=$(curl -s https://download.qemu.org/ | \
    grep -oP 'qemu-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=.tar.xz)' | \
    sort -V | tail -1)

echo " Latest QEMU version is: $LATEST"

# ==============================
# STEP 2: Set variables
# ==============================
FILENAME="qemu-${LATEST}.tar.xz"
ARCHIVE_NAME="qemu-${LATEST}-win64.tar.gz"
TARGETS="x86_64-softmmu"
PREFIX="$PWD/qemu-install"

# ==============================
# STEP 3: Install dependencies
# ==============================
echo " Installing required packages..."
pacman -S --needed --noconfirm \
    base-devel \
    mingw-w64-x86_64-toolchain \
    mingw-w64-x86_64-glib2 \
    mingw-w64-x86_64-pixman \
    mingw-w64-x86_64-zlib \
    mingw-w64-x86_64-nasm \
    python3 \
    wget \
    ninja \
    meson \
    curl

# ==============================
# STEP 4: Download and extract
# ==============================
if [[ -f "${FILENAME}" && "$REUSE_DOWNLOAD" == true ]]; then
    echo " Using existing archive ${FILENAME}"
else
    echo "⬇ Downloading QEMU..."
    curl -LO https://download.qemu.org/${FILENAME}
fi

echo " Extracting..."
rm -rf "qemu-${LATEST}"
tar --force-local -xvf "${FILENAME}" || true

cd "qemu-${LATEST}"

# ==============================
# STEP 5: Configure build
# ==============================
echo " Configuring QEMU..."
./configure \
    --prefix="${PREFIX}" \
    --target-list="${TARGETS}" \
    --enable-slirp \
    --enable-tools \
    $ENABLE_VIRTFS \
    --disable-gtk \
    --disable-opengl \
    --disable-xen \
    --disable-werror

# ==============================
# STEP 6: Optional: Inject CACHE_ALIGN into .h files
# ==============================
if [[ " $@ " =~ " --inject-alignment " ]]; then
    echo " Injecting CACHE_ALIGN into headers..."

    for file in $(find . -name "*.h" -type f); do
        grep -q "CACHE_ALIGN" "$file" && continue
        grep -q "CACHE_LINE" "$file" && continue

        sed -i '1i#define CACHE_LINE 64\n#define CACHE_ALIGN __declspec(align(CACHE_LINE))\n' "$file"
        sed -i -E '/^[[:space:]]*class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*;/! s/^[[:space:]]*class[[:space:]]+/class CACHE_ALIGN /' "$file"
    done

    echo " Alignment injected."
fi

# ==============================
# STEP 7: Build and install
# ==============================
echo " Building QEMU..."
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

if $USE_NASM; then
    make -j"${CPU_CORES}" NASMFLAGS="-f win64 -Ox -Worphan-labels"
else
    make -j"${CPU_CORES}"
fi

echo " Installing to ${PREFIX}..."
make install

# ==============================
# STEP 8: Create archive
# ==============================
cd ..
echo " Creating archive ${ARCHIVE_NAME}..."
tar -czvf "${ARCHIVE_NAME}" -C "${PREFIX}" .

echo " Build completed with success! File: ${ARCHIVE_NAME}"


