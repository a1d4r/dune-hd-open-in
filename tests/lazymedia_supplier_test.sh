#!/bin/sh
# Tests for plugin/lazymedia_supplier. Run: dash tests/lazymedia_supplier_test.sh
# TEST_SH selects the shell used to run plugin scripts (default: dash).

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/plugin/lazymedia_supplier"
fx="$root/tests/fixtures"
sh_bin=${TEST_SH:-dash}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Plugin copy at a device-like path; FS_PREFIX and LAZYMEDIA_TMP point into $work.
FS_PREFIX="$work/fs"
LAZYMEDIA_TMP="$work/tmp"
export FS_PREFIX LAZYMEDIA_TMP
plugin="$FS_PREFIX/flashdata/plugins/lazymedia_supplier"
mkdir -p "$FS_PREFIX/flashdata/plugins" "$LAZYMEDIA_TMP/applications" "$LAZYMEDIA_TMP/movie_suppliers"
cp -R "$src" "$plugin"
bin="$plugin/bin"
reg="$FS_PREFIX/flashdata/plugins_data/lazymedia_supplier/movie_suppliers"
apps="$LAZYMEDIA_TMP/applications/app_data.json"

failed=0
check() {
    desc=$1
    shift
    if "$@" >/dev/null 2>&1; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        failed=1
    fi
}

o="$work/out"

# run <script> [args...]: stdin passes through; stdout/stderr/rc into $o*.
run() {
    script=$1
    shift
    "$sh_bin" "$bin/$script" "$@" >"$o" 2>"$o.err"
    echo "$?" >"$o.rc"
}

rc_is() { [ "$(cat "$o.rc")" = "$1" ]; }
no_file() { [ ! -e "$1" ]; }
dir_empty() { [ -z "$(ls -A "$1")" ]; }

# one_json: stdout is exactly one line holding one JSON object.
one_json() {
    [ "$(wc -l <"$o" | tr -d ' ')" = 1 ] &&
        python3 -c 'import json,sys; assert isinstance(json.load(open(sys.argv[1])), dict)' "$o"
}

# launch_is <query>: launch reply searching for this percent-encoded query.
launch_is() {
    python3 - "$o" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
want = {
    "bin": "am start --activity-clear-task 'intent:#Intent;component=com.lazycatsoftware.lmd/com.lazycatsoftware.lazymediadeluxe.ui.tv.activities.ActivityTvSearch;S.query=%s;end'" % sys.argv[2],
    "package": "com.lazycatsoftware.lmd",
    "title": "LazyMedia",
    "wait_app_start_delay": 10,
}
sys.exit(d != want)
EOF
}

# error_is <key>: error dialog with this plugin's translation key.
error_is() {
    python3 - "$o" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
want = {"error": {"message": "%%ext%%<key_global>lazymedia_supplier_plugin_%s</key_global>" % sys.argv[2]}}
sys.exit(d != want)
EOF
}

# supplier <stdin file> <check> <arg>: run supplier, check exit 0, one JSON, reply.
supplier() {
    run supplier.sh start_playback_app <"$1"
    check "$2 $3 ($(basename "$1")): exit 0" rc_is 0
    check "$2 $3 ($(basename "$1")): one line of JSON" one_json
    check "$2 $3 ($(basename "$1")): reply" "$2" "$3"
}

# search_is <title>: launch reply that searches LazyMedia for this title.
search_is() {
    launch_is "$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1")"
}

# --- supplier.sh: real inputs and inputs derived from them.
# IDs do not matter: always search by the Russian title.
cp "$fx/app_data.json" "$apps"
supplier "$fx/movie.json" search_is 'Гладиатор 2'
supplier "$fx/series.json" search_is 'Дом Дракона'
supplier "$fx/movie_tmdb_only.json" search_is 'Гладиатор 2'
supplier "$fx/series_tmdbtv_only.json" search_is 'Дом Дракона'
supplier "$fx/series_movie_tmdb_only.json" search_is 'Дом Дракона'
supplier "$fx/movie_no_ids.json" search_is 'Гладиатор 2'
supplier "$fx/series_no_ids.json" search_is 'Мастера меча онлайн: Алисизация '
check "supplier writes uri to stderr" grep -q 'uri: intent:#Intent;component=com.lazycatsoftware.lmd/.*;S.query=%D0%9C.*%20;end$' "$o.err"

# --- LazyMedia not installed (the other apps are)
cp "$fx/app_data_no_lazymedia.json" "$apps"
supplier "$fx/movie.json" error_is err_not_installed
rm -f "$apps"
supplier "$fx/movie.json" error_is err_not_installed
cp "$fx/app_data.json" "$apps"

# --- LAZYMEDIA_TMP unset: app_data.json is under $FS_PREFIX/tmp (no /tmp root on Android TV)
mkdir -p "$work/atv/tmp/applications" "$work/atv_none/tmp"
cp "$fx/app_data.json" "$work/atv/tmp/applications/app_data.json"
env -u LAZYMEDIA_TMP FS_PREFIX="$work/atv" "$sh_bin" "$bin/supplier.sh" start_playback_app <"$fx/movie.json" >"$o" 2>"$o.err"
check "LAZYMEDIA_TMP unset: app_data.json from \$FS_PREFIX/tmp" search_is 'Гладиатор 2'
env -u LAZYMEDIA_TMP FS_PREFIX="$work/atv_none" "$sh_bin" "$bin/supplier.sh" start_playback_app <"$fx/movie.json" >"$o" 2>"$o.err"
check "LAZYMEDIA_TMP unset, no \$FS_PREFIX/tmp/applications: err_not_installed" error_is err_not_installed

# --- garbage and hostile inputs
hostile() {
    printf '%s\n' "$1" >"$work/in.json"
    supplier "$work/in.json" "$2" "$3"
}
: >"$work/empty"
supplier "$work/empty" error_is err_no_title
head -c 20000 /dev/urandom >"$work/random"
supplier "$work/random" error_is err_no_title
hostile 'not json at all' error_is err_no_title
hostile '{"movieInfo":{"movieExtId":"imdb:tt9218128,tmdb:558449","type":"single"}}' error_is err_no_title
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","type":"single;reboot","title":{"ru":"x"}}}' launch_is x
# Title text that looks like keys must not win over the real fields.
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"en":"\"movieExtId\":\"imdb:tt2\"","ru":"\"title\":{\"ru\":\"evil\"}"}}}' search_is '"title":{"ru":"evil"}'
hostile '{"movieInfo":{"movieExtId":"","title":{"en":"a}b \"ru\":\"evil\"","ru":"good"}}}' search_is good
# Intent URI syntax inside the title stays inside S.query.
hostile '{"movieInfo":{"title":{"ru":"x;end;component=a/b;S.query=y#Intent"}}}' search_is 'x;end;component=a/b;S.query=y#Intent'

# --- titles: JSON escapes, raw UTF-8, percent-encoding, fallback to English
hostile '{"movieInfo":{"title":{"ru":"Дом Дракона"}}}' search_is 'Дом Дракона'
hostile '{"movieInfo":{"title":{"ru":"\u041F\u043f"}}}' search_is 'Пп'
hostile '{"movieInfo":{"title":{"ru":"Ocean\u0027s 11 & co \"x\" \\ \/\n\u00e9\u20AC?#%+=;"}}}' search_is "Ocean's 11 & co \"x\" \\ / é€?#%+=;"
# shellcheck disable=SC2016 # literal $(...) on purpose
hostile '{"movieInfo":{"title":{"ru":"$(reboot) `id` '"'"'q'"'"'"}}}' search_is '$(reboot) `id` '"'"'q'"'"
hostile '{"movieInfo":{"title":{"ru":"","en":"Gladiator II"}}}' search_is 'Gladiator II'
hostile '{"movieInfo":{"title":{"en":"Gladiator II"}}}' search_is 'Gladiator II'
hostile '{"movieInfo":{"title":{"ru":"~a-b_c.d"}}}' launch_is '~a-b_c.d'
hostile '{"movieInfo":{"title":{"ru":"a😀b"}}}' search_is 'a😀b'
# Escaped emoji (surrogate pairs) are dropped; broken escapes do not stop the rest.
hostile '{"movieInfo":{"title":{"ru":"a\ud83d\ude00b"}}}' search_is ab
hostile '{"movieInfo":{"title":{"ru":"a\u04Zz\q"}}}' search_is aZz
hostile '{"movieInfo":{"title":{"ru":"\ud83d\ude00"}}}' error_is err_no_title
hostile '{"movieInfo":{"title":{"ru":"\ud83d\ude00","en":"Fallback"}}}' search_is Fallback
hostile '{"movieInfo":{"title":{"ru":"unterminated\"}}}' error_is err_no_title
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"ru":"","en":""}}}' error_is err_no_title
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":"Gladiator"}}' error_is err_no_title
long=$(python3 -c 'print("\\u0416" * 300)')
hostile '{"movieInfo":{"title":{"ru":"'"$long"'"}}}' search_is "$(python3 -c 'print("Ж" * 100)')"


# --- unexpected command line
for args in '' get_stream_url; do
    # shellcheck disable=SC2086 # split on purpose
    run supplier.sh $args <"$fx/movie.json"
    check "supplier args '$args': exit 0" rc_is 0
    check "supplier args '$args': err_unsupported" error_is err_unsupported
done

# --- movie_suppliers_update.sh
run movie_suppliers_update.sh lazymedia lazymedia
check "update: exit 0" rc_is 0
check "update: only the supplier file, no temp left" test "$(ls -A "$reg")" = lazymedia
check "update: supplier JSON" python3 - "$reg/lazymedia" "$bin" "$FS_PREFIX" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
want = {
    "plugin": "lazymedia_supplier",
    "caption": "%tr%supplier_caption",
    "langs": "any",
    "supported_video_types": "video",
    "bin": "sh %s/supplier.sh" % sys.argv[2],
    "playback_type": "app",
    "icon_url": "file://%s/tmp/applications/icon_cache/icon_com.lazycatsoftware.lmd.png" % sys.argv[3],
}
sys.exit(d != want)
EOF

# The shell runs "<bin> start_playback_app" via /bin/sh -c from cwd /.
cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bin"])' "$reg/lazymedia")
(cd / && "$sh_bin" -c "$cmd start_playback_app" <"$fx/series.json" >"$o" 2>"$o.err")
check "registered bin searches series" search_is "Дом Дракона"

rm -rf "$reg"
run movie_suppliers_update.sh other other '../evil' x
check "update ignores args, writes only own id" test "$(ls -A "$reg")" = lazymedia

mkdir -p "$work/cwd"
for fp in relative '/data/x"y' '/data/x y'; do
    (cd "$work/cwd" && FS_PREFIX="$fp" "$sh_bin" "$bin/movie_suppliers_update.sh" lazymedia lazymedia >"$o" 2>&1)
    check "update FS_PREFIX='$fp': nothing written" dir_empty "$work/cwd"
done

# Older Android models leave FS_PREFIX unset: paths start at the root.
# LAZYMEDIA_FLASHDATA keeps the write inside $work instead of /flashdata.
for fp in unset empty; do
    rm -rf "$reg"
    (
        cd "$work/cwd" || exit 1
        if [ "$fp" = unset ]; then unset FS_PREFIX; else FS_PREFIX=; fi
        LAZYMEDIA_FLASHDATA="$work/fs/flashdata" "$sh_bin" "$bin/movie_suppliers_update.sh" lazymedia lazymedia >"$o" 2>"$o.err"
        echo "$?" >"$o.rc"
    )
    check "update FS_PREFIX $fp: exit 0" rc_is 0
    check "update FS_PREFIX $fp: only the supplier file" test "$(ls -A "$reg")" = lazymedia
    check "update FS_PREFIX $fp: supplier JSON, icon from /tmp" python3 - "$reg/lazymedia" "$bin" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(not (d["plugin"] == "lazymedia_supplier" and d["bin"] == "sh %s/supplier.sh" % sys.argv[2]
              and d["icon_url"] == "file:///tmp/applications/icon_cache/icon_com.lazycatsoftware.lmd.png"))
EOF
    check "update FS_PREFIX $fp: nothing in cwd" dir_empty "$work/cwd"
done

unsafe="$work/bad dir"
mkdir -p "$unsafe"
cp -R "$src" "$unsafe/lazymedia_supplier"
rm -rf "$reg"
"$sh_bin" "$unsafe/lazymedia_supplier/bin/movie_suppliers_update.sh" lazymedia lazymedia >"$o" 2>&1
check "update from unsafe path: nothing written" no_file "$reg/lazymedia"

# --- uninstall.sh
: >"$LAZYMEDIA_TMP/movie_suppliers/lazymedia"
: >"$LAZYMEDIA_TMP/movie_suppliers/YouTube"
run uninstall.sh
check "uninstall: exit 0" rc_is 0
check "uninstall: supplier removed" no_file "$LAZYMEDIA_TMP/movie_suppliers/lazymedia"
check "uninstall: other suppliers kept" test -e "$LAZYMEDIA_TMP/movie_suppliers/YouTube"
run uninstall.sh
check "uninstall twice: exit 0" rc_is 0
# LAZYMEDIA_TMP unset: the supplier copy is under $FS_PREFIX/tmp (no /tmp root on Android TV).
mkdir -p "$work/atv/tmp/movie_suppliers"
: >"$work/atv/tmp/movie_suppliers/lazymedia"
env -u LAZYMEDIA_TMP FS_PREFIX="$work/atv" "$sh_bin" "$bin/uninstall.sh" >"$o" 2>"$o.err"
check "uninstall LAZYMEDIA_TMP unset: supplier removed from \$FS_PREFIX/tmp" no_file "$work/atv/tmp/movie_suppliers/lazymedia"

# --- manifest and translations
check "manifest: supplier id and uninstall action" python3 - "$src/dune_plugin.xml" <<'EOF'
import re, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
ok = (r.findtext("name") == "lazymedia_supplier"
      and r.findtext("type") == "plain"
      and r.findtext("params/movie_suppliers") == "lazymedia"
      and r.findtext("global_actions/uninstall/data/run_string") == "bin/uninstall.sh"
      and re.fullmatch(r"\d+\.\d+\.\d+", r.findtext("version") or "")
      and re.fullmatch(r"\d+", r.findtext("version_index") or ""))
sys.exit(not ok)
EOF
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' "$src/dune_plugin.xml")
check "CHANGELOG has the manifest version" grep -q "^## $version" "$src/CHANGELOG.md"

keys=$(grep -ho 'err_[a-z_]*' "$src/bin/supplier.sh" | sort -u)
for lang in english russian; do
    tr_file="$src/translations/dune_language_$lang.txt"
    for key in plugin_caption supplier_caption $keys; do
        check "translation $lang: $key" grep -q "^$key = ." "$tr_file"
    done
done

if [ "$failed" -ne 0 ]; then
    echo "SOME TESTS FAILED"
    exit 1
fi
echo "ALL PASSED"
