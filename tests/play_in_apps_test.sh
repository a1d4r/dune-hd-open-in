#!/bin/sh
# Tests for plugin/play_in_apps. Run: dash tests/play_in_apps_test.sh
# TEST_SH selects the shell used to run plugin scripts (default: dash).
# PHP selects the PHP CLI for main.php (default: php). The device runs PHP 5.3.6:
# tests/php53/Dockerfile has it with the other tools (see the comment there).

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/plugin/play_in_apps"
fx="$root/tests/fixtures"
sh_bin=${TEST_SH:-dash}
php_bin=${PHP:-php}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Plugin copy at a device-like path; FS_PREFIX and PLAY_IN_APPS_TMP point into $work.
FS_PREFIX="$work/fs"
PLAY_IN_APPS_TMP="$work/tmp"
export FS_PREFIX PLAY_IN_APPS_TMP
plugins="$FS_PREFIX/flashdata/plugins"
plugin="$plugins/play_in_apps"
mkdir -p "$plugins" "$PLAY_IN_APPS_TMP/applications" "$PLAY_IN_APPS_TMP/movie_suppliers"
cp -R "$src" "$plugin"
bin="$plugin/bin"
data="$FS_PREFIX/flashdata/plugins_data/play_in_apps"
reg="$data/movie_suppliers"
menu="$PLAY_IN_APPS_TMP/movie_suppliers"
apps="$PLAY_IN_APPS_TMP/applications/app_data.json"

android="num lampa prisma vokino lazymedia stremio nuvio"
all="num lampa prisma vokino lazymedia filmix_api stremio nuvio"

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
# listing_is <dir> <names...>: exactly these files in dir (sorted, no temp files).
listing_is() {
    d=$1
    shift
    # shellcheck disable=SC2012 # plain file names only
    [ "$(ls -A "$d" | LC_ALL=C sort | tr '\n' ' ')" = "$(printf '%s\n' "$@" | LC_ALL=C sort | tr '\n' ' ')" ]
}

# one_json: stdout is exactly one line holding one JSON object.
one_json() {
    [ "$(wc -l <"$o" | tr -d ' ')" = 1 ] &&
        python3 -c 'import json,sys; assert isinstance(json.load(open(sys.argv[1])), dict)' "$o"
}

# --- item scripts bin/<id>.sh. $id is the app under test.

# launch_is <uri>: launch reply of app $id for this URI, nothing else. For
# LazyMedia the argument is the percent-encoded search query.
launch_is() {
    python3 - "$o" "$id" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
app, arg = sys.argv[2], sys.argv[3]
pkg, title, flags = {
    "nuvio": ("com.nuvio.tv", "Nuvio", ""),
    "stremio": ("com.stremio.one", "Stremio", ""),
    "num": ("ru.yourok.num", "NUM", "--activity-clear-task "),
    "lampa": ("top.rootu.lampa", "Lampa", "--activity-clear-task "),
    "prisma": ("top.rootu.prisma", "Prisma", "--activity-clear-task "),
    "vokino": ("ru.vokino.web", "VoKino", "--activity-clear-task "),
    "lazymedia": ("com.lazycatsoftware.lmd", "LazyMedia", "--activity-clear-task "),
}[app]
if app == "lazymedia":
    cmd = ("am start --activity-clear-task 'intent:#Intent;component=com.lazycatsoftware.lmd/"
           "com.lazycatsoftware.lazymediadeluxe.ui.tv.activities.ActivityTvSearch;S.query=%s;end'" % arg)
else:
    cmd = "am start %s-a android.intent.action.VIEW -d '%s' -p %s" % (flags, arg, pkg)
sys.exit(d != {"bin": cmd, "package": pkg, "title": title, "wait_app_start_delay": 10})
EOF
}

# search_is <title>: launch reply of app $id that searches for this title.
search_is() {
    q=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1")
    case "$id" in
        vokino) launch_is "vokino://ru.vokino.web/search?name=$q" ;;
        *) launch_is "$q" ;;
    esac
}

# error_is <key>: error dialog with the translation key <id>_<key> of this plugin.
error_is() {
    python3 - "$o" "$id" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
want = {"error": {"message": "%%ext%%<key_global>play_in_apps_plugin_%s_%s</key_global>" % tuple(sys.argv[2:])}}
sys.exit(d != want)
EOF
}

# supplier <stdin file> <check> <arg>: run bin/$id.sh, check exit 0, one JSON, reply.
supplier() {
    run "$id.sh" start_playback_app <"$1"
    check "$id $2 $3 ($(basename "$1")): exit 0" rc_is 0
    check "$id $2 $3 ($(basename "$1")): one line of JSON" one_json
    check "$id $2 $3 ($(basename "$1")): reply" "$2" "$3"
}

hostile() {
    printf '%s\n' "$1" >"$work/in.json"
    supplier "$work/in.json" "$2" "$3"
}

: >"$work/empty"
head -c 20000 /dev/urandom >"$work/random"
mkdir -p "$work/atv/tmp/applications" "$work/atv_none/tmp"
cp "$fx/app_data.json" "$work/atv/tmp/applications/app_data.json"

# common <check> <arg> <no-data error key>: checks shared by all Android apps.
# <check> <arg> is the reply for movie.json.
common() {
    # App not installed (the apps before it in the fixture list are).
    cp "$fx/app_data_no_$id.json" "$apps"
    supplier "$fx/movie.json" error_is err_not_installed
    rm -f "$apps"
    supplier "$fx/movie.json" error_is err_not_installed
    cp "$fx/app_data.json" "$apps"

    # PLAY_IN_APPS_TMP unset: app_data.json is under $FS_PREFIX/tmp (no /tmp root on Android TV).
    env -u PLAY_IN_APPS_TMP FS_PREFIX="$work/atv" "$sh_bin" "$bin/$id.sh" start_playback_app <"$fx/movie.json" >"$o" 2>"$o.err"
    check "$id PLAY_IN_APPS_TMP unset: app_data.json from \$FS_PREFIX/tmp" "$1" "$2"
    env -u PLAY_IN_APPS_TMP FS_PREFIX="$work/atv_none" "$sh_bin" "$bin/$id.sh" start_playback_app <"$fx/movie.json" >"$o" 2>"$o.err"
    check "$id PLAY_IN_APPS_TMP unset, no \$FS_PREFIX/tmp/applications: err_not_installed" error_is err_not_installed

    # Garbage.
    supplier "$work/empty" error_is "$3"
    supplier "$work/random" error_is "$3"
    hostile 'not json at all' error_is "$3"

    # Unexpected command line.
    for args in '' get_stream_url; do
        # shellcheck disable=SC2086 # split on purpose
        run "$id.sh" $args <"$fx/movie.json"
        check "$id args '$args': exit 0" rc_is 0
        check "$id args '$args': err_unsupported" error_is err_unsupported
    done
}

cp "$fx/app_data.json" "$apps"

# --- nuvio: IMDb, else TMDB
id=nuvio
supplier "$fx/movie.json" launch_is nuvio://movie/tt9218128
supplier "$fx/series.json" launch_is nuvio://series/tt11198330
supplier "$fx/movie_tmdb_only.json" launch_is nuvio://tmdb/movie/558449
supplier "$fx/series_tmdbtv_only.json" launch_is nuvio://tmdb/series/94997
check "nuvio writes uri to stderr" grep -q 'uri: nuvio://tmdb/series/94997' "$o.err"
supplier "$fx/movie_no_ids.json" error_is err_no_id
supplier "$fx/series_no_ids.json" error_is err_no_id
# TMDB movie and TV ids overlap: a series with a movie tmdb id is not opened.
supplier "$fx/series_movie_tmdb_only.json" error_is err_no_id
common launch_is nuvio://movie/tt9218128 err_no_id
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

# --- stremio: IMDb, else TMDB; Nuvio also handles stremio: links
id=stremio
supplier "$fx/movie.json" launch_is stremio:///detail/movie/tt9218128
supplier "$fx/series.json" launch_is stremio:///detail/series/tt11198330
supplier "$fx/movie_tmdb_only.json" launch_is stremio:///detail/movie/tmdb:558449
supplier "$fx/series_tmdbtv_only.json" launch_is stremio:///detail/series/tmdb:94997
check "stremio writes uri to stderr" grep -q 'uri: stremio:///detail/series/tmdb:94997' "$o.err"
supplier "$fx/movie_no_ids.json" error_is err_no_id
supplier "$fx/series_no_ids.json" error_is err_no_id
supplier "$fx/series_movie_tmdb_only.json" error_is err_no_id
common launch_is stremio:///detail/movie/tt9218128 err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt123'"'"';reboot;'"'"'","type":"single"}}' error_is err_no_id
# shellcheck disable=SC2016 # literal $(...) on purpose
hostile '{"movieInfo":{"movieExtId":"imdb:tt123 x,tmdb:1$(reboot)","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"xximdb:tt123,imdb:tt12345678901","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt1,imdb:tt2","type":"single"}}' launch_is stremio:///detail/movie/tt1
hostile '{"movieInfo":{"movieExtId":"dunemdb:x,kinopoisk:1,imdb:tt0111161","type":"single"}}' launch_is stremio:///detail/movie/tt0111161
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","type":"movie"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","type":"single;reboot"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt1"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","title":{"en":"\"type\":\"series\" \"movieExtId\":\"imdb:tt2\""},"type":"single"}}' launch_is stremio:///detail/movie/tt1

# --- num, lampa, prisma: TMDB only, ids up to Java int
t=https://www.themoviedb.org
for id in num lampa prisma; do
    supplier "$fx/movie.json" launch_is "$t/movie/558449"
    supplier "$fx/series.json" launch_is "$t/tv/94997"
    supplier "$fx/movie_tmdb_only.json" launch_is "$t/movie/558449"
    supplier "$fx/series_tmdbtv_only.json" launch_is "$t/tv/94997"
    check "$id writes uri to stderr" grep -q "uri: $t/tv/94997" "$o.err"
    supplier "$fx/movie_no_ids.json" error_is err_no_id
    supplier "$fx/series_no_ids.json" error_is err_no_id
    supplier "$fx/series_movie_tmdb_only.json" error_is err_no_id
    common launch_is "$t/movie/558449" err_no_id
    hostile '{"movieInfo":{"movieExtId":"tmdb:123'"'"';reboot;'"'"'","type":"single"}}' error_is err_no_id
    # shellcheck disable=SC2016 # literal $(...) on purpose
    hostile '{"movieInfo":{"movieExtId":"tmdb:123 x,tmdb:1$(reboot)","type":"single"}}' error_is err_no_id
    hostile '{"movieInfo":{"movieExtId":"xxtmdb:123,tmdb:12345678901","type":"single"}}' error_is err_no_id
    # IMDb alone is not enough: these apps open titles only by TMDB ID.
    hostile '{"movieInfo":{"movieExtId":"dunemdb:x,imdb:tt9218128","type":"single"}}' error_is err_no_id
    hostile '{"movieInfo":{"movieExtId":"tmdb:1,tmdb:2","type":"single"}}' launch_is "$t/movie/1"
    hostile '{"movieInfo":{"movieExtId":"dunemdb:x,kinopoisk:1,imdb:tt0111161,tmdb:278","type":"single"}}' launch_is "$t/movie/278"
    hostile '{"movieInfo":{"movieExtId":"tmdbtv:1399,tmdb:278","type":"series"}}' launch_is "$t/tv/1399"
    hostile '{"movieInfo":{"movieExtId":"tmdb:278-slug,tmdb:12345678901","type":"single"}}' error_is err_no_id
    # The apps parse the id as a Java int (NUM could crash, Lampa drops it silently).
    hostile '{"movieInfo":{"movieExtId":"tmdb:9999999999","type":"single"}}' error_is err_no_id
    hostile '{"movieInfo":{"movieExtId":"tmdb:999999999","type":"single"}}' launch_is "$t/movie/999999999"
    hostile '{"movieInfo":{"movieExtId":"tmdb:1","type":"movie"}}' error_is err_no_id
    hostile '{"movieInfo":{"movieExtId":"tmdb:1","type":"single;reboot"}}' error_is err_no_id
    hostile '{"movieInfo":{"movieExtId":"tmdb:1"}}' error_is err_no_id
    hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"en":"\"type\":\"series\" \"movieExtId\":\"tmdbtv:2\""},"type":"single"}}' launch_is "$t/movie/1"
done

# titles <no-title error key> <launch_is prefix>: title parsing shared by VoKino
# and LazyMedia:
# JSON escapes, raw UTF-8, percent-encoding, fallback to English.
titles() {
    hostile '{"movieInfo":{"movieExtId":"","title":{"en":"a}b \"ru\":\"evil\"","ru":"good"}}}' search_is good
    hostile '{"movieInfo":{"title":{"ru":"Дом Дракона"}}}' search_is 'Дом Дракона'
    hostile '{"movieInfo":{"title":{"ru":"\u041F\u043f"}}}' search_is 'Пп'
    hostile '{"movieInfo":{"title":{"ru":"Ocean\u0027s 11 & co \"x\" \\ \/\n\u00e9\u20AC?#%+=;"}}}' search_is "Ocean's 11 & co \"x\" \\ / é€?#%+=;"
    # shellcheck disable=SC2016 # literal $(...) on purpose
    hostile '{"movieInfo":{"title":{"ru":"$(reboot) `id` '"'"'q'"'"'"}}}' search_is '$(reboot) `id` '"'"'q'"'"
    hostile '{"movieInfo":{"title":{"ru":"","en":"Gladiator II"}}}' search_is 'Gladiator II'
    hostile '{"movieInfo":{"title":{"en":"Gladiator II"}}}' search_is 'Gladiator II'
    # Unreserved characters are not percent-encoded.
    hostile '{"movieInfo":{"title":{"ru":"~a-b_c.d"}}}' launch_is "$2~a-b_c.d"
    hostile '{"movieInfo":{"title":{"ru":"a😀b"}}}' search_is 'a😀b'
    # Escaped emoji (surrogate pairs) are dropped; broken escapes do not stop the rest.
    hostile '{"movieInfo":{"title":{"ru":"a\ud83d\ude00b"}}}' search_is ab
    hostile '{"movieInfo":{"title":{"ru":"a\u04Zz\q"}}}' search_is aZz
    hostile '{"movieInfo":{"title":{"ru":"\ud83d\ude00"}}}' error_is "$1"
    hostile '{"movieInfo":{"title":{"ru":"\ud83d\ude00","en":"Fallback"}}}' search_is Fallback
    hostile '{"movieInfo":{"title":{"ru":"unterminated\"}}}' error_is "$1"
    hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"ru":"","en":""}}}' error_is "$1"
    hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":"Gladiator"}}' error_is "$1"
    long=$(python3 -c 'print("\\u0416" * 300)')
    hostile '{"movieInfo":{"title":{"ru":"'"$long"'"}}}' search_is "$(python3 -c 'print("Ж" * 100)')"
}

# --- vokino: IMDb for movies and series alike, else search by title
id=vokino
v=vokino://ru.vokino.web/view
supplier "$fx/movie.json" launch_is "$v/tt9218128"
supplier "$fx/series.json" launch_is "$v/tt11198330"
check "vokino writes uri to stderr" grep -q "uri: $v/tt11198330" "$o.err"
# No IMDb: search by the Russian title.
supplier "$fx/movie_tmdb_only.json" search_is 'Гладиатор 2'
supplier "$fx/series_tmdbtv_only.json" search_is 'Дом Дракона'
supplier "$fx/series_movie_tmdb_only.json" search_is 'Дом Дракона'
supplier "$fx/movie_no_ids.json" search_is 'Гладиатор 2'
supplier "$fx/series_no_ids.json" search_is 'Мастера меча онлайн: Алисизация '
check "vokino writes search uri to stderr" grep -q 'uri: vokino://ru.vokino.web/search?name=%D0%9C' "$o.err"
common launch_is "$v/tt9218128" err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt123'"'"';reboot;'"'"'","type":"single"}}' error_is err_no_id
# shellcheck disable=SC2016 # literal $(...) on purpose
hostile '{"movieInfo":{"movieExtId":"imdb:tt123 x,imdb:tt1$(reboot)","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"ximdb:tt123,imdb:tt12345678901,imdb:123","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"imdb:tt1,imdb:tt2","type":"single"}}' launch_is "$v/tt1"
hostile '{"movieInfo":{"movieExtId":"dunemdb:x,kinopoisk:1,tmdb:278,imdb:tt0111161","type":"single"}}' launch_is "$v/tt0111161"
# Type does not matter: VoKino opens movies and series by the same path.
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","type":"single;reboot"}}' launch_is "$v/tt1"
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","title":{"ru":"x"}}}' launch_is "$v/tt1"
# Title text that looks like keys must not win over the real fields.
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"en":"\"movieExtId\":\"imdb:tt2\"","ru":"\"title\":{\"ru\":\"evil\"}"}}}' search_is '"title":{"ru":"evil"}'
titles err_no_id "vokino://ru.vokino.web/search?name="

# --- lazymedia: no IDs, always search by the Russian title
id=lazymedia
supplier "$fx/movie.json" search_is 'Гладиатор 2'
supplier "$fx/series.json" search_is 'Дом Дракона'
supplier "$fx/movie_tmdb_only.json" search_is 'Гладиатор 2'
supplier "$fx/series_tmdbtv_only.json" search_is 'Дом Дракона'
supplier "$fx/series_movie_tmdb_only.json" search_is 'Дом Дракона'
supplier "$fx/movie_no_ids.json" search_is 'Гладиатор 2'
supplier "$fx/series_no_ids.json" search_is 'Мастера меча онлайн: Алисизация '
check "lazymedia writes uri to stderr" grep -q 'uri: intent:#Intent;component=com.lazycatsoftware.lmd/.*;S.query=%D0%9C.*%20;end$' "$o.err"
common search_is 'Гладиатор 2' err_no_title
hostile '{"movieInfo":{"movieExtId":"imdb:tt9218128,tmdb:558449","type":"single"}}' error_is err_no_title
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","type":"single;reboot","title":{"ru":"x"}}}' search_is x
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"en":"\"movieExtId\":\"imdb:tt2\"","ru":"\"title\":{\"ru\":\"evil\"}"}}}' search_is '"title":{"ru":"evil"}'
# Intent URI syntax inside the title stays inside S.query.
hostile '{"movieInfo":{"title":{"ru":"x;end;component=a/b;S.query=y#Intent"}}}' search_is 'x;end;component=a/b;S.query=y#Intent'
titles err_no_title ''

# --- filmix_api.sh: answers only if play_action was ignored
id=filmix_api
for args in start_playback_app '' get_stream_url; do
    # shellcheck disable=SC2086 # split on purpose
    run filmix_api.sh $args <"$fx/movie.json"
    check "filmix_api args '$args': exit 0" rc_is 0
    check "filmix_api args '$args': one line of JSON" one_json
    check "filmix_api args '$args': err_unsupported" error_is err_unsupported
done
run filmix_api.sh start_playback_app </dev/null
check "filmix_api empty stdin: exit 0" rc_is 0
check "filmix_api empty stdin: one line of JSON" one_json

# --- sync.sh: the item JSON of every app

# item_is <file> <id>: supplier JSON of app <id> with its bin and icon.
# FS_PREFIX in the icon path is the fixture's (from app_data.json).
item_is() {
    python3 - "$1" "$2" "$3" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
app, bindir = sys.argv[2], sys.argv[3]
pkg = {"nuvio": "com.nuvio.tv", "stremio": "com.stremio.one", "num": "ru.yourok.num",
       "lampa": "top.rootu.lampa", "prisma": "top.rootu.prisma", "vokino": "ru.vokino.web",
       "lazymedia": "com.lazycatsoftware.lmd"}.get(app)
want = {
    "plugin": "play_in_apps",
    "caption": "%%tr%%%s_caption" % app,
    "langs": "any",
    "supported_video_types": "video",
    "bin": "sh %s/%s.sh" % (bindir, app),
    "playback_type": "app",
}
if pkg:
    want["icon_url"] = "file:///data/data/com.dunehd.app/tmp/applications/icon_cache/icon_%s.png" % pkg
else:
    want["icon_url"] = "plugin_file://%Filmix_api%/icons/logo.png"
    want["play_action"] = {
        "handler_string_id": "plugin_handle_user_input",
        "plugin_name": "play_in_apps",
        "params": {"handler_id": "filmix_api", "control_id": "play"},
    }
sys.exit(d != want)
EOF
}

# shown <ids...>: exactly these items in plugins_data and in /tmp, same content.
shown() {
    listing_is "$reg" "$@" && listing_is "$menu" "$@" || return 1
    for i in "$@"; do
        cmp -s "$reg/$i" "$menu/$i" || return 1
    done
}

# Filmix_API is not installed yet.
run sync.sh
check "sync: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "sync: items of all Android apps, no Filmix, no temp files" shown $android
for i in $android; do
    check "sync: $i item JSON" item_is "$reg/$i" "$i" "$bin"
done
# The shell runs "<bin> start_playback_app" via /bin/sh -c from cwd /.
# opens_series <id> <check> <arg>: the registered bin of <id> gets series.json.
opens_series() {
    id=$1
    cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bin"])' "$menu/$id")
    (cd / && "$sh_bin" -c "$cmd start_playback_app" <"$fx/series.json" >"$o" 2>"$o.err")
    check "registered bin of $id opens series" "$2" "$3"
}
opens_series nuvio launch_is nuvio://series/tt11198330
opens_series stremio launch_is stremio:///detail/series/tt11198330
opens_series num launch_is "$t/tv/94997"
opens_series lampa launch_is "$t/tv/94997"
opens_series prisma launch_is "$t/tv/94997"
opens_series vokino launch_is "$v/tt11198330"
opens_series lazymedia search_is 'Дом Дракона'

mkdir -p "$plugins/Filmix_api"
run sync.sh
check "sync Filmix_API dir without manifest: no Filmix item" no_file "$reg/filmix_api"
: >"$plugins/Filmix_api/dune_plugin.xml"
run sync.sh
check "sync Filmix_API installed: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "sync Filmix_API installed: all items" shown $all
check "sync: filmix_api item JSON" item_is "$reg/filmix_api" filmix_api "$bin"
cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bin"])' "$menu/filmix_api")
(cd / && "$sh_bin" -c "$cmd start_playback_app" <"$fx/series.json" >"$o" 2>"$o.err")
id=filmix_api
check "registered bin of filmix_api: err_unsupported" error_is err_unsupported

# --- sync: hidden items
printf 'nuvio\nfilmix_api\n' >"$data/hidden"
run sync.sh
check "sync hidden: exit 0" rc_is 0
check "sync hidden: nuvio and filmix_api removed" shown num lampa prisma vokino lazymedia stremio
rm -f "$data/hidden"
run sync.sh
# shellcheck disable=SC2086 # one word per id
check "sync hidden list removed: all items back" shown $all

# A separate "Open in <app>" plugin keeps its copy with the same id in /tmp:
# a shown item is overwritten with ours, a hidden one is removed.
printf '{"plugin":"nuvio_supplier","caption":"%%tr%%supplier_caption"}\n' >"$menu/nuvio"
printf '{"plugin":"stremio_supplier","caption":"%%tr%%supplier_caption"}\n' >"$menu/stremio"
printf 'stremio\n' >"$data/hidden"
run sync.sh
check "sync over an old plugin's copy: shown item is ours" item_is "$menu/nuvio" nuvio "$bin"
check "sync over an old plugin's copy: hidden item removed" no_file "$menu/stremio"
rm -f "$data/hidden"
run sync.sh

# hidden is untrusted: only exact lines with known ids count.
{
    # shellcheck disable=SC2016 # literal $(...) on purpose
    printf ' nuvio\nNUVIO\nnuvio \n../stremio\nstremio\r\n$(reboot)\n*\n.*\nnum;lampa\n\n'
    head -c 3000 /dev/urandom
    printf '\nprisma\n'
} >"$data/hidden"
run sync.sh
check "sync garbage in hidden: exit 0" rc_is 0
check "sync garbage in hidden: only prisma hidden" shown num lampa vokino lazymedia filmix_api stremio nuvio
check "sync garbage in hidden: no stray files" listing_is "$data" hidden movie_suppliers
rm -f "$data/hidden"

# --- sync: an app not installed (or uninstalled later)
cp "$fx/app_data_no_lazymedia.json" "$apps"
run sync.sh
check "sync LazyMedia not installed: item removed" shown num lampa prisma vokino filmix_api stremio nuvio
cp "$fx/app_data_no_nuvio.json" "$apps"
run sync.sh
check "sync only Settings installed: only Filmix" shown filmix_api
cp "$fx/app_data.json" "$apps"
run sync.sh
# shellcheck disable=SC2086 # one word per id
check "sync apps installed again: all items" shown $all

# --- sync: no app list -> Android items stay as they are, Filmix still synced
printf 'lazymedia\n' >"$data/hidden"
run sync.sh
rm -f "$apps"
printf 'lazymedia\nnuvio\n' >"$data/hidden"
rm -f "$plugins/Filmix_api/dune_plugin.xml"
run sync.sh
check "sync no app_data.json: exit 0" rc_is 0
check "sync no app_data.json: Android items unchanged, Filmix removed" shown num lampa prisma vokino stremio nuvio
for content in '' '{}' 'garbage' '{"applications":['; do
    printf '%s' "$content" >"$apps"
    run sync.sh
    check "sync app_data.json '$content': Android items unchanged" shown num lampa prisma vokino stremio nuvio
done
# Read while the shell rewrites it: cut short, most apps missing.
head -c 1500 "$fx/app_data.json" >"$apps"
run sync.sh
check "sync app_data.json cut short: Android items unchanged" shown num lampa prisma vokino stremio nuvio
cp "$fx/app_data.json" "$apps"
: >"$plugins/Filmix_api/dune_plugin.xml"
rm -f "$data/hidden"
run sync.sh

# --- movie_suppliers_update.sh: runs sync.sh, arguments are ignored
rm -rf "$reg" "$menu"
run movie_suppliers_update.sh other other '../evil' x
check "update: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "update: all items, nothing else" shown $all
check "update: nothing outside" listing_is "$data" movie_suppliers

# --- sync: icon_url is "file://" + the app's "icon" from app_data.json

# apps_icon <icon template> [flat]: app_data.json with every app's "icon" set
# ({pkg} is replaced, "-" deletes the field), "/" escaped as on the device;
# "flat": one line, "icon" before "package_name".
apps_icon() {
    python3 - "$fx/app_data.json" "$apps" "$@" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for a in d["applications"]:
    if sys.argv[3] == "-":
        del a["icon"]
    else:
        a["icon"] = sys.argv[3].replace("{pkg}", a["package_name"])
if sys.argv[4:] == ["flat"]:
    d["applications"] = [{"icon": a.pop("icon", ""), **a} for a in d["applications"]]
    out = json.dumps(d, ensure_ascii=False)
else:
    out = json.dumps(d, indent=2, ensure_ascii=False).replace("/", "\\/")
open(sys.argv[2], "w").write(out)
EOF
}
# icons_are <icon_url template> [reg dir]: after sync every Android item has this icon_url.
icons_are() {
    # shellcheck disable=SC2086 # one word per id
    python3 - "${2:-$reg}" "$1" $android <<'EOF'
import json, sys
pkg = {"nuvio": "com.nuvio.tv", "stremio": "com.stremio.one", "num": "ru.yourok.num",
       "lampa": "top.rootu.lampa", "prisma": "top.rootu.prisma", "vokino": "ru.vokino.web",
       "lazymedia": "com.lazycatsoftware.lmd"}
for app in sys.argv[3:]:
    want = sys.argv[2].replace("{pkg}", pkg[app])
    if json.load(open("%s/%s" % (sys.argv[1], app)))["icon_url"] != want:
        sys.exit(1)
EOF
}
old="file://$FS_PREFIX/tmp/applications/icon_cache/icon_{pkg}.png"
# Dune HD Media Center installed as an app on Android TV keeps icons in flashdata.
atv='/data/data/com.dunehd.app/flashdata/applications/icon_cache/icon_{pkg}.png'
apps_icon "$atv"
run sync.sh
check "sync: icons from app_data.json (Android TV)" icons_are "file://$atv"
apps_icon "$atv" flat
run sync.sh
check "sync: icons from app_data.json, other field order, one line" icons_are "file://$atv"
apps_icon -
run sync.sh
check "sync: no icon in app_data.json, icon_cache path" icons_are "$old"
for bad in '/data/x"y{pkg}.png' '/data/x y{pkg}.png' 'data/{pkg}.png' ''; do
    apps_icon "$bad"
    run sync.sh
    check "sync: unsafe icon '$bad', icon_cache path" icons_are "$old"
done

# PLAY_IN_APPS_TMP unset: app_data.json and the /tmp copies are under $FS_PREFIX/tmp
# (no /tmp root on Android TV).
mkdir -p "$FS_PREFIX/tmp/applications"
apps_icon "$atv"
mv "$apps" "$FS_PREFIX/tmp/applications/app_data.json"
rm -rf "$reg"
env -u PLAY_IN_APPS_TMP "$sh_bin" "$bin/sync.sh" >"$o" 2>"$o.err"
check "sync PLAY_IN_APPS_TMP unset: icons from \$FS_PREFIX/tmp app_data.json" icons_are "file://$atv"
# shellcheck disable=SC2086 # one word per id
check "sync PLAY_IN_APPS_TMP unset: copies in \$FS_PREFIX/tmp/movie_suppliers" \
    listing_is "$FS_PREFIX/tmp/movie_suppliers" $all
rm -rf "$FS_PREFIX/tmp"
cp "$fx/app_data.json" "$apps"

mkdir -p "$work/cwd"
for fp in relative '/data/x"y' '/data/x y'; do
    (cd "$work/cwd" && FS_PREFIX="$fp" "$sh_bin" "$bin/sync.sh" >"$o" 2>&1)
    check "sync FS_PREFIX='$fp': nothing written" dir_empty "$work/cwd"
done

# Older Android models leave FS_PREFIX unset: paths start at the root.
# PLAY_IN_APPS_FLASHDATA keeps the write inside $work instead of /flashdata.
# No icon in app_data.json: the fallback icon path starts at the root too.
apps_icon -
for fp in unset empty; do
    rm -rf "$reg"
    (
        cd "$work/cwd" || exit 1
        if [ "$fp" = unset ]; then unset FS_PREFIX; else FS_PREFIX=; fi
        PLAY_IN_APPS_FLASHDATA="$work/fs/flashdata" "$sh_bin" "$bin/sync.sh" >"$o" 2>"$o.err"
        echo "$?" >"$o.rc"
    )
    check "sync FS_PREFIX $fp: exit 0" rc_is 0
    # shellcheck disable=SC2086 # one word per id
    check "sync FS_PREFIX $fp: all items" listing_is "$reg" $all
    check "sync FS_PREFIX $fp: icons from /tmp" icons_are "file:///tmp/applications/icon_cache/icon_{pkg}.png"
    check "sync FS_PREFIX $fp: bin path" python3 -c \
        'import json, sys; sys.exit(json.load(open(sys.argv[1]))["bin"] != sys.argv[2])' "$reg/nuvio" "sh $bin/nuvio.sh"
    check "sync FS_PREFIX $fp: nothing in cwd" dir_empty "$work/cwd"
done
cp "$fx/app_data.json" "$apps"

unsafe="$work/bad dir"
mkdir -p "$unsafe"
cp -R "$src" "$unsafe/play_in_apps"
rm -rf "$reg"
"$sh_bin" "$unsafe/play_in_apps/bin/sync.sh" >"$o" 2>&1
check "sync from unsafe path: nothing written" no_file "$reg"
run sync.sh

# --- uninstall.sh
: >"$menu/YouTube"
run uninstall.sh
check "uninstall: exit 0" rc_is 0
check "uninstall: all items removed, other suppliers kept" listing_is "$menu" YouTube
run uninstall.sh
check "uninstall twice: exit 0" rc_is 0
mkdir -p "$work/atv/tmp/movie_suppliers"
for i in $all; do printf '{"plugin":"play_in_apps"}\n' >"$work/atv/tmp/movie_suppliers/$i"; done
: >"$work/atv/tmp/movie_suppliers/YouTube"
env -u PLAY_IN_APPS_TMP FS_PREFIX="$work/atv" "$sh_bin" "$bin/uninstall.sh" >"$o" 2>"$o.err"
check "uninstall PLAY_IN_APPS_TMP unset: items removed from \$FS_PREFIX/tmp" \
    listing_is "$work/atv/tmp/movie_suppliers" YouTube
# An old single-app plugin with the same id still installed: its copy stays.
printf '{"plugin":"nuvio_supplier"}\n' >"$menu/nuvio"
printf '{"plugin":"play_in_apps"}\n' >"$menu/num"
run uninstall.sh
check "uninstall: exit 0 with an old plugin's copy" rc_is 0
check "uninstall: old plugin's copy kept" listing_is "$menu" YouTube nuvio
rm -f "$menu/nuvio"

# --- main.php on a stub of the firmware PHP API (/firmware_ext/php/); values as in r24 dune_api.php
cat >"$work/fw_stub.php" <<'EOF'
<?php
define('PLUGIN_OP_GET_FOLDER_VIEW', 'get_folder_view');
define('PLUGIN_OP_HANDLE_USER_INPUT', 'handle_user_input');
define('PLUGIN_OUT_DATA_PLUGIN_FOLDER_VIEW', 'plugin_folder_view');
define('PLUGIN_OUT_DATA_GUI_ACTION', 'gui_action');
define('PLUGIN_OPEN_FOLDER_ACTION_ID', 'plugin_open_folder');
define('PLUGIN_SHOW_ERROR_ACTION_ID', 'plugin_show_error');
define('PLUGIN_HANDLE_USER_INPUT_ACTION_ID', 'plugin_handle_user_input');
define('PLUGIN_FOLDER_VIEW_CONTROLS', 'view_controls');
define('GUI_CONTROL_LABEL', 'label');
define('GUI_CONTROL_COMBOBOX', 'combobox');
class PluginOutputData
{
    const has_data = 'has_data';
    const data_type = 'data_type';
    const data = 'data';
    const plugin_cookies = 'plugin_cookies';
    const is_error = 'is_error';
    const error_action = 'error_action';
}
class PluginFolderView
{
    const view_kind = 'view_kind';
    const data = 'data';
    const multiple_views_supported = 'multiple_views_supported';
}
class PluginControlsFolderView
{
    const defs = 'defs';
    const initial_sel_ndx = 'initial_sel_ndx';
}
class GuiControlDef
{
    const name = 'name';
    const title = 'title';
    const kind = 'kind';
    const specific_def = 'specific_def';
    const params = 'params';
}
class GuiComboboxDef
{
    const initial_value = 'initial_value';
    const value_caption_pairs = 'value_caption_pairs';
    const width = 'width';
    const apply_action = 'apply_action';
}
class GuiLabelDef
{
    const caption = 'caption';
}
class GuiAction
{
    const handler_string_id = 'handler_string_id';
    const params = 'params';
}
abstract class DunePluginFw
{
    public static $instance = null;
    public abstract function call_plugin($call_ctx_json);
}
class DuneSystem
{
    public static $properties = array();
}
DuneSystem::$properties = array(
    'data_dir_path' => getenv('T_DATA_DIR'),
    'tmp_dir_path' => getenv('T_TMP_DIR'));
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
    T_DATA_DIR=${T_DATA_DIR:-$data} T_TMP_DIR="$PLAY_IN_APPS_TMP/plugins/play_in_apps" \
        $php_bin "$work/fw_stub.php" "$plugin/main.php" <"$1" >"$o" 2>"$o.err"
    echo "$?" >"$o.rc"
}

# only_own_log: no PHP warnings/notices, only hd_print lines of the plugin.
only_own_log() { ! grep -v '^play_in_apps: ' "$o.err"; }

# ctx <input_data file> [op]: plugin call context around input_data.
ctx() {
    python3 - "$1" "${2:-handle_user_input}" >"$work/ctx.json" <<'EOF'
import json, sys
print(json.dumps({"op_type_code": sys.argv[2],
                  "input_data": json.load(open(sys.argv[1])),
                  "plugin_cookies": {"k": "v"}}))
EOF
}

# out_is <expected action JSON or "none">: plugin output with this GUI action.
# media_url is compared as decoded JSON (PHP 5.3 escapes "/" and non-ASCII).
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

# user_input <movie_str JSON or raw value for movie_str>: play_action user_input around it.
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

    # --- Filmix play_action. Filmix_API not installed yet.
    rm -rf "$plugins/Filmix_api"
    error "$fx/play_action_movie.json" "no Filmix_API" filmix_api_err_not_installed
    mkdir -p "$plugins/Filmix_api"
    error "$fx/play_action_movie.json" "Filmix_API dir without manifest" filmix_api_err_not_installed
    : >"$plugins/Filmix_api/dune_plugin.xml"

    # Real inputs from the device (probe log, 03.10.2026).
    search "$fx/play_action_movie.json" movie 'Прошлой ночью в Сохо'
    check "main.php logs the search to stderr" grep -q '^play_in_apps: filmix search: Прошлой ночью в Сохо$' "$o.err"
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
    error "$work/ui.json" "lone surrogate" filmix_api_err_no_title
    user_input '{"title":"\ud800","native_title":"Good"}'
    if [ "$("$php_bin" -r 'echo PHP_MAJOR_VERSION;')" -lt 7 ]; then
        search "$work/ui.json" "lone surrogate title, fallback to native_title" Good
    else
        # PHP 7+ json_decode rejects the whole movie_str.
        error "$work/ui.json" "lone surrogate title (PHP 7+)" filmix_api_err_no_title
    fi
    user_input '{"title":"\ud800","native_title":"x\udc00"}'
    error "$work/ui.json" "lone surrogates in both titles" filmix_api_err_no_title
    user_input '{"\u0000a":1,"x":{"\u0000":2},"title":"T"}'
    search "$work/ui.json" "keys starting with NUL" T
    user_input '["title","native_title"]'
    error "$work/ui.json" "movie_str JSON list" filmix_api_err_no_title
    user_input '{"title":2049}'
    search "$work/ui.json" "numeric title" 2049
    user_input '{"title":{"ru":"x"},"native_title":"Nested"}'
    search "$work/ui.json" "object title skipped" Nested
    user_input '{"title":["x"]}'
    error "$work/ui.json" "array title" filmix_api_err_no_title
    user_input '{"title":"   ","native_title":""}'
    error "$work/ui.json" "blank titles" filmix_api_err_no_title
    user_input '{"year":2021}'
    error "$work/ui.json" "no titles" filmix_api_err_no_title
    user_input 'not json'
    error "$work/ui.json" "movie_str not JSON" filmix_api_err_no_title
    user_input '"just a string"'
    error "$work/ui.json" "movie_str JSON string" filmix_api_err_no_title
    printf '%s\n' '{"handler_id":"filmix_api","control_id":"play"}' >"$work/ui.json"
    error "$work/ui.json" "no movie_str" filmix_api_err_no_title
    printf '%s\n' '{"handler_id":"filmix_api","movie_str":{"title":"obj"}}' >"$work/ui.json"
    error "$work/ui.json" "movie_str is an object" filmix_api_err_no_title

    # Not our call: no action, no error.
    printf '%s\n' '{"handler_id":"other","movie_str":"{\"title\":\"x\"}"}' >"$work/ui.json"
    handler "$work/ui.json" "other handler" none
    ctx "$fx/play_action_movie.json" get_vod_info
    php_run "$work/ctx.json"
    check "main.php other op: no action" out_is none
    for raw in '' 'garbage' '[]' '"str"' '{"op_type_code":"handle_user_input"}' \
        '{"op_type_code":"handle_user_input","input_data":"x"}'; do
        printf '%s' "$raw" >"$work/raw.json"
        php_run "$work/raw.json"
        check "main.php raw '$raw': exit 0" rc_is 0
        check "main.php raw '$raw': has_data false" python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(d["has_data"] is not False)' "$o"
    done

    # --- the screen: get_folder_view

    # screen_is <installed ids> <hidden ids> <ids with an old plugin>: view_controls
    # with a hint label, two warning labels if a separate "Open in <app>" plugin
    # is there (the caption, then the app names), then a combobox per app in
    # the manifest order. The screen does not scroll on r24: two lines at most.
    screen_is() {
        python3 - "$o" "$@" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
installed, hidden, old = (set(a.split()) for a in sys.argv[2:5])
names = [("num", "NUM"), ("lampa", "Lampa"), ("prisma", "Prisma"), ("vokino", "VoKino"),
         ("lazymedia", "LazyMedia"), ("filmix_api", "Filmix"), ("stremio", "Stremio"), ("nuvio", "Nuvio")]
defs = [{"name": "", "title": None, "kind": "label", "specific_def": {"caption": "%tr%screen_hint"}}]
if old:
    for caption in ("%tr%old_plugins", ", ".join(cap for i, cap in names if i in old)):
        defs.append({"name": "", "title": None, "kind": "label", "specific_def": {"caption": caption}})
for i, cap in names:
    defs.append({
        "name": i, "title": cap, "kind": "combobox",
        "specific_def": {
            "initial_value": "hide" if i in hidden else "show",
            "value_caption_pairs": {"show": "%tr%choice_show", "hide": "%tr%choice_hide"},
            "width": 400,
            "apply_action": {"handler_string_id": "plugin_handle_user_input",
                             "params": {"handler_id": "setup", "control_id": i}}},
        "params": None if i in installed else {"text_right": "%tr%not_installed"}})
want = {"has_data": True, "plugin_cookies": {"k": "v"}, "is_error": False, "error_action": None,
        "data_type": "plugin_folder_view",
        "data": {"view_kind": "view_controls", "multiple_views_supported": False,
                 "data": {"defs": defs, "initial_sel_ndx": -1}}}
sys.exit(d != want)
EOF
    }

    # folder_view [media_url]: open the screen.
    folder_view() {
        python3 -c 'import json, sys; print(json.dumps({"media_url": sys.argv[1]}))' "${1:-setup}" >"$work/fv.json"
        ctx "$work/fv.json" get_folder_view
        php_run "$work/ctx.json"
    }

    rm -rf "$reg" "$menu"
    folder_view
    check "screen: exit 0" rc_is 0
    check "screen: stderr has only own log lines" only_own_log
    check "screen: all installed and shown" screen_is "$all" "" ""
    check "screen without old plugins: 9 controls, no warning" python3 -c \
        'import json, sys; sys.exit(len(json.load(open(sys.argv[1]))["data"]["data"]["defs"]) != 9)' "$o"
    # shellcheck disable=SC2086 # one word per id
    check "screen opening runs sync" shown $all

    printf 'nuvio\nprisma\n' >"$data/hidden"
    cp "$fx/app_data_no_lazymedia.json" "$apps"
    rm -f "$plugins/Filmix_api/dune_plugin.xml"
    mkdir -p "$plugins/nuvio_supplier" "$plugins/num_supplier" "$plugins/stremio_supplier"
    : >"$plugins/nuvio_supplier/dune_plugin.xml"
    : >"$plugins/num_supplier/dune_plugin.xml"
    folder_view 'garbage"url'
    check "screen hidden, not installed, old plugins: exit 0" rc_is 0
    check "screen hidden, not installed, old plugins: stderr has only own log lines" only_own_log
    check "screen hidden, not installed, old plugins: controls" \
        screen_is "num lampa prisma vokino stremio nuvio" "nuvio prisma" "num nuvio"
    check "screen hidden, not installed: sync" shown num lampa vokino stremio
    rm -rf "$apps"
    folder_view
    check "screen no app_data.json: Android apps marked not installed" \
        screen_is "" "nuvio prisma" "num nuvio"
    for i in $all; do
        mkdir -p "$plugins/${i}_supplier"
        : >"$plugins/${i}_supplier/dune_plugin.xml"
    done
    folder_view
    check "screen all 8 old plugins: two warning lines, 8 comboboxes" \
        screen_is "" "nuvio prisma" "$all"
    check "screen all 8 old plugins: 11 controls" python3 -c \
        'import json, sys; sys.exit(len(json.load(open(sys.argv[1]))["data"]["data"]["defs"]) != 11)' "$o"
    for i in $all; do rm -rf "$plugins/${i}_supplier"; done
    cp "$fx/app_data.json" "$apps"
    : >"$plugins/Filmix_api/dune_plugin.xml"
    rm -rf "$plugins/nuvio_supplier" "$plugins/num_supplier" "$plugins/stremio_supplier"

    # --- the screen: a combobox changed

    # set_shown <control_id JSON> <value JSON or "none">: apply_action of a combobox.
    set_shown() {
        python3 - "$1" "$2" >"$work/ui.json" <<'EOF'
import json, sys
ui = {"handler_id": "setup", "control_id": json.loads(sys.argv[1]), "selected_control_id": "x"}
if sys.argv[2] != "none" and isinstance(ui["control_id"], str):
    ui[ui["control_id"]] = json.loads(sys.argv[2])
print(json.dumps(ui))
EOF
    }
    hidden_is() { [ "$(cat "$data/hidden")" = "$1" ]; }

    rm -f "$data/hidden"
    set_shown '"stremio"' '"hide"'
    handler "$work/ui.json" "hide stremio" none
    check "hide stremio: hidden file" hidden_is stremio
    check "hide stremio: item removed" shown num lampa prisma vokino lazymedia filmix_api nuvio
    set_shown '"num"' '"hide"'
    handler "$work/ui.json" "hide num" none
    check "hide num: hidden file in manifest order" hidden_is "$(printf 'num\nstremio')"
    check "hide num: item removed" shown lampa prisma vokino lazymedia filmix_api nuvio
    set_shown '"filmix_api"' '"hide"'
    handler "$work/ui.json" "hide filmix_api" none
    check "hide filmix_api: item removed" shown lampa prisma vokino lazymedia nuvio
    folder_view
    check "screen shows hidden items" screen_is "$all" "num filmix_api stremio" ""
    set_shown '"stremio"' '"show"'
    handler "$work/ui.json" "show stremio" none
    check "show stremio: hidden file" hidden_is "$(printf 'num\nfilmix_api')"
    check "show stremio: item back" shown lampa prisma vokino lazymedia stremio nuvio
    set_shown '"stremio"' '"show"'
    handler "$work/ui.json" "show stremio again" none
    check "show stremio again: hidden file unchanged" hidden_is "$(printf 'num\nfilmix_api')"

    # Hidden but not installed: the choice is kept for later.
    cp "$fx/app_data_no_lazymedia.json" "$apps"
    set_shown '"lazymedia"' '"hide"'
    handler "$work/ui.json" "hide lazymedia not installed" none
    check "hide lazymedia not installed: remembered" hidden_is "$(printf 'num\nlazymedia\nfilmix_api')"
    cp "$fx/app_data.json" "$apps"

    # Garbage in the hidden file is dropped on the next change.
    printf 'garbage\n../x\nnuvio \nlampa\n' >>"$data/hidden"
    set_shown '"num"' '"show"'
    handler "$work/ui.json" "show num, garbage in hidden" none
    check "show num: garbage dropped" hidden_is "$(printf 'lampa\nlazymedia\nfilmix_api')"
    check "show num: items" shown num prisma vokino stremio nuvio

    # Hostile or foreign input: nothing changes.
    cp "$data/hidden" "$work/hidden.before"
    for c in '"evil"' '"../num"' '"num "' '"handler_id"' '"0"' '0' '["num"]' '{"a":"num"}' 'null'; do
        set_shown "$c" '"hide"'
        handler "$work/ui.json" "control_id $c" none
    done
    for val in '"maybe"' '"HIDE"' '1' 'true' '["hide"]' 'null' none; do
        set_shown '"nuvio"' "$val"
        handler "$work/ui.json" "value $val" none
    done
    printf '%s\n' '{"handler_id":"other","control_id":"nuvio","nuvio":"hide"}' >"$work/ui.json"
    handler "$work/ui.json" "other handler_id" none
    printf '%s\n' '{"control_id":"nuvio","nuvio":"hide"}' >"$work/ui.json"
    handler "$work/ui.json" "no handler_id" none
    check "hostile input: hidden file unchanged" cmp -s "$data/hidden" "$work/hidden.before"
    check "hostile input: no temp files" listing_is "$data" hidden movie_suppliers

    # The data dir is created if missing; the choice cannot be saved: error.
    rm -rf "$data"
    set_shown '"vokino"' '"hide"'
    handler "$work/ui.json" "hide vokino, no data dir" none
    check "hide vokino, no data dir: hidden file" hidden_is vokino
    : >"$work/notadir"
    set_shown '"vokino"' '"show"'
    # PHP warnings are expected here, they go to the plugin log.
    ctx "$work/ui.json"
    T_DATA_DIR="$work/notadir/x" php_run "$work/ctx.json"
    check "main.php data dir not writable: exit 0" rc_is 0
    check "main.php data dir not writable: err_save" out_is "$(error_json err_save)"
fi

# --- manifest and translations
check "manifest: php, suppliers, entry point, global actions" python3 - "$src/dune_plugin.xml" "$all" <<'EOF'
import re, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
e = r.find("entry_points/entry_point")
ok = (r.findtext("name") == "play_in_apps"
      and r.findtext("type") == "php"
      and r.findtext("params/program") == "main.php"
      and r.findtext("params/movie_suppliers") == "-".join(sys.argv[2].split())
      and r.findtext("global_actions/uninstall/data/run_string") == "bin/uninstall.sh"
      and r.findtext("global_actions/early_gui_start/data/run_string") == "bin/sync.sh"
      and e.findtext("parent_media_url") == "setup://applications"
      and e.findtext("actions/key_enter/type") == "plugin_open_folder"
      and re.fullmatch(r"\d+\.\d+\.\d+", r.findtext("version") or "")
      and re.fullmatch(r"\d+", r.findtext("version_index") or ""))
sys.exit(not ok)
EOF
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' "$src/dune_plugin.xml")
check "CHANGELOG has the manifest version" grep -q "^## $version" "$src/CHANGELOG.md"

# The same ids everywhere: manifest (above), an item script each, sync.sh,
# uninstall.sh and main.php.
for i in $all; do
    check "id $i: bin/$i.sh" test -f "$src/bin/$i.sh"
    check "id $i: sync.sh" grep -q " $i:" "$src/bin/sync.sh"
    check "id $i: uninstall.sh" grep -q "^for id in .* $i\\b\\|^for id in $i " "$src/bin/uninstall.sh"
    check "id $i: main.php" grep -q "^        '$i' => array(" "$src/main.php"
done
scripts=$(for i in $all; do echo "$i.sh"; done)
# shellcheck disable=SC2086 # one word per script
check "no other item scripts" listing_is "$src/bin" movie_suppliers_update.sh sync.sh uninstall.sh $scripts

keys="plugin_caption"
for i in $all; do
    keys="$keys ${i}_caption $(grep -ho 'fail err_[a-z_]*' "$src/bin/$i.sh" | sed "s/^fail /${i}_/" | sort -u)"
done
keys="$keys filmix_api_err_unsupported $(grep -o "%tr%[a-z_]*\|pia_error_action('[a-z_]*')\|play_in_apps_plugin_[a-z_0-9]*" "$src/main.php" |
    sed "s/^%tr%//; s/^pia_error_action('//; s/')\$//; s/^play_in_apps_plugin_//" | sort -u)"
for lang in english russian; do
    tr_file="$src/translations/dune_language_$lang.txt"
    for key in $keys; do
        check "translation $lang: $key" grep -q "^$key = ." "$tr_file"
    done
done
check "translations: same keys in both languages" test \
    "$(cut -d' ' -f1 "$src/translations/dune_language_english.txt" | sort)" = \
    "$(cut -d' ' -f1 "$src/translations/dune_language_russian.txt" | sort)"

if [ "$failed" -ne 0 ]; then
    echo "SOME TESTS FAILED"
    exit 1
fi
echo "ALL PASSED"
