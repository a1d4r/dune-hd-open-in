#!/bin/sh
# Movie supplier bin: supplier.sh start_playback_app, Dune movie info JSON on stdin.
# Replies with a launch command that the shell runs itself (it needs "package"
# to be a known app), or with an error shown as a dialog.
# stdout: exactly one JSON object. Diagnostics go to stderr, which the shell
# appends to $FS_PREFIX/tmp/run/prisma__supplier.log.

name=play_in_apps
id=prisma
pkg=top.rootu.prisma
tmp=${PLAY_IN_APPS_TMP:-$FS_PREFIX/tmp}

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >&2
}

# Error dialog text is this plugin's translation key <id>_<key>; the GUI resolves
# %ext%<key_global> the same way as the translated supplier caption.
fail() {
    log "error: $1"
    printf '{"error":{"message":"%%ext%%<key_global>%s_plugin_%s_%s</key_global>"}}\n' "$name" "$id" "$1"
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
if ! grep -qE '"package_name": *"top\.rootu\.prisma"' "$tmp/applications/app_data.json" 2>/dev/null; then
    fail err_not_installed
fi

# Prisma is a Lampa fork with the same intent handling: open by TMDB link only,
# as for Lampa (Lampa's IMDb extras give a broken card).
# Ids above Java int are dropped silently, hence 9 digits.
case "$type" in
    single) kind=movie tmdb=$(ext_id 'tmdb:[0-9]{1,9}') ;;
    series) kind=tv tmdb=$(ext_id 'tmdbtv:[0-9]{1,9}') ;;
    *) fail err_no_id ;;
esac
[ -n "$tmdb" ] || fail err_no_id

uri="https://www.themoviedb.org/$kind/$tmdb"
log "uri: $uri"
# The package is required: NUM, Lampa and a web browser also handle themoviedb.org links.
# --activity-clear-task: otherwise every launch stacks another card in Prisma.
# An intent: URI rather than -a/-d/-p: the shell's command parser on some
# firmware (r24 260214) rejects -p. The link has no '#', ';', spaces or quotes.
printf '{"bin":"am start --activity-clear-task '\''intent:%s#Intent;scheme=%s;action=android.intent.action.VIEW;package=%s;end'\''","package":"%s","title":"Prisma","wait_app_start_delay":10}\n' \
    "${uri#*:}" "${uri%%:*}" "$pkg" "$pkg"
