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
# od -b, not -An -tx1: BusyBox 1.22 without CONFIG_DESKTOP (older Android) has
# no -A or -t. Its words are 3-digit octal bytes and 7-digit offsets.
# $esc: the last byte was a backslash; $left: hex digits of \uXXXX still due.
percent_encode() {
    fmt=
    args=
    esc=0
    left=0
    # shellcheck disable=SC2046 # one word per byte or offset, digits only
    set -- $(head -c 600 | od -v -b)
    for w in "$@"; do
        case "$w" in
            [0-3][0-7][0-7]) ;;
            *) continue ;;
        esac
        b=${w#?}
        b=$((${w%??} * 64 + ${b%?} * 8 + ${w#??}))
        if [ "$left" -gt 0 ]; then
            case "$b" in
                4[89] | 5[0-7]) u=$((u * 16 + b - 48)) ;;
                6[5-9] | 70) u=$((u * 16 + b - 55)) ;;
                9[7-9] | 10[0-2]) u=$((u * 16 + b - 87)) ;;
                # Not a hex digit: the escape is dropped, the byte read as usual.
                *) left=0 ;;
            esac
            if [ "$left" -gt 0 ]; then
                left=$((left - 1))
                [ "$left" -gt 0 ] || utf8 "$u"
                continue
            fi
        fi
        if [ "$esc" = 1 ]; then
            esc=0
            case "$b" in
                34 | 47 | 92) put "$b" ;;
                98 | 102 | 110 | 114 | 116) put 32 ;;
                117) left=4 u=0 ;;
            esac
        elif [ "$b" = 92 ]; then
            esc=1
        else
            put "$b"
        fi
    done
    # shellcheck disable=SC2059,SC2086 # format built above, args are numbers
    printf "$fmt" $args
}
