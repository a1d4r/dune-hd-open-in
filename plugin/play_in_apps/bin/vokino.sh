#!/bin/sh
# Movie supplier bin: supplier.sh start_playback_app, Dune movie info JSON on stdin.
# Replies with a launch command that the shell runs itself (it needs "package"
# to be a known app), or with an error shown as a dialog.
# stdout: exactly one JSON object. Diagnostics go to stderr, which the shell
# appends to $FS_PREFIX/tmp/run/vokino__supplier.log.

name=play_in_apps
id=vokino
pkg=ru.vokino.web
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

# ext_id <regex>: id part of the first movieExtId item matching ^regex$.
ext_id() {
    printf '%s\n' "$ext" | tr ',' '\n' | grep -E "^$1\$" | head -n 1 | cut -d: -f2
}

# title <lang>: body of the "title":{"<lang>":"..."} JSON string, escapes kept.
title() {
    printf '%s\n' "$input" |
        grep -oE '"title": *\{("([^"\\]|\\.)*"|[^"}])*\}' | head -n 1 |
        grep -oE "\"$1\": *\"([^\"\\\\]|\\\\.)*\"" | head -n 1 |
        sed 's/^[^:]*: *"//; s/"$//'
}

# put <byte>: add one UTF-8 byte to the printf format $fmt and its numeric
# arguments $args, percent-encoded unless unreserved (RFC 3986). printf runs
# once at the end: on the device it is not a shell builtin.
put() {
    if [ $(($1 >= 48 && $1 <= 57 || $1 >= 65 && $1 <= 90 || $1 >= 97 && $1 <= 122 ||
        $1 == 45 || $1 == 46 || $1 == 95 || $1 == 126)) = 1 ]; then
        fmt="$fmt\\$(($1 / 64))$(($1 / 8 % 8))$(($1 % 8))"
    else
        fmt="$fmt%%%02X"
        args="$args $1"
    fi
}

# utf8 <code unit>: bytes of a \uXXXX escape. Surrogates (emoji) are dropped.
utf8() {
    if [ "$1" -lt 128 ]; then
        put "$1"
    elif [ "$1" -lt 2048 ]; then
        put $((192 + $1 / 64))
        put $((128 + $1 % 64))
    elif [ "$1" -lt 55296 ] || [ "$1" -gt 57343 ]; then
        put $((224 + $1 / 4096))
        put $((128 + $1 / 64 % 64))
        put $((128 + $1 % 64))
    fi
}

# query: JSON string body on stdin (raw UTF-8 and/or \u escapes) -> query value.
# Only the first 600 bytes are used: 100 Cyrillic letters as \u escapes.
query() {
    fmt=
    args=
    # shellcheck disable=SC2046 # one word per byte, od prints only hex
    set -- $(head -c 600 | od -An -v -tx1)
    while [ $# -gt 0 ]; do
        b=$1
        shift
        if [ "$b" != 5c ]; then
            put $((0x$b))
            continue
        fi
        e=${1-}
        [ $# -eq 0 ] || shift
        case "$e" in
            22 | 2f | 5c) put $((0x$e)) ;;
            62 | 66 | 6e | 72 | 74) put 32 ;;
            75)
                u=0
                for _ in 1 2 3 4; do
                    case "${1-}" in
                        3[0-9]) u=$((u * 16 + ${1#3})) ;;
                        4[1-6] | 6[1-6]) u=$((u * 16 + ${1#?} + 9)) ;;
                        *) u=-1 && break ;;
                    esac
                    shift
                done
                [ "$u" -lt 0 ] || utf8 "$u"
                ;;
        esac
    done
    # shellcheck disable=SC2059,SC2086 # format built above, args are numbers
    printf "$fmt" $args
}

if [ "${1-}" != start_playback_app ]; then
    log "unsupported command: $*"
    fail err_unsupported
fi

input=$(cat)
ext=$(printf '%s\n' "$input" | grep -o '"movieExtId": *"[^"]*"' | head -n 1 |
    sed 's/^[^:]*: *"//; s/"$//')
log "movieExtId: $ext"

# Same source the shell uses to resolve "package".
if ! grep -qE '"package_name": *"ru\.vokino\.web"' "$tmp/applications/app_data.json" 2>/dev/null; then
    fail err_not_installed
fi

# VoKino opens movies and series alike by IMDb ID (not TMDB or Kinopoisk).
# Without one, search by title; VoKino ignores the year.
imdb=$(ext_id 'imdb:tt[0-9]{1,10}')
if [ -n "$imdb" ]; then
    path="view/$imdb"
else
    # "ru" is the title in the Dune UI language, "en" is the original title.
    q=
    for lang in ru en; do
        [ -n "$q" ] || q=$(printf '%s' "$(title "$lang")" | query)
    done
    [ -n "$q" ] || fail err_no_id
    path="search?name=$q"
fi

uri="vokino://ru.vokino.web/$path"
log "uri: $uri"
# --activity-clear-task is required: without it a running VoKino gets the URI
# via javascript:window.load('<uri>'), unescaped, and keeps WebView history.
# An intent: URI rather than -a/-d/-p: the shell's command parser on some
# firmware (r24 260214) rejects -p. The link has no '#', ';', spaces or quotes.
printf '{"bin":"am start --activity-clear-task '\''intent:%s#Intent;scheme=%s;action=android.intent.action.VIEW;package=%s;end'\''","package":"%s","title":"VoKino","wait_app_start_delay":10}\n' \
    "${uri#*:}" "${uri%%:*}" "$pkg" "$pkg"
