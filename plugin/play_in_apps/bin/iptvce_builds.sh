# iptvce_ is an item of a plugin with the vod_search entry or of an IPTV
# Channel Editor build with VOD; the prefix is kept for the ids of 0.10.x.
# Shared by sync.sh and diag.sh; only function definitions. main.php has the
# same checks (iptvce_is_build, iptvce_vod_search, iptvce_info).
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

# iptvce_is_build <plugins dir> <name>: a safe folder name and either the
# vod_search action (iptvce_vod_search) or the builder's files and VOD on
# ("vod_engine" in config.json, other than "None" in any case). A safe name:
# 1-40 of [A-Za-z0-9_.-], not starting with . or -, no "..". The name pattern
# has one more copy: iptvce_valid_name in main.php.
iptvce_is_build() {
    case "$2" in
        '' | [.-]* | *[!A-Za-z0-9_.-]* | *..*) return 1 ;;
    esac
    [ "${#2}" -le 40 ] || return 1
    iptvce_vod_search "$1/$2" >/dev/null && return 0
    [ -f "$1/$2/starnet_plugin.php" ] && [ -f "$1/$2/screens_vod/starnet_vod_list_screen.php" ] &&
        [ -f "$1/$2/config.json" ] || return 1
    e=$(grep -o '"vod_engine": *"[^"]*"' "$1/$2/config.json" 2>/dev/null | head -n 1)
    case "$e" in
        '' | *'"'[Nn][Oo][Nn][Ee]'"') return 1 ;;
    esac
}

# iptvce_vod_search <build dir>: "<handler_id> <control_id>" of the
# plugin's search entry for other plugins, declared in its dune_plugin.xml:
#   <public_actions><action id="vod_search">
#     <type>plugin_handle_user_input</type>
#     <params><handler_id>H</handler_id><control_id>C</control_id></params>
#   </action></public_actions>
# Only the first action with id vod_search (" or ') inside a <public_actions>
# counts; its first <type> must be plugin_handle_user_input, its first
# <handler_id> and <control_id> 1-64 of [A-Za-z0-9_.-]. Fails (no output) if
# not, or if the file is over 32768 bytes, has no "vod_search" (not parsed:
# sync.sh checks every plugin) or the handler_id is one of ours. The text is
# read as one line, NUL bytes, comments dropped, spaces around < > = and
# after </ removed. Variables are prefixed: callers keep theirs. The same
# parse: iptvce_vod_search in main.php.
iptvce_vod_search() {
    [ -f "$1/dune_plugin.xml" ] || return 1
    # -z: toybox grep does not see past a NUL in a line.
    LC_ALL=C grep -qzF vod_search "$1/dune_plugin.xml" 2>/dev/null || return 1
    ivs_n=$(wc -c <"$1/dune_plugin.xml" 2>/dev/null)
    ivs_n=${ivs_n##* }
    case "$ivs_n" in
        '' | *[!0-9]*) return 1 ;;
    esac
    [ "$ivs_n" -le 32768 ] || return 1
    ivs_x=$(LC_ALL=C tr '\n\r\t' '   ' <"$1/dune_plugin.xml" 2>/dev/null)
    ivs_o='<!--'
    ivs_e='-->'
    ivs_s=
    while :; do
        case "$ivs_x" in
            *"$ivs_o"*)
                ivs_p=${ivs_x%%"$ivs_o"*}
                ivs_s="$ivs_s$ivs_p "
                ivs_x=${ivs_x#*"$ivs_o"}
                case "$ivs_x" in
                    *"$ivs_e"*) ivs_x=${ivs_x#*"$ivs_e"} ;;
                    *) ivs_x= ;;
                esac
                ;;
            *)
                ivs_s="$ivs_s$ivs_x"
                break
                ;;
        esac
    done
    ivs_s=$(printf '%s' "$ivs_s" | LC_ALL=C sed 's/  */ /g; s/ *\([<>=]\) */\1/g; s:</ *:</:g')
    # The <public_actions> blocks, each followed by a space.
    ivs_o='<public_actions>'
    ivs_e='</public_actions>'
    ivs_a=
    while :; do
        case "$ivs_s" in
            *"$ivs_o"*"$ivs_e"*) ;;
            *) break ;;
        esac
        ivs_s=${ivs_s#*"$ivs_o"}
        ivs_p=${ivs_s%%"$ivs_e"*}
        ivs_a="$ivs_a$ivs_p "
        ivs_s=${ivs_s#*"$ivs_e"}
    done
    # <action attributes>body</action>, in order.
    ivs_o='<action '
    ivs_e='</action>'
    while :; do
        case "$ivs_a" in
            *"$ivs_o"*"$ivs_e"*) ;;
            *) return 1 ;;
        esac
        ivs_a=${ivs_a#*"$ivs_o"}
        ivs_t=${ivs_a%%'>'*}
        ivs_b=${ivs_a#*'>'}
        case "$ivs_b" in
            *"$ivs_e"*) ;;
            *) continue ;;
        esac
        ivs_a=${ivs_b#*"$ivs_e"}
        case " $ivs_t " in
            *' id="vod_search" '* | *" id='vod_search' "*) ;;
            *) continue ;;
        esac
        ivs_b=${ivs_b%%"$ivs_e"*}
        [ "$(iptvce_tag type "$ivs_b")" = plugin_handle_user_input ] || return 1
        ivs_h=$(iptvce_tag handler_id "$ivs_b")
        ivs_c=$(iptvce_tag control_id "$ivs_b")
        for ivs_v in "$ivs_h" "$ivs_c"; do
            case "$ivs_v" in
                '' | *[!A-Za-z0-9_.-]*) return 1 ;;
            esac
            [ "${#ivs_v}" -le 64 ] || return 1
        done
        # The handler_ids of main.php (pia_handle_user_input; the other copy:
        # iptvce_own_handler there): if the shell turns down plugin_name, it
        # calls ours with them.
        case "$ivs_h" in
            setup | check | filmix_api | bazinga | iptvce_*) return 1 ;;
        esac
        printf '%s %s\n' "$ivs_h" "$ivs_c"
        return 0
    done
}

# iptvce_tag <tag> <text>: what is between the first <tag> and the </tag>
# after it; nothing if there are none.
iptvce_tag() {
    case "$2" in
        *"<$1>"*"</$1>"*)
            ivs_r=${2#*"<$1>"}
            printf '%s' "${ivs_r%%"</$1>"*}"
            ;;
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
