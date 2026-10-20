#!/bin/sh
# Movie supplier bin: supplier.sh start_playback_app, Dune movie info JSON on stdin.
# Replies with a launch command that the shell runs itself (it needs "package"
# to be a known app), or with an error shown as a dialog.
# stdout: exactly one JSON object. Diagnostics go to stderr, which the shell
# appends to $FS_PREFIX/tmp/run/lazymedia__supplier.log.

name=play_in_apps
id=lazymedia
pkg=com.lazycatsoftware.lmd
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
if ! grep -qE '"package_name": *"com\.lazycatsoftware\.lmd"' "$tmp/applications/app_data.json" 2>/dev/null; then
    fail err_not_installed
fi

# LazyMedia has no IDs of its own (a title page belongs to one source site),
# so it can only search. "ru" is the title in the Dune UI language, "en" is
# the original title.
q=
for lang in ru en; do
    [ -n "$q" ] || q=$(printf '%s' "$(title "$lang")" | query)
done
[ -n "$q" ] || fail err_no_title

# ActivityTvSearch is exported without intent filters and reads only the
# "query" extra. Intent.parseUri decodes S.query, so the argument has no spaces
# or quotes for the shell's tokenizer.
uri="intent:#Intent;component=$pkg/com.lazycatsoftware.lazymediadeluxe.ui.tv.activities.ActivityTvSearch;S.query=$q;end"
log "uri: $uri"
# --activity-clear-task is required: the search activity has no onNewIntent,
# so a running one would ignore the new query.
printf '{"bin":"am start --activity-clear-task '\''%s'\''","package":"%s","title":"LazyMedia","wait_app_start_delay":10}\n' \
    "$uri" "$pkg"
