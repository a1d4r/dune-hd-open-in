#!/bin/sh
# Movie supplier bin: supplier.sh start_playback_app, Dune movie info JSON on stdin.
# Replies with a launch command that the shell runs itself (it needs "package"
# to be a known app), or with an error shown as a dialog.
# stdout: exactly one JSON object. Diagnostics go to stderr, which the shell
# appends to $FS_PREFIX/tmp/run/seasonhit__supplier.log.

name=play_in_apps
id=seasonhit
pkg=com.jimdo.xakerd.season2hit
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

# shellcheck source=search.sh
. "${0%/*}/search.sh"

if [ "${1-}" != start_playback_app ]; then
    log "unsupported command: $*"
    fail err_unsupported
fi

input=$(cat)

# Same source the shell uses to resolve "package".
if ! grep -qE '"package_name": *"com\.jimdo\.xakerd\.season2hit"' "$tmp/applications/app_data.json" 2>/dev/null; then
    fail err_not_installed
fi

# SeasonHit knows only seasonvar IDs (one per season), not TMDB/IMDb/Kinopoisk,
# so it can only search. Its search lists seasonvar series, for movies too.
q=$(search_query "$input")
[ -n "$q" ] || fail err_no_title

# SearchActivity reads the "query" extra and searches at once. It is not
# exported: from adb (uid 2000) am start fails, the shell starts it as the
# system uid (hypothesis, to check on the device). Intent.parseUri decodes
# S.query, so the argument has no spaces or quotes for the shell's tokenizer.
uri="intent:#Intent;component=$pkg/com.jimdo.xakerd.season2hit.activity.SearchActivity;S.query=$q;end"
log "uri: $uri"
# --activity-clear-task: else a new query could be lost under the results of
# the previous one.
printf '{"bin":"am start --activity-clear-task '\''%s'\''","package":"%s","title":"SeasonHit","wait_app_start_delay":10}\n' \
    "$uri" "$pkg"
