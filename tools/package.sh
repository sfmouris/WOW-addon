#!/usr/bin/env bash
# Builds dist/QuestKompas-<version>.zip: the addon folder plus the
# double-click Mac installer and a short Dutch readme.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^## Version: *//p' "$REPO/QuestKompas/QuestKompas.toc" | tr -d '\r')"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$REPO/dist" "$STAGE/QuestKompas-$VERSION"
cp -R "$REPO/QuestKompas" "$STAGE/QuestKompas-$VERSION/"
cp "$REPO/tools/mac/Installeer QuestKompas.command" "$REPO/tools/mac/LEESMIJ.txt" "$STAGE/QuestKompas-$VERSION/"
chmod +x "$STAGE/QuestKompas-$VERSION/Installeer QuestKompas.command"
OUT="$REPO/dist/QuestKompas-$VERSION.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -qr "$OUT" "QuestKompas-$VERSION" -x '*.DS_Store')
echo "$OUT"
