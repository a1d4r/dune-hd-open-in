#!/bin/sh
# Movie supplier bin. The shell runs play_action (main.php) instead, so this
# only answers if play_action was ignored: an error dialog, never a launch.
# stdout: exactly one JSON object. Diagnostics go to stderr, which the shell
# appends to /tmp/run/filmix__supplier.log.

name=filmix_api_supplier

cat >/dev/null
printf '%s bin called instead of play_action: %s\n' "$(date '+%F %T')" "$*" >&2
printf '{"error":{"message":"%%ext%%<key_global>%s_plugin_err_unsupported</key_global>"}}\n' "$name"
