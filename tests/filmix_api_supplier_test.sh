#!/bin/sh
# Tests for plugin/filmix_api_supplier. Run: dash tests/filmix_api_supplier_test.sh
# TEST_SH selects the shell used to run plugin scripts (default: dash).
# PHP selects the PHP CLI for main.php (default: php). The device runs PHP 5.6.

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/plugin/filmix_api_supplier"
fx="$root/tests/fixtures"
sh_bin=${TEST_SH:-dash}
php_bin=${PHP:-php}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Plugin copy at a device-like path; FS_PREFIX and FILMIX_API_TMP point into $work.
FS_PREFIX="$work/fs"
FILMIX_API_TMP="$work/tmp"
export FS_PREFIX FILMIX_API_TMP
plugins="$FS_PREFIX/flashdata/plugins"
plugin="$plugins/filmix_api_supplier"
mkdir -p "$plugins" "$FILMIX_API_TMP/movie_suppliers"
cp -R "$src" "$plugin"
bin="$plugin/bin"
reg="$FS_PREFIX/flashdata/plugins_data/filmix_api_supplier/movie_suppliers"

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

# --- main.php on a stub of the firmware PHP API (/firmware_ext/php/)
cat >"$work/fw_stub.php" <<'EOF'
<?php
define('PLUGIN_OP_HANDLE_USER_INPUT', 'handle_user_input');
define('PLUGIN_OUT_DATA_GUI_ACTION', 'gui_action');
define('PLUGIN_OPEN_FOLDER_ACTION_ID', 'plugin_open_folder');
define('PLUGIN_SHOW_ERROR_ACTION_ID', 'plugin_show_error');
class PluginOutputData
{
    const has_data = 'has_data';
    const data_type = 'data_type';
    const data = 'data';
    const plugin_cookies = 'plugin_cookies';
    const is_error = 'is_error';
    const error_action = 'error_action';
}
abstract class DunePluginFw
{
    public static $instance = null;
    public abstract function call_plugin($call_ctx_json);
}
function hd_print($str)
{
    fwrite(STDERR, "$str\n");
}
error_reporting(E_ALL);
ini_set('display_errors', 'stderr');
require $argv[1];
echo DunePluginFw::$instance->call_plugin(file_get_contents('php://stdin'));
EOF

# php_run <call ctx file>: stdout/stderr/rc of main.php into $o*.
php_run() {
    $php_bin "$work/fw_stub.php" "$plugin/main.php" <"$1" >"$o" 2>"$o.err"
    echo "$?" >"$o.rc"
}

# only_own_log: no PHP warnings/notices, only hd_print lines of the plugin.
only_own_log() { ! grep -v '^filmix_api_supplier: ' "$o.err"; }

# ctx <user_input file> [op]: plugin call context around user_input.
ctx() {
    python3 - "$1" "${2:-handle_user_input}" >"$work/ctx.json" <<'EOF'
import json, sys
print(json.dumps({"op_type_code": sys.argv[2],
                  "input_data": json.load(open(sys.argv[1])),
                  "plugin_cookies": {"k": "v"}}))
EOF
}

# out_is <expected action JSON or "none">: plugin output with this GUI action.
# media_url is compared as decoded JSON (PHP 5.6 escapes "/" and non-ASCII).
out_is() {
    python3 - "$o" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
try:
    d["data"]["data"]["media_url"] = json.loads(d["data"]["data"]["media_url"])
except (KeyError, TypeError):
    pass
want = {"has_data": False, "plugin_cookies": {"k": "v"},
        "is_error": False, "error_action": None}
if sys.argv[2] != "none":
    want.update(has_data=True, data_type="gui_action", data=json.loads(sys.argv[2]))
sys.exit(d != want)
EOF
}

search_json() {
    python3 -c 'import json, sys
print(json.dumps({"handler_string_id": "plugin_open_folder", "plugin_name": "Filmix_api",
    "data": {"media_url": {"screen_id": "vod_list", "category_id": "search",
        "genre_id": sys.argv[1]}, "caption": sys.argv[1]}}))' "$1"
}

error_json() {
    printf '{"handler_string_id":"plugin_show_error","data":{"fatal":false,"title":"%%tr%%%s"}}' "$1"
}

# handler <user_input file> <desc> <expected action JSON>
handler() {
    ctx "$1"
    php_run "$work/ctx.json"
    check "main.php $2: exit 0" rc_is 0
    check "main.php $2: stderr has only own log lines" only_own_log
    check "main.php $2: output" out_is "$3"
}

search() { handler "$1" "$2" "$(search_json "$3")"; }
error() { handler "$1" "$2" "$(error_json "$3")"; }

# user_input <movie_str JSON or raw value for movie_str>: user_input around it.
user_input() {
    python3 - "$1" >"$work/ui.json" <<'EOF'
import json, sys
print(json.dumps({"handler_id": "filmix_api", "control_id": "play", "supplier_id": "filmix_api",
                  "season": -1, "episode": -1, "movie_str": sys.argv[1]}))
EOF
}

php_ok=1
"$php_bin" -r 'exit(0);' >/dev/null 2>&1 || php_ok=0
check "PHP CLI available ($php_bin)" test "$php_ok" = 1

if [ "$php_ok" = 1 ]; then
    check "main.php: php -l" "$php_bin" -l "$src/main.php"

    # Filmix_API not installed yet.
    error "$fx/play_action_movie.json" "no Filmix_API" err_not_installed
    mkdir -p "$plugins/Filmix_api"
    error "$fx/play_action_movie.json" "Filmix_API dir without manifest" err_not_installed
    : >"$plugins/Filmix_api/dune_plugin.xml"

    # Real inputs from the device (probe log, 03.10.2026).
    search "$fx/play_action_movie.json" movie 'Прошлой ночью в Сохо'
    check "main.php logs the search to stderr" grep -q '^filmix_api_supplier: search: Прошлой ночью в Сохо$' "$o.err"
    search "$fx/play_action_series.json" series 'Дом Дракона'

    # Titles: fallback to the original title, trimming, hostile text.
    user_input '{"title":"","native_title":"Last Night in Soho"}'
    search "$work/ui.json" "empty title" 'Last Night in Soho'
    user_input '{"native_title":"Only Native"}'
    search "$work/ui.json" "no title" 'Only Native'
    user_input '{"title":"  Дом  ","native_title":"x"}'
    search "$work/ui.json" "title trimmed" 'Дом'
    # shellcheck disable=SC2016 # literal $(...) on purpose
    user_input '{"title":"\"},\"plugin_name\":\"evil\" ; $(reboot) `id` \\ /&?#%","native_title":"x"}'
    # shellcheck disable=SC2016 # literal $(...) on purpose
    search "$work/ui.json" "hostile title stays text" '"},"plugin_name":"evil" ; $(reboot) `id` \ /&?#%'
    user_input '{"title":"a😀b\ud83d\ude00c"}'
    search "$work/ui.json" "emoji" 'a😀b😀c'
    user_input '{"title":"ab\ud800cd"}'
    error "$work/ui.json" "lone surrogate" err_no_title
    user_input '{"title":2049}'
    search "$work/ui.json" "numeric title" 2049
    user_input '{"title":{"ru":"x"},"native_title":"Nested"}'
    search "$work/ui.json" "object title skipped" Nested
    user_input '{"title":["x"]}'
    error "$work/ui.json" "array title" err_no_title
    user_input '{"title":"   ","native_title":""}'
    error "$work/ui.json" "blank titles" err_no_title
    user_input '{"year":2021}'
    error "$work/ui.json" "no titles" err_no_title
    user_input 'not json'
    error "$work/ui.json" "movie_str not JSON" err_no_title
    user_input '"just a string"'
    error "$work/ui.json" "movie_str JSON string" err_no_title
    printf '%s\n' '{"handler_id":"filmix_api","control_id":"play"}' >"$work/ui.json"
    error "$work/ui.json" "no movie_str" err_no_title
    printf '%s\n' '{"handler_id":"filmix_api","movie_str":{"title":"obj"}}' >"$work/ui.json"
    error "$work/ui.json" "movie_str is an object" err_no_title

    # Not our call: no action, no error.
    printf '%s\n' '{"handler_id":"other","movie_str":"{\"title\":\"x\"}"}' >"$work/ui.json"
    handler "$work/ui.json" "other handler" none
    ctx "$fx/play_action_movie.json" get_folder_view
    php_run "$work/ctx.json"
    check "main.php other op: no action" out_is none
    for raw in '' 'garbage' '[]' '{"op_type_code":"handle_user_input"}' \
        '{"op_type_code":"handle_user_input","input_data":"x"}'; do
        printf '%s' "$raw" >"$work/raw.json"
        php_run "$work/raw.json"
        check "main.php raw '$raw': exit 0" rc_is 0
        check "main.php raw '$raw': has_data false" python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(d["has_data"] is not False)' "$o"
    done
fi

# --- supplier.sh: answers only if play_action was ignored
for args in start_playback_app '' get_stream_url; do
    # shellcheck disable=SC2086 # split on purpose
    run supplier.sh $args <"$fx/movie.json"
    check "supplier args '$args': exit 0" rc_is 0
    check "supplier args '$args': one line of JSON" one_json
    check "supplier args '$args': err_unsupported" python3 - "$o" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(d != {"error": {"message": "%ext%<key_global>filmix_api_supplier_plugin_err_unsupported</key_global>"}})
EOF
done
run supplier.sh start_playback_app </dev/null
check "supplier empty stdin: exit 0" rc_is 0
check "supplier empty stdin: one line of JSON" one_json

# --- movie_suppliers_update.sh
run movie_suppliers_update.sh filmix_api filmix_api
check "update: exit 0" rc_is 0
check "update: only the supplier file, no temp left" test "$(ls -A "$reg")" = filmix_api
check "update: supplier JSON" python3 - "$reg/filmix_api" "$bin" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
want = {
    "plugin": "filmix_api_supplier",
    "caption": "%tr%supplier_caption",
    "langs": "any",
    "supported_video_types": "video",
    "bin": "sh %s/supplier.sh" % sys.argv[2],
    "playback_type": "app",
    "icon_url": "plugin_file://%Filmix_api%/icons/logo.png",
    "play_action": {
        "handler_string_id": "plugin_handle_user_input",
        "plugin_name": "filmix_api_supplier",
        "params": {"handler_id": "filmix_api", "control_id": "play"},
    },
}
sys.exit(d != want)
EOF

# The shell runs "<bin> start_playback_app" via /bin/sh -c from cwd /.
cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bin"])' "$reg/filmix_api")
(cd / && "$sh_bin" -c "$cmd start_playback_app" <"$fx/series.json" >"$o" 2>"$o.err")
check "registered bin answers with one JSON" one_json

rm -rf "$reg"
run movie_suppliers_update.sh other other '../evil' x
check "update ignores args, writes only own id" test "$(ls -A "$reg")" = filmix_api

mkdir -p "$work/cwd"
for fp in relative '/data/x"y' '/data/x y'; do
    (cd "$work/cwd" && FS_PREFIX="$fp" "$sh_bin" "$bin/movie_suppliers_update.sh" filmix_api filmix_api >"$o" 2>&1)
    check "update FS_PREFIX='$fp': nothing written" dir_empty "$work/cwd"
done

# Older Android models leave FS_PREFIX unset: paths start at the root.
# FILMIX_API_FLASHDATA keeps the write inside $work instead of /flashdata.
for fp in unset empty; do
    rm -rf "$reg"
    (
        cd "$work/cwd" || exit 1
        if [ "$fp" = unset ]; then unset FS_PREFIX; else FS_PREFIX=; fi
        FILMIX_API_FLASHDATA="$work/fs/flashdata" "$sh_bin" "$bin/movie_suppliers_update.sh" filmix_api filmix_api >"$o" 2>"$o.err"
        echo "$?" >"$o.rc"
    )
    check "update FS_PREFIX $fp: exit 0" rc_is 0
    check "update FS_PREFIX $fp: only the supplier file" test "$(ls -A "$reg")" = filmix_api
    check "update FS_PREFIX $fp: supplier JSON" python3 - "$reg/filmix_api" "$bin" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(not (d["plugin"] == "filmix_api_supplier" and d["bin"] == "sh %s/supplier.sh" % sys.argv[2]
              and d["icon_url"] == "plugin_file://%Filmix_api%/icons/logo.png"))
EOF
    check "update FS_PREFIX $fp: nothing in cwd" dir_empty "$work/cwd"
done

unsafe="$work/bad dir"
mkdir -p "$unsafe"
cp -R "$src" "$unsafe/filmix_api_supplier"
rm -rf "$reg"
"$sh_bin" "$unsafe/filmix_api_supplier/bin/movie_suppliers_update.sh" filmix_api filmix_api >"$o" 2>&1
check "update from unsafe path: nothing written" no_file "$reg/filmix_api"

# --- uninstall.sh
: >"$FILMIX_API_TMP/movie_suppliers/filmix_api"
: >"$FILMIX_API_TMP/movie_suppliers/YouTube"
run uninstall.sh
check "uninstall: exit 0" rc_is 0
check "uninstall: supplier removed" no_file "$FILMIX_API_TMP/movie_suppliers/filmix_api"
check "uninstall: other suppliers kept" test -e "$FILMIX_API_TMP/movie_suppliers/YouTube"
run uninstall.sh
check "uninstall twice: exit 0" rc_is 0
# FILMIX_API_TMP unset: the supplier copy is under $FS_PREFIX/tmp (no /tmp root on Android TV).
mkdir -p "$work/atv/tmp/movie_suppliers"
: >"$work/atv/tmp/movie_suppliers/filmix_api"
env -u FILMIX_API_TMP FS_PREFIX="$work/atv" "$sh_bin" "$bin/uninstall.sh" >"$o" 2>"$o.err"
check "uninstall FILMIX_API_TMP unset: supplier removed from \$FS_PREFIX/tmp" no_file "$work/atv/tmp/movie_suppliers/filmix_api"

# --- manifest and translations
check "manifest: php program, supplier id and uninstall action" python3 - "$src/dune_plugin.xml" <<'EOF'
import re, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
ok = (r.findtext("name") == "filmix_api_supplier"
      and r.findtext("type") == "php"
      and r.findtext("params/program") == "main.php"
      and r.findtext("params/movie_suppliers") == "filmix_api"
      and r.findtext("global_actions/uninstall/data/run_string") == "bin/uninstall.sh"
      and re.fullmatch(r"\d+\.\d+\.\d+", r.findtext("version") or "")
      and re.fullmatch(r"\d+", r.findtext("version_index") or ""))
sys.exit(not ok)
EOF
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' "$src/dune_plugin.xml")
check "CHANGELOG has the manifest version" grep -q "^## $version" "$src/CHANGELOG.md"

keys=$(grep -ho 'err_[a-z_]*' "$src/bin/supplier.sh" "$src/main.php" | sort -u)
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
