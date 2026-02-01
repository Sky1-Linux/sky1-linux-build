#!/bin/bash
# Build linux-sky1 meta packages
# These provide stable package names that depend on specific kernel versions
set -e

VERSION="${1:-6.18.7}"
REVISION="${2:-1}"
VARIANT="${3:-sky1}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
META_DIR="$SCRIPT_DIR/meta"
BUILD_DIR="$SCRIPT_DIR/build"

# Derive suffix from variant: sky1 -> "", sky1-rc -> "-rc", sky1-latest -> "-latest"
if [ "$VARIANT" = "sky1" ]; then
    SUFFIX=""
    SUFFIX_DESC=""
else
    SUFFIX="${VARIANT#sky1}"   # e.g. "-rc", "-latest", "-next"
    SUFFIX_DESC=" (${SUFFIX#-})"  # e.g. " (rc)", " (latest)"
fi

# Meta package version matches kernel version
META_VERSION="${VERSION}"

echo "=== Building linux-sky1${SUFFIX}-meta packages ==="
echo "Kernel version: ${VERSION}-${VARIANT}"
echo "Kernel revision: ${REVISION}"
echo "Meta version: ${META_VERSION}"
echo "Suffix: '${SUFFIX}'"
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"

# Create temporary build directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Copy meta package source
cp -r "$META_DIR/debian" "$TMPDIR/"
chmod 755 "$TMPDIR/debian/rules"

# Generate control file from template
DATE=$(date -R)
sed -e "s/__VERSION__/${VERSION}/g" \
    -e "s/__REVISION__/${REVISION}/g" \
    -e "s/__META_VERSION__/${META_VERSION}/g" \
    -e "s/__SUFFIX__/${SUFFIX}/g" \
    -e "s/__SUFFIX_DESC__/${SUFFIX_DESC}/g" \
    "$META_DIR/debian/control.template" > "$TMPDIR/debian/control"

# Generate changelog from template
sed -e "s/__VERSION__/${VERSION}/g" \
    -e "s/__META_VERSION__/${META_VERSION}/g" \
    -e "s/__DATE__/${DATE}/g" \
    -e "s/__SUFFIX__/${SUFFIX}/g" \
    "$META_DIR/debian/changelog.template" > "$TMPDIR/debian/changelog"

echo "Generated control:"
cat "$TMPDIR/debian/control"
echo ""

# Build packages
cd "$TMPDIR"
dpkg-buildpackage -us -uc -b

# Move packages to build directory
mv ../*.deb "$BUILD_DIR/"

echo ""
echo "=== Meta Packages Built ==="
ls -lh "$BUILD_DIR"/linux-*-sky1${SUFFIX}_*.deb 2>/dev/null | grep -v "image-${VERSION}" | grep -v "headers-${VERSION}" || true
ls -lh "$BUILD_DIR"/linux-sky1${SUFFIX}_*.deb 2>/dev/null || true

echo ""
echo "Package info:"
for pkg in linux-image-sky1${SUFFIX} linux-headers-sky1${SUFFIX} linux-sky1${SUFFIX}; do
    deb="$BUILD_DIR/${pkg}_${META_VERSION}_arm64.deb"
    if [ -f "$deb" ]; then
        echo "$pkg:"
        dpkg-deb -I "$deb" | grep -E "Package:|Version:|Depends:" | sed 's/^/  /'
    fi
done
