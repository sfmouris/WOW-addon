#!/usr/bin/env bash
# Installs QuestKompas into the WoW Forever AddOns folder (macOS, also Linux).
#
#   tools/install.sh            symlink the addon (default, edits are live after /reload)
#   tools/install.sh --copy     copy instead of symlink
#   tools/install.sh --remove   remove the installed addon
#   tools/install.sh --reset    forget the stored AddOns path and ask again
#
# The AddOns path is asked once and stored in .env.local (not in git).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/QuestKompas"
ENV_FILE="$REPO/.env.local"
MODE="link"

for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    --remove) MODE="remove" ;;
    --reset) rm -f "$ENV_FILE" ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "Onbekende optie: $arg" >&2; exit 2 ;;
  esac
done

# Candidate flavor folders. The live Forever client is reported as _forever_,
# the beta used _classic_beta_. [VERIFIEER] which one exists on your Mac.
FLAVORS=("_forever_" "_classic_beta_" "_camelot_")
BASES=("/Applications/World of Warcraft" "$HOME/Applications/World of Warcraft"
       "/Applications/Games/World of Warcraft" "$HOME/Games/World of Warcraft")

detect() {
  local found=()
  for base in "${BASES[@]}"; do
    for flavor in "${FLAVORS[@]}"; do
      if [ -d "$base/$flavor" ]; then found+=("$base/$flavor/Interface/AddOns"); fi
    done
  done
  printf '%s\n' "${found[@]+"${found[@]}"}"
}

ADDONS_DIR=""
if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  ADDONS_DIR="${WOW_ADDONS_DIR:-}"
fi

if [ -z "$ADDONS_DIR" ]; then
  mapfile_compat() { local i=0; while IFS= read -r line; do CANDIDATES[i]="$line"; i=$((i + 1)); done; }
  CANDIDATES=()
  mapfile_compat < <(detect)
  echo "QuestKompas installeren."
  if [ "${#CANDIDATES[@]}" -gt 0 ]; then
    echo "Gevonden WoW-mappen:"
    for i in "${!CANDIDATES[@]}"; do echo "  $((i + 1))) ${CANDIDATES[$i]}"; done
    read -r -p "Kies een nummer, of plak een ander pad naar Interface/AddOns: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#CANDIDATES[@]}" ]; then
      ADDONS_DIR="${CANDIDATES[$((choice - 1))]}"
    else
      ADDONS_DIR="$choice"
    fi
  else
    echo "Geen WoW Forever-map gevonden op de standaardplekken."
    echo "Tip: in de Battle.net-app, kies WoW Forever, tandwiel, 'Show in Finder'."
    read -r -p "Plak het pad naar .../_forever_/Interface/AddOns: " ADDONS_DIR
  fi
  ADDONS_DIR="${ADDONS_DIR%/}"
  ADDONS_DIR="${ADDONS_DIR/#\~/$HOME}"
  case "$ADDONS_DIR" in
    */Interface/AddOns) ;;
    */Interface) ADDONS_DIR="$ADDONS_DIR/AddOns" ;;
    */_*_) ADDONS_DIR="$ADDONS_DIR/Interface/AddOns" ;;
  esac
  printf 'WOW_ADDONS_DIR=%q\n' "$ADDONS_DIR" > "$ENV_FILE"
  echo "Pad bewaard in .env.local"
fi

TARGET="$ADDONS_DIR/QuestKompas"

if [ "$MODE" = "remove" ]; then
  if [ -L "$TARGET" ] || [ -d "$TARGET" ]; then rm -rf "$TARGET"; echo "Verwijderd: $TARGET"; else echo "Niet geinstalleerd."; fi
  exit 0
fi

mkdir -p "$ADDONS_DIR"
if [ -L "$TARGET" ] || [ -e "$TARGET" ]; then
  if [ -L "$TARGET" ]; then rm "$TARGET"; else
    BACKUP="$TARGET.backup.$(date +%Y%m%d%H%M%S)"
    mv "$TARGET" "$BACKUP"
    echo "Bestaande map verplaatst naar $BACKUP"
  fi
fi

if [ "$MODE" = "copy" ]; then
  cp -R "$SRC" "$TARGET"
  echo "Gekopieerd naar $TARGET"
else
  ln -s "$SRC" "$TARGET"
  echo "Symlink gemaakt: $TARGET -> $SRC"
fi

cat <<MSG

Klaar. Volgende stappen in WoW Forever:
  1. Start de client opnieuw (een nieuwe addon of TOC vraagt een volledige herstart).
  2. Controleer het interfacenummer:  /run print(select(4, GetBuildInfo()))   (verwacht 16001)
  3. /qk version   en   /qk help
  4. Zet foutmeldingen aan:  /console scriptErrors 1   (of installeer BugSack + BugGrabber)
Na een wijziging in Lua volstaat /reload.
MSG
