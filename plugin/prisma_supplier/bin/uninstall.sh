#!/bin/sh
# global_actions/uninstall. The shell removes the plugin's own files, but not
# the supplier copy in /tmp: without this the menu item stays until reboot.

rm -f "${PRISMA_TMP:-/tmp}/movie_suppliers/prisma"
