#!/bin/bash
# Export patches from mainline-linux working tree to linux-sky1 repo
#
# Usage: ./export-patches.sh [mainline-path]
#
# Detects the current branch to choose the output directory:
#   main/latest → patches/     rc → patches-rc/     next → patches-next/
set -e

MAINLINE="${1:-$HOME/mainline-linux}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LINUX_SKY1="${LINUX_SKY1:-$(dirname "$SCRIPT_DIR")/linux-sky1}"

echo "=== Exporting patches from $MAINLINE ==="

if [ ! -d "$MAINLINE/.git" ]; then
    echo "Error: Not a git repo: $MAINLINE"
    exit 1
fi

if [ ! -d "$LINUX_SKY1" ]; then
    echo "Error: linux-sky1 repo not found at $LINUX_SKY1"
    exit 1
fi

cd "$MAINLINE"

# Determine output directory from current branch
BRANCH=$(git branch --show-current)
case "$BRANCH" in
    main)        OUTPUT="$LINUX_SKY1/patches" ;;
    latest)      OUTPUT="$LINUX_SKY1/patches-latest" ;;
    rc)          OUTPUT="$LINUX_SKY1/patches-rc" ;;
    next)        OUTPUT="$LINUX_SKY1/patches-next" ;;
    *)
        echo "Error: Unknown branch '$BRANCH'. Expected main, latest, rc, or next."
        exit 1
        ;;
esac

echo "Branch: $BRANCH"

# Get the upstream tag to diff against
UPSTREAM_TAG=$(git describe --abbrev=0 --tags HEAD 2>/dev/null || echo "")
if [ -z "$UPSTREAM_TAG" ]; then
    echo "Error: Cannot find upstream tag"
    echo "Make sure the mainline-linux repo has upstream tags (e.g., v6.18.2)"
    exit 1
fi

echo "Upstream tag: $UPSTREAM_TAG"
echo "Output dir: $OUTPUT"

# Count commits
COMMIT_COUNT=$(git rev-list "$UPSTREAM_TAG"..HEAD | wc -l)
echo "Commits to export: $COMMIT_COUNT"

if [ "$COMMIT_COUNT" -eq 0 ]; then
    echo "No commits to export (HEAD is at $UPSTREAM_TAG)"
    exit 0
fi

# Backup old patches
if [ -d "$OUTPUT" ] && [ "$(ls -A "$OUTPUT"/*.patch 2>/dev/null)" ]; then
    BACKUP="$OUTPUT.backup.$(date +%Y%m%d-%H%M%S)"
    echo "Backing up old patches to: $BACKUP"
    mv "$OUTPUT" "$BACKUP"
    mkdir -p "$OUTPUT"
fi

# Export patches
echo ""
echo "Exporting patches..."
git format-patch -o "$OUTPUT" "$UPSTREAM_TAG"..HEAD

# Create series file (for quilt compatibility)
echo ""
echo "Creating series file..."
ls "$OUTPUT"/*.patch 2>/dev/null | xargs -n1 basename > "$OUTPUT/series"

# Summary
EXPORTED=$(ls "$OUTPUT"/*.patch 2>/dev/null | wc -l)
echo ""
echo "=== Exported $EXPORTED patches to $OUTPUT ==="
echo ""
echo "First 5 patches:"
ls "$OUTPUT"/*.patch 2>/dev/null | head -5 | xargs -n1 basename | sed 's/^/  /'
echo "..."
echo ""
echo "Last 3 patches:"
ls "$OUTPUT"/*.patch 2>/dev/null | tail -3 | xargs -n1 basename | sed 's/^/  /'
