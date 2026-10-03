#!/bin/sh
# Called by shell_ext async_worker after install and whenever version_index
# changes: movie_suppliers_update.sh <id> <caption> [...]. Arguments are ignored:
# the plugin registers exactly one supplier. The shell copies the written file
# to /tmp/movie_suppliers/ on every boot.
# Choosing the item runs play_action (main.php of this plugin) instead of bin;
# bin only answers if the shell ever ignores play_action. The icon is
# Filmix_API's own.
# Output is not logged anywhere; the messages are for running it by hand.

name=filmix_api_supplier
id=filmix_api

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
    printf '{"plugin":"%s","caption":"%%tr%%supplier_caption","langs":"any","supported_video_types":"video","bin":"sh %s/supplier.sh","playback_type":"app","icon_url":"plugin_file://%%Filmix_api%%/icons/logo.png","play_action":{"handler_string_id":"plugin_handle_user_input","plugin_name":"%s","params":{"handler_id":"filmix_api","control_id":"play"}}}\n' \
        "$name" "$mydir" "$name" >"$tmp" &&
    mv -f "$tmp" "$dir/$id"; then
    echo "$name: supplier $id written"
else
    rm -f "$tmp"
    echo "$name: failed to write supplier $id"
    exit 1
fi
