#!/bin/sh
# global_actions/uninstall. The shell removes the plugin's own files, but not
# the supplier copies in /tmp: without this the menu items stay until reboot.
# A copy written by an old single-app plugin with the same id is left alone.
# Also removes the shell's file of the item choice dialog (config_id
# play_in_apps), which lives outside the plugin's dirs.

dir=${PLAY_IN_APPS_TMP:-$FS_PREFIX/tmp}/movie_suppliers
for id in num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona; do
    grep -q '"plugin":"play_in_apps"' "$dir/$id" 2>/dev/null && rm -f "$dir/$id"
done
rm -f "$FS_PREFIX/config/lcfg_play_in_apps.txt"
exit 0
