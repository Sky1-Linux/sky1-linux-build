#!/bin/bash
# Download kernel tarball and apply Sky1 patches from linux-sky1 repo
set -e

VERSION="${1:-6.18.2}"
WORK_DIR="${2:-build}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# linux-sky1 repo location (sibling directory)
LINUX_SKY1="${LINUX_SKY1:-$(dirname "$SCRIPT_DIR")/linux-sky1}"

if [ ! -d "$LINUX_SKY1/patches" ]; then
    echo "Error: linux-sky1 repo not found at $LINUX_SKY1"
    echo "Set LINUX_SKY1 environment variable or clone linux-sky1 as sibling directory"
    exit 1
fi

echo "=== Preparing Linux ${VERSION} source ==="
echo "Using patches from: $LINUX_SKY1"

mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Download kernel tarball if not present
if [ ! -f "linux-${VERSION}.tar.xz" ]; then
    MAJOR_VER="${VERSION%%.*}"
    echo "Downloading linux-${VERSION}.tar.xz..."
    wget -q --show-progress \
        "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR_VER}.x/linux-${VERSION}.tar.xz"
fi

# Extract fresh source
echo "Extracting source..."
rm -rf "linux-${VERSION}"
tar xf "linux-${VERSION}.tar.xz"
cd "linux-${VERSION}"

# Apply patches from linux-sky1 repo
echo "Applying patches..."
PATCH_COUNT=0
for patch in "$LINUX_SKY1"/patches/*.patch; do
    if [ -f "$patch" ]; then
        echo "  $(basename "$patch")"
        patch -p1 -s < "$patch"
        PATCH_COUNT=$((PATCH_COUNT + 1))
    fi
done

# Save hash of patches for staleness detection
PATCHES_HASH=$(cat "$LINUX_SKY1"/patches/*.patch 2>/dev/null | sha256sum | cut -d' ' -f1)
echo "$PATCHES_HASH" > .patches-hash
echo "Patches hash: ${PATCHES_HASH:0:16}..."

echo ""
echo "=== Source prepared: $WORK_DIR/linux-${VERSION} ==="
echo "Applied $PATCH_COUNT patches"
