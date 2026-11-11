#!/usr/bin/env bash
# Builds dist/QuestKompas-<version>.zip with only the addon folder.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^## Version: *//p' "$REPO/QuestKompas/QuestKompas.toc" | tr -d '\r')"
mkdir -p "$REPO/dist"
OUT="$REPO/dist/QuestKompas-$VERSION.zip"
rm -f "$OUT"
cd "$REPO"
zip -qr "$OUT" QuestKompas -x '*.DS_Store' -x '*/.git*'
echo "$OUT"
