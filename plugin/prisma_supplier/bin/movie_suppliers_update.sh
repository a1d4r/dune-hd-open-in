#!/bin/sh
# Called by shell_ext async_worker after install and whenever version_index
# changes: movie_suppliers_update.sh <id> <caption> [...]. Arguments are ignored:
# the plugin registers exactly one supplier. The shell copies the written file
# to /tmp/movie_suppliers/ on every boot. The icon is Prisma's own: the "icon"
# path from the shell's app list, as in its Applications menu (file:// form).
# Output is not logged anywhere; the messages are for running it by hand.

name=prisma_supplier
id=prisma

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

# On Dune HD Media Center installed as an app on Android TV the icon is not
# in tmp/applications/icon_cache, so take it from app_data.json. Records are
# split at "}" so field order and layout do not matter.
icon=$(tr '\n}' ' \n' 2>/dev/null <"${PRISMA_TMP:-$FS_PREFIX/tmp}/applications/app_data.json" |
    grep '"package_name": *"top\.rootu\.prisma"' | grep -o '"icon": *"[^"]*"' | head -n 1 |
    sed 's/^[^:]*: *"//; s/"$//; s#\\/#/#g')
# The path goes into JSON.
case "$icon" in
    /*[!A-Za-z0-9/._-]* | [!/]* | '')
        icon="$FS_PREFIX/tmp/applications/icon_cache/icon_top.rootu.prisma.png"
        ;;
esac

dir="${PRISMA_FLASHDATA:-$FS_PREFIX/flashdata}/plugins_data/$name/movie_suppliers"
tmp="$dir/.$id.tmp"

if mkdir -p "$dir" &&
    printf '{"plugin":"%s","caption":"%%tr%%supplier_caption","langs":"any","supported_video_types":"video","bin":"sh %s/supplier.sh","playback_type":"app","icon_url":"file://%s"}\n' \
        "$name" "$mydir" "$icon" >"$tmp" &&
    mv -f "$tmp" "$dir/$id"; then
    echo "$name: supplier $id written"
else
    rm -f "$tmp"
    echo "$name: failed to write supplier $id"
    exit 1
fi
