#!/bin/bash
# QuestKompas auto-update: pulls the newest version into the repo that the
# AddOns symlink points at. Run by the launchd agent that
# "Automatisch bijwerken.command" installs; the repo path is the argument.
# Output goes to the log file that launchd is told to use.
REPO="$1"
STATE_DIR="${QK_STATE_DIR:-$HOME/Library/Application Support/QuestKompas}"
export GIT_TERMINAL_PROMPT=0

notify() {
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$1\" with title \"QuestKompas\"" >/dev/null 2>&1 || true
  fi
}

# A failure is reported at most once a day, so a broken setup does not nag.
fail() {
  echo "FOUT: $1"
  local today stamp="$STATE_DIR/last-failure"
  today="$(date +%Y-%m-%d)"
  if [ "$(cat "$stamp" 2>/dev/null)" != "$today" ]; then
    mkdir -p "$STATE_DIR" && echo "$today" > "$stamp"
    notify "Bijwerken mislukt: $1"
  fi
  exit 1
}

echo "--- $(date '+%Y-%m-%d %H:%M:%S')"
[ -n "$REPO" ] || fail "geen map opgegeven"
cd "$REPO" 2>/dev/null || fail "geen toegang tot $REPO"
git rev-parse --git-dir >/dev/null 2>&1 || fail "$REPO is geen git-map (of geen toegang)"

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "Lokale wijzigingen gevonden, bijwerken overgeslagen."
  exit 0
fi

before="$(git rev-parse HEAD)"
git fetch --prune --quiet origin || fail "ophalen van GitHub lukte niet (geen internet of niet ingelogd)"
git remote set-head origin --auto >/dev/null 2>&1 || true

branch="$(git symbolic-ref --quiet --short HEAD || true)"
default="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
[ -n "$branch" ] || fail "de map staat niet op een branch"

# Follow the default branch once this branch is finished: its work is
# already in the default branch, or the branch was deleted on GitHub.
if [ -n "$default" ] && [ "$branch" != "$default" ]; then
  if git merge-base --is-ancestor HEAD "origin/$default" 2>/dev/null \
     || ! git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
    echo "Branch $branch is klaar, overstappen naar $default."
    if git show-ref --verify --quiet "refs/heads/$default"; then
      git checkout --quiet "$default" || fail "overstappen naar $default lukte niet"
    else
      git checkout --quiet -b "$default" --track "origin/$default" || fail "overstappen naar $default lukte niet"
    fi
    branch="$default"
  fi
fi

git merge --ff-only --quiet "origin/$branch" || fail "samenvoegen lukte niet (lokale commits op $branch?)"

after="$(git rev-parse HEAD)"
if [ "$before" = "$after" ]; then
  echo "Al bij."
else
  version="$(sed -n 's/^## Version: *//p' QuestKompas/QuestKompas.toc | tr -d '\r')"
  echo "Bijgewerkt naar $version ($(git rev-parse --short HEAD), branch $branch)."
  notify "Bijgewerkt naar versie $version. Herstart WoW om hem te laden."
fi
rm -f "$STATE_DIR/last-failure"
