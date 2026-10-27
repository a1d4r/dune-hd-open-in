#!/bin/sh
# Shows the "Play..." item of every app that is installed and not hidden on
# the plugin screen, removes the others. A shown item is the supplier JSON in
# plugins_data/<plugin>/movie_suppliers/<id> (the shell copies it to
# /tmp/movie_suppliers/ on every boot) plus the same copy in
# /tmp/movie_suppliers/<id> (the menu rereads it for every card).
# Runs from movie_suppliers_update.sh, on early_gui_start and from the screen
# (main.php). Output is for running it by hand.
# IPTV Channel Editor builds with VOD (iptvce_builds.sh) get an item each,
# iptvce_<name>, after the fixed ones; their ids are not in dune_plugin.xml.

name=play_in_apps

# FS_PREFIX goes into JSON (icon path). It is unset on older Android models,
# where paths start at the root.
case "$FS_PREFIX" in
    /*[!A-Za-z0-9/._-]* | [!/]*)
        echo "$name: FS_PREFIX is relative or unsafe, nothing written"
        exit 1
        ;;
esac

mydir=$(cd "$(dirname "$0")" && pwd)
# The path goes into JSON and into a shell command line.
case "$mydir" in
    /*[!A-Za-z0-9/._-]* | [!/]* | '')
        echo "$name: unsafe plugin path, nothing written: $mydir"
        exit 1
        ;;
esac

tmp=${PLAY_IN_APPS_TMP:-$FS_PREFIX/tmp}
data="${PLAY_IN_APPS_FLASHDATA:-$FS_PREFIX/flashdata}/plugins_data/$name"
apps="$tmp/applications/app_data.json"
plugins=$(dirname "$(dirname "$mydir")")

# shellcheck source=iptvce_builds.sh
. "$mydir/iptvce_builds.sh"

# Without the shell's app list (missing, empty or not written yet) nothing is
# known about Android apps: their items stay as they are. A list read while the
# shell rewrites it is cut short: its braces do not balance.
apps_known=0
if grep -q '"package_name"' "$apps" 2>/dev/null &&
    [ "$(tr -cd '{' <"$apps" | wc -c)" -eq "$(tr -cd '}' <"$apps" | wc -c)" ]; then
    apps_known=1
fi

# icon <package>: the app's own icon, the "icon" path from the shell's app
# list, as in its Applications menu. On Dune HD Media Center installed as an
# app on Android TV it is not in tmp/applications/icon_cache. Records are
# split at "}" so field order and layout do not matter.
icon() {
    i=$(tr '\n}' ' \n' 2>/dev/null <"$apps" |
        grep "\"package_name\": *\"$(printf '%s' "$1" | sed 's/\./\\./g')\"" |
        grep -o '"icon": *"[^"]*"' | head -n 1 |
        sed 's/^[^:]*: *"//; s/"$//; s#\\/#/#g')
    # The path goes into JSON.
    case "$i" in
        /*[!A-Za-z0-9/._-]* | [!/]* | '')
            i="$FS_PREFIX/tmp/applications/icon_cache/icon_$1.png"
            ;;
    esac
    printf '%s' "$i"
}

failed=0

# show <id> <supplier JSON>
show() {
    if mkdir -p "$data/movie_suppliers" "$tmp/movie_suppliers" &&
        printf '%s\n' "$2" >"$data/movie_suppliers/.$1.tmp" &&
        mv -f "$data/movie_suppliers/.$1.tmp" "$data/movie_suppliers/$1" &&
        cp -f "$data/movie_suppliers/$1" "$tmp/movie_suppliers/$1"; then
        echo "$name: $1 shown"
    else
        rm -f "$data/movie_suppliers/.$1.tmp"
        echo "$name: failed to write $1"
        failed=1
    fi
}

hide() {
    rm -f "$data/movie_suppliers/$1" "$tmp/movie_suppliers/$1"
    echo "$name: $1 hidden"
}

# id:package; an empty package: a Dune plugin, not an Android app (Filmix:
# Filmix_API, Bazinga: Bazinga3).
for app in num:ru.yourok.num lampa:top.rootu.lampa bylampa:top.rootu.bylumpa \
    lampa_atv:top.rootu.lumpa prisma:top.rootu.prisma vokino:ru.vokino.web \
    lazymedia:com.lazycatsoftware.lmd filmix_api: stremio:com.stremio.one \
    nuvio:com.nuvio.tv freezona:free.zona alpac:cc.alcopa.tv flux:app.flux.tv \
    seasonhit:com.jimdo.xakerd.season2hit bazinga:; do
    id=${app%%:*}
    pkg=${app#*:}

    if [ -z "$pkg" ]; then
        # The Dune plugin's folder; an unknown id: none, not installed.
        dplug=''
        case $id in
            filmix_api) dplug=Filmix_api ;;
            bazinga) dplug=Bazinga3 ;;
        esac
        installed=0
        [ -n "$dplug" ] && [ -f "$plugins/$dplug/dune_plugin.xml" ] && installed=1
    elif [ "$apps_known" = 1 ]; then
        installed=0
        grep -q "\"package_name\": *\"$(printf '%s' "$pkg" | sed 's/\./\\./g')\"" "$apps" && installed=1
    else
        echo "$name: no app list, $id left as is"
        continue
    fi

    # "hidden" holds one id per line, written by main.php; other lines are ignored.
    if [ "$installed" = 0 ] || grep -qxF "$id" "$data/hidden" 2>/dev/null; then
        hide "$id"
    elif [ -z "$pkg" ]; then
        # Choosing the item runs play_action (main.php); bin only answers if
        # the shell ever ignores play_action. The icon is the plugin's own.
        show "$id" "$(printf '{"plugin":"%s","caption":"%%tr%%%s_caption","langs":"any","supported_video_types":"video","bin":"sh %s/%s.sh","playback_type":"app","icon_url":"plugin_file://%%%s%%/icons/logo.png","play_action":{"handler_string_id":"plugin_handle_user_input","plugin_name":"%s","params":{"handler_id":"%s","control_id":"play"}}}' \
            "$name" "$id" "$mydir" "$id" "$dplug" "$name" "$id")"
    else
        show "$id" "$(printf '{"plugin":"%s","caption":"%%tr%%%s_caption","langs":"any","supported_video_types":"video","bin":"sh %s/%s.sh","playback_type":"app","icon_url":"file://%s"}' \
            "$name" "$id" "$mydir" "$id" "$(icon "$pkg")")"
    fi
done

# IPTV Channel Editor builds. Choosing the item runs play_action, as
# Bazinga's; the handler (main.php) takes the build from handler_id. The
# caption and the icon are the build's own.
shown=
for b in $(iptvce_builds "$plugins"); do
    id=iptvce_$b
    grep -qxF "$id" "$data/hidden" 2>/dev/null && continue
    cap=$(iptvce_caption "$plugins/$b" "$b" | LC_ALL=C sed 's/\\/\\\\/g; s/"/\\"/g')
    icon=$(iptvce_icon "$plugins/$b")
    [ -z "$icon" ] || icon=$(printf '"icon_url":"plugin_file://%%%s%%/%s",' "$b" "$icon")
    show "$id" "$(printf '{"plugin":"%s","caption":"%s","langs":"any","supported_video_types":"video","bin":"sh %s/iptvce.sh","playback_type":"app",%s"play_action":{"handler_string_id":"plugin_handle_user_input","plugin_name":"%s","params":{"handler_id":"%s","control_id":"play"}}}' \
        "$name" "$cap" "$mydir" "$icon" "$name" "$id")"
    shown="$shown $id"
done
# The items of builds that are gone or hidden; only our own copies, as in
# uninstall.sh.
for f in "$data/movie_suppliers"/iptvce_* "$tmp/movie_suppliers"/iptvce_*; do
    case " $shown " in
        *" ${f##*/} "*) ;;
        *)
            if grep -q '"plugin":"play_in_apps"' "$f" 2>/dev/null; then
                rm -f "$f"
                echo "$name: ${f##*/} hidden"
            fi
            ;;
    esac
done

exit "$failed"
