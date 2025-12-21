#!/bin/bash
# Build kernel packages using make bindeb-pkg
set -e

VERSION="${1:-6.18.2}"
REVISION="${2:-1}"
VARIANT="${3:-sky1}"           # sky1 or sky1-dev
WORK_DIR="${4:-build}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# linux-sky1 repo location (sibling directory)
LINUX_SKY1="${LINUX_SKY1:-$(dirname "$SCRIPT_DIR")/linux-sky1}"

echo "=== Building linux-${VERSION}-${VARIANT} revision ${REVISION} ==="

# Check source is prepared
if [ ! -d "$WORK_DIR/linux-${VERSION}" ]; then
    echo "Error: Source not found at $WORK_DIR/linux-${VERSION}"
    echo "Run prepare-source.sh first"
    exit 1
fi

cd "$WORK_DIR/linux-${VERSION}"

# Copy config from linux-sky1 repo
CONFIG_FILE="$LINUX_SKY1/config/config.${VARIANT}"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config not found: $CONFIG_FILE"
    echo "Available configs in $LINUX_SKY1/config/:"
    ls "$LINUX_SKY1/config/"*.sky1* 2>/dev/null || echo "  (none found)"
    exit 1
fi
echo "Using config: $CONFIG_FILE"
cp "$CONFIG_FILE" .config

# Create localversion file
echo "-${VARIANT}" > localversion

# Ensure consistent version string
./scripts/config --set-str LOCALVERSION ""
./scripts/config --disable LOCALVERSION_AUTO

# Update config
make ARCH=arm64 olddefconfig

# Set environment for package naming
export LOCALVERSION="-${VARIANT}"
export KDEB_PKGVERSION="${VERSION}-${VARIANT}.${REVISION}"
export KDEB_SOURCENAME="linux-${VARIANT}"
export DEBEMAIL="entrpi@proton.me"
export DEBFULLNAME="Entrpi"

# Build packages (image + headers, no libc-dev)
echo ""
echo "Building packages with:"
echo "  LOCALVERSION=$LOCALVERSION"
echo "  KDEB_PKGVERSION=$KDEB_PKGVERSION"
echo ""

make ARCH=arm64 -j"$(nproc)" bindeb-pkg

# Move packages to work dir root for easier access
mv ../*.deb "$SCRIPT_DIR/$WORK_DIR/" 2>/dev/null || true
mv ../*.buildinfo "$SCRIPT_DIR/$WORK_DIR/" 2>/dev/null || true
mv ../*.changes "$SCRIPT_DIR/$WORK_DIR/" 2>/dev/null || true

# List results
echo ""
echo "=== Generated Packages ==="
ls -lh "$SCRIPT_DIR/$WORK_DIR"/*.deb 2>/dev/null || echo "No .deb files found"

echo ""
echo "=== Package Info ==="
for deb in "$SCRIPT_DIR/$WORK_DIR"/*.deb; do
    if [ -f "$deb" ]; then
        echo "$(basename "$deb"):"
        dpkg-deb -I "$deb" | grep -E "Package:|Version:|Installed-Size:" | sed 's/^/  /'
    fi
done
