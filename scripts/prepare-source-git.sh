#!/bin/bash
# Prepare kernel source from git (for RC/Next builds)
# Unlike prepare-source.sh which downloads tarballs, this exports from local mainline-linux repo
set -e

REF="${1:-v6.19-rc7}"           # Tag or branch (e.g., v6.19-rc7, origin/master)
VARIANT="${2:-rc}"              # rc or next
WORK_DIR="${3:-build}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Mainline Linux repo location
MAINLINE="${MAINLINE:-$HOME/mainline-linux}"

# linux-sky1 repo location (sibling directory)
LINUX_SKY1="${LINUX_SKY1:-$(dirname "$SCRIPT_DIR")/linux-sky1}"

# Validate mainline-linux repo exists
if [ ! -d "$MAINLINE/.git" ]; then
    echo "Error: mainline-linux repo not found at $MAINLINE"
    echo "Set MAINLINE environment variable or clone to ~/mainline-linux"
    exit 1
fi

# Determine patch directory based on variant
PATCH_DIR="$LINUX_SKY1/patches-${VARIANT}"
if [ ! -d "$PATCH_DIR" ]; then
    echo "Error: Patch directory not found: $PATCH_DIR"
    echo "Expected patches-rc/, patches-latest/, or patches-next/ in linux-sky1 repo"
    exit 1
fi

# Determine version string from ref
cd "$MAINLINE"
if [[ "$REF" =~ ^v([0-9]+\.[0-9]+)-rc([0-9]+)$ ]]; then
    # RC tag: v6.19-rc7 -> 6.19-rc7
    VERSION="${BASH_REMATCH[1]}-rc${BASH_REMATCH[2]}"
elif [[ "$REF" == "master" ]] || [[ "$REF" == "origin/master" ]]; then
    # Master branch: use git describe format
    # e.g., v6.20-rc1-123-gabcdef -> 6.20-rc1-123-gabcdef
    VERSION="$(git describe --always "$REF" 2>/dev/null | sed 's/^v//')"
    if [ -z "$VERSION" ]; then
        echo "Error: Could not determine version from git describe for $REF"
        exit 1
    fi
elif [[ "$REF" =~ ^v([0-9]+\.[0-9]+(\.[0-9]+)?)$ ]]; then
    # Stable tag (fallback): v6.18.7 -> 6.18.7
    VERSION="${BASH_REMATCH[1]}"
else
    # Try git describe for arbitrary refs
    VERSION="$(git describe --always "$REF" 2>/dev/null | sed 's/^v//')"
    if [ -z "$VERSION" ]; then
        echo "Error: Could not determine version from ref: $REF"
        echo "Supported formats: v6.19-rc7, origin/master, v6.18.7"
        exit 1
    fi
fi

# Verify ref exists
if ! git rev-parse --verify "$REF" >/dev/null 2>&1; then
    echo "Error: Ref not found in mainline-linux: $REF"
    echo ""
    echo "To fetch an RC tag:"
    echo "  cd $MAINLINE"
    echo "  git fetch origin tag $REF --no-tags"
    exit 1
fi

echo "=== Preparing Linux ${VERSION} from git ==="
echo "Ref: $REF"
echo "Variant: $VARIANT"
echo "Patches: $PATCH_DIR"
echo ""

mkdir -p "$SCRIPT_DIR/$WORK_DIR"
cd "$SCRIPT_DIR/$WORK_DIR"

# Remove old source if exists
if [ -d "linux-${VERSION}" ]; then
    echo "Removing existing source directory..."
    rm -rf "linux-${VERSION}"
fi

# Export clean source from mainline-linux using git archive
# This is much faster than git checkout and doesn't require worktrees
echo "Exporting source from $MAINLINE ($REF)..."
(cd "$MAINLINE" && git archive --prefix="linux-${VERSION}/" "$REF") | tar x

cd "linux-${VERSION}"

# Apply patches from variant-specific directory
echo "Applying patches from $PATCH_DIR..."
PATCH_COUNT=0
PATCH_FAILED=0
for patch in "$PATCH_DIR"/*.patch; do
    if [ -f "$patch" ]; then
        patchname=$(basename "$patch")
        if patch -p1 -s --dry-run < "$patch" >/dev/null 2>&1; then
            echo "  $patchname"
            patch -p1 -s < "$patch"
            PATCH_COUNT=$((PATCH_COUNT + 1))
        else
            echo "  $patchname [FAILED]"
            PATCH_FAILED=$((PATCH_FAILED + 1))
        fi
    fi
done

if [ $PATCH_FAILED -gt 0 ]; then
    echo ""
    echo "WARNING: $PATCH_FAILED patch(es) failed to apply!"
    echo "The patches may need to be updated for $REF"
    echo ""
    echo "To fix:"
    echo "  1. cd $MAINLINE"
    echo "  2. git checkout $VARIANT  # or create branch if needed"
    echo "  3. git rebase --onto $REF <old-base>"
    echo "  4. Re-export patches to $PATCH_DIR"
fi

# Save hash of patches for staleness detection (same as tarball script)
PATCHES_HASH=$(cat "$PATCH_DIR"/*.patch 2>/dev/null | sha256sum | cut -d' ' -f1)
echo "$PATCHES_HASH" > .patches-hash
echo "Patches hash: ${PATCHES_HASH:0:16}..."

# Save ref for reference
echo "$REF" > .git-ref

echo ""
echo "=== Source prepared: $SCRIPT_DIR/$WORK_DIR/linux-${VERSION} ==="
echo "Applied $PATCH_COUNT patches"
if [ $PATCH_FAILED -gt 0 ]; then
    echo "Failed: $PATCH_FAILED patches (see above)"
    exit 1
fi
