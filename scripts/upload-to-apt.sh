#!/bin/bash
# Upload packages to apt repository
#
# Kernel packages:
#   ./scripts/upload-to-apt.sh <work_dir> <apt_repo> <dist> <component> [version]
#
# Arbitrary packages (firmware, drivers, etc.):
#   ./scripts/upload-to-apt.sh --package <apt_repo> <dist> <component> <deb>...
#
# When version is given for kernel uploads, only debs matching that version are
# uploaded. This prevents uploading stale debs from earlier builds that accumulate
# in the work directory.
set -e

# --- Package mode: upload arbitrary .deb files ---
if [ "$1" = "--package" ]; then
    shift
    APT_REPO="${1:?Usage: upload-to-apt.sh --package <apt_repo> <dist> <component> <deb>...}"
    DIST="${2:?Missing dist}"
    COMPONENT="${3:?Missing component}"
    shift 3

    if [ $# -eq 0 ]; then
        echo "Error: No .deb files specified"
        exit 1
    fi

    if [ ! -d "$APT_REPO" ]; then
        echo "Error: APT repo not found at $APT_REPO"
        exit 1
    fi

    cd "$APT_REPO"

    echo "=== Uploading packages to apt repository ==="
    echo "Target: $APT_REPO ($DIST/$COMPONENT)"
    echo ""

    for deb in "$@"; do
        if [ ! -f "$deb" ]; then
            echo "Error: File not found: $deb"
            exit 1
        fi
        pkg=$(dpkg-deb -f "$deb" Package)
        echo "  Removing old: $pkg"
        reprepro -C "$COMPONENT" remove "$DIST" "$pkg" 2>/dev/null || true
        echo "  Adding: $(basename "$deb")"
        reprepro -C "$COMPONENT" includedeb "$DIST" "$deb"
    done

    echo ""
    echo "=== Repository updated ==="
    echo ""
    echo "Packages in $DIST/$COMPONENT:"
    reprepro -C "$COMPONENT" list "$DIST" | head -20
    exit 0
fi

# --- Kernel mode ---
WORK_DIR="${1:-build}"
APT_REPO="${2:-$HOME/sky1-linux-distro/apt-repo}"
DIST="${3:-sid}"
COMPONENT="${4:-main}"          # main, rc, latest, or next
VERSION="$5"                    # optional: only upload debs for this kernel version
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Uploading kernel packages to apt repository ==="
echo "Source: $SCRIPT_DIR/$WORK_DIR/*.deb"
echo "Target: $APT_REPO ($DIST/$COMPONENT)"
if [ -n "$VERSION" ]; then
    echo "Filter: version $VERSION only"
fi

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
# Patterns use [._]* after VARIANT to match both old-style (direct _) and
# new-style (.rN_) package names from revision-aware LOCALVERSION.
#   linux-*-${VARIANT}[._]*       — versioned packages (linux-image-6.19.0-rc8-sky1-rc.r6_...)
#   linux-${VARIANT}_*.deb        — top-level meta package (linux-sky1_6.18.7_...)
#   linux-image-${VARIANT}_*.deb  — image meta package
#   linux-headers-${VARIANT}_*.deb — headers meta package
DEBS=$(ls "$SCRIPT_DIR/$WORK_DIR"/linux-*-"${VARIANT}"[._]*arm64.deb \
          "$SCRIPT_DIR/$WORK_DIR"/linux-"${VARIANT}"_*.deb \
          "$SCRIPT_DIR/$WORK_DIR"/linux-image-"${VARIANT}"_*.deb \
          "$SCRIPT_DIR/$WORK_DIR"/linux-headers-"${VARIANT}"_*.deb \
          2>/dev/null | grep -v linux-libc-dev | sort -u || true)

# Filter to only debs matching the requested version
if [ -n "$VERSION" ]; then
    FILTERED=""
    for deb in $DEBS; do
        fname=$(basename "$deb")
        # Match: version appears in the filename (versioned pkgs have it in name,
        # meta pkgs have it in version field — both contain it in the filename)
        if echo "$fname" | grep -q "$VERSION"; then
            FILTERED="$FILTERED $deb"
        fi
    done
    DEBS=$(echo "$FILTERED" | xargs)

    if [ -z "$DEBS" ]; then
        echo ""
        echo "Error: No packages matching version '$VERSION' for variant '${VARIANT}'"
        echo ""
        echo "Available debs for ${VARIANT}:"
        ls "$SCRIPT_DIR/$WORK_DIR"/linux-*"${VARIANT}"*.deb 2>/dev/null \
            | xargs -I{} basename {} | grep -v linux-libc-dev || echo "  (none)"
        exit 1
    fi
fi

if [ -z "$DEBS" ]; then
    echo "Error: No packages found for variant '${VARIANT}' in $SCRIPT_DIR/$WORK_DIR/"
    echo ""
    echo "Available debs:"
    ls "$SCRIPT_DIR/$WORK_DIR"/linux-*.deb 2>/dev/null | xargs -I{} basename {} || echo "  (none)"
    exit 1
fi

# Warn if uploading debs from multiple kernel versions (likely stale build dir)
if [ -z "$VERSION" ]; then
    VERSIONS_FOUND=$(for deb in $DEBS; do
        dpkg-deb -f "$deb" Package
    done | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?-?(rc[0-9]+)?' | sort -Vu)
    NUM_VERSIONS=$(echo "$VERSIONS_FOUND" | wc -l)
    if [ "$NUM_VERSIONS" -gt 1 ]; then
        echo ""
        echo "WARNING: Build directory contains debs from $NUM_VERSIONS kernel versions:"
        echo "$VERSIONS_FOUND" | sed 's/^/  /'
        echo ""
        echo "This will upload ALL of them. To upload only one version, pass it as arg 5:"
        echo "  $0 $WORK_DIR $APT_REPO $DIST $COMPONENT <version>"
        echo ""
        echo "Continuing in 5 seconds (Ctrl-C to abort)..."
        sleep 5
    fi
fi

# Check for version downgrade — warn if uploading a lower revision than what's in the repo
REPO_VER=$(reprepro -C "$COMPONENT" list "$DIST" 2>/dev/null \
    | grep "linux-image-sky1" | grep -v dbg | head -1 \
    | awk '{print $NF}' || echo "")
if [ -n "$REPO_VER" ]; then
    # Extract revision from repo version (e.g., "6.19.0-rc8-6" -> "6")
    REPO_REV=$(echo "$REPO_VER" | grep -oE '[0-9]+$')
    # Extract highest revision from debs being uploaded
    UPLOAD_REV=0
    for deb in $DEBS; do
        fname=$(basename "$deb")
        REV=$(echo "$fname" | sed -n 's/.*_\([0-9]\+\)_arm64\.deb$/\1/p')
        if [ -n "$REV" ] && [ "$REV" -gt "$UPLOAD_REV" ] 2>/dev/null; then
            UPLOAD_REV="$REV"
        fi
    done
    if [ -n "$REPO_REV" ] && [ "$UPLOAD_REV" -lt "$REPO_REV" ] 2>/dev/null; then
        echo ""
        echo "ERROR: Uploading revision $UPLOAD_REV but repo has revision $REPO_REV"
        echo "This would be a downgrade. Use a higher revision number."
        echo "  Current repo: $REPO_VER"
        exit 1
    fi
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
