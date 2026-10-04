#!/bin/sh
# Movie supplier bin of the Filmix item. The shell runs play_action (main.php)
# instead, so this only answers if play_action was ignored: an error dialog,
# never a launch.
# stdout: exactly one JSON object. Diagnostics go to stderr, which the shell
# appends to /tmp/run/filmix_api__supplier.log.

name=play_in_apps
id=filmix_api

cat >/dev/null
printf '%s bin called instead of play_action: %s\n' "$(date '+%F %T')" "$*" >&2
printf '{"error":{"message":"%%ext%%<key_global>%s_plugin_%s_err_unsupported</key_global>"}}\n' "$name" "$id"
