# Dune plugins made by IPTV Channel Editor (the builder by sharky72) that
# have VOD: each is an item iptvce_<name> of the "Play..." menu. Shared by
# sync.sh and diag.sh; only function definitions. main.php has the same checks
# (iptvce_is_build, iptvce_info).
# Everything read from a build is untrusted: only printed, never run.
# shellcheck shell=sh

# iptvce_builds <plugins dir>: names of the builds, one per line, in name order.
iptvce_builds() {
    for b in "$1"/*/; do
        b=${b%/}
        b=${b##*/}
        if iptvce_is_build "$1" "$b"; then
            printf '%s\n' "$b"
        fi
    done
}

# iptvce_is_build <plugins dir> <name>: a safe folder name, the builder's
# files and VOD on ("vod_engine" in config.json, other than "None").
# The name pattern has two more copies: iptvce_valid_name in main.php and the
# log name in cgi/logs.php.
iptvce_is_build() {
    case "$2" in
        '' | *[!A-Za-z0-9_]*) return 1 ;;
    esac
    [ "${#2}" -le 40 ] || return 1
    [ -f "$1/$2/starnet_plugin.php" ] && [ -f "$1/$2/screens_vod/starnet_vod_list_screen.php" ] &&
        [ -f "$1/$2/config.json" ] || return 1
    e=$(grep -o '"vod_engine": *"[^"]*"' "$1/$2/config.json" 2>/dev/null | head -n 1)
    case "$e" in
        '' | *'"None"') return 1 ;;
    esac
}

# iptvce_caption <build dir> <name>: the first <caption> of its
# dune_plugin.xml (XML entities decoded, then < and > dropped, spaces
# trimmed), cut to 40 characters; <name> if there is none or it is not safe
# text: control characters, bad UTF-8, a leading % (%tr%: a key of our own
# translations).
# Bytes are matched in the C locale: toybox tr does not take octal ranges.
iptvce_caption() {
    c=$(LC_ALL=C grep -o '<caption>[^<]*</caption>' "$1/dune_plugin.xml" 2>/dev/null | head -n 1 |
        LC_ALL=C sed "s:^<caption>::; s:</caption>\$::; s/&lt;/</g; s/&gt;/>/g; s/&quot;/\"/g; s/&apos;/'/g; s/&amp;/\\&/g; s/[<>]//g; s/^ *//; s/ *\$//")
    # Valid UTF-8 sequences of 2-4 bytes, as pia_utf8_clean in main.php.
    v=$(printf '[\302-\337][\200-\277]|\340[\240-\277][\200-\277]|[\341-\354\356\357][\200-\277]{2}|')
    v=$v$(printf '\355[\200-\237][\200-\277]|\360[\220-\277][\200-\277]{2}|[\361-\363][\200-\277]{3}|')
    v=$v$(printf '\364[\200-\217][\200-\277]{2}')
    k=$(printf '\200-\277')
    case "$c" in
        '' | %*) c=$2 ;;
    esac
    if printf '%s' "$c" | LC_ALL=C grep -q "$(printf '[\001-\037\177]')" ||
        printf '%s' "$c" | LC_ALL=C sed -E "s/$v//g" | LC_ALL=C grep -q "$(printf '[\200-\377]')"; then
        c=$2
    fi
    # 40 characters: a lead byte and its continuation bytes each.
    printf '%s' "$c" | LC_ALL=C sed -E "s/^(([^$k][$k]*){40}).+/\\1/"
}

# iptvce_icon <build dir>: the path of its icon inside the build's folder,
# from the first <icon_url> of its dune_plugin.xml if that is
# plugin_file://<path>; empty if not, an unsafe path or no such file.
iptvce_icon() {
    i=$(LC_ALL=C grep -o '<icon_url>[^<]*</icon_url>' "$1/dune_plugin.xml" 2>/dev/null | head -n 1 |
        LC_ALL=C sed 's:^<icon_url>::; s:</icon_url>$::')
    case "$i" in
        plugin_file://*) i=${i#plugin_file://} ;;
        *) return 0 ;;
    esac
    case "$i" in
        '' | /* | *[!A-Za-z0-9/._-]* | *..*) return 0 ;;
    esac
    if [ -f "$1/$i" ]; then
        printf '%s' "$i"
    fi
}
