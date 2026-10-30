#!/bin/sh
# Called by shell_ext async_worker after install, when version_index changes
# and on every change of the plugin list (see sync.sh):
# movie_suppliers_update.sh <id> <caption> [...]. Arguments are ignored:
# sync.sh decides which items to show.

sh "$(dirname "$0")/sync.sh"
