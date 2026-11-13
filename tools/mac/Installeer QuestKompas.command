#!/bin/bash
# Dubbelklik-installer voor QuestKompas op de Mac.
# Kopieert de map QuestKompas (naast dit bestand) naar de AddOns-map van WoW Forever.
cd "$(dirname "$0")" || exit 1
SRC="$(pwd)/QuestKompas"

say_done() { echo; read -r -p "Druk op Enter om dit venster te sluiten. " _; exit "${1:-0}"; }

if [ ! -f "$SRC/QuestKompas.toc" ]; then
  echo "De map QuestKompas staat niet naast dit bestand. Pak de zip eerst helemaal uit."
  say_done 1
fi

# Bekende plekken. _forever_ is de live client, _classic_beta_ was de beta.
ADDONS=""
for base in "/Applications/World of Warcraft" "$HOME/Applications/World of Warcraft" "/Applications/Games/World of Warcraft"; do
  for flavor in _forever_ _classic_beta_ _camelot_; do
    if [ -z "$ADDONS" ] && [ -d "$base/$flavor" ]; then ADDONS="$base/$flavor/Interface/AddOns"; fi
  done
done

if [ -z "$ADDONS" ]; then
  echo "WoW Forever niet gevonden op de standaardplek. Kies de map _forever_ in het venster."
  if command -v osascript >/dev/null 2>&1; then
    PICK="$(osascript -e 'POSIX path of (choose folder with prompt "Kies de map _forever_ van World of Warcraft")' 2>/dev/null)"
  else
    read -r -p "Pad naar de map _forever_: " PICK
  fi
  PICK="${PICK%/}"
  [ -z "$PICK" ] && { echo "Geannuleerd."; say_done 1; }
  case "$PICK" in
    */Interface/AddOns) ADDONS="$PICK" ;;
    */Interface) ADDONS="$PICK/AddOns" ;;
    *) ADDONS="$PICK/Interface/AddOns" ;;
  esac
fi

mkdir -p "$ADDONS" || { echo "Kan $ADDONS niet aanmaken."; say_done 1; }
TARGET="$ADDONS/QuestKompas"
if [ -L "$TARGET" ]; then
  rm "$TARGET"
elif [ -d "$TARGET" ]; then
  rm -rf "$TARGET.vorige"
  mv "$TARGET" "$TARGET.vorige"
  echo "Oude versie bewaard als QuestKompas.vorige"
fi
cp -R "$SRC" "$TARGET" || { echo "Kopiëren mislukt."; say_done 1; }
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null

echo "QuestKompas is geinstalleerd in:"
echo "  $TARGET"
echo
echo "Start WoW Forever opnieuw en typ in de chat:  /qk version"
say_done 0
