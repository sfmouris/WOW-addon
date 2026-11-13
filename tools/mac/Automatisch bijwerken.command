#!/bin/bash
# Double-click setup for automatic QuestKompas updates on the Mac.
# Installs a launchd agent that runs update-runner.sh at login and every
# four hours. Run with --remove (or use "Automatisch bijwerken uitzetten")
# to switch it off again.
LABEL="nl.questkompas.autoupdate"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
STATE_DIR="$HOME/Library/Application Support/QuestKompas"
RUNNER="$STATE_DIR/update-runner.sh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/QuestKompas-update.log"

say_done() { echo; read -r -p "Druk op Enter om dit venster te sluiten. " _; exit "${1:-0}"; }

unload() {
  launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || launchctl unload "$PLIST" >/dev/null 2>&1 || true
}

if [ "$1" = "--remove" ]; then
  unload
  rm -f "$PLIST" "$RUNNER"
  echo "Automatisch bijwerken staat uit. De addon zelf blijft staan."
  say_done 0
fi

echo "QuestKompas automatisch bijwerken instellen"
echo "Map: $REPO"
echo

if ! command -v git >/dev/null 2>&1 || ! git --version >/dev/null 2>&1; then
  echo "Git ontbreekt. Typ in Terminal:  xcode-select --install"
  echo "Wacht tot de installatie klaar is en dubbelklik dit bestand opnieuw."
  say_done 1
fi
if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "Deze map is geen git-map. Haal de repo op met GitHub Desktop (Clone Repository)"
  echo "en dubbelklik daarna dit bestand in die map."
  say_done 1
fi

# The background job cannot ask for a password, so test that first.
echo "Verbinding met GitHub testen..."
if ! GIT_TERMINAL_PROMPT=0 git -C "$REPO" fetch --quiet origin 2>/dev/null; then
  echo
  echo "Git kan de repo niet ophalen zonder wachtwoord. Kies een van deze twee:"
  echo "  1. Maak de repo openbaar: github.com, de repo, Settings, onderaan"
  echo "     'Change repository visibility'. Dan is inloggen niet nodig."
  echo "  2. Log Terminal in bij GitHub: typ hieronder"
  echo "       git -C \"$REPO\" fetch"
  echo "     en vul je GitHub-naam in, met als wachtwoord een 'personal access token'"
  echo "     (github.com, Settings, Developer settings, Personal access tokens)."
  echo "Dubbelklik daarna dit bestand opnieuw."
  say_done 1
fi
echo "Verbinding werkt."

# WoW must read straight from this repo: the AddOns entry has to be a symlink.
ADDONS_DIR=""
if [ -f "$REPO/.env.local" ]; then
  # shellcheck disable=SC1090,SC1091
  . "$REPO/.env.local"
  ADDONS_DIR="${WOW_ADDONS_DIR:-}"
fi
if [ -z "$ADDONS_DIR" ] || [ "$(readlink "$ADDONS_DIR/QuestKompas" 2>/dev/null)" != "$REPO/QuestKompas" ]; then
  echo
  echo "De addon in WoW wijst nog niet naar deze map. Dat wordt nu ingesteld."
  echo "(Sluit WoW eerst. Een bestaande map wordt bewaard als QuestKompas.backup.)"
  if ! "$REPO/tools/install.sh"; then
    echo "Installeren lukte niet. Los dat eerst op en probeer het opnieuw."
    say_done 1
  fi
fi

mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cp "$HERE/update-runner.sh" "$RUNNER" && chmod +x "$RUNNER"

xml() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml "$RUNNER")</string>
    <string>$(xml "$REPO")</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>14400</integer>
  <key>StandardOutPath</key><string>$(xml "$LOG")</string>
  <key>StandardErrorPath</key><string>$(xml "$LOG")</string>
</dict>
</plist>
PLIST

unload
if ! launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null && ! launchctl load -w "$PLIST"; then
  echo "De achtergrondtaak kon niet gestart worden."
  say_done 1
fi

echo
echo "Klaar. QuestKompas werkt zichzelf nu bij: bij het inloggen en elke vier uur."
echo "Na een update krijg je een melding; herstart WoW om de nieuwe versie te laden."
echo
echo "De eerste controle loopt nu. Vraagt macOS of 'bash' of 'git' bij je map"
echo "Documenten mag, kies dan Sta toe. Anders kan de taak niet bij de repo."
sleep 4
echo
echo "Laatste regels van het logboek ($LOG):"
tail -n 4 "$LOG" 2>/dev/null || echo "(nog leeg)"
say_done 0
