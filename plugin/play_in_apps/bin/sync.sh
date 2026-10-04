#!/bin/sh
# Shows the "Play..." item of every app that is installed and not hidden on
# the plugin screen, removes the others. A shown item is the supplier JSON in
# plugins_data/<plugin>/movie_suppliers/<id> (the shell copies it to
# /tmp/movie_suppliers/ on every boot) plus the same copy in
# /tmp/movie_suppliers/<id> (the menu rereads it for every card).
# Runs from movie_suppliers_update.sh, on early_gui_start and from the screen
# (main.php). Output is for running it by hand.

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

# Without the shell's app list (missing, empty or not written yet) nothing is
# known about Android apps: their items stay as they are.
apps_known=0
grep -q '"package_name"' "$apps" 2>/dev/null && apps_known=1

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

# id:package; Filmix is the Filmix_API Dune plugin, not an Android app.
for app in num:ru.yourok.num lampa:top.rootu.lampa prisma:top.rootu.prisma \
    vokino:ru.vokino.web lazymedia:com.lazycatsoftware.lmd filmix_api: \
    stremio:com.stremio.one nuvio:com.nuvio.tv; do
    id=${app%%:*}
    pkg=${app#*:}

    if [ -z "$pkg" ]; then
        installed=0
        [ -f "$plugins/Filmix_api/dune_plugin.xml" ] && installed=1
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
        # the shell ever ignores play_action. The icon is Filmix_API's own.
        show "$id" "$(printf '{"plugin":"%s","caption":"%%tr%%%s_caption","langs":"any","supported_video_types":"video","bin":"sh %s/%s.sh","playback_type":"app","icon_url":"plugin_file://%%Filmix_api%%/icons/logo.png","play_action":{"handler_string_id":"plugin_handle_user_input","plugin_name":"%s","params":{"handler_id":"%s","control_id":"play"}}}' \
            "$name" "$id" "$mydir" "$id" "$name" "$id")"
    else
        show "$id" "$(printf '{"plugin":"%s","caption":"%%tr%%%s_caption","langs":"any","supported_video_types":"video","bin":"sh %s/%s.sh","playback_type":"app","icon_url":"file://%s"}' \
            "$name" "$id" "$mydir" "$id" "$(icon "$pkg")")"
    fi
done

exit "$failed"
