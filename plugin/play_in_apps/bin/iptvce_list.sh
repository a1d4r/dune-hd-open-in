#!/bin/sh
# The plugins that get an iptvce_ item (iptvce_builds.sh), for main.php: one
# line each, in name order,
#   <name> TAB <caption> TAB <icon> TAB <handler_id> TAB <control_id>
# caption: iptvce_caption, no control characters, so no TAB or line break;
# icon: iptvce_icon, a path inside the plugin's folder; handler_id and
# control_id: of its vod_search action (iptvce_vod_search). Each of the last
# three is empty if there is none.
# Usage: sh iptvce_list.sh [<name>]; with a name only that plugin is read and
# there is no line if it gets no item. Read only.

mydir=$(cd "$(dirname "$0")" && pwd)
plugins=$(dirname "$(dirname "$mydir")")

# shellcheck source=iptvce_builds.sh
. "$mydir/iptvce_builds.sh"

# line <name>: its line, if it gets an item. vod_search first: the item of
# such a plugin is its vod_search, and iptvce_gets_item would parse it again.
line() {
    iptvce_name_ok "$1" || return 0
    if ! l_vs=$(iptvce_vod_search "$plugins/$1"); then
        iptvce_gets_item "$plugins" "$1" || return 0
        l_vs=
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$(iptvce_caption "$plugins/$1" "$1")" \
        "$(iptvce_icon "$plugins/$1")" "${l_vs% *}" "${l_vs#* }"
}

if [ $# -gt 0 ]; then
    line "$1"
else
    for b in "$plugins"/*/; do
        b=${b%/}
        line "${b##*/}"
    done
fi
exit 0
