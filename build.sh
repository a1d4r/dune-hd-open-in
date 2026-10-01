#!/bin/sh
# Build dist/dune_plugin_<name>_<version>.zip from plugin/<name> once
# tests/<name>_test.sh and shellcheck pass. Version comes from dune_plugin.xml.
# Usage: sh build.sh <name>, e.g. sh build.sh nuvio_supplier

set -eu

root=$(cd "$(dirname "$0")" && pwd)
name=${1-}
case "$name" in
    '' | *[!abcdefghijklmnopqrstuvwxyz0123456789_]*)
        echo "usage: sh build.sh <name>, where plugin/<name> exists" >&2
        exit 2
        ;;
esac
src="$root/plugin/$name"
test="$root/tests/${name}_test.sh"
[ -d "$src" ] && [ -f "$test" ] || {
    echo "no plugin/$name or tests/${name}_test.sh" >&2
    exit 2
}
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' "$src/dune_plugin.xml")
out="$root/dist/dune_plugin_${name}_$version.zip"

shellcheck -s sh "$src"/bin/*.sh "$test"
dash "$test" >/dev/null || {
    echo "tests failed: dash tests/${name}_test.sh" >&2
    exit 1
}
# mksh is the shell on the device; run the tests under it too when available.
if command -v mksh >/dev/null 2>&1; then
    TEST_SH=mksh dash "$test" >/dev/null || {
        echo "tests failed: TEST_SH=mksh dash tests/${name}_test.sh" >&2
        exit 1
    }
fi

mkdir -p "$root/dist"
rm -f "$out"
(cd "$src" && zip -q -X -r "$out" dune_plugin.xml bin translations LICENSE -x '*.DS_Store' '*/._*')
unzip -l "$out"
