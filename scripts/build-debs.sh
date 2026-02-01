#!/bin/bash
# Build kernel packages using make bindeb-pkg
set -e

VERSION="${1:-6.18.2}"
REVISION="${2:-1}"
VARIANT="${3:-sky1}"           # sky1, sky1-rc, sky1-next, or sky1-dev
WORK_DIR="${4:-build}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# linux-sky1 repo location (sibling directory)
LINUX_SKY1="${LINUX_SKY1:-$(dirname "$SCRIPT_DIR")/linux-sky1}"

# Determine patch directory based on variant
# sky1-rc uses patches-rc/, sky1-next uses patches-next/, others use patches/
case "$VARIANT" in
    sky1-rc)     PATCH_DIR="$LINUX_SKY1/patches-rc" ;;
    sky1-latest) PATCH_DIR="$LINUX_SKY1/patches-latest" ;;
    sky1-next)   PATCH_DIR="$LINUX_SKY1/patches-next" ;;
    *)           PATCH_DIR="$LINUX_SKY1/patches" ;;
esac

echo "=== Building linux-${VERSION}-${VARIANT} revision ${REVISION} ==="

# Check source is prepared
if [ ! -d "$WORK_DIR/linux-${VERSION}" ]; then
    echo "Error: Source not found at $WORK_DIR/linux-${VERSION}"
    if [[ "$VARIANT" == "sky1-rc" ]] || [[ "$VARIANT" == "sky1-latest" ]] || [[ "$VARIANT" == "sky1-next" ]]; then
        echo "Run prepare-source-git.sh first (for RC/Next builds)"
    else
        echo "Run prepare-source.sh first"
    fi
    exit 1
fi

cd "$WORK_DIR/linux-${VERSION}"

# Check if patches are stale
if [ ! -f .patches-hash ]; then
    echo "Error: No .patches-hash found - source was prepared without hash tracking"
    echo ""
    echo "Run these commands to rebuild with fresh source:"
    if [[ "$VARIANT" == "sky1-rc" ]] || [[ "$VARIANT" == "sky1-latest" ]] || [[ "$VARIANT" == "sky1-next" ]]; then
        echo "  rm -rf $WORK_DIR/linux-${VERSION}"
        echo "  ./scripts/prepare-source-git.sh <ref> ${VARIANT#sky1-}"
        echo "  ./scripts/build-debs.sh ${VERSION} ${REVISION} ${VARIANT}"
    else
        echo "  rm -rf $WORK_DIR/linux-${VERSION}"
        echo "  ./scripts/prepare-source.sh ${VERSION}"
        echo "  ./scripts/build-debs.sh ${VERSION} ${REVISION}"
    fi
    exit 1
fi

SAVED_HASH=$(cat .patches-hash)
CURRENT_HASH=$(cat "$PATCH_DIR"/*.patch 2>/dev/null | sha256sum | cut -d' ' -f1)
if [ "$SAVED_HASH" != "$CURRENT_HASH" ]; then
    echo "Error: Patches have changed since source was prepared!"
    echo "  Saved hash:   ${SAVED_HASH:0:16}..."
    echo "  Current hash: ${CURRENT_HASH:0:16}..."
    echo "  Patch dir:    $PATCH_DIR"
    echo ""
    echo "Run these commands to rebuild with updated patches:"
    if [[ "$VARIANT" == "sky1-rc" ]] || [[ "$VARIANT" == "sky1-latest" ]] || [[ "$VARIANT" == "sky1-next" ]]; then
        echo "  rm -rf $WORK_DIR/linux-${VERSION}"
        echo "  ./scripts/prepare-source-git.sh <ref> ${VARIANT#sky1-}"
        echo "  ./scripts/build-debs.sh ${VERSION} ${REVISION} ${VARIANT}"
    else
        echo "  rm -rf $WORK_DIR/linux-${VERSION}"
        echo "  ./scripts/prepare-source.sh ${VERSION}"
        echo "  ./scripts/build-debs.sh ${VERSION} ${REVISION}"
    fi
    exit 1
fi

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

# Remove any localversion files (we use LOCALVERSION env var instead)
rm -f localversion*

# Ensure consistent version string (no config-based suffix)
./scripts/config --set-str LOCALVERSION ""
./scripts/config --disable LOCALVERSION_AUTO

# Update config
make ARCH=arm64 olddefconfig

# Set environment for package naming
# Package name includes kernel version (e.g., linux-image-6.18.2-sky1)
# Version is just the revision number to avoid redundancy in filenames
export LOCALVERSION="-${VARIANT}"
export KDEB_PKGVERSION="${REVISION}"
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

# Fix headers package: remove /lib/modules dir and add postinst for build symlink
# This prevents conflicts with linux-image which owns /lib/modules/<version>/
fix_headers_package() {
    local headers_deb="$1"
    local kernel_ver="$2"

    [ -f "$headers_deb" ] || return 0

    echo ""
    echo "=== Fixing headers package ==="

    local tmpdir=$(mktemp -d)
    local pkg_name=$(dpkg-deb -f "$headers_deb" Package)
    local pkg_version=$(dpkg-deb -f "$headers_deb" Version)

    # Extract package
    dpkg-deb -R "$headers_deb" "$tmpdir"

    # Remove /lib/modules directory (image package owns this)
    if [ -d "$tmpdir/lib/modules" ]; then
        echo "  Removing /lib/modules from headers package"
        rm -rf "$tmpdir/lib/modules"
        rm -rf "$tmpdir/lib" 2>/dev/null || true
    fi

    # Add dependency on the image package and postinst script
    local image_pkg="linux-image-${kernel_ver}"

    # Update control file with dependency
    if ! grep -q "^Depends:" "$tmpdir/DEBIAN/control"; then
        echo "Depends: ${image_pkg} (= ${pkg_version})" >> "$tmpdir/DEBIAN/control"
    fi

    # Create postinst to make build symlink
    cat > "$tmpdir/DEBIAN/postinst" << 'POSTINST'
#!/bin/sh
set -e

KERNEL_VERSION="__KERNEL_VERSION__"
HEADERS_DIR="/usr/src/linux-headers-${KERNEL_VERSION}"
MODULES_DIR="/lib/modules/${KERNEL_VERSION}"

if [ "$1" = "configure" ]; then
    # Create build symlink in modules directory
    if [ -d "$MODULES_DIR" ] && [ -d "$HEADERS_DIR" ]; then
        ln -sf "$HEADERS_DIR" "$MODULES_DIR/build"
    fi
fi

exit 0
POSTINST
    sed -i "s/__KERNEL_VERSION__/${kernel_ver}/" "$tmpdir/DEBIAN/postinst"
    chmod 755 "$tmpdir/DEBIAN/postinst"

    # Create prerm to remove build symlink
    cat > "$tmpdir/DEBIAN/prerm" << 'PRERM'
#!/bin/sh
set -e

KERNEL_VERSION="__KERNEL_VERSION__"
MODULES_DIR="/lib/modules/${KERNEL_VERSION}"

if [ "$1" = "remove" ] || [ "$1" = "upgrade" ]; then
    rm -f "$MODULES_DIR/build" 2>/dev/null || true
fi

exit 0
PRERM
    sed -i "s/__KERNEL_VERSION__/${kernel_ver}/" "$tmpdir/DEBIAN/prerm"
    chmod 755 "$tmpdir/DEBIAN/prerm"

    # Rebuild package
    dpkg-deb -b "$tmpdir" "$headers_deb"

    rm -rf "$tmpdir"
    echo "  Headers package fixed: $headers_deb"
}

# Add Provides field to image package for stable package name
# e.g., linux-image-6.18.2-sky1 provides linux-image-6.18-sky1
fix_image_package() {
    local image_deb="$1"
    local stable_name="$2"

    [ -f "$image_deb" ] || return 0

    echo ""
    echo "=== Adding Provides to image package ==="

    local tmpdir=$(mktemp -d)

    # Extract package
    dpkg-deb -R "$image_deb" "$tmpdir"

    # Add Provides field if not present
    if ! grep -q "^Provides:" "$tmpdir/DEBIAN/control"; then
        # Insert Provides after Architecture line
        sed -i "/^Architecture:/a Provides: ${stable_name}" "$tmpdir/DEBIAN/control"
        echo "  Added Provides: ${stable_name}"
    fi

    # Rebuild package
    dpkg-deb -b "$tmpdir" "$image_deb"

    rm -rf "$tmpdir"
    echo "  Image package fixed: $image_deb"
}

# Determine kernel version string from actual build output
# The kernel uses VERSION.PATCHLEVEL.SUBLEVEL from its Makefile (e.g., 6.19.0-rc7),
# which may differ from the user-supplied version (e.g., 6.19-rc7 omits .0 sublevel).
KERN_RELEASE=$(make -s ARCH=arm64 kernelrelease LOCALVERSION="-${VARIANT}")
KERNEL_VER="$KERN_RELEASE"

# Extract major.minor for stable package name
# 6.18.2-sky1 -> 6.18, 6.19.0-rc7-sky1-rc -> 6.19
KVER_BASE=$(make -s ARCH=arm64 kernelversion)
MAJOR_MINOR=$(echo "$KVER_BASE" | sed 's/-rc.*//' | cut -d. -f1,2)

# Fix image package - add Provides for stable name
IMAGE_PKG="$SCRIPT_DIR/$WORK_DIR/linux-image-${KERNEL_VER}_${KDEB_PKGVERSION}_arm64.deb"
fix_image_package "$IMAGE_PKG" "linux-image-${MAJOR_MINOR}-${VARIANT}"

# Fix headers package
HEADERS_PKG="$SCRIPT_DIR/$WORK_DIR/linux-headers-${KERNEL_VER}_${KDEB_PKGVERSION}_arm64.deb"
fix_headers_package "$HEADERS_PKG" "$KERNEL_VER"

# Also add Provides to headers package
fix_image_package "$HEADERS_PKG" "linux-headers-${MAJOR_MINOR}-${VARIANT}"
mv ../*.buildinfo "$SCRIPT_DIR/$WORK_DIR/" 2>/dev/null || true
mv ../*.changes "$SCRIPT_DIR/$WORK_DIR/" 2>/dev/null || true

# Build meta packages (linux-image-sky1, linux-headers-sky1, linux-sky1)
# Only for stable variant (not rc/next/dev)
if [ "$VARIANT" = "sky1" ]; then
    echo ""
    "$SCRIPT_DIR/scripts/build-meta.sh" "$VERSION" "$REVISION"
fi

# List results
echo ""
echo "=== Generated Packages ==="
ls -lh "$SCRIPT_DIR/$WORK_DIR"/*.deb 2>/dev/null || echo "No .deb files found"

echo ""
echo "=== Package Info ==="
for deb in "$SCRIPT_DIR/$WORK_DIR"/*.deb; do
    if [ -f "$deb" ]; then
        echo "$(basename "$deb"):"
        dpkg-deb -I "$deb" | grep -E "Package:|Version:|Provides:|Installed-Size:" | sed 's/^/  /'
    fi
done
