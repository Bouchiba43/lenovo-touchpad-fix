#!/bin/bash
# Adds a GNOME keyboard shortcut that runs "touchpad-fix --hard --notify".
# Run as your normal user, not with sudo.
#
#   ./install-shortcut.sh                      bind Ctrl+Alt+O
#   ./install-shortcut.sh '<Control><Alt>p'    bind another combination (GNOME syntax)
#   ./install-shortcut.sh --remove             remove the shortcut
#
# GNOME shortcuts are modifiers plus ONE key; a two-letter chord such as Ctrl+T+O is not possible.
set -euo pipefail

SCHEMA=org.gnome.settings-daemon.plugins.media-keys
KEYPATH=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/touchpad-fix/
ITEM=$SCHEMA.custom-keybinding:$KEYPATH
binding=${1:-<Control><Alt>o}

case "$binding" in -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
[ "$(id -u)" -ne 0 ] || { echo "install-shortcut.sh: run this as your normal user, not root" >&2; exit 1; }
command -v gsettings >/dev/null 2>&1 || { echo "install-shortcut.sh: gsettings not found (GNOME only)" >&2; exit 1; }

# Add or remove our path in GNOME's list of custom shortcuts, keeping the others.
update_list() {
  local cur new
  cur=$(gsettings get "$SCHEMA" custom-keybindings)
  new=$(python3 -c '
import ast, sys
paths = ast.literal_eval(sys.argv[1].replace("@as ", "", 1))
path, action = sys.argv[2], sys.argv[3]
paths = [p for p in paths if p != path]
if action == "add":
    paths.append(path)
print(paths)' "$cur" "$KEYPATH" "$1")
  gsettings set "$SCHEMA" custom-keybindings "$new"
}

if [ "$binding" = --remove ]; then
  update_list remove
  gsettings reset-recursively "$ITEM"
  echo "Shortcut removed."
  exit 0
fi

# Refuse a combination another custom shortcut already uses.
for p in $(gsettings get "$SCHEMA" custom-keybindings | grep -o "/[^']*" || true); do
  [ "$p" = "$KEYPATH" ] && continue
  if [ "$(gsettings get "$SCHEMA.custom-keybinding:$p" binding)" = "'$binding'" ]; then
    echo "install-shortcut.sh: $binding is already used by the shortcut $(gsettings get "$SCHEMA.custom-keybinding:$p" name)" >&2
    exit 1
  fi
done

gsettings set "$ITEM" name 'Touchpad fix'
gsettings set "$ITEM" command '/usr/local/bin/touchpad-fix --hard --notify'
gsettings set "$ITEM" binding "$binding"
update_list add
echo "Shortcut set: $binding runs 'touchpad-fix --hard --notify'."
