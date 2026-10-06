#!/bin/sh
# Build dist/dune_plugin_<name>_<version>.zip from plugin/<name> once
# tests/<name>_test.sh and shellcheck pass. Version comes from dune_plugin.xml.
# A plugin with <check_update> in its manifest also gets its online update
# channel in dist/pages/<name>/: the same files as .tar.gz (the updater takes
# tar.gz only) and update_info.xml (schema 2). dist/pages is the Pages site root.
# Usage: sh build.sh <name>, e.g. sh build.sh play_in_apps

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
manifest="$src/dune_plugin.xml"
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' "$manifest")
out="$root/dist/dune_plugin_${name}_$version.zip"

# Optional parts of a plugin: the CGI page (www/cgi-bin holds only sh
# wrappers, run by the shell as `sh <file>`; PHP and php.ini are in cgi/) and
# third-party code in its own dir with its license.
extra_dirs=$(cd "$src" && for d in cgi qrcode www; do if [ -d "$d" ]; then echo "$d"; fi; done)
# The shell runs every file of www/cgi-bin as root: only the logs wrapper.
if [ -e "$src/www/cgi-bin" ]; then
    cgi_list=$(ls -A "$src/www/cgi-bin" 2>&1 || true)
    if [ "$cgi_list" != logs ] || [ -L "$src/www/cgi-bin/logs" ] || [ ! -f "$src/www/cgi-bin/logs" ]; then
        echo "plugin/$name/www/cgi-bin may hold only the file logs, it has: $(printf '%s ' "$cgi_list" | tr '\n' ' ')" >&2
        exit 1
    fi
fi
cgi_bins=$(find "$src/www/cgi-bin" -type f 2>/dev/null || true)
# shellcheck disable=SC2086 # one word per file
shellcheck -s sh "$src"/bin/*.sh "$test" $cgi_bins
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
# PHP plugins also ship their top-level *.php (names are plain words).
php_files=$(cd "$src" && find . -maxdepth 1 -name '*.php' | sed 's:^\./::')
# shellcheck disable=SC2086 # one word per file
(cd "$src" && zip -q -X -r "$out" dune_plugin.xml bin icons translations LICENSE $php_files $extra_dirs -x '*.DS_Store' '*/._*')
unzip -l "$out"

# No leftovers of an earlier build, with or without <check_update> now.
pages="$root/dist/pages/$name"
rm -rf "$pages"
grep -q '<check_update>' "$manifest" || exit 0

# --- Online update channel (check_update schema 2).

fail() {
    echo "update channel: $*" >&2
    exit 1
}
# tag <name> <file>: text of the first <name>...</name> written on one line.
tag() { sed -n "s:.*<$1>\(.*\)</$1>.*:\1:p" "$2" | head -n 1; }
md5_of() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum <"$1" | cut -c 1-32
    else
        md5 -q "$1"
    fi
}

[ "$(tag name "$manifest")" = "$name" ] || fail "manifest <name> is not $name"
vi=$(tag version_index "$manifest")
case "$vi" in '' | 0* | *[!0-9]*) fail "bad version_index '$vi'" ;; esac
case "$version" in '' | *[!0-9A-Za-z.-]*) fail "bad version '$version'" ;; esac
channel=$(sed -n '/<check_update>/,/<\/check_update>/s:.*<url>\(.*\)</url>.*:\1:p' "$manifest")
# The site serves dist/pages as is, so the URL must end in <name>/update_info.xml.
case "$channel" in
    https://*/"$name"/update_info.xml) ;;
    *) fail "check_update url '$channel' is not https://.../$name/update_info.xml" ;;
esac
caption=$(sed -n 's/^plugin_caption = //p' "$src/translations/dune_language_russian.txt" |
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')
[ -n "$caption" ] || fail "no plugin_caption in translations/dune_language_russian.txt"

archive="dune_plugin_${name}_$version.tar.gz"
tgz="$pages/$archive"
info="$pages/update_info.xml"
url="${channel%/update_info.xml}/$archive"
mkdir -p "$pages"

# The zip's files, directories included, as paths from the plugin root.
files=$(mktemp)
trap 'rm -f "$files"' EXIT
# shellcheck disable=SC2086 # one word per file
(cd "$src" && find dune_plugin.xml bin icons translations LICENSE $php_files $extra_dirs \
    ! -name .DS_Store ! -name '._*' | LC_ALL=C sort) >"$files"
if tar --version 2>/dev/null | grep -q 'GNU tar'; then
    set -- --format=gnu --owner=0 --group=0 --numeric-owner
else
    # bsdtar (macOS): no AppleDouble ._* entries, xattrs, ACLs or file flags.
    set -- --format=gnutar --uid 0 --gid 0 --numeric-owner \
        --no-mac-metadata --no-xattrs --no-acls --no-fflags
fi
(cd "$src" && COPYFILE_DISABLE=1 tar "$@" --no-recursion -cf "${tgz%.gz}" -T "$files")
# -n: no file name or time in the gzip header.
gzip -n -9 "${tgz%.gz}"
md5=$(md5_of "$tgz")
size=$(cd "$src" && while IFS= read -r f; do [ -d "$f" ] || cat "$f"; done <"$files" | wc -c | tr -d ' ')

printf '%s\n' \
    '<dune_plugin_update_info>' \
    '  <schema>2</schema>' \
    "  <name>$name</name>" \
    '  <plugin_version_descriptor>' \
    "    <version_index>$vi</version_index>" \
    "    <version>$version</version>" \
    '    <beta>no</beta>' \
    '    <critical>no</critical>' \
    "    <url>$url</url>" \
    "    <md5>$md5</md5>" \
    "    <size>$size</size>" \
    "    <caption>$caption $version</caption>" \
    '  </plugin_version_descriptor>' \
    '</dune_plugin_update_info>' >"$info"

# A wrong archive or update_info means "update available" forever or
# "checksum error" on every Dune, so check what was written.
listing=$(tar -tzf "$tgz")
[ "$(printf '%s\n' "$listing" | LC_ALL=C sort)" = "$(unzip -Z1 "$out" | LC_ALL=C sort)" ] ||
    fail "$archive and the zip hold different files"
printf '%s\n' "$listing" | grep -qx 'dune_plugin.xml' || fail "no dune_plugin.xml in the root of $archive"
if printf '%s\n' "$listing" | grep -q '^\./\|^/\|\(^\|/\)\._\|\.DS_Store'; then
    fail "$archive has ./, /, ._* or .DS_Store entries"
fi
[ "$(tar -xzOf "$tgz" dune_plugin.xml | sed -n 's:.*<version_index>\(.*\)</version_index>.*:\1:p')" = "$vi" ] ||
    fail "version_index in $archive differs from plugin/$name"
[ "$(tag md5 "$info")" = "$(md5_of "$tgz")" ] || fail "md5 in update_info.xml is not the archive's"
[ "$(tag name "$info")" = "$name" ] || fail "name in update_info.xml is not $name"
[ "$(tag version_index "$info")" = "$vi" ] || fail "version_index in update_info.xml is not $vi"
[ "$(tag url "$info")" = "${channel%update_info.xml}$archive" ] || fail "url in update_info.xml is not next to it"
echo "update channel: dist/pages/$name/$archive ($size bytes unpacked), update_info.xml:"
cat "$info"
