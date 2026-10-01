#!/bin/sh
# Called by shell_ext async_worker after install and whenever version_index
# changes: movie_suppliers_update.sh <id> <caption> [...]. Arguments are ignored:
# the plugin registers exactly one supplier. The shell copies the written file
# to /tmp/movie_suppliers/ on every boot. The icon is Stremio's own, from the
# cache the shell fills for its Applications menu (same file:// form).
# Output is not logged anywhere; the messages are for running it by hand.

name=stremio_supplier
id=stremio

# FS_PREFIX goes into JSON (icon path).
case "$FS_PREFIX" in
    /*[!A-Za-z0-9/._-]* | [!/]* | '')
        echo "$name: FS_PREFIX is empty, relative or unsafe, nothing written"
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

dir="$FS_PREFIX/flashdata/plugins_data/$name/movie_suppliers"
tmp="$dir/.$id.tmp"

if mkdir -p "$dir" &&
    printf '{"plugin":"%s","caption":"%%tr%%supplier_caption","langs":"any","supported_video_types":"video","bin":"sh %s/supplier.sh","playback_type":"app","icon_url":"file://%s/tmp/applications/icon_cache/icon_com.stremio.one.png"}\n' \
        "$name" "$mydir" "$FS_PREFIX" >"$tmp" &&
    mv -f "$tmp" "$dir/$id"; then
    echo "$name: supplier $id written"
else
    rm -f "$tmp"
    echo "$name: failed to write supplier $id"
    exit 1
fi
