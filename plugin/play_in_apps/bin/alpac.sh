#!/bin/sh
# Movie supplier bin: supplier.sh start_playback_app, Dune movie info JSON on stdin.
# Replies with a launch command that the shell runs itself (it needs "package"
# to be a known app), or with an error shown as a dialog.
# stdout: exactly one JSON object. Diagnostics go to stderr, which the shell
# appends to $FS_PREFIX/tmp/run/alpac__supplier.log.

name=play_in_apps
id=alpac
pkg=cc.alcopa.tv
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

# shellcheck source=search.sh
. "${0%/*}/search.sh"

if [ "${1-}" != start_playback_app ]; then
    log "unsupported command: $*"
    fail err_unsupported
fi

input=$(cat)
ext=$(value movieExtId)
type=$(value type)
log "movieExtId: $ext type: $type"

# Same source the shell uses to resolve "package".
if ! grep -qE '"package_name": *"cc\.alcopa\.tv"' "$tmp/applications/app_data.json" 2>/dev/null; then
    fail err_not_installed
fi

# ALPAC opens a title by TMDB ID. The type in the path must match the ID:
# movie/ with a TV id (or the reverse) opens an empty card with no error.
# ID 0 closes the card at once, so only a positive number without leading zeros.
tmdb=
case "$type" in
    single) kind=movie tmdb=$(ext_id 'tmdb:[1-9][0-9]{0,8}') ;;
    series) kind=tv tmdb=$(ext_id 'tmdbtv:[1-9][0-9]{0,8}') ;;
esac

if [ -n "$tmdb" ]; then
    uri="alpac://title/$kind/$tmdb"
    log "uri: $uri"
    # --activity-clear-task: the card activity has the standard launch mode,
    # without it every launch stacks another card.
    # An intent: URI rather than -a/-d/-p: the shell's command parser on some
    # firmware (r24 260214) rejects -p. The link has no '#', ';', spaces or quotes.
    printf '{"bin":"am start --activity-clear-task '\''intent:%s#Intent;scheme=%s;action=android.intent.action.VIEW;package=%s;end'\''","package":"%s","title":"ALPAC","wait_app_start_delay":10}\n' \
        "${uri#*:}" "${uri%%:*}" "$pkg" "$pkg"
    exit 0
fi

# No TMDB ID: search by title. "ru" is the title in the Dune UI language,
# "en" is the original title.
q=
for lang in ru en; do
    [ -n "$q" ] || q=$(printf '%s' "$(title "$lang")" | query)
done
[ -n "$q" ] || fail err_no_id

# SearchActivity's filter has no DEFAULT category, so only the explicit
# component finds it; it reads the "query" extra and searches at once.
# Intent.parseUri decodes S.query, so the argument has no spaces or quotes
# for the shell's tokenizer.
uri="intent:#Intent;component=$pkg/cc.alcopa.tv.SearchActivity;S.query=$q;end"
log "uri: $uri"
# --activity-clear-task: one search screen, Back returns to the Dune.
printf '{"bin":"am start --activity-clear-task '\''%s'\''","package":"%s","title":"ALPAC","wait_app_start_delay":10}\n' \
    "$uri" "$pkg"
