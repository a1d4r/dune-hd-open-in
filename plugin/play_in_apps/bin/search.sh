# Search by title, shared by the item scripts that fall back to an app's
# search: vokino.sh, lazymedia.sh, alpac.sh and seasonhit.sh source it.
# Only function definitions; the entry point is search_query.
# shellcheck shell=sh

# search_query <movie info JSON>: percent-encoded title in the Dune UI language
# ("ru"), else the original title ("en"); empty if there is neither.
search_query() {
    q=
    for lang in ru en; do
        [ -n "$q" ] || q=$(printf '%s' "$(title "$1" "$lang")" | percent_encode)
    done
    printf '%s' "$q"
}

# title <JSON> <lang>: body of the "title":{"<lang>":"..."} JSON string,
# escapes kept.
title() {
    printf '%s\n' "$1" |
        grep -oE '"title": *\{("([^"\\]|\\.)*"|[^"}])*\}' | head -n 1 |
        grep -oE "\"$2\": *\"([^\"\\\\]|\\\\.)*\"" | head -n 1 |
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

# percent_encode: JSON string body on stdin (raw UTF-8 and/or \u escapes) ->
# query value.
# Only the first 600 bytes are used: 100 Cyrillic letters as \u escapes.
percent_encode() {
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
