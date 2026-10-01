#!/bin/sh
# Movie supplier bin: supplier.sh start_playback_app, Dune movie info JSON on stdin.
# Replies with a launch command that the shell runs itself (it needs "package"
# to be a known app), or with an error shown as a dialog.
# stdout: exactly one JSON object. Diagnostics go to stderr, which the shell
# appends to /tmp/run/nuvio__supplier.log.

name=nuvio_supplier
pkg=com.nuvio.tv
tmp=${NUVIO_TMP:-/tmp}

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >&2
}

# Error dialog text is this plugin's translation key; the GUI resolves
# %ext%<key_global> the same way as the translated supplier caption.
fail() {
    log "error: $1"
    printf '{"error":{"message":"%%ext%%<key_global>%s_plugin_%s</key_global>"}}\n' "$name" "$1"
    exit 0
}

# value <key>: first "key":"value" string in the input JSON.
value() {
    printf '%s\n' "$input" | grep -o "\"$1\": *\"[^\"]*\"" | head -n 1 |
        sed 's/^[^:]*: *"//; s/"$//'
}

# ext_id <regex>: number part of the first movieExtId item matching ^regex$.
ext_id() {
    printf '%s\n' "$ext" | tr ',' '\n' | grep -E "^$1\$" | head -n 1 | cut -d: -f2
}

if [ "${1-}" != start_playback_app ]; then
    log "unsupported command: $*"
    fail err_unsupported
fi

input=$(cat)
ext=$(value movieExtId)
type=$(value type)
log "movieExtId: $ext type: $type"

# Same source the shell uses to resolve "package".
if ! grep -qE '"package_name": *"com\.nuvio\.tv"' "$tmp/applications/app_data.json" 2>/dev/null; then
    fail err_not_installed
fi

case "$type" in
    single) kind=movie tmdb=$(ext_id 'tmdb:[0-9]{1,10}') ;;
    series) kind=series tmdb=$(ext_id 'tmdbtv:[0-9]{1,10}') ;;
    *) fail err_no_id ;;
esac
imdb=$(ext_id 'imdb:tt[0-9]{1,10}')

if [ -n "$imdb" ]; then
    uri="nuvio://$kind/$imdb"
elif [ -n "$tmdb" ]; then
    uri="nuvio://tmdb/$kind/$tmdb"
else
    fail err_no_id
fi

log "uri: $uri"
printf '{"bin":"am start -a android.intent.action.VIEW -d '\''%s'\'' -p %s","package":"%s","title":"Nuvio","wait_app_start_delay":10}\n' \
    "$uri" "$pkg" "$pkg"
