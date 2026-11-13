#!/usr/bin/env bash
# Fetches the exported Blizzard interface code for WoW Forever (spec 12.2)
# next to the repo, for grepping API signatures. Mirror: Gethe/wow-ui-source,
# branch "forever" (1.60.1 build 70888 at the time of writing).
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$REPO/../wow-ui-source-forever}"
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only
else
  git clone --depth 1 --single-branch -b forever https://github.com/Gethe/wow-ui-source "$DEST"
fi
cat "$DEST/version.txt" 2>/dev/null || true
echo "Export in: $DEST/Interface/AddOns/Blizzard_APIDocumentationGenerated"
