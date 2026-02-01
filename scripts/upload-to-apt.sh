#!/bin/bash
# Upload kernel packages to apt repository
set -e

WORK_DIR="${1:-build}"
APT_REPO="${2:-$HOME/sky1-linux-distro/apt-repo}"
DIST="${3:-sid}"
COMPONENT="${4:-main}"          # main, rc, or next
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Uploading packages to apt repository ==="
echo "Source: $SCRIPT_DIR/$WORK_DIR/*.deb"
echo "Target: $APT_REPO ($DIST/$COMPONENT)"

if [ ! -d "$APT_REPO" ]; then
    echo "Error: APT repo not found at $APT_REPO"
    exit 1
fi

cd "$APT_REPO"

# Determine variant name from component
# main -> sky1, rc -> sky1-rc, latest -> sky1-latest, next -> sky1-next
case "$COMPONENT" in
    main) VARIANT="sky1" ;;
    *)    VARIANT="sky1-${COMPONENT}" ;;
esac

# Find kernel packages matching this variant (exclude linux-libc-dev - use Debian's)
# Patterns:
#   linux-*-${VARIANT}_*.deb       — versioned packages (linux-image-6.19.0-rc7-sky1-rc_1_...)
#   linux-*-${VARIANT}-dbg_*.deb   — debug packages
#   linux-${VARIANT}_*.deb         — top-level meta package (linux-sky1_6.18.7_...)
#   linux-image-${VARIANT}_*.deb   — image meta package
#   linux-headers-${VARIANT}_*.deb — headers meta package
DEBS=$(ls "$SCRIPT_DIR/$WORK_DIR"/linux-*-"${VARIANT}"_*.deb \
          "$SCRIPT_DIR/$WORK_DIR"/linux-*-"${VARIANT}"-dbg_*.deb \
          "$SCRIPT_DIR/$WORK_DIR"/linux-"${VARIANT}"_*.deb \
          "$SCRIPT_DIR/$WORK_DIR"/linux-image-"${VARIANT}"_*.deb \
          "$SCRIPT_DIR/$WORK_DIR"/linux-headers-"${VARIANT}"_*.deb \
          2>/dev/null | grep -v linux-libc-dev | sort -u || true)

if [ -z "$DEBS" ]; then
    echo "Error: No packages found for variant '${VARIANT}' in $SCRIPT_DIR/$WORK_DIR/"
    echo ""
    echo "Available debs:"
    ls "$SCRIPT_DIR/$WORK_DIR"/linux-*.deb 2>/dev/null | xargs -I{} basename {} || echo "  (none)"
    exit 1
fi

# Remove old versions of same packages from this component
echo ""
echo "Removing old package versions from $COMPONENT..."
for deb in $DEBS; do
    pkg=$(dpkg-deb -f "$deb" Package)
    echo "  Removing old: $pkg"
    reprepro -C "$COMPONENT" remove "$DIST" "$pkg" 2>/dev/null || true
done

# Add new packages to specified component
echo ""
echo "Adding new packages to $COMPONENT..."
for deb in $DEBS; do
    echo "  Adding: $(basename "$deb")"
    reprepro -C "$COMPONENT" includedeb "$DIST" "$deb"
done

echo ""
echo "=== Repository updated ==="
echo ""
echo "Kernel packages in $DIST/$COMPONENT:"
reprepro -C "$COMPONENT" list "$DIST" | grep -E "^$DIST\|.*\|.*linux-" || echo "(none)"
