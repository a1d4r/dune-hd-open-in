#!/bin/sh
# Tests for plugin/nuvio_supplier. Run: dash tests/nuvio_supplier_test.sh
# TEST_SH selects the shell used to run plugin scripts (default: dash).

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/plugin/nuvio_supplier"
fx="$root/tests/fixtures"
sh_bin=${TEST_SH:-dash}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Plugin copy at a device-like path; FS_PREFIX and NUVIO_TMP point into $work.
FS_PREFIX="$work/fs"
NUVIO_TMP="$work/tmp"
export FS_PREFIX NUVIO_TMP
plugin="$FS_PREFIX/flashdata/plugins/nuvio_supplier"
mkdir -p "$FS_PREFIX/flashdata/plugins" "$NUVIO_TMP/applications" "$NUVIO_TMP/movie_suppliers"
cp -R "$src" "$plugin"
bin="$plugin/bin"
reg="$FS_PREFIX/flashdata/plugins_data/nuvio_supplier/movie_suppliers"
apps="$NUVIO_TMP/applications/app_data.json"

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

# launch_is <uri>: launch reply for this URI, nothing else.
launch_is() {
    python3 - "$o" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
want = {
    "bin": "am start -a android.intent.action.VIEW -d '%s' -p com.nuvio.tv" % sys.argv[2],
    "package": "com.nuvio.tv",
    "title": "Nuvio",
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
want = {"error": {"message": "%%ext%%<key_global>nuvio_supplier_plugin_%s</key_global>" % sys.argv[2]}}
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

# --- supplier.sh: real inputs and inputs derived from them
cp "$fx/app_data.json" "$apps"
supplier "$fx/movie.json" launch_is nuvio://movie/tt9218128
supplier "$fx/series.json" launch_is nuvio://series/tt11198330
supplier "$fx/movie_tmdb_only.json" launch_is nuvio://tmdb/movie/558449
supplier "$fx/series_tmdbtv_only.json" launch_is nuvio://tmdb/series/94997
check "supplier writes uri to stderr" grep -q 'uri: nuvio://tmdb/series/94997' "$o.err"
supplier "$fx/movie_no_ids.json" error_is err_no_id
supplier "$fx/series_no_ids.json" error_is err_no_id
# TMDB movie and TV ids overlap: a series with a movie tmdb id is not opened.
supplier "$fx/series_movie_tmdb_only.json" error_is err_no_id

# --- Nuvio not installed
cp "$fx/app_data_no_nuvio.json" "$apps"
supplier "$fx/movie.json" error_is err_not_installed
rm -f "$apps"
supplier "$fx/movie.json" error_is err_not_installed
cp "$fx/app_data.json" "$apps"

# --- NUVIO_TMP unset: app_data.json is under $FS_PREFIX/tmp (no /tmp root on Android TV)
mkdir -p "$work/atv/tmp/applications" "$work/atv_none/tmp"
cp "$fx/app_data.json" "$work/atv/tmp/applications/app_data.json"
env -u NUVIO_TMP FS_PREFIX="$work/atv" "$sh_bin" "$bin/supplier.sh" start_playback_app <"$fx/movie.json" >"$o" 2>"$o.err"
check "NUVIO_TMP unset: app_data.json from \$FS_PREFIX/tmp" launch_is nuvio://movie/tt9218128
env -u NUVIO_TMP FS_PREFIX="$work/atv_none" "$sh_bin" "$bin/supplier.sh" start_playback_app <"$fx/movie.json" >"$o" 2>"$o.err"
check "NUVIO_TMP unset, no \$FS_PREFIX/tmp/applications: err_not_installed" error_is err_not_installed

# --- garbage and hostile inputs
hostile() {
    printf '%s\n' "$1" >"$work/in.json"
    supplier "$work/in.json" "$2" "$3"
}
: >"$work/empty"
supplier "$work/empty" error_is err_no_id
head -c 20000 /dev/urandom >"$work/random"
supplier "$work/random" error_is err_no_id
hostile 'not json at all' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt123'"'"';reboot;'"'"'","type":"single"}}' error_is err_no_id
# shellcheck disable=SC2016 # literal $(...) on purpose
hostile '{"movieInfo":{"movieExtId":"imdb:tt123 x,tmdb:1$(reboot)","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"xximdb:tt123,imdb:tt12345678901","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt1,imdb:tt2","type":"single"}}' launch_is nuvio://movie/tt1
hostile '{"movieInfo":{"movieExtId":"dunemdb:x,kinopoisk:1,imdb:tt0111161","type":"single"}}' launch_is nuvio://movie/tt0111161
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","type":"movie"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","type":"single;reboot"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt1"}}' error_is err_no_id
# Title text that looks like keys must not win over the real fields.
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","title":{"en":"\"type\":\"series\" \"movieExtId\":\"imdb:tt2\""},"type":"single"}}' launch_is nuvio://movie/tt1

# --- unexpected command line
for args in '' get_stream_url; do
    # shellcheck disable=SC2086 # split on purpose
    run supplier.sh $args <"$fx/movie.json"
    check "supplier args '$args': exit 0" rc_is 0
    check "supplier args '$args': err_unsupported" error_is err_unsupported
done

# --- movie_suppliers_update.sh
run movie_suppliers_update.sh nuvio nuvio
check "update: exit 0" rc_is 0
check "update: only the supplier file, no temp left" test "$(ls -A "$reg")" = nuvio
# The icon is the "icon" field of the fixture app_data.json.
check "update: supplier JSON" python3 - "$reg/nuvio" "$bin" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
want = {
    "plugin": "nuvio_supplier",
    "caption": "%tr%supplier_caption",
    "langs": "any",
    "supported_video_types": "video",
    "bin": "sh %s/supplier.sh" % sys.argv[2],
    "playback_type": "app",
    "icon_url": "file:///data/data/com.dunehd.app/tmp/applications/icon_cache/icon_com.nuvio.tv.png",
}
sys.exit(d != want)
EOF

# The shell runs "<bin> start_playback_app" via /bin/sh -c from cwd /.
cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bin"])' "$reg/nuvio")
(cd / && "$sh_bin" -c "$cmd start_playback_app" <"$fx/series.json" >"$o" 2>"$o.err")
check "registered bin opens series" launch_is nuvio://series/tt11198330

rm -rf "$reg"
run movie_suppliers_update.sh other other '../evil' x
check "update ignores args, writes only own id" test "$(ls -A "$reg")" = nuvio

# --- update: icon_url is "file://" + Nuvio's "icon" from app_data.json
# icon_is <icon_url>: update writes a valid supplier JSON with this icon_url.
icon_is() {
    rm -rf "$reg"
    run movie_suppliers_update.sh nuvio nuvio
    rc_is 0 && python3 - "$reg/nuvio" "$1" <<'EOF'
import json, sys
sys.exit(json.load(open(sys.argv[1]))["icon_url"] != sys.argv[2])
EOF
}
# apps_icon <icon> [flat]: app_data.json with Nuvio's "icon" set, "/" escaped as
# on the device; "flat": one line, "icon" before "package_name".
apps_icon() {
    python3 - "$fx/app_data.json" "$apps" "$@" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for a in d["applications"]:
    if a["package_name"] == "com.nuvio.tv":
        a["icon"] = sys.argv[3]
if sys.argv[4:] == ["flat"]:
    d["applications"] = [{"icon": a.pop("icon"), **a} for a in d["applications"]]
    out = json.dumps(d, ensure_ascii=False)
else:
    out = json.dumps(d, indent=2, ensure_ascii=False).replace("/", "\\/")
open(sys.argv[2], "w").write(out)
EOF
}
old="file://$FS_PREFIX/tmp/applications/icon_cache/icon_com.nuvio.tv.png"
# Dune HD Media Center installed as an app on Android TV keeps icons in flashdata.
atv=/data/data/com.dunehd.app/flashdata/applications/icon_cache/icon_com.nuvio.tv.png
apps_icon "$atv"
check "update: icon from app_data.json (Android TV)" icon_is "file://$atv"
apps_icon "$atv" flat
check "update: icon from app_data.json, other field order, one line" icon_is "file://$atv"
cp "$fx/app_data_no_nuvio.json" "$apps"
check "update: Nuvio not in app_data.json, icon_cache path" icon_is "$old"
for bad in '/data/x"y.png' '/data/x y.png' 'data/x.png' ''; do
    apps_icon "$bad"
    check "update: unsafe icon '$bad', icon_cache path" icon_is "$old"
done
rm -f "$apps"
check "update: no app_data.json, icon_cache path" icon_is "$old"

mkdir -p "$work/cwd"
for fp in relative '/data/x"y' '/data/x y'; do
    (cd "$work/cwd" && FS_PREFIX="$fp" "$sh_bin" "$bin/movie_suppliers_update.sh" nuvio nuvio >"$o" 2>&1)
    check "update FS_PREFIX='$fp': nothing written" dir_empty "$work/cwd"
done

# Older Android models leave FS_PREFIX unset: paths start at the root.
# NUVIO_FLASHDATA keeps the write inside $work instead of /flashdata. No
# app_data.json: the fallback icon path starts at the root too.
for fp in unset empty; do
    rm -rf "$reg"
    (
        cd "$work/cwd" || exit 1
        if [ "$fp" = unset ]; then unset FS_PREFIX; else FS_PREFIX=; fi
        NUVIO_FLASHDATA="$work/fs/flashdata" "$sh_bin" "$bin/movie_suppliers_update.sh" nuvio nuvio >"$o" 2>"$o.err"
        echo "$?" >"$o.rc"
    )
    check "update FS_PREFIX $fp: exit 0" rc_is 0
    check "update FS_PREFIX $fp: only the supplier file" test "$(ls -A "$reg")" = nuvio
    check "update FS_PREFIX $fp: supplier JSON, icon from /tmp" python3 - "$reg/nuvio" "$bin" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(not (d["plugin"] == "nuvio_supplier" and d["bin"] == "sh %s/supplier.sh" % sys.argv[2]
              and d["icon_url"] == "file:///tmp/applications/icon_cache/icon_com.nuvio.tv.png"))
EOF
    check "update FS_PREFIX $fp: nothing in cwd" dir_empty "$work/cwd"
done

unsafe="$work/bad dir"
mkdir -p "$unsafe"
cp -R "$src" "$unsafe/nuvio_supplier"
rm -rf "$reg"
"$sh_bin" "$unsafe/nuvio_supplier/bin/movie_suppliers_update.sh" nuvio nuvio >"$o" 2>&1
check "update from unsafe path: nothing written" no_file "$reg/nuvio"

# --- uninstall.sh
: >"$NUVIO_TMP/movie_suppliers/nuvio"
: >"$NUVIO_TMP/movie_suppliers/YouTube"
run uninstall.sh
check "uninstall: exit 0" rc_is 0
check "uninstall: supplier removed" no_file "$NUVIO_TMP/movie_suppliers/nuvio"
check "uninstall: other suppliers kept" test -e "$NUVIO_TMP/movie_suppliers/YouTube"
run uninstall.sh
check "uninstall twice: exit 0" rc_is 0
# NUVIO_TMP unset: the supplier copy is under $FS_PREFIX/tmp (no /tmp root on Android TV).
mkdir -p "$work/atv/tmp/movie_suppliers"
: >"$work/atv/tmp/movie_suppliers/nuvio"
env -u NUVIO_TMP FS_PREFIX="$work/atv" "$sh_bin" "$bin/uninstall.sh" >"$o" 2>"$o.err"
check "uninstall NUVIO_TMP unset: supplier removed from \$FS_PREFIX/tmp" no_file "$work/atv/tmp/movie_suppliers/nuvio"

# --- manifest and translations
check "manifest: supplier id and uninstall action" python3 - "$src/dune_plugin.xml" <<'EOF'
import re, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
ok = (r.findtext("name") == "nuvio_supplier"
      and r.findtext("type") == "plain"
      and r.findtext("params/movie_suppliers") == "nuvio"
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
