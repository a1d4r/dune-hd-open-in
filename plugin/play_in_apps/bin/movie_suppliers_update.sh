#!/bin/sh
# Called by shell_ext async_worker after install and whenever version_index
# changes: movie_suppliers_update.sh <id> <caption> [...]. Arguments are
# ignored: sync.sh decides which items to show.

sh "$(dirname "$0")/sync.sh"
