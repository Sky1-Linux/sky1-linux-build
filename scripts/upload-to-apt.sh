#!/bin/bash
# Upload kernel packages to apt repository
set -e

WORK_DIR="${1:-build}"
APT_REPO="${2:-$HOME/sky1-linux-distro/apt-repo}"
DIST="${3:-sid}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Uploading packages to apt repository ==="
echo "Source: $SCRIPT_DIR/$WORK_DIR/*.deb"
echo "Target: $APT_REPO ($DIST)"

if [ ! -d "$APT_REPO" ]; then
    echo "Error: APT repo not found at $APT_REPO"
    exit 1
fi

cd "$APT_REPO"

# Find kernel packages to upload (exclude linux-libc-dev - use Debian's)
DEBS=$(ls "$SCRIPT_DIR/$WORK_DIR"/linux-*.deb 2>/dev/null | grep -v linux-libc-dev)
if [ -z "$DEBS" ]; then
    echo "Error: No linux-*.deb files found in $SCRIPT_DIR/$WORK_DIR/"
    exit 1
fi

# Remove old versions of same packages
echo ""
echo "Removing old package versions..."
for deb in $DEBS; do
    pkg=$(dpkg-deb -f "$deb" Package)
    echo "  Removing old: $pkg"
    reprepro remove "$DIST" "$pkg" 2>/dev/null || true
done

# Add new packages
echo ""
echo "Adding new packages..."
for deb in $DEBS; do
    echo "  Adding: $(basename "$deb")"
    reprepro includedeb "$DIST" "$deb"
done

echo ""
echo "=== Repository updated ==="
echo ""
echo "Kernel packages in $DIST:"
reprepro list "$DIST" | grep -E "^$DIST\|.*\|.*linux-" || echo "(none)"
