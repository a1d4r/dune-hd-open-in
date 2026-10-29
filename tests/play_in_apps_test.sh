#!/bin/sh
# Tests for plugin/play_in_apps. Run: dash tests/play_in_apps_test.sh
# TEST_SH selects the shell used to run plugin scripts (default: dash).
# PHP selects the PHP CLI for main.php (default: php). The device runs PHP 5.3.6:
# tests/php53/Dockerfile has it with the other tools (see the comment there).
# shellcheck disable=SC2016 # sh -c '<script>' _ <args>: the script expands its own $1, $2

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

android="num lampa bylampa lampa_atv prisma vokino lazymedia stremio nuvio freezona alpac flux seasonhit"
all="num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona alpac flux seasonhit bazinga"
# Ids that had a separate "Open in <app>" plugin (<id>_supplier) before.
old_ids="num lampa prisma vokino lazymedia filmix_api stremio nuvio"

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
# LazyMedia and SeasonHit, and for ALPAC when it is not an alpac: URI, the argument is the
# percent-encoded search query, sent to the app's search activity. Otherwise
# the app gets the URI as an intent: URI with the package (no -p: the shell's command
# parser on some firmware rejects it); it is parsed back the way
# Intent.parseUri does to the scheme, data, action and package.
launch_is() {
    python3 - "$o" "$id" "$1" <<'EOF'
import json, re, sys
d = json.load(open(sys.argv[1]))
app, arg = sys.argv[2], sys.argv[3]
pkg, title, flags = {
    "nuvio": ("com.nuvio.tv", "Nuvio", "--activity-clear-task "),
    "stremio": ("com.stremio.one", "Stremio", "--activity-clear-task "),
    "num": ("ru.yourok.num", "NUM", "--activity-clear-task "),
    "lampa": ("top.rootu.lampa", "Lampa", "--activity-clear-task "),
    "bylampa": ("top.rootu.bylumpa", "BYLAMPA", "--activity-clear-task "),
    "lampa_atv": ("top.rootu.lumpa", "LAMPA ATV", "--activity-clear-task "),
    "prisma": ("top.rootu.prisma", "Prisma", "--activity-clear-task "),
    "vokino": ("ru.vokino.web", "VoKino", "--activity-clear-task "),
    "lazymedia": ("com.lazycatsoftware.lmd", "LazyMedia", "--activity-clear-task "),
    "freezona": ("free.zona", "FreeZona", "--activity-clear-task "),
    "alpac": ("cc.alcopa.tv", "ALPAC", "--activity-clear-task "),
    "flux": ("app.flux.tv", "Flux", "--activity-clear-task "),
    "seasonhit": ("com.jimdo.xakerd.season2hit", "SeasonHit", "--activity-clear-task "),
}[app]
search = {
    "lazymedia": "com.lazycatsoftware.lmd/com.lazycatsoftware.lazymediadeluxe.ui.tv.activities.ActivityTvSearch",
    "alpac": "cc.alcopa.tv/cc.alcopa.tv.SearchActivity",
    "seasonhit": "com.jimdo.xakerd.season2hit/com.jimdo.xakerd.season2hit.activity.SearchActivity",
}.get(app)
if app == "alpac" and arg.startswith("alpac:"):
    search = None
if search:
    cmd = "am start --activity-clear-task 'intent:#Intent;component=%s;S.query=%s;end'" % (search, arg)
else:
    scheme, rest = arg.split(":", 1)
    cmd = ("am start %s'intent:%s#Intent;scheme=%s;action=android.intent.action.VIEW;package=%s;end'"
           % (flags, rest, scheme, pkg))
if d != {"bin": cmd, "package": pkg, "title": title, "wait_app_start_delay": 10}:
    sys.exit(1)
if " -p " in d["bin"] + " ":
    sys.exit("-p in the command")
if not search:
    # One shell word: no spaces or quotes inside the URI.
    m = re.match(r"^am start (--activity-clear-task )?'([^' \"]*)'$", d["bin"])
    if not m:
        sys.exit("not one quoted intent: URI")
    uri = m.group(2)
    # Intent.parseUri: data is before the last '#', fields "k=v;" after "#Intent;".
    i = uri.rfind("#")
    data, frag = uri[:i], uri[i:]
    if not (data.startswith("intent:") and frag.startswith("#Intent;") and frag.endswith(";end")):
        sys.exit("not an intent: URI")
    if "#" in data or ";" in data:
        sys.exit("'#' or ';' in the link")
    fields = [f.split("=", 1) for f in frag[len("#Intent;"):-len(";end")].split(";")]
    if [k for k, _ in fields] != ["scheme", "action", "package"]:
        sys.exit("fields %r" % fields)
    f = dict(fields)
    got = (f["scheme"] + ":" + data[len("intent:"):], f["action"], f["package"])
    sys.exit(got != (arg, "android.intent.action.VIEW", pkg))
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

# --- num, lampa, bylampa, lampa_atv, prisma: TMDB only, ids up to Java int
t=https://www.themoviedb.org
for id in num lampa bylampa lampa_atv prisma; do
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

# --- lampa, bylampa, lampa_atv: packages top.rootu.lampa, top.rootu.bylumpa
# and top.rootu.lumpa, each found by its exact name.
cp "$fx/app_data_no_lampa_atv.json" "$apps"
for id in lampa bylampa; do
    supplier "$fx/movie.json" launch_is "$t/movie/558449"
done
id=lampa_atv
supplier "$fx/movie.json" error_is err_not_installed
cp "$fx/app_data_no_bylampa.json" "$apps"
id=lampa
supplier "$fx/movie.json" launch_is "$t/movie/558449"
id=bylampa
supplier "$fx/movie.json" error_is err_not_installed
# app_data_only_<id>.json: app_data.json without the other two Lampa apps.
python3 - "$fx/app_data.json" "$work" <<'EOF'
import json, sys
lampas = {"lampa": "top.rootu.lampa", "bylampa": "top.rootu.bylumpa", "lampa_atv": "top.rootu.lumpa"}
for app, pkg in lampas.items():
    d = json.load(open(sys.argv[1]))
    others = set(lampas.values()) - {pkg}
    d["applications"] = [a for a in d["applications"] if a["package_name"] not in others]
    open("%s/app_data_only_%s.json" % (sys.argv[2], app), "w").write(
        json.dumps(d, indent=2, ensure_ascii=False).replace("/", "\\/"))
EOF
for only in lampa bylampa lampa_atv; do
    cp "$work/app_data_only_$only.json" "$apps"
    for id in lampa bylampa lampa_atv; do
        if [ "$id" = "$only" ]; then
            supplier "$fx/movie.json" launch_is "$t/movie/558449"
        else
            supplier "$fx/movie.json" error_is err_not_installed
        fi
    done
done
# Look-alike names: a dot matches only a dot, the name ends at the quote.
sed -e 's/"top\.rootu\.lampa"/"topxrootuxlampa"/' -e 's/"top\.rootu\.bylumpa"/"top.rootu.bylumpa.tv"/' \
    -e 's/"top\.rootu\.lumpa"/"top.rootu.lumpa.tv"/' "$fx/app_data.json" >"$apps"
for id in lampa bylampa lampa_atv; do
    supplier "$fx/movie.json" error_is err_not_installed
done
cp "$fx/app_data.json" "$apps"

# --- freezona: Kinopoisk only, movies and series by the same link
id=freezona
k=https://www.kinopoisk.ru/film
supplier "$fx/movie_kinopoisk.json" launch_is "$k/61249"
supplier "$fx/series_kinopoisk.json" launch_is "$k/464963"
check "freezona writes uri to stderr" grep -q "uri: $k/464963" "$o.err"
# No Kinopoisk ID: IMDb and TMDB are not enough.
for f in movie series movie_tmdb_only series_tmdbtv_only series_movie_tmdb_only movie_no_ids series_no_ids; do
    supplier "$fx/$f.json" error_is err_no_id
done
common error_is err_no_id err_no_id
hostile '{"movieInfo":{"movieExtId":"kinopoisk:123'"'"';reboot;'"'"'","type":"single"}}' error_is err_no_id
# shellcheck disable=SC2016 # literal $(...) on purpose
hostile '{"movieInfo":{"movieExtId":"kinopoisk:123 x,kinopoisk:1$(reboot)","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"xxkinopoisk:123,kp:5,kinopoisk:tt1","type":"single"}}' error_is err_no_id
# Ten digits: not a Kinopoisk ID.
hostile '{"movieInfo":{"movieExtId":"kinopoisk:1234567890","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"kinopoisk:123456789","type":"single"}}' launch_is "$k/123456789"
hostile '{"movieInfo":{"movieExtId":"kinopoisk:1,kinopoisk:2","type":"single"}}' launch_is "$k/1"
hostile '{"movieInfo":{"movieExtId":"kinopoisk:1234567890,kinopoisk:2","type":"single"}}' launch_is "$k/2"
# Type does not matter.
hostile '{"movieInfo":{"movieExtId":"kinopoisk:5","type":"movie"}}' launch_is "$k/5"
hostile '{"movieInfo":{"movieExtId":"kinopoisk:5","type":"single;reboot"}}' launch_is "$k/5"
hostile '{"movieInfo":{"movieExtId":"kinopoisk:5","type":""}}' launch_is "$k/5"
hostile '{"movieInfo":{"movieExtId":"kinopoisk:5"}}' launch_is "$k/5"
# Title text that looks like keys must not win over the real fields.
hostile '{"movieInfo":{"movieExtId":"kinopoisk:1","title":{"en":"\"movieExtId\":\"kinopoisk:2\""},"type":"single"}}' launch_is "$k/1"
hostile '{"movieInfo":{"title":{"en":"\"movieExtId\":\"kinopoisk:2\""},"type":"single"}}' error_is err_no_id

# titles <no-title error key> <launch_is prefix>: title parsing shared by VoKino,
# LazyMedia, ALPAC and SeasonHit:
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

# --- alpac: TMDB ID of the matching type (movie/ or tv/), else search by title
id=alpac
a=alpac://title
supplier "$fx/movie.json" launch_is "$a/movie/558449"
supplier "$fx/series.json" launch_is "$a/tv/94997"
supplier "$fx/movie_tmdb_only.json" launch_is "$a/movie/558449"
supplier "$fx/series_tmdbtv_only.json" launch_is "$a/tv/94997"
check "alpac writes uri to stderr" grep -q "uri: $a/tv/94997" "$o.err"
supplier "$fx/movie_kinopoisk.json" launch_is "$a/movie/920"
supplier "$fx/series_kinopoisk.json" launch_is "$a/tv/1399"
# A series with only a movie tmdb: id: search, never movie/ (an empty card).
supplier "$fx/series_movie_tmdb_only.json" search_is 'Дом Дракона'
supplier "$fx/movie_no_ids.json" search_is 'Гладиатор 2'
supplier "$fx/series_no_ids.json" search_is 'Мастера меча онлайн: Алисизация '
check "alpac writes search uri to stderr" grep -q 'uri: intent:#Intent;component=cc.alcopa.tv/cc.alcopa.tv.SearchActivity;S.query=%D0%9C.*%20;end$' "$o.err"
common launch_is "$a/movie/558449" err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:123'"'"';reboot;'"'"'","type":"single"}}' error_is err_no_id
# shellcheck disable=SC2016 # literal $(...) on purpose
hostile '{"movieInfo":{"movieExtId":"tmdb:123 x,tmdb:1$(reboot)","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"xxtmdb:123,tmdb:12345678901","type":"single"}}' error_is err_no_id
# IMDb and Kinopoisk are not used.
hostile '{"movieInfo":{"movieExtId":"dunemdb:x,kinopoisk:1,imdb:tt9218128","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:1,tmdb:2","type":"single"}}' launch_is "$a/movie/1"
hostile '{"movieInfo":{"movieExtId":"dunemdb:x,kinopoisk:1,imdb:tt0111161,tmdb:278","type":"single"}}' launch_is "$a/movie/278"
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1399,tmdb:278","type":"series"}}' launch_is "$a/tv/1399"
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1399,tmdb:278","type":"single"}}' launch_is "$a/movie/278"
# The ID of the other type: search, not a path with the wrong type.
hostile '{"movieInfo":{"movieExtId":"tmdb:278","type":"series","title":{"ru":"x"}}}' search_is x
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1399","type":"single","title":{"ru":"y"}}}' search_is y
hostile '{"movieInfo":{"movieExtId":"tmdb:278","type":"series"}}' error_is err_no_id
# Ten digits do not go into the path (ALPAC parses a Java int).
hostile '{"movieInfo":{"movieExtId":"tmdb:9999999999","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:9999999999","type":"single","title":{"ru":"z"}}}' search_is z
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1234567890","type":"series","title":{"ru":"z"}}}' search_is z
hostile '{"movieInfo":{"movieExtId":"tmdb:999999999","type":"single"}}' launch_is "$a/movie/999999999"
# ID 0 closes ALPAC's card at once; a leading zero is not a TMDB ID either:
# search. The first item that is a valid ID wins.
hostile '{"movieInfo":{"movieExtId":"tmdb:0","type":"single","title":{"ru":"z"}}}' search_is z
hostile '{"movieInfo":{"movieExtId":"tmdbtv:0","type":"series","title":{"ru":"z"}}}' search_is z
hostile '{"movieInfo":{"movieExtId":"tmdb:007","type":"single","title":{"ru":"z"}}}' search_is z
hostile '{"movieInfo":{"movieExtId":"tmdbtv:0123","type":"series"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:0,tmdb:007,tmdb:5","type":"single"}}' launch_is "$a/movie/5"
hostile '{"movieInfo":{"movieExtId":"tmdbtv:10","type":"series"}}' launch_is "$a/tv/10"
hostile '{"movieInfo":{"movieExtId":"tmdb:278-slug,tmdb:12345678901","type":"single"}}' error_is err_no_id
# Other types: search.
hostile '{"movieInfo":{"movieExtId":"tmdb:1","type":"movie","title":{"ru":"x"}}}' search_is x
hostile '{"movieInfo":{"movieExtId":"tmdb:1","type":"single;reboot"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:1"}}' error_is err_no_id
# Title text that looks like keys must not win over the real fields.
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"en":"\"type\":\"series\" \"movieExtId\":\"tmdbtv:2\""},"type":"single"}}' launch_is "$a/movie/1"
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"en":"\"movieExtId\":\"imdb:tt2\"","ru":"\"title\":{\"ru\":\"evil\"}"}}}' search_is '"title":{"ru":"evil"}'
# Intent URI syntax inside the title stays inside S.query.
hostile '{"movieInfo":{"title":{"ru":"x;end;component=a/b;S.query=y#Intent"}}}' search_is 'x;end;component=a/b;S.query=y#Intent'
titles err_no_id ''
# Look-alike names: a dot matches only a dot, the name ends at the quote.
sed 's/"cc\.alcopa\.tv"/"ccxalcopaxtv"/' "$fx/app_data.json" >"$apps"
supplier "$fx/movie.json" error_is err_not_installed
sed 's/"cc\.alcopa\.tv"/"cc.alcopa.tv.dev"/' "$fx/app_data.json" >"$apps"
supplier "$fx/movie.json" error_is err_not_installed
cp "$fx/app_data.json" "$apps"

# --- flux: TMDB ID of the matching type (movie/ or series/) only, no search
id=flux
x=flux:/
check "fixture app_data.json has Flux" grep -qE '"package_name": *"app\.flux\.tv"' "$fx/app_data.json"
supplier "$fx/movie.json" launch_is "$x/movie/558449"
supplier "$fx/series.json" launch_is "$x/series/94997"
supplier "$fx/movie_tmdb_only.json" launch_is "$x/movie/558449"
supplier "$fx/series_tmdbtv_only.json" launch_is "$x/series/94997"
check "flux writes uri to stderr" grep -q "uri: $x/series/94997" "$o.err"
supplier "$fx/movie_kinopoisk.json" launch_is "$x/movie/920"
supplier "$fx/series_kinopoisk.json" launch_is "$x/series/1399"
# No TMDB ID: an error, Flux has no search from outside.
supplier "$fx/movie_no_ids.json" error_is err_no_id
supplier "$fx/series_no_ids.json" error_is err_no_id
# A series with only a movie tmdb: id: never series/ (another series) or movie/.
supplier "$fx/series_movie_tmdb_only.json" error_is err_no_id
common launch_is "$x/movie/558449" err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:123'"'"';reboot;'"'"'","type":"single"}}' error_is err_no_id
# shellcheck disable=SC2016 # literal $(...) on purpose
hostile '{"movieInfo":{"movieExtId":"tmdb:123 x,tmdb:1$(reboot)","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"xxtmdb:123,tmdb:12345678901","type":"single"}}' error_is err_no_id
# IMDb and Kinopoisk are not used; a title alone is not enough.
hostile '{"movieInfo":{"movieExtId":"dunemdb:x,kinopoisk:1,imdb:tt9218128","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"","title":{"ru":"x","en":"y"},"type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:1,tmdb:2","type":"single"}}' launch_is "$x/movie/1"
hostile '{"movieInfo":{"movieExtId":"dunemdb:x,kinopoisk:1,imdb:tt0111161,tmdb:278","type":"single"}}' launch_is "$x/movie/278"
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1399,tmdb:278","type":"series"}}' launch_is "$x/series/1399"
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1399,tmdb:278","type":"single"}}' launch_is "$x/movie/278"
# The ID of the other type: an error, not a path with the wrong type.
hostile '{"movieInfo":{"movieExtId":"tmdb:278","type":"series","title":{"ru":"x"}}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1399","type":"single","title":{"ru":"y"}}}' error_is err_no_id
# Ten digits do not go into the path (Flux parses a Java int).
hostile '{"movieInfo":{"movieExtId":"tmdb:9999999999","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1234567890","type":"series"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:999999999","type":"single"}}' launch_is "$x/movie/999999999"
hostile '{"movieInfo":{"movieExtId":"tmdbtv:999999999","type":"series"}}' launch_is "$x/series/999999999"
# ID 0 and leading zeros are not TMDB IDs. The first valid item wins.
hostile '{"movieInfo":{"movieExtId":"tmdb:0","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdbtv:0","type":"series"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:007","type":"single"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdbtv:0123","type":"series"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:0,tmdb:007,tmdb:5","type":"single"}}' launch_is "$x/movie/5"
hostile '{"movieInfo":{"movieExtId":"tmdbtv:10","type":"series"}}' launch_is "$x/series/10"
hostile '{"movieInfo":{"movieExtId":"tmdb:278-slug,tmdb:12345678901","type":"single"}}' error_is err_no_id
# Other types.
hostile '{"movieInfo":{"movieExtId":"tmdb:1","type":"movie"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1","type":"tv"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:1","type":"single;reboot"}}' error_is err_no_id
hostile '{"movieInfo":{"movieExtId":"tmdb:1"}}' error_is err_no_id
# Title text that looks like keys must not win over the real fields.
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"en":"\"type\":\"series\" \"movieExtId\":\"tmdbtv:2\""},"type":"single"}}' launch_is "$x/movie/1"
# Look-alike names: a dot matches only a dot, the name ends at the quote.
sed 's/"app\.flux\.tv"/"appxfluxxtv"/' "$fx/app_data.json" >"$apps"
supplier "$fx/movie.json" error_is err_not_installed
sed 's/"app\.flux\.tv"/"app.flux.tv.dev"/' "$fx/app_data.json" >"$apps"
supplier "$fx/movie.json" error_is err_not_installed
cp "$fx/app_data.json" "$apps"

# --- seasonhit: no IDs, always search by the Russian title, movies too
id=seasonhit
check "fixture app_data.json has SeasonHit" grep -qE '"package_name": *"com\.jimdo\.xakerd\.season2hit"' "$fx/app_data.json"
supplier "$fx/movie.json" search_is 'Гладиатор 2'
supplier "$fx/series.json" search_is 'Дом Дракона'
supplier "$fx/movie_tmdb_only.json" search_is 'Гладиатор 2'
supplier "$fx/series_tmdbtv_only.json" search_is 'Дом Дракона'
supplier "$fx/series_movie_tmdb_only.json" search_is 'Дом Дракона'
supplier "$fx/movie_no_ids.json" search_is 'Гладиатор 2'
supplier "$fx/series_no_ids.json" search_is 'Мастера меча онлайн: Алисизация '
supplier "$fx/movie_kinopoisk.json" search_is 'Тачки'
supplier "$fx/series_kinopoisk.json" search_is 'Игра престолов'
check "seasonhit writes uri to stderr" grep -q 'uri: intent:#Intent;component=com.jimdo.xakerd.season2hit/com.jimdo.xakerd.season2hit.activity.SearchActivity;S.query=%D0%98.*;end$' "$o.err"
common search_is 'Гладиатор 2' err_no_title
hostile '{"movieInfo":{"movieExtId":"imdb:tt9218128,tmdb:558449","type":"single"}}' error_is err_no_title
hostile '{"movieInfo":{"movieExtId":"imdb:tt1","type":"single;reboot","title":{"ru":"x"}}}' search_is x
hostile '{"movieInfo":{"movieExtId":"tmdbtv:1399","type":"series","title":{"ru":"","en":"Game of Thrones"}}}' search_is 'Game of Thrones'
hostile '{"movieInfo":{"movieExtId":"tmdb:1","title":{"en":"\"movieExtId\":\"imdb:tt2\"","ru":"\"title\":{\"ru\":\"evil\"}"}}}' search_is '"title":{"ru":"evil"}'
# Intent URI syntax inside the title stays inside S.query.
hostile '{"movieInfo":{"title":{"ru":"x;end;component=a/b;S.query=y#Intent"}}}' search_is 'x;end;component=a/b;S.query=y#Intent'
titles err_no_title ''
cp "$fx/app_data_no_seasonhit.json" "$apps"
supplier "$fx/series.json" error_is err_not_installed
# Look-alike names: a dot matches only a dot, the name ends at the quote.
sed 's/"com\.jimdo\.xakerd\.season2hit"/"comxjimdoxxakerdxseason2hit"/' "$fx/app_data.json" >"$apps"
supplier "$fx/series.json" error_is err_not_installed
sed 's/"com\.jimdo\.xakerd\.season2hit"/"com.jimdo.xakerd.season2hit.tv"/' "$fx/app_data.json" >"$apps"
supplier "$fx/series.json" error_is err_not_installed
# The other SeasonHit package of older versions is another app.
sed 's/"com\.jimdo\.xakerd\.season2hit"/"com.jimdo.xakerd.seasonhit"/' "$fx/app_data.json" >"$apps"
supplier "$fx/series.json" error_is err_not_installed
cp "$fx/app_data.json" "$apps"

# --- Search by title: the helpers live in search.sh only, the items that
# search call its search_query.
# only_in_search: no other bin/*.sh defines a function of search.sh (any
# spacing or indent before "()").
only_in_search() {
    fns=$(sed -n 's/^[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)[[:space:]]*([[:space:]]*).*/\1/p' "$src/bin/search.sh")
    [ -n "$fns" ] || return 1
    for f in $fns; do
        [ "$(grep -lE "^[[:space:]]*${f}[[:space:]]*\\([[:space:]]*\\)" "$src"/bin/*.sh)" = "$src/bin/search.sh" ] || return 1
    done
}
check "search.sh: its functions are defined in no other bin/*.sh" only_in_search
check "vokino.sh, lazymedia.sh, alpac.sh and seasonhit.sh source search.sh and call search_query" sh -c '
    for s in vokino lazymedia alpac seasonhit; do
        grep -qx "\. \"\${0%/\*}/search\.sh\"" "$1/$s.sh" && grep -q "q=\$(search_query \"\$input\")" "$1/$s.sh" || exit 1
    done' _ "$src/bin"

# --- filmix_api.sh, bazinga.sh, iptvce.sh: answer only if play_action was ignored
for id in filmix_api bazinga iptvce; do
    for args in start_playback_app '' get_stream_url; do
        # shellcheck disable=SC2086 # split on purpose
        run "$id.sh" $args <"$fx/movie.json"
        check "$id args '$args': exit 0" rc_is 0
        check "$id args '$args': one line of JSON" one_json
        check "$id args '$args': err_unsupported" error_is err_unsupported
    done
    run "$id.sh" start_playback_app </dev/null
    check "$id empty stdin: exit 0" rc_is 0
    check "$id empty stdin: one line of JSON" one_json
done

# --- sync.sh: the item JSON of every app

# item_is <file> <id>: supplier JSON of app <id> with its bin and icon.
# FS_PREFIX in the icon path is the fixture's (from app_data.json).
item_is() {
    python3 - "$1" "$2" "$3" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
app, bindir = sys.argv[2], sys.argv[3]
pkg = {"nuvio": "com.nuvio.tv", "stremio": "com.stremio.one", "num": "ru.yourok.num",
       "lampa": "top.rootu.lampa", "bylampa": "top.rootu.bylumpa", "lampa_atv": "top.rootu.lumpa",
       "prisma": "top.rootu.prisma", "vokino": "ru.vokino.web",
       "lazymedia": "com.lazycatsoftware.lmd", "freezona": "free.zona", "alpac": "cc.alcopa.tv",
       "flux": "app.flux.tv", "seasonhit": "com.jimdo.xakerd.season2hit"}.get(app)
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
    want["icon_url"] = "plugin_file://%%%s%%/icons/logo.png" % {"filmix_api": "Filmix_api", "bazinga": "Bazinga3"}[app]
    want["play_action"] = {
        "handler_string_id": "plugin_handle_user_input",
        "plugin_name": "play_in_apps",
        "params": {"handler_id": app, "control_id": "play"},
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

# Filmix_API and Bazinga3 are not installed yet.
run sync.sh
check "sync: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "sync: items of all Android apps, no Filmix and Bazinga, no temp files" shown $android
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
opens_series bylampa launch_is "$t/tv/94997"
opens_series lampa_atv launch_is "$t/tv/94997"
opens_series prisma launch_is "$t/tv/94997"
opens_series vokino launch_is "$v/tt11198330"
opens_series lazymedia search_is 'Дом Дракона'
# series.json has no Kinopoisk ID; the error key shows bin/freezona.sh ran.
opens_series freezona error_is err_no_id
opens_series alpac launch_is "$a/tv/94997"
opens_series flux launch_is flux://series/94997
opens_series seasonhit search_is 'Дом Дракона'

mkdir -p "$plugins/Filmix_api" "$plugins/Bazinga3"
run sync.sh
check "sync Filmix_API dir without manifest: no Filmix item" no_file "$reg/filmix_api"
check "sync Bazinga3 dir without manifest: no Bazinga item" no_file "$reg/bazinga"
: >"$plugins/Filmix_api/dune_plugin.xml"
run sync.sh
check "sync Filmix_API installed: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "sync Filmix_API installed: its item, no Bazinga" shown $android filmix_api
: >"$plugins/Bazinga3/dune_plugin.xml"
run sync.sh
check "sync Bazinga3 installed: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "sync Bazinga3 installed: all items" shown $all
for id in filmix_api bazinga; do
    check "sync: $id item JSON" item_is "$reg/$id" "$id" "$bin"
    cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bin"])' "$menu/$id")
    (cd / && "$sh_bin" -c "$cmd start_playback_app" <"$fx/series.json" >"$o" 2>"$o.err")
    check "registered bin of $id: err_unsupported" error_is err_unsupported
done

# --- sync: hidden items
printf 'nuvio\nfilmix_api\n' >"$data/hidden"
run sync.sh
check "sync hidden: exit 0" rc_is 0
check "sync hidden: nuvio and filmix_api removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia stremio freezona alpac flux seasonhit bazinga
printf 'freezona\n' >"$data/hidden"
run sync.sh
check "sync hidden: freezona removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio alpac flux seasonhit bazinga
printf 'alpac\n' >"$data/hidden"
run sync.sh
check "sync hidden: alpac removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona flux seasonhit bazinga
printf 'flux\n' >"$data/hidden"
run sync.sh
check "sync hidden: flux removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona alpac seasonhit bazinga
printf 'seasonhit\n' >"$data/hidden"
run sync.sh
check "sync hidden: seasonhit removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona alpac flux bazinga
printf 'bazinga\n' >"$data/hidden"
run sync.sh
check "sync hidden: bazinga removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona alpac flux seasonhit
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
check "sync garbage in hidden: only prisma hidden" shown num lampa bylampa lampa_atv vokino lazymedia filmix_api stremio nuvio freezona alpac flux seasonhit bazinga
check "sync garbage in hidden: no stray files" listing_is "$data" hidden movie_suppliers
rm -f "$data/hidden"

# --- sync: an app not installed (or uninstalled later)
cp "$fx/app_data_no_lazymedia.json" "$apps"
run sync.sh
check "sync LazyMedia not installed: item removed" shown num lampa prisma vokino filmix_api stremio nuvio bazinga
cp "$fx/app_data_no_alpac.json" "$apps"
run sync.sh
check "sync ALPAC not installed: item removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona bazinga
cp "$fx/app_data_no_flux.json" "$apps"
run sync.sh
check "sync Flux not installed: item removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona alpac bazinga
cp "$fx/app_data_no_seasonhit.json" "$apps"
run sync.sh
check "sync SeasonHit not installed: item removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona alpac flux bazinga
cp "$fx/app_data_no_freezona.json" "$apps"
run sync.sh
check "sync FreeZona not installed: item removed" shown num lampa prisma vokino lazymedia filmix_api stremio nuvio bazinga
cp "$fx/app_data_no_bylampa.json" "$apps"
run sync.sh
check "sync BYLAMPA not installed: item removed, Lampa shown" shown num lampa prisma vokino lazymedia filmix_api stremio nuvio freezona bazinga
cp "$work/app_data_only_bylampa.json" "$apps"
run sync.sh
check "sync Lampa not installed: item removed, BYLAMPA shown" shown num bylampa prisma vokino lazymedia filmix_api stremio nuvio freezona alpac flux seasonhit bazinga
cp "$fx/app_data_no_lampa_atv.json" "$apps"
run sync.sh
check "sync LAMPA ATV not installed: item removed" shown num lampa bylampa prisma vokino lazymedia filmix_api stremio nuvio freezona bazinga
cp "$work/app_data_only_lampa_atv.json" "$apps"
run sync.sh
check "sync only LAMPA ATV of the Lampa apps: its item shown" shown num lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona alpac flux seasonhit bazinga
cp "$fx/app_data_no_nuvio.json" "$apps"
run sync.sh
check "sync only Settings installed: only Filmix and Bazinga" shown filmix_api bazinga
cp "$fx/app_data.json" "$apps"
run sync.sh
# shellcheck disable=SC2086 # one word per id
check "sync apps installed again: all items" shown $all

# --- sync: no app list -> Android items stay as they are, Filmix still synced
printf 'lazymedia\n' >"$data/hidden"
run sync.sh
rm -f "$apps"
printf 'lazymedia\nnuvio\n' >"$data/hidden"
rm -f "$plugins/Filmix_api/dune_plugin.xml" "$plugins/Bazinga3/dune_plugin.xml"
run sync.sh
check "sync no app_data.json: exit 0" rc_is 0
check "sync no app_data.json: Android items unchanged, Filmix and Bazinga removed" shown num lampa bylampa lampa_atv prisma vokino stremio nuvio freezona alpac flux seasonhit
for content in '' '{}' 'garbage' '{"applications":['; do
    printf '%s' "$content" >"$apps"
    run sync.sh
    check "sync app_data.json '$content': Android items unchanged" shown num lampa bylampa lampa_atv prisma vokino stremio nuvio freezona alpac flux seasonhit
done
# Read while the shell rewrites it: cut short, most apps missing.
head -c 1500 "$fx/app_data.json" >"$apps"
run sync.sh
check "sync app_data.json cut short: Android items unchanged" shown num lampa bylampa lampa_atv prisma vokino stremio nuvio freezona alpac flux seasonhit
cp "$fx/app_data.json" "$apps"
: >"$plugins/Filmix_api/dune_plugin.xml"
: >"$plugins/Bazinga3/dune_plugin.xml"
rm -f "$data/hidden"
run sync.sh

# --- movie_suppliers_update.sh: runs sync.sh, arguments are ignored
rm -rf "$reg" "$menu"
run movie_suppliers_update.sh other other '../evil' x
check "update: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "update: all items, nothing else" shown $all
check "update: nothing outside" listing_is "$data" movie_suppliers

# --- sync: IPTV Channel Editor builds (iptvce_builds.sh), an item each

# build <name> [<caption XML text> [<icon_url XML text>]]: plugins/<name> made
# of the Mir Kino fixture (tests/fixtures/iptvce_mirkino); a caption or an
# icon_url given goes first in its dune_plugin.xml, an empty one removes all
# of them. Bytes of the arguments are written as they are.
build() {
    rm -rf "${plugins:?}/$1"
    cp -R "$fx/iptvce_mirkino" "$plugins/$1"
    [ $# -gt 1 ] || return 0
    # Through files: bytes in argv reach Python decoded by the locale.
    printf '%s' "$2" >"$work/build_caption"
    printf '%s' "${3-plugin_file://img/logo_mirkino.png}" >"$work/build_icon"
    python3 - "$fx/iptvce_mirkino/dune_plugin.xml" "$plugins/$1/dune_plugin.xml" "$work/build_caption" "$work/build_icon" <<'EOF'
import re, sys
x = open(sys.argv[1], "rb").read()
for tag, v in ((b"icon_url", open(sys.argv[4], "rb").read()), (b"caption", open(sys.argv[3], "rb").read())):
    if v == b"":
        x = re.sub(rb"\s*<" + tag + rb">[^<]*</" + tag + rb">", b"", x)
    else:
        x = x.replace(b"<dune_plugin>", b"<dune_plugin>\n\t<" + tag + b">" + v + b"</" + tag + b">", 1)
open(sys.argv[2], "wb").write(x)
EOF
}
# build_item_is <name> <caption> [<icon path in the build>]: the item JSON of
# a build in plugins_data, one line.
build_item_is() {
    [ "$(wc -l <"$reg/iptvce_$1" | tr -d ' ')" = 1 ] || return 1
    python3 - "$reg/iptvce_$1" "$1" "$2" "${3-}" "$bin" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
name, cap, icon, bindir = sys.argv[2:6]
want = {"plugin": "play_in_apps", "caption": cap, "langs": "any", "supported_video_types": "video",
        "bin": "sh %s/iptvce.sh" % bindir, "playback_type": "app",
        "play_action": {"handler_string_id": "plugin_handle_user_input", "plugin_name": "play_in_apps",
                        "params": {"handler_id": "iptvce_" + name, "control_id": "play"}}}
if icon:
    want["icon_url"] = "plugin_file://%%%s%%/%s" % (name, icon)
sys.exit(d != want)
EOF
}

build mirkino
run sync.sh
check "sync build: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "sync build: its item after the fixed ones" shown $all iptvce_mirkino
check "sync build: item JSON, caption and icon of the build" build_item_is mirkino 'Mir Kino' img/logo_mirkino.png
cmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["bin"])' "$menu/iptvce_mirkino")
(cd / && "$sh_bin" -c "$cmd start_playback_app" <"$fx/movie.json" >"$o" 2>"$o.err")
id=iptvce
check "registered bin of a build: err_unsupported" error_is err_unsupported

# Captions: Cyrillic, entities, " and \ as they are, < and > dropped, spaces
# trimmed, cut at 40 characters; anything unsafe -> the folder name.
build kino ' Кино &quot;Мир&quot; "x" \ &amp;lt; &lt;b&gt; '
build long "$(printf 'Ж%.0s' $(seq 1 39))Юя"
build ascii40 "$(printf 'a%.0s' $(seq 1 40))"
build tab "$(printf 'Mir\tKino')"
build badutf "$(printf 'Mir \377 Kino')"
build surrogate "$(printf 'Mir \355\240\200 Kino')"
build overlong "$(printf 'Mir \300\257 Kino')"
build trkey '%tr%plugin_caption'
build blank '   '
build nocap ''
run sync.sh
check "sync captions: exit 0" rc_is 0
check "sync caption: Cyrillic, entities, quote and backslash, no < >" build_item_is kino 'Кино "Мир" "x" \ &lt; b' img/logo_mirkino.png
check "sync caption: cut at 40 characters" build_item_is long "$(printf 'Ж%.0s' $(seq 1 39))Ю" img/logo_mirkino.png
check "sync caption: 40 characters kept" build_item_is ascii40 "$(printf 'a%.0s' $(seq 1 40))" img/logo_mirkino.png
for b in tab badutf surrogate overlong trkey blank nocap; do
    check "sync caption $b: the folder name" build_item_is "$b" "$b" img/logo_mirkino.png
done
check "sync captions: valid JSON for PHP too (one line, no raw control bytes)" sh -c \
    '! LC_ALL=C grep -q "$(printf "[\001-\037]")" "$1"/iptvce_*' _ "$reg"
for b in kino long ascii40 tab badutf surrogate overlong trkey blank nocap; do rm -rf "${plugins:?}/$b"; done

# Icons: only plugin_file:// with a safe path of an existing file.
build icon_up 'Up' 'plugin_file://../play_in_apps/icons/logo.png'
build icon_space 'Space' 'plugin_file://img/logo mirkino.png'
build icon_abs 'Abs' "plugin_file://$plugins/mirkino/img/logo_mirkino.png"
build icon_http 'Http' 'http://example.com/logo.png'
build icon_skin 'Skin' 'gui_skin://small_icons/tv.aai'
build icon_missing 'Missing' 'plugin_file://img/none.png'
build icon_dir 'Dir' 'plugin_file://img'
build icon_quote 'Quote' 'plugin_file://img/a"b.png'
build icon_none 'None' ''
run sync.sh
check "sync icons: exit 0" rc_is 0
for b in up:Up space:Space abs:Abs http:Http skin:Skin missing:Missing dir:Dir quote:Quote none:None; do
    check "sync icon ${b%%:*}: no icon" build_item_is "icon_${b%%:*}" "${b#*:}"
done
for b in up space abs http skin missing dir quote none; do rm -rf "${plugins:?}/icon_$b"; done

# Not a build with VOD, or an unsafe folder name: no item.
build novod
sed 's/"Json"/"None"/' "$fx/iptvce_mirkino/config.json" >"$plugins/novod/config.json"
build noengine
sed '/vod_engine/d' "$fx/iptvce_mirkino/config.json" >"$plugins/noengine/config.json"
build noconfig
rm -f "$plugins/noconfig/config.json"
build nostarnet
rm -f "$plugins/nostarnet/starnet_plugin.php"
build novodlist
rm -f "$plugins/novodlist/screens_vod/starnet_vod_list_screen.php"
build nostarnetfile
rm -f "$plugins/nostarnetfile/starnet_plugin.php"
mkdir "$plugins/nostarnetfile/starnet_plugin.php"
# "None" in any case is VOD off.
build novodlow
sed 's/"Json"/"none"/' "$fx/iptvce_mirkino/config.json" >"$plugins/novodlow/config.json"
build novodup
sed 's/"Json"/"NONE"/' "$fx/iptvce_mirkino/config.json" >"$plugins/novodup/config.json"
for b in 'mir kino' a..b .x -x 'мир' "$(printf 'n%.0s' $(seq 1 41))"; do
    build "$b"
done
# Dots and hyphens inside a name: builds (the author's iedem.tv and others).
for b in iedem.tv fox-fun.tv viplime.fun.tv "$(printf 'n%.0s' $(seq 1 40))"; do
    build "$b"
done
: >"$plugins/notadir"
run sync.sh
check "sync not builds, unsafe names: exit 0" rc_is 0
# shellcheck disable=SC2086 # one word per id
check "sync not builds, unsafe names: only mirkino, names with . and -, the 40-character name" \
    shown $all iptvce_mirkino iptvce_iedem.tv iptvce_fox-fun.tv iptvce_viplime.fun.tv \
    "iptvce_$(printf 'n%.0s' $(seq 1 40))"
check "sync build iedem.tv: item JSON, icon of the build" build_item_is iedem.tv 'Mir Kino' img/logo_mirkino.png
for b in novod noengine noconfig nostarnet novodlist nostarnetfile novodlow novodup 'mir kino' a..b .x -x 'мир' \
    "$(printf 'n%.0s' $(seq 1 41))" iedem.tv fox-fun.tv viplime.fun.tv "$(printf 'n%.0s' $(seq 1 40))" notadir; do
    rm -rf "${plugins:?}/$b"
done

# Hidden, removed, two builds; the copies in /tmp follow.
build kino 'Кино'
printf 'iptvce_mirkino\n' >"$data/hidden"
run sync.sh
# shellcheck disable=SC2086 # one word per id
check "sync build hidden: its item removed, the other shown" shown $all iptvce_kino
printf 'iptvce_mirkino \niptvce_*\nIPTVCE_KINO\n' >"$data/hidden"
run sync.sh
# shellcheck disable=SC2086 # one word per id
check "sync build, garbage in hidden: both shown" shown $all iptvce_kino iptvce_mirkino
rm -f "$data/hidden"
rm -rf "${plugins:?}/kino"
run sync.sh
# shellcheck disable=SC2086 # one word per id
check "sync build removed: its item removed" shown $all iptvce_mirkino
# Left by an older state: a copy only in /tmp; files of others stay, also
# with our prefix.
printf '{"plugin":"play_in_apps"}\n' >"$menu/iptvce_gone"
printf '{"plugin":"other"}\n' >"$menu/iptvce_foreign"
printf '{"plugin":"other"}\n' >"$reg/iptvce_foreign2"
: >"$menu/iptvce_a b"
: >"$menu/YouTube"
run sync.sh
# shellcheck disable=SC2086 # one word per id
check "sync: stale build copies in /tmp removed, others kept" \
    listing_is "$menu" $all iptvce_mirkino YouTube iptvce_foreign "iptvce_a b"
check "sync: a file of another plugin with our prefix kept as is" \
    grep -qxF '{"plugin":"other"}' "$menu/iptvce_foreign"
check "sync: not our file in plugins_data kept" test -f "$reg/iptvce_foreign2"
rm -f "$menu/YouTube" "$menu/iptvce_foreign" "$menu/iptvce_a b" "$reg/iptvce_foreign2"

# Other device classes: the builds are found next to the plugin, whatever
# FS_PREFIX is; the icon is the build's plugin_file://.
rm -rf "$reg"
(cd "$work" && FS_PREFIX='' PLAY_IN_APPS_FLASHDATA="$work/fs/flashdata" "$sh_bin" "$bin/sync.sh" >"$o" 2>"$o.err")
check "sync FS_PREFIX empty: build item" build_item_is mirkino 'Mir Kino' img/logo_mirkino.png
rm -rf "${plugins:?}/mirkino"
run sync.sh
# shellcheck disable=SC2086 # one word per id
check "sync builds gone: fixed items only" shown $all

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
       "lampa": "top.rootu.lampa", "bylampa": "top.rootu.bylumpa", "lampa_atv": "top.rootu.lumpa",
       "prisma": "top.rootu.prisma", "vokino": "ru.vokino.web",
       "lazymedia": "com.lazycatsoftware.lmd", "freezona": "free.zona", "alpac": "cc.alcopa.tv",
       "flux": "app.flux.tv", "seasonhit": "com.jimdo.xakerd.season2hit"}
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

# The shell's file of the item choice dialog goes too; a symlink there is
# removed, not followed.
cfg="$work/fs/config"
lcfg="$cfg/lcfg_play_in_apps.txt"
mkdir -p "$cfg"
printf '%s\n' -num >"$lcfg"
: >"$cfg/lcfg_other.txt"
run uninstall.sh
check "uninstall with a choice file: exit 0" rc_is 0
check "uninstall: choice file removed, others kept" listing_is "$cfg" lcfg_other.txt
printf 'keep\n' >"$work/lcfg_target"
ln -s "$work/lcfg_target" "$lcfg"
run uninstall.sh
check "uninstall: choice file symlink removed, target kept" \
    sh -c '[ ! -e "$1" ] && [ ! -L "$1" ] && [ "$(cat "$2")" = keep ]' _ "$lcfg" "$work/lcfg_target"
rm -f "$cfg/lcfg_other.txt"
# The items of builds: ours removed, a file of another plugin with that name kept.
printf '{"plugin":"play_in_apps","caption":"Mir Kino"}\n' >"$menu/iptvce_mirkino"
printf '{"plugin":"play_in_apps"}\n' >"$menu/iptvce_kino"
printf '{"plugin":"other"}\n' >"$menu/iptvce_other"
: >"$menu/iptvce_a b"
run uninstall.sh
check "uninstall: build items removed, others kept" listing_is "$menu" YouTube iptvce_other "iptvce_a b"
rm -f "$menu/iptvce_other" "$menu/iptvce_a b"

# --- diag.sh: the "Check" report. cmd, getprop, ifconfig and logcat are stand-ins.
sbin="$work/sbin"
mkdir -p "$sbin" "$work/sbin_nocmd"
cat >"$sbin/android_stub" <<'EOF'
#!/bin/sh
# Stand-ins for cmd, getprop, id, ifconfig and logcat, in the formats seen on
# the device (exit code 0 either way, as there). cmd: packages listed in
# STUB_RESOLVE resolve, others do not; STUB_CMD=deny answers with an
# exception. Every cmd call is appended to STUB_LOG. id -u: STUB_UID, 1000 by
# default (the shell's uid on Dune models). ifconfig: the interfaces of
# STUB_IFCONFIG, "<name>:<address>" each, loopback first.
name=${0##*/}
case $name in
cmd)
    printf '%s\n' "$*" >>"${STUB_LOG:-/dev/null}"
    if [ "${STUB_CMD-}" = deny ]; then
        echo 'Exception occurred while executing:'
        echo 'java.lang.SecurityException: Permission Denial'
        exit 0
    fi
    # The intent: URI: package=<pkg> or component=<pkg>/<class>.
    pkg=
    comp=
    for a in "$@"; do
        case $a in
        intent:*)
            pkg=$(printf '%s\n' "$a" | sed -n 's/.*;package=\([^;]*\);.*/\1/p')
            comp=$(printf '%s\n' "$a" | sed -n 's/.*;component=\([^;]*\);.*/\1/p')
            ;;
        esac
    done
    [ -z "$comp" ] || pkg=${comp%%/*}
    case " ${STUB_RESOLVE-} " in
    *" $pkg "*)
        echo '1 activities found:'
        echo '  Activity #0:'
        echo "    priority=0 preferredOrder=0 match=0x508000 specificIndex=-1 isDefault=${STUB_DEFAULT:-true}"
        echo "    ${comp:-$pkg/.MainActivity}"
        ;;
    *) echo 'No activities found' ;;
    esac
    ;;
getprop)
    case $1 in
    ro.product.model) printf '%s\n' "${STUB_MODEL-Pro 8K Plus}" ;;
    ro.build.version.release) echo 11 ;;
    esac
    ;;
id)
    [ "${1-}" = -u ] && echo "${STUB_UID:-1000}"
    ;;
ifconfig)
    for i in lo:127.0.0.1 ${STUB_IFCONFIG:-eth0:192.0.2.10}; do
        printf '%-10sLink encap:Ethernet\n' "${i%%:*}"
        echo "          inet addr:${i#*:}  Mask:255.255.255.0"
        echo '          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1'
        echo
    done
    ;;
logcat) echo '10-06 12:00:00.000  1000  1000 I Stub: LOGCAT_MARK' ;;
esac
exit 0
EOF
chmod 755 "$sbin/android_stub"
for n in cmd getprop id ifconfig logcat; do
    ln -s "$sbin/android_stub" "$sbin/$n"
done
ln -s "$sbin/android_stub" "$work/sbin_nocmd/getprop"
STUB_LOG="$work/cmd.log"
all_pkgs="ru.yourok.num top.rootu.lampa top.rootu.bylumpa top.rootu.lumpa top.rootu.prisma ru.vokino.web com.lazycatsoftware.lmd com.stremio.one com.nuvio.tv free.zona cc.alcopa.tv app.flux.tv com.jimdo.xakerd.season2hit"
STUB_RESOLVE=$all_pkgs
export STUB_LOG STUB_RESOLVE

# diag [args]: bin/diag.sh with the stand-ins first in PATH.
diag() {
    PATH="$sbin:$PATH" "$sh_bin" "$bin/diag.sh" "$@" >"$o" 2>"$o.err"
    echo "$?" >"$o.rc"
}
has_line() { grep -qxF -- "$1" "$o"; }
no_text() { ! grep -qF -- "$1" "$o"; }
# in_item <caption> <text>: the item's verdict line or a reason line under it is text.
in_item() {
    python3 - "$o" "$1" "$2" <<'EOF'
import sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
for i, l in enumerate(lines):
    if l.startswith(sys.argv[2] + ": "):
        block = [l]
        for m in lines[i + 1:]:
            if not m.startswith("  "):
                break
            block.append(m)
        sys.exit(sys.argv[3] not in block)
sys.exit(1)
EOF
}
# verdicts_are <verdict> [<caption>=<verdict>...]: the 15 verdict lines, in
# the order of the items, after the 4 lines about the device.
verdicts_are() {
    python3 - "$o" "$@" <<'EOF'
import sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
caps = ["NUM", "Lampa", "BYLAMPA", "LAMPA ATV", "Prisma", "VoKino", "LazyMedia", "Filmix",
        "Stremio", "Nuvio", "FreeZona", "ALPAC", "Flux", "SeasonHit", "Bazinga"]
want = dict((c, sys.argv[2]) for c in caps)
for a in sys.argv[3:]:
    c, v = a.split("=", 1)
    want[c] = v
got = [l for l in lines if l and not l.startswith(" ")][4:4 + len(caps)]
sys.exit(got != ["%s: %s" % (c, want[c]) for c in caps])
EOF
}

# brief_is <en|ru> [<caption>=<verdict>...]: the brief report is exactly 16
# lines: the device, then "<caption> <version> — <verdict>" per item, OK by
# default.
brief_is() {
    python3 - "$o" "$plugin_version" "$@" <<'EOF'
import sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
ver, ru = sys.argv[2], sys.argv[3] == "ru"
items = [("NUM", "1.0.150"), ("Lampa", "1.13.1"), ("BYLAMPA", "1.13.3"), ("LAMPA ATV", "1.13.3"),
         ("Prisma", "1.3.4"), ("VoKino", "1.1.1-android"), ("LazyMedia", "3.467"), ("Filmix", ""),
         ("Stremio", "1.11.2"), ("Nuvio", "1.0.0"), ("FreeZona", "3.0.74"), ("ALPAC", "1.0.96"),
         ("Flux", "1.63"), ("SeasonHit", "2.4.4.2"), ("Bazinga", "")]
ok = "ОК" if ru else "OK"
verdict = dict((c, ok) for c, _ in items)
verdict["Filmix"] = ok + (" (через плагин Filmix_API)" if ru else " (through the Dune plugin Filmix_API)")
verdict["Bazinga"] = ok + (" (через плагин Bazinga3)" if ru else " (through the Dune plugin Bazinga3)")
version = dict(items)
for a in sys.argv[4:]:
    c, v = a.split("=", 1)
    verdict[c] = v
want = ["Pro 8K Plus · r24 260827 · Android 11 · %s %s" % ("плагин" if ru else "plugin", ver)]
want += ["%s%s — %s" % (c, " " + version[c] if version[c] else "", verdict[c]) for c, _ in items]
sys.exit(lines != want + [""])
EOF
}
# brief_all <verdict> [args of brief_is]: every Android item has this verdict.
brief_all() {
    v=$1
    shift
    brief_is en NUM="$v" Lampa="$v" BYLAMPA="$v" "LAMPA ATV=$v" Prisma="$v" VoKino="$v" \
        LazyMedia="$v" Stremio="$v" Nuvio="$v" FreeZona="$v" ALPAC="$v" Flux="$v" SeasonHit="$v" "$@"
}
# no_details: none of the full report's details.
no_details() { ! grep -qE 'am start|intent|menu item|installed:|launch:|FS_PREFIX|records|movie_suppliers' "$o"; }

mkdir -p "$plugins/Filmix_api" "$plugins/Bazinga3" "$PLAY_IN_APPS_TMP/run"
: >"$plugins/Filmix_api/dune_plugin.xml"
: >"$plugins/Bazinga3/dune_plugin.xml"
cp "$fx/app_data.json" "$apps"
rm -f "$data/hidden"
run sync.sh
printf 'api_version=1.1.0\nfirmware_version=260827_0003_r24\nproduct=tv188b\n' >"$PLAY_IN_APPS_TMP/run/versions.txt"
plugin_version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' "$src/dune_plugin.xml")
q='package query-activities --brief'

: >"$STUB_LOG"
diag
check "diag: exit 0, no stderr" sh -c '[ "$(cat "$1.rc")" = 0 ] && [ ! -s "$1.err" ]' _ "$o"
check "diag: device" has_line "Device: Pro 8K Plus, Android 11"
check "diag: firmware" has_line "Firmware: 260827_0003_r24 (tv188b)"
check "diag: FS_PREFIX set" has_line "FS_PREFIX: set"
check "diag: plugin version and uid" has_line "Plugin: play_in_apps $plugin_version (uid 1000)"
check "diag all resolve: every item OK" verdicts_are OK
check "diag NUM: installed with version" in_item NUM "  installed: yes, version 1.0.150 (ru.yourok.num)"
check "diag NUM: not hidden" in_item NUM "  hidden: no"
check "diag NUM: menu file ours" in_item NUM "  menu item: yes, plugin play_in_apps"
check "diag NUM: launch command of bin/num.sh" in_item NUM \
    "  launch: am start --activity-clear-task 'intent://www.themoviedb.org/movie/920#Intent;scheme=https;action=android.intent.action.VIEW;package=ru.yourok.num;end'"
check "diag NUM: resolves" in_item NUM "  intent: resolves -> ru.yourok.num/.MainActivity"
check "diag VoKino: resolves" in_item VoKino "  intent: resolves -> ru.vokino.web/.MainActivity"
check "diag LazyMedia: resolves by component" in_item LazyMedia \
    "  intent: resolves -> com.lazycatsoftware.lmd/com.lazycatsoftware.lazymediadeluxe.ui.tv.activities.ActivityTvSearch"
check "diag Filmix: Filmix_API installed" in_item Filmix "  installed: yes (Filmix_API)"
check "diag Filmix: not checked" in_item Filmix "  launch: through the Dune plugin Filmix_API, not checked"
check "diag Bazinga: Bazinga3 installed" in_item Bazinga "  installed: yes (Bazinga3)"
check "diag Bazinga: not checked" in_item Bazinga "  launch: through the Dune plugin Bazinga3, not checked"
check "diag: no shell log lines" has_line "  none"
check "diag: no empty lines" sh -c '! grep -q "^\$" "$1"' _ "$o"
check "diag: 13 queries, Filmix and Bazinga none" test "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 13
ifr='#Intent;scheme=https;action=android.intent.action.VIEW;package'
check "diag query NUM: the intent: URI of the item" grep -qxF \
    "$q intent://www.themoviedb.org/movie/920$ifr=ru.yourok.num;end" "$STUB_LOG"
check "diag query FreeZona: Kinopoisk link" grep -qxF \
    "$q intent://www.kinopoisk.ru/film/61249$ifr=free.zona;end" "$STUB_LOG"
check "diag query VoKino" grep -qxF \
    "$q intent://ru.vokino.web/view/tt0317219#Intent;scheme=vokino;action=android.intent.action.VIEW;package=ru.vokino.web;end" "$STUB_LOG"
check "diag query ALPAC: TMDB movie link" grep -qxF \
    "$q intent://title/movie/920#Intent;scheme=alpac;action=android.intent.action.VIEW;package=cc.alcopa.tv;end" "$STUB_LOG"
check "diag query Flux: TMDB movie link" grep -qxF \
    "$q intent://movie/920#Intent;scheme=flux;action=android.intent.action.VIEW;package=app.flux.tv;end" "$STUB_LOG"
check "diag query Stremio" grep -qxF \
    "$q intent:///detail/movie/tt0317219#Intent;scheme=stremio;action=android.intent.action.VIEW;package=com.stremio.one;end" "$STUB_LOG"
check "diag query Nuvio" grep -qxF \
    "$q intent://movie/tt0317219#Intent;scheme=nuvio;action=android.intent.action.VIEW;package=com.nuvio.tv;end" "$STUB_LOG"
check "diag query LazyMedia: the intent: URI with the component" grep -qxF \
    "$q intent:#Intent;component=com.lazycatsoftware.lmd/com.lazycatsoftware.lazymediadeluxe.ui.tv.activities.ActivityTvSearch;S.query=%D0%A2%D0%B0%D1%87%D0%BA%D0%B8;end" "$STUB_LOG"
check "diag query SeasonHit: the intent: URI with the component" grep -qxF \
    "$q intent:#Intent;component=com.jimdo.xakerd.season2hit/com.jimdo.xakerd.season2hit.activity.SearchActivity;S.query=%D0%A2%D0%B0%D1%87%D0%BA%D0%B8;end" "$STUB_LOG"
check "diag: no query has -p" sh -c '! grep -q -- " -p " "$1"' _ "$STUB_LOG"
check "diag: no -p warning" no_text "has -p"

# An item whose command has -p (a regression) or is not one known intent: URI.
# fake_num <command>: bin/num.sh answers with this command.
fake_num() {
    printf '{"bin":"%s","package":"ru.yourok.num"}\n' "$1" >"$work/num_reply"
    printf 'cat "%s"\n' "$work/num_reply" >"$bin/num.sh"
}
cp "$bin/num.sh" "$work/num.sh.orig"
for c in "am start --activity-clear-task -a android.intent.action.VIEW -d 'https://www.themoviedb.org/movie/920' -p ru.yourok.num" \
    "am start 'intent://www.themoviedb.org/movie/920$ifr=ru.yourok.num;end' -p ru.yourok.num"; do
    fake_num "$c"
    : >"$STUB_LOG"
    diag
    check "diag -p in the command: warning" in_item NUM "  warning: the command has -p, some firmware (r24 260214) rejects it"
    check "diag -p in the command: not checked" in_item NUM "  intent: no data (unknown command)"
    check "diag -p in the command: verdict" verdicts_are OK "NUM=?? could not check the launch"
    check "diag -p in the command: no query for NUM" sh -c '! grep -q ru.yourok.num "$1"' _ "$STUB_LOG"
done
diag russian
check "diag russian -p warning" in_item NUM "  внимание: в команде есть -p, его не понимают некоторые прошивки (r24 260214)"
for c in "am start 'intent://www.themoviedb.org/movie/920#Intent;scheme=https;end'" \
    "am start 'intent://a b$ifr=ru.yourok.num;end'" \
    "am start 'intent://a$ifr=ru.yourok.num;end' x" \
    "am start --activity-clear-task 'https://www.themoviedb.org/movie/920'"; do
    fake_num "$c"
    diag
    check "diag unknown command ($c): not checked" in_item NUM "  intent: no data (unknown command)"
    check "diag unknown command ($c): no -p warning" no_text "has -p"
done
cp "$work/num.sh.orig" "$bin/num.sh"

# Brief: the check screen, one line per item.
: >"$STUB_LOG"
diag english brief
check "diag brief: exit 0, no stderr" sh -c '[ "$(cat "$1.rc")" = 0 ] && [ ! -s "$1.err" ]' _ "$o"
check "diag brief: device line, then one line per item with version" brief_is en
check "diag brief: no details" no_details
check "diag brief: the same 13 queries" test "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 13
diag russian brief
check "diag brief russian" brief_is ru
diag english brief extra
check "diag brief, extra argument: still brief" brief_is en
diag brief
check "diag brief as the first argument: full report" has_line "Device: Pro 8K Plus, Android 11"
cp "$PLAY_IN_APPS_TMP/run/versions.txt" "$work/versions.txt"
printf 'firmware_version=custom_build\n' >"$PLAY_IN_APPS_TMP/run/versions.txt"
diag english brief
check "diag brief, other firmware name: as is" sh -c 'head -n 1 "$1" | grep -qxF "Pro 8K Plus · custom_build · Android 11 · plugin $2"' _ "$o" "$plugin_version"
rm -f "$PLAY_IN_APPS_TMP/run/versions.txt"
diag english brief
check "diag brief, no versions.txt: ?" sh -c 'head -n 1 "$1" | grep -qxF "Pro 8K Plus · ? · Android 11 · plugin $2"' _ "$o" "$plugin_version"
cp "$work/versions.txt" "$PLAY_IN_APPS_TMP/run/versions.txt"

STUB_RESOLVE=
diag
check "diag none resolves: verdicts" verdicts_are "!! the app will not take the link" Filmix=OK Bazinga=OK
check "diag none resolves: reason" in_item NUM "  intent: does not resolve, the app will not take this link"
diag english brief
check "diag brief none resolves" brief_all "the app will not take the link"
diag russian brief
check "diag brief russian none resolves: FreeZona" grep -qxF "FreeZona 3.0.74 — приложение не примет ссылку" "$o"
STUB_RESOLVE=$all_pkgs
STUB_DEFAULT=false
export STUB_DEFAULT
diag
check "diag isDefault=false: noted" in_item NUM "  intent: resolves -> ru.yourok.num/.MainActivity (isDefault=false)"
unset STUB_DEFAULT
STUB_CMD=deny
export STUB_CMD
diag
check "diag cmd refuses: no data" verdicts_are "?? could not check the launch" Filmix=OK Bazinga=OK
check "diag cmd refuses: first line" in_item NUM "  intent: no data: Exception occurred while executing:"
diag english brief
check "diag brief cmd refuses" brief_all "could not check the launch"
check "diag brief cmd refuses: no details" no_details
unset STUB_CMD
# Not the system uid (Dune HD as an app on Android TV): Android 11+ may hide
# installed apps from it, so "No activities found" proves nothing.
STUB_UID=10123
export STUB_UID
STUB_RESOLVE=
diag
check "diag uid 10123, No activities found: no data" verdicts_are "?? could not check the launch" Filmix=OK Bazinga=OK
check "diag uid 10123: the answer in the full report" in_item NUM \
    "  intent: no data (not a system process, uid 10123): No activities found"
check "diag uid 10123: uid in the full report" has_line "Plugin: play_in_apps $plugin_version (uid 10123)"
diag english brief
check "diag brief uid 10123: could not check" brief_all "could not check the launch"
check "diag brief uid 10123: no details" no_details
STUB_RESOLVE=$all_pkgs
diag
check "diag uid 10123, resolves: OK" verdicts_are OK
STUB_RESOLVE=
for u in 0 1000 2000 9999; do
    STUB_UID=$u
    diag
    check "diag uid $u (not an ordinary app): does not resolve" verdicts_are "!! the app will not take the link" Filmix=OK Bazinga=OK
done
STUB_UID=10000
diag
check "diag uid 10000 (an ordinary app): no data" verdicts_are "?? could not check the launch" Filmix=OK Bazinga=OK
STUB_RESOLVE=$all_pkgs
unset STUB_UID
if ! command -v cmd >/dev/null 2>&1; then
    PATH="$work/sbin_nocmd:$PATH" "$sh_bin" "$bin/diag.sh" >"$o" 2>"$o.err"
    check "diag no cmd: no data" verdicts_are "?? could not check the launch" Filmix=OK Bazinga=OK
    check "diag no cmd: reason" in_item NUM "  intent: no data (no cmd command)"
fi

diag russian
check "diag russian: device" has_line "Устройство: Pro 8K Plus, Android 11"
check "diag russian: FS_PREFIX" has_line "FS_PREFIX: задан"
check "diag russian: verdict" has_line "NUM: OK"
check "diag russian: reason" in_item NUM "  установлено: да, версия 1.0.150 (ru.yourok.num)"
diag 'russian;id'
check "diag unknown language: English" has_line "Device: Pro 8K Plus, Android 11"

# Hidden and not installed items.
printf 'num\nfilmix_api\nbazinga\n' >"$data/hidden"
run sync.sh
diag
check "diag hidden: verdicts" verdicts_are OK NUM="-- hidden" Filmix="-- hidden" Bazinga="-- hidden"
check "diag hidden: reason" in_item NUM "  hidden: yes"
check "diag hidden: no menu file" in_item NUM "  menu item: no"
diag english brief
check "diag brief hidden" brief_is en NUM=hidden Filmix=hidden Bazinga=hidden
diag russian brief
check "diag brief russian hidden" brief_is ru NUM=скрыт Filmix=скрыт Bazinga=скрыт
cp "$fx/app_data_no_vokino.json" "$apps"
diag
check "diag VoKino not installed: verdict" in_item VoKino "VoKino: -- not installed"
check "diag VoKino not installed: reason" in_item VoKino "  installed: no (ru.vokino.web)"
check "diag VoKino not installed: what the item says" in_item VoKino "  launch: error: VoKino is not installed"
diag english brief
check "diag brief VoKino not installed: no version" sh -c 'grep -qxF "VoKino — not installed" "$1" && grep -qxF "NUM 1.0.150 — hidden" "$1"' _ "$o"
rm -f "$plugins/Filmix_api/dune_plugin.xml" "$plugins/Bazinga3/dune_plugin.xml"
diag russian brief
check "diag brief Filmix_API not installed" grep -qxF "Filmix — не установлено" "$o"
check "diag brief Bazinga3 not installed" grep -qxF "Bazinga — не установлено" "$o"
diag
check "diag Bazinga3 not installed: reason" in_item Bazinga "  installed: no (Bazinga3)"
: >"$plugins/Filmix_api/dune_plugin.xml"
: >"$plugins/Bazinga3/dune_plugin.xml"
rm -f "$data/hidden"
cp "$fx/app_data.json" "$apps"
run sync.sh
# Each Dune plugin item looks at its own plugin's folder only.
rm -f "$plugins/Bazinga3/dune_plugin.xml"
run sync.sh
diag
check "diag only Filmix_API installed: verdicts" verdicts_are OK Bazinga="-- not installed"
check "diag only Filmix_API installed: Filmix installed" in_item Filmix "  installed: yes (Filmix_API)"
check "diag only Filmix_API installed: Bazinga not" in_item Bazinga "  installed: no (Bazinga3)"
: >"$plugins/Bazinga3/dune_plugin.xml"
rm -f "$plugins/Filmix_api/dune_plugin.xml"
run sync.sh
diag
check "diag only Bazinga3 installed: verdicts" verdicts_are OK Filmix="-- not installed"
check "diag only Bazinga3 installed: Bazinga installed" in_item Bazinga "  installed: yes (Bazinga3)"
check "diag only Bazinga3 installed: Filmix not" in_item Filmix "  installed: no (Filmix_API)"
: >"$plugins/Filmix_api/dune_plugin.xml"
run sync.sh

# The menu file of an item: someone else's, a missing or relative bin, none.
printf '{"plugin":"num_supplier","bin":"sh %s/num.sh"}\n' "$bin" >"$menu/num"
diag
check "diag foreign menu file" verdicts_are OK NUM="!! the item is from another plugin: num_supplier"
diag english brief
check "diag brief foreign menu file" brief_is en NUM="the item is from another plugin: num_supplier"
printf '{"plugin":"play_in_apps","bin":"sh \\/nonexistent\\/bin\\/num.sh"}\n' >"$menu/num"
diag
check "diag missing bin: verdict" verdicts_are OK NUM="!! the item script is missing"
check "diag missing bin: path" in_item NUM "  menu item: yes, plugin play_in_apps, no script: /nonexistent/bin/num.sh"
diag english brief
check "diag brief missing bin" brief_is en NUM="the item script is missing"
printf '{"plugin":"play_in_apps","bin":"bin/num.sh"}\n' >"$menu/num"
diag
check "diag relative bin: missing" verdicts_are OK NUM="!! the item script is missing"
rm -f "$menu/num"
diag
check "diag no menu file" verdicts_are OK NUM="!! the item is not in the menu"
diag english brief
check "diag brief no menu file" brief_is en NUM="the item is not in the menu"

# Hostile files: their text is only printed.
# shellcheck disable=SC2016 # literal $(...) on purpose
printf '{"plugin":"x\\"; touch %s/pwned1","bin":"sh $(touch %s/pwned2)/num.sh;touch %s/pwned3"}\n' \
    "$work" "$work" "$work" >"$menu/num"
# shellcheck disable=SC2016 # literal $(...) on purpose
sed 's/"version": "1.0.150"/"version": "$(touch pwned4)`id`"/' "$fx/app_data.json" >"$apps"
diag
check "diag hostile files: exit 0" rc_is 0
check "diag hostile files: nothing run" sh -c '[ -z "$(ls "$1" | grep pwned)" ] && [ ! -e /pwned4 ] && [ ! -e pwned4 ]' _ "$work"
# shellcheck disable=SC2016 # literal $(...) on purpose
check "diag hostile version printed as is" in_item NUM '  installed: yes, version $(touch pwned4)`id` (ru.yourok.num)'
cp "$fx/app_data.json" "$apps"
run sync.sh

# Lines of the shell about launches: the last 5 of shell.log, the last 5
# "sup E:" of shell_ext.log, cut at 300 characters.
{
    for n in 1 2 3 4 5 6 7; do
        echo "[2026-10-06 12:00:0$n] gui_action D: activity launch status: $n"
        echo "[2026-10-06 12:00:0$n] noise line $n"
    done
    printf '[2026-10-06 12:00:09] wait for shell app loosing focus timed-out %0400d\n' 0
} >"$PLAY_IN_APPS_TMP/run/shell.log"
printf 'sup E: app not found for package: x\nother\nsup E: second\n' >"$PLAY_IN_APPS_TMP/run/shell_ext.log"
diag
check "diag shell log: heading" has_line "The shell's last records about launching items:"
check "diag shell log: last 5 lines" sh -c 'grep -qF "launch status: 4" "$1" && grep -qF "launch status: 7" "$1" && ! grep -qF "launch status: 3" "$1"' _ "$o"
check "diag shell log: noise left out" no_text "noise line"
check "diag shell log: timed-out cut at 300" sh -c '[ "$(grep "timed-out" "$1" | wc -c | tr -d " ")" = 303 ]' _ "$o"
check "diag shell_ext.log: sup E" sh -c 'grep -qxF "  sup E: app not found for package: x" "$1" && grep -qxF "  sup E: second" "$1"' _ "$o"
diag english brief
check "diag brief: no shell log lines" brief_is en

# A long version in the brief line: 19 characters and "…"; bytes past ASCII
# of a long one become "?", a short one stays as is.
# version_line <version>: the NUM line of the brief report with that version.
version_line() {
    python3 -c 'import sys; open(sys.argv[2], "w").write(open(sys.argv[1]).read().replace("1.0.150", sys.argv[3]))' \
        "$fx/app_data.json" "$apps" "$1"
    diag english brief
    sed -n 2p "$o"
}
check "diag brief version of 20: as is" test "$(version_line 12345678901234567890)" = "NUM 12345678901234567890 — OK"
check "diag brief version of 21: cut" test "$(version_line 123456789012345678901)" = "NUM 1234567890123456789… — OK"
check "diag brief short UTF-8 version: as is" test "$(version_line 'бета 2')" = "NUM бета 2 — OK"
check "diag brief long UTF-8 version: ? in place of bytes, valid UTF-8" test \
    "$(version_line '1.0 бета-сборка')" = "NUM 1.0 ????????-??????… — OK"
check "diag brief: 16 lines with a long version" test "$(wc -l <"$o" | tr -d ' ')" = 16
cp "$fx/app_data.json" "$apps"
rm -f "$PLAY_IN_APPS_TMP/run/shell.log" "$PLAY_IN_APPS_TMP/run/shell_ext.log"

# Other device classes: Android TV (no PLAY_IN_APPS_TMP: paths under
# $FS_PREFIX/tmp) and older Android (FS_PREFIX empty: paths from the root).
env -u PLAY_IN_APPS_TMP FS_PREFIX="$work/atv" PATH="$sbin:$PATH" "$sh_bin" "$bin/diag.sh" >"$o" 2>"$o.err"
check "diag PLAY_IN_APPS_TMP unset: app list from \$FS_PREFIX/tmp" in_item NUM "  installed: yes, version 1.0.150 (ru.yourok.num)"
check "diag PLAY_IN_APPS_TMP unset: menu from \$FS_PREFIX/tmp" in_item NUM "NUM: !! the item is not in the menu"
env -u PLAY_IN_APPS_TMP FS_PREFIX= PATH="$sbin:$PATH" "$sh_bin" "$bin/diag.sh" >"$o" 2>"$o.err"
echo "$?" >"$o.rc"
check "diag FS_PREFIX empty: exit 0" rc_is 0
check "diag FS_PREFIX empty: said so" has_line "FS_PREFIX: empty"
if [ ! -e /tmp/applications/app_data.json ]; then
    check "diag FS_PREFIX empty: app list from /tmp" in_item NUM "NUM: -- not installed"
fi
STUB_MODEL=$(printf 'Pro\377\376\t8K')
export STUB_MODEL
diag
check "diag bad UTF-8 in getprop: exit 0" rc_is 0
unset STUB_MODEL

# IPTV Channel Editor builds: a line each after the fixed items, in name
# order, with the build's caption; nothing to query.
build mirkino
build kino 'Кино "Мир"'
cp "$fx/app_data.json" "$apps"
rm -f "$data/hidden"
run sync.sh
: >"$STUB_LOG"
diag english brief
check "diag brief builds: 18 lines" test "$(wc -l <"$o" | tr -d ' ')" = 18
check "diag brief builds: after Bazinga, in name order" sh -c \
    '[ "$(sed -n "16,18p" "$1")" = "$(printf "%s\n" "Bazinga — OK (through the Dune plugin Bazinga3)" \
        "Кино \"Мир\" — OK (through the Dune plugin kino)" "Mir Kino — OK (through the Dune plugin mirkino)")" ]' _ "$o"
check "diag builds: no queries for them" test "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 13
diag
check "diag build: verdict" in_item "Mir Kino" "Mir Kino: OK"
check "diag build: installed" in_item "Mir Kino" "  installed: yes (mirkino)"
check "diag build: not hidden" in_item "Mir Kino" "  hidden: no"
check "diag build: menu file ours" in_item "Mir Kino" "  menu item: yes, plugin play_in_apps"
check "diag build: not checked" in_item "Mir Kino" "  launch: through the Dune plugin mirkino, not checked"
diag russian brief
check "diag brief russian build" grep -qxF "Mir Kino — ОК (через плагин mirkino)" "$o"
printf 'iptvce_mirkino\n' >"$data/hidden"
run sync.sh
diag english brief
check "diag brief build hidden" grep -qxF "Mir Kino — hidden" "$o"
rm -f "$data/hidden"
diag english brief
check "diag brief build not in the menu" grep -qxF "Mir Kino — the item is not in the menu" "$o"
run sync.sh
printf '{"plugin":"other","bin":"sh %s/iptvce.sh"}\n' "$bin" >"$menu/iptvce_mirkino"
diag english brief
check "diag brief build, another plugin's file" grep -qxF "Mir Kino — the item is from another plugin: other" "$o"
sed 's/"Json"/"None"/' "$fx/iptvce_mirkino/config.json" >"$plugins/mirkino/config.json"
diag english brief
check "diag build without VOD: no line" sh -c '! grep -q "Mir Kino" "$1" && [ "$(wc -l <"$1" | tr -d " ")" = 17 ]' _ "$o"
rm -rf "${plugins:?}/mirkino" "${plugins:?}/kino"
run sync.sh
diag english brief
check "diag builds gone: 16 lines" test "$(wc -l <"$o" | tr -d ' ')" = 16
# A name with a dot: a build like the others.
build iedem.tv 'iLook TV'
run sync.sh
diag english brief
check "diag brief build with a dot in its name" sh -c \
    '[ "$(wc -l <"$1" | tr -d " ")" = 17 ] && [ "$(sed -n 17p "$1")" = "iLook TV — OK (through the Dune plugin iedem.tv)" ]' _ "$o"
diag
check "diag build with a dot: installed" in_item "iLook TV" "  installed: yes (iedem.tv)"
check "diag build with a dot: menu file ours" in_item "iLook TV" "  menu item: yes, plugin play_in_apps"
rm -rf "${plugins:?}/iedem.tv"
run sync.sh

# --- main.php on a stub of the firmware PHP API (/firmware_ext/php/); values as in r24 dune_api.php
cat >"$work/fw_stub.php" <<'EOF'
<?php
define('PLUGIN_OP_GET_FOLDER_VIEW', 'get_folder_view');
define('PLUGIN_OP_HANDLE_USER_INPUT', 'handle_user_input');
define('PLUGIN_OUT_DATA_PLUGIN_FOLDER_VIEW', 'plugin_folder_view');
define('PLUGIN_OUT_DATA_GUI_ACTION', 'gui_action');
define('PLUGIN_OPEN_FOLDER_ACTION_ID', 'plugin_open_folder');
define('COMPOSITE_ACTION_ID', 'composite');
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
    const data = 'data';
    const params = 'params';
}
define('PLUGIN_OP_GET_REGULAR_FOLDER_ITEMS', 'get_regular_folder_items');
define('PLUGIN_OUT_DATA_PLUGIN_REGULAR_FOLDER_RANGE', 'plugin_regular_folder_range');
define('PLUGIN_FOLDER_VIEW_REGULAR', 'view_regular');
define('GUI_CONTROL_BUTTON', 'button');
define('GUI_CONTROL_VGAP', 'vgap');
define('GUI_EVENT_KEY_ENTER', 'key_enter');
define('GUI_EVENT_KEY_RETURN', 'key_return');
define('GUI_EVENT_TIMER', 'timer');
define('CLOSE_DIALOG_AND_RUN_ACTION_ID', 'close_dialog_and_run');
define('SHOW_DIALOG_ACTION_ID', 'show_dialog');
define('HALIGN_LEFT', 0);
define('FONT_SIZE_SMALL', 1);
// T_NO_LCFG: firmware without the item choice dialog (older than r22).
if (!getenv('T_NO_LCFG'))
{
    define('EDIT_LIST_CONFIG_ACTION_ID', 'edit_list_config');
    define('EDIT_LIST_CONFIG_OPT_ALLOW_EMPTY', 0x2);
    class EditListConfigActionData
    {
        const config_id = 'config_id';
        const title = 'title';
        const all_items = 'all_items';
        const checked_ids = 'checked_ids';
        const groups = 'groups';
        const def_id = 'def_id';
        const options = 'options';
        const sel_id = 'sel_id';
        const post_action = 'post_action';
    }
}
class GuiItem
{
    const id = 'id';
    const caption = 'caption';
    const icon_url = 'icon_url';
    const group_id = 'group_id';
}
class GuiButtonDef
{
    const caption = 'caption';
    const width = 'width';
    const push_action = 'push_action';
}
class GuiVGapDef
{
    const vgap = 'vgap';
}
class GuiTimerDef
{
    const delay_ms = 'delay_ms';
}
class ShowDialogActionData
{
    const title = 'title';
    const defs = 'defs';
    const actions = 'actions';
    const timer = 'timer';
    const close_by_return = 'close_by_return';
    const preferred_width = 'preferred_width';
}
class CloseDialogAndRunActionData
{
    const post_action = 'post_action';
}
class PluginOpenFolderActionData
{
    const media_url = 'media_url';
    const caption = 'caption';
}
class PluginShowErrorActionData
{
    const fatal = 'fatal';
    const title = 'title';
}
class PluginRegularFolderItem
{
    const media_url = 'media_url';
    const caption = 'caption';
    const view_item_params = 'view_item_params';
}
class PluginRegularFolderRange
{
    const total = 'total';
    const more_items_available = 'more_items_available';
    const from_ndx = 'from_ndx';
    const count = 'count';
    const items = 'items';
}
class PluginRegularFolderView
{
    const view_params = 'view_params';
    const base_view_item_params = 'base_view_item_params';
    const not_loaded_view_item_params = 'not_loaded_view_item_params';
    const async_icon_loading = 'async_icon_loading';
    const actions = 'actions';
    const initial_range = 'initial_range';
}
class ViewParams
{
    const num_cols = 'num_cols';
    const num_rows = 'num_rows';
    const paint_details = 'paint_details';
    const paint_scrollbar = 'paint_scrollbar';
    const scroll_animation_enabled = 'scroll_animation_enabled';
}
class ViewItemParams
{
    const item_padding_top = 'item_padding_top';
    const item_padding_bottom = 'item_padding_bottom';
    const item_layout = 'item_layout';
    const item_caption_width = 'item_caption_width';
    const item_caption_font_size = 'item_caption_font_size';
}
require dirname(__FILE__) . '/gz_stub.php';
function hd_silence_warnings()
{
}
function hd_restore_warnings()
{
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

cat >"$work/gz_stub.php" <<'EOF'
<?php
// The device's PHP has zlib, the PHP 5.3.6 image does not: stored deflate
// blocks in a zlib stream, enough for the QR PNG.
if (!function_exists('gzcompress'))
{
    function gzcompress($data, $level = -1)
    {
        $out = "\x78\x01";
        $len = strlen($data);
        $pos = 0;
        do
        {
            $chunk = (string) substr($data, $pos, 65535);
            $n = strlen($chunk);
            $pos += $n;
            $out .= chr($pos >= $len ? 1 : 0) . pack('v', $n) . pack('v', ~$n & 0xffff) . $chunk;
        } while ($pos < $len);
        $a = 1;
        $b = 0;
        for ($i = 0; $i < $len; $i++)
        {
            $a = ($a + ord($data[$i])) % 65521;
            $b = ($b + $a) % 65521;
        }
        return $out . pack('N', ($b << 16) | $a);
    }
}
EOF
# qr_png <url>: the QR picture qrpng.php makes for this URL, as the dialog's.
cat >"$work/qr_of.php" <<'EOF'
<?php
require dirname(__FILE__) . '/gz_stub.php';
require $argv[1];
$q = PiaQrPng::make($argv[2], 8, 4);
echo $q['png'];
EOF

# php_run <call ctx file>: stdout/stderr/rc of main.php into $o*.
# PIA_T_TMP: tmp_dir_path other than the usual one. Android commands are the stand-ins.
php_run() {
    T_DATA_DIR=${T_DATA_DIR:-$data} T_TMP_DIR=${PIA_T_TMP:-"$PLAY_IN_APPS_TMP/plugins/play_in_apps"} \
        PATH="$sbin:$PATH" $php_bin "$work/fw_stub.php" "$plugin/main.php" <"$1" >"$o" 2>"$o.err"
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
    a = d["data"]["data"]["actions"][-1]
except (KeyError, TypeError, IndexError):
    a = d.get("data")
try:
    a["data"]["media_url"] = json.loads(a["data"]["media_url"])
except (KeyError, TypeError, ValueError):
    pass
want = {"has_data": False, "plugin_cookies": {"k": "v"},
        "is_error": False, "error_action": None}
if sys.argv[2] != "none":
    want.update(has_data=True, data_type="gui_action", data=json.loads(sys.argv[2]))
sys.exit(d != want)
EOF
}

# Composite: load Filmix_API's token in its main menu handler, then open the search.
search_json() {
    python3 -c 'import json, sys
print(json.dumps({"handler_string_id": "composite", "data": {"actions": [
    {"handler_string_id": "plugin_handle_user_input", "plugin_name": "Filmix_api",
        "params": {"handler_id": "main_menu", "control_id": "fx_token"}},
    {"handler_string_id": "plugin_open_folder", "plugin_name": "Filmix_api",
        "data": {"media_url": {"screen_id": "vod_list", "category_id": "search",
            "genre_id": sys.argv[1]}, "caption": sys.argv[1]}}]}}))' "$1"
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
    for f in main.php qrpng.php cgi/logs.php; do
        check "$f: php -l" "$php_bin" -l "$src/$f"
    done

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

    # --- Bazinga play_action: the Bazinga3 plugin's Kinopoisk card by kp_id,
    # else its Kinopoisk search by title.
    # bz_input <file>: the device's play_action input with handler_id bazinga.
    bz_input() {
        python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
d.update(handler_id="bazinga", supplier_id="bazinga")
print(json.dumps(d))' "$1" >"$work/bz.json"
        mv -f "$work/bz.json" "$work/ui.json"
    }
    # bz_movie <movie_str JSON or raw value for movie_str>
    bz_movie() {
        user_input "$1"
        bz_input "$work/ui.json"
    }
    # bz_card_json <kp_id> <caption> [<caption_original> [<year>]]; "" or none: no field.
    bz_card_json() {
        python3 -c 'import json, sys
a = sys.argv[1:] + ["", ""]
url = {"movie_id": a[0], "screen_id": "vod_movie", "class_name": "Kinopoisk_Class", "caption": a[1]}
if a[2]:
    url["caption_original"] = a[2]
if a[3]:
    url["year"] = a[3]
print(json.dumps({"handler_string_id": "plugin_open_folder", "plugin_name": "Bazinga3",
    "data": {"media_url": url, "caption": a[1]}}))' "$@"
    }
    bz_search_json() {
        python3 -c 'import json, sys
url = {"searchStr": sys.argv[1], "screen_id": "vod_list", "class_name": "Kinopoisk_Class"}
print(json.dumps({"handler_string_id": "plugin_open_folder", "plugin_name": "Bazinga3",
    "data": {"media_url": url, "caption": sys.argv[1]}}))' "$1"
    }
    bz_card() {
        bzf=$1 bzd=$2
        shift 2
        handler "$bzf" "bazinga $bzd" "$(bz_card_json "$@")"
    }
    bz_search() { handler "$1" "bazinga $2" "$(bz_search_json "$3")"; }
    bz_error() { handler "$1" "bazinga $2" "$(error_json "$3")"; }

    rm -rf "$plugins/Bazinga3"
    bz_input "$fx/play_action_movie.json"
    bz_error "$work/ui.json" "no Bazinga3" bazinga_err_not_installed
    mkdir -p "$plugins/Bazinga3"
    bz_error "$work/ui.json" "Bazinga3 dir without manifest" bazinga_err_not_installed
    : >"$plugins/Bazinga3/dune_plugin.xml"

    # Real inputs from the device: the movie has kp_id, the series has none.
    bz_card "$work/ui.json" "movie with kp_id: card" 1236583 'Прошлой ночью в Сохо' 'Last Night in Soho' 2021
    check "main.php bazinga logs the card" grep -qx 'play_in_apps: bazinga card: 1236583' "$o.err"
    check "main.php bazinga card: Cyrillic as \\u escapes in media_url" python3 -c 'import json, sys
u = json.load(open(sys.argv[1]))["data"]["data"]["media_url"]
sys.exit("\\u041f" not in u or not u.isascii())' "$o"
    bz_input "$fx/play_action_series.json"
    bz_search "$work/ui.json" "series without kp_id: search" 'Дом Дракона'
    check "main.php bazinga logs the search" grep -qx 'play_in_apps: bazinga search: Дом Дракона' "$o.err"

    # kp_id: digits only after trim, a string or an integer.
    bz_movie '{"kp_id":" 409424 ","title":"Дюна","native_title":"Dune","year":"2021"}'
    bz_card "$work/ui.json" "kp_id trimmed" 409424 'Дюна' Dune 2021
    bz_movie '{"kp_id":"1234567890","title":"Дюна"}'
    bz_card "$work/ui.json" "kp_id of 10 digits: card" 1234567890 'Дюна'
    bz_movie '{"kp_id":409424,"title":"Дюна","year":2021}'
    bz_card "$work/ui.json" "kp_id and year as numbers, no native_title" 409424 'Дюна' '' 2021
    bz_movie '{"kp_id":"409424","title":"Дюна","native_title":"","year":""}'
    bz_card "$work/ui.json" "empty native_title and year: no fields" 409424 'Дюна'
    bz_movie '{"kp_id":"409424","title":"","native_title":"Dune"}'
    bz_card "$work/ui.json" "empty title: caption from native_title" 409424 Dune Dune
    bz_movie '{"kp_id":"409424","title":"  ","year":"2021"}'
    bz_card "$work/ui.json" "no titles: card with kp_id as caption" 409424 409424 '' 2021
    # shellcheck disable=SC2016 # literal $(...) on purpose
    bz_movie '{"kp_id":"1","title":"\"},\"plugin_name\":\"evil\" ; $(reboot) `id` \\ /&?#%"}'
    # shellcheck disable=SC2016 # literal $(...) on purpose
    bz_card "$work/ui.json" "hostile title stays text" 1 '"},"plugin_name":"evil" ; $(reboot) `id` \ /&?#%'
    for kp in '"tt9639470"' '"12a"' '"-1"' '"+1"' '"1.5"' '"12 3"' '"0x1A"' '""' '1.5' 'true' '["1"]' '{"a":"1"}' 'null' \
        '"0"' '0' '"0409424"' '"12345678901"' '12345678901'; do
        bz_movie "{\"kp_id\":$kp,\"title\":\"Дюна\",\"native_title\":\"Dune\",\"year\":\"2021\"}"
        bz_search "$work/ui.json" "kp_id $kp: search" 'Дюна'
    done
    bz_movie '{"title":"","native_title":"Dune"}'
    bz_search "$work/ui.json" "no kp_id, empty title: search by native_title" Dune
    bz_movie '{"kp_id":"tt1","title":"ab\ud800cd","native_title":"Dune"}'
    if [ "$("$php_bin" -r 'echo PHP_MAJOR_VERSION;')" -lt 7 ]; then
        bz_search "$work/ui.json" "lone surrogate title: search by native_title" Dune
        bz_movie '{"kp_id":"7","title":"T","native_title":"x\udc00","year":"y\ud800"}'
        bz_card "$work/ui.json" "lone surrogates in native_title and year: fields left out" 7 T
    else
        # PHP 7+ json_decode rejects the whole movie_str.
        bz_error "$work/ui.json" "lone surrogate title (PHP 7+)" bazinga_err_no_title
    fi
    bz_movie '{"kp_id":"","title":" ","native_title":""}'
    bz_error "$work/ui.json" "no kp_id, no titles" bazinga_err_no_title
    for raw in 'not json' '"just a string"' '["kp_id","title"]' ''; do
        bz_movie "$raw"
        bz_error "$work/ui.json" "movie_str '$raw'" bazinga_err_no_title
    done
    printf '%s\n' '{"handler_id":"bazinga","control_id":"play"}' >"$work/ui.json"
    bz_error "$work/ui.json" "no movie_str" bazinga_err_no_title
    printf '%s\n' '{"handler_id":"bazinga","movie_str":{"kp_id":"1","title":"obj"}}' >"$work/ui.json"
    bz_error "$work/ui.json" "movie_str is an object" bazinga_err_no_title

    # --- IPTV Channel Editor builds: play_action with handler_id
    # iptvce_<name> opens the build's search results for the title.
    # ic_input <file> [handler_id]: the device's play_action input with this handler_id.
    ic_input() {
        python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
d.update(handler_id=sys.argv[2], supplier_id=sys.argv[2])
print(json.dumps(d))' "$1" "${2:-iptvce_mirkino}" >"$work/ic.json"
        mv -f "$work/ic.json" "$work/ui.json"
    }
    # ic_movie <movie_str JSON or raw value> [handler_id]
    ic_movie() {
        user_input "$1"
        ic_input "$work/ui.json" "${2-}"
    }
    # ic_search_json <build> <caption> <query>
    ic_search_json() {
        python3 -c 'import json, sys
name, cap, q = sys.argv[1:4]
url = {"screen_id": "vod_list", "category_id": "##search##", "genre_id": q}
print(json.dumps({"handler_string_id": "plugin_open_folder", "plugin_name": name,
    "data": {"media_url": url, "caption": cap + ": " + q}}))' "$@"
    }
    ic_message_json() {
        python3 -c 'import json, sys
print(json.dumps({"handler_string_id": "plugin_show_error", "data": {"fatal": False, "title": sys.argv[1]}}))' "$1"
    }
    ic_search() { handler "$1" "iptvce $2" "$(ic_search_json mirkino 'Mir Kino' "$3")"; }
    ic_msg() { handler "$1" "iptvce $2" "$(ic_message_json "$3")"; }
    ic_no_title='This title has no name, Mir Kino cannot search for it'

    build mirkino
    # Real inputs from the device, the Mir Kino fixture.
    ic_input "$fx/play_action_movie.json"
    ic_search "$work/ui.json" "movie: search by title" 'Прошлой ночью в Сохо'
    check "main.php iptvce logs the search" grep -qx 'play_in_apps: iptvce mirkino search: Прошлой ночью в Сохо' "$o.err"
    check "main.php iptvce: media_url as the probe's, Cyrillic as \\u escapes" python3 -c 'import json, sys
u = json.load(open(sys.argv[1]))["data"]["data"]["media_url"]
sys.exit(not u.isascii() or json.loads(u) != {"screen_id": "vod_list", "category_id": "##search##",
    "genre_id": "Прошлой ночью в Сохо"} or not u.startswith("{\"screen_id\""))' "$o"
    ic_input "$fx/play_action_series.json"
    ic_search "$work/ui.json" "series: search by title" 'Дом Дракона'

    # Titles: title, else native_title; no year, no IDs.
    ic_movie '{"title":"","native_title":"Last Night in Soho","year":"2021","kp_id":"1236583"}'
    ic_search "$work/ui.json" "empty title: native_title" 'Last Night in Soho'
    ic_movie '{"title":"  Дом  ","native_title":"x"}'
    ic_search "$work/ui.json" "title trimmed" 'Дом'
    # shellcheck disable=SC2016 # literal $(...) on purpose
    ic_movie '{"title":"\"},\"plugin_name\":\"evil\" ; $(reboot) `id` \\ /&?#% ##search##"}'
    # shellcheck disable=SC2016 # literal $(...) on purpose
    ic_search "$work/ui.json" "hostile title stays text" '"},"plugin_name":"evil" ; $(reboot) `id` \ /&?#% ##search##'
    ic_movie '{"title":2049}'
    ic_search "$work/ui.json" "numeric title" 2049
    ic_movie '{"title":{"ru":"x"},"native_title":"Nested"}'
    ic_search "$work/ui.json" "object title skipped" Nested
    ic_movie '{"title":"ab\ud800cd","native_title":"Good"}'
    if [ "$("$php_bin" -r 'echo PHP_MAJOR_VERSION;')" -lt 7 ]; then
        ic_search "$work/ui.json" "lone surrogate title: native_title" Good
    else
        ic_msg "$work/ui.json" "lone surrogate title (PHP 7+)" "$ic_no_title"
    fi
    ic_movie '{"title":" ","native_title":""}'
    ic_msg "$work/ui.json" "no titles" "$ic_no_title"
    for raw in 'not json' '"just a string"' '["title"]' ''; do
        ic_movie "$raw"
        ic_msg "$work/ui.json" "movie_str '$raw'" "$ic_no_title"
    done
    printf '%s\n' '{"handler_id":"iptvce_mirkino","control_id":"play"}' >"$work/ui.json"
    ic_msg "$work/ui.json" "no movie_str" "$ic_no_title"
    printf '%s\n' '{"handler_id":"iptvce_mirkino","movie_str":{"title":"obj"}}' >"$work/ui.json"
    ic_msg "$work/ui.json" "movie_str is an object" "$ic_no_title"

    # The build's caption in the folder caption and the messages.
    build kino "Кино &quot;Мир&quot; \\"
    ic_movie '{"title":"Дюна"}' iptvce_kino
    handler "$work/ui.json" "iptvce caption of the build" "$(ic_search_json kino "Кино \"Мир\" \\" 'Дюна')"
    build tabcap "$(printf 'Mir\tKino')"
    ic_movie '{"title":""}' iptvce_tabcap
    ic_msg "$work/ui.json" "unsafe caption: the folder name" 'This title has no name, tabcap cannot search for it'
    build trcap '%tr%plugin_caption'
    ic_movie '{"title":""}' iptvce_trcap
    ic_msg "$work/ui.json" "%tr% caption: the folder name" 'This title has no name, trcap cannot search for it'
    build badcap "$(printf 'Mir \355\240\200')"
    ic_movie '{"title":""}' iptvce_badcap
    ic_msg "$work/ui.json" "surrogate in the caption: the folder name" 'This title has no name, badcap cannot search for it'
    build longcap "$(printf 'Ж%.0s' $(seq 1 39))Юя"
    ic_movie '{"title":""}' iptvce_longcap
    ic_msg "$work/ui.json" "long caption: 40 characters" "This title has no name, $(printf 'Ж%.0s' $(seq 1 39))Ю cannot search for it"
    rm -rf "${plugins:?}/kino" "${plugins:?}/tabcap" "${plugins:?}/trcap" "${plugins:?}/badcap" "${plugins:?}/longcap"

    # Not a build now, or not a valid name: not installed, named by its caption.
    ic_movie '{"title":"Дюна"}' iptvce_nosuch
    ic_msg "$work/ui.json" "no such build" 'The nosuch plugin is not installed'
    sed 's/"Json"/"None"/' "$fx/iptvce_mirkino/config.json" >"$plugins/mirkino/config.json"
    ic_movie '{"title":"Дюна"}'
    ic_msg "$work/ui.json" "VOD off" 'The Mir Kino plugin is not installed'
    build mirkino
    rm -f "$plugins/mirkino/screens_vod/starnet_vod_list_screen.php"
    ic_msg "$work/ui.json" "no VOD list screen" 'The Mir Kino plugin is not installed'
    build mirkino
    for v in none NONE; do
        sed "s/\"Json\"/\"$v\"/" "$fx/iptvce_mirkino/config.json" >"$plugins/mirkino/config.json"
        ic_movie '{"title":"Дюна"}'
        ic_msg "$work/ui.json" "VOD off: $v" 'The Mir Kino plugin is not installed'
    done
    build mirkino
    # Dots and hyphens inside a name: a build, opened by its folder name.
    build iedem.tv 'iLook TV'
    ic_movie '{"title":"Дюна"}' iptvce_iedem.tv
    handler "$work/ui.json" "iptvce name with a dot" "$(ic_search_json iedem.tv 'iLook TV' 'Дюна')"
    check "main.php iptvce name with a dot: logged" grep -qx 'play_in_apps: iptvce iedem.tv search: Дюна' "$o.err"
    build fox-fun.tv
    ic_movie '{"title":"Дюна"}' iptvce_fox-fun.tv
    handler "$work/ui.json" "iptvce name with a hyphen" "$(ic_search_json fox-fun.tv 'Mir Kino' 'Дюна')"
    rm -rf "${plugins:?}/iedem.tv" "${plugins:?}/fox-fun.tv"
    # Unsafe names, also of a folder that is a build: not opened.
    mkdir -p "$plugins/mir kino"
    build a..b
    build .x
    build -x
    for h in 'iptvce_mir kino' iptvce_../mirkino 'iptvce_mirkino ' "iptvce_$(printf 'n%.0s' $(seq 1 41))" \
        iptvce_a..b iptvce_.x iptvce_-x; do
        ic_movie '{"title":"Дюна"}' "$h"
        name=${h#iptvce_}
        shown_name=$(printf '%s' "$name" | cut -c 1-40 | sed 's/[^A-Za-z0-9_]/?/g')
        ic_msg "$work/ui.json" "handler_id '$h'" "The $shown_name plugin is not installed"
    done
    rm -rf "${plugins:?}/mir kino" "${plugins:?}/a..b" "${plugins:?}/.x" "${plugins:?}/-x"
    # No name: not an item id, not our call.
    ic_movie '{"title":"Дюна"}' iptvce_
    handler "$work/ui.json" "iptvce handler_id 'iptvce_'" none
    # The message in the Dune's language.
    mkdir -p "$cfg"
    printf 'interface_language = russian\n' >"$cfg/settings.properties"
    ic_movie '{"title":"Дюна"}' iptvce_nosuch
    ic_msg "$work/ui.json" "no such build, Russian Dune" 'Плагин nosuch не установлен'
    ic_movie '{"title":""}'
    ic_msg "$work/ui.json" "no titles, Russian Dune" 'У этой карточки нет названия, Mir Kino не сможет её найти'
    rm -f "$cfg/settings.properties"
    rm -rf "${plugins:?}/mirkino"

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

    # --- the screen "setup": get_folder_view

    # setup_is <ids with an old plugin>: view_controls with a hint label, two
    # warning labels if a separate "Open in <app>" plugin is there (the
    # caption, then the app names), then the three buttons.
    setup_is() {
        python3 - "$o" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
old = set(sys.argv[2].split())
names = [("num", "NUM"), ("lampa", "Lampa"), ("bylampa", "BYLAMPA"), ("lampa_atv", "LAMPA ATV"),
         ("prisma", "Prisma"), ("vokino", "VoKino"), ("lazymedia", "LazyMedia"), ("filmix_api", "Filmix"),
         ("stremio", "Stremio"), ("nuvio", "Nuvio"), ("freezona", "FreeZona"), ("alpac", "ALPAC"),
         ("flux", "Flux"), ("seasonhit", "SeasonHit"), ("bazinga", "Bazinga")]
def label(c):
    return {"name": "", "title": None, "kind": "label", "specific_def": {"caption": c}}
def button(n):
    return {"name": n, "title": "%%tr%%%s_title" % n, "kind": "button",
            "specific_def": {"caption": "%%tr%%%s_button" % n, "width": 400, "push_action": {
                "handler_string_id": "plugin_handle_user_input", "data": None,
                "params": {"handler_id": "setup", "control_id": n}}}}
defs = [label("%tr%screen_hint")]
if old:
    defs += [label("%tr%old_plugins"), label(", ".join(c for i, c in names if i in old))]
defs += [button("items"), button("check"), button("logs")]
want = {"has_data": True, "plugin_cookies": {"k": "v"}, "is_error": False, "error_action": None,
        "data_type": "plugin_folder_view",
        "data": {"view_kind": "view_controls", "multiple_views_supported": False,
                 "data": {"defs": defs, "initial_sel_ndx": -1}}}
sys.exit(d != want)
EOF
    }

    # folder_view [media_url] [op]: open a screen.
    folder_view() {
        python3 -c 'import json, sys; print(json.dumps({"media_url": sys.argv[1]}))' "${1:-setup}" >"$work/fv.json"
        ctx "$work/fv.json" "${2:-get_folder_view}"
        php_run "$work/ctx.json"
    }

    rm -rf "${reg:?}" "${menu:?}"
    rm -f "$data/hidden"
    cp "$fx/app_data.json" "$apps"
    folder_view
    check "setup screen: exit 0" rc_is 0
    check "setup screen: stderr has only own log lines" only_own_log
    check "setup screen: hint and three buttons" setup_is ""
    # shellcheck disable=SC2086 # one word per id
    check "setup screen opening runs sync" shown $all
    mkdir -p "$plugins/nuvio_supplier" "$plugins/num_supplier"
    : >"$plugins/nuvio_supplier/dune_plugin.xml"
    : >"$plugins/num_supplier/dune_plugin.xml"
    folder_view 'garbage"url'
    check "setup screen, other media_url, old plugins: exit 0" rc_is 0
    check "setup screen, old plugins: warning lines" setup_is "num nuvio"
    for i in $old_ids; do
        mkdir -p "$plugins/${i}_supplier"
        : >"$plugins/${i}_supplier/dune_plugin.xml"
    done
    folder_view
    check "setup screen, all 8 old plugins: two warning lines" setup_is "$old_ids"
    for i in $old_ids; do rm -rf "${plugins:?}/${i:?}_supplier"; done

    # press <control_id> [handler_id]: a button of the screen or a dialog.
    press() {
        printf '{"handler_id":"%s","control_id":"%s"}\n' "${2:-setup}" "$1" >"$work/ui.json"
        ctx "$work/ui.json"
        php_run "$work/ctx.json"
    }
    message_json() {
        python3 -c 'import json, sys
print(json.dumps({"handler_string_id": "plugin_show_error", "data": {"fatal": False, "title": sys.argv[1]}}))' "$1"
    }
    file_is() { [ "$(cat "$1")" = "$2" ]; }
    mode_is() { python3 -c 'import os, sys; sys.exit(os.stat(sys.argv[1]).st_mode & 0o777 != int(sys.argv[2], 8))' "$1" "$2"; }

    # --- "Configure…": the shell's dialog with checkmarks (edit_list_config)

    # items_is <installed ids> <ids with an icon in icon_cache> <en|ru> [<id>=<icon> ...]:
    # the dialog action; the other icons are apps.aai.
    items_is() {
        python3 - "$o" "$1" "$2" "$3" "$PLAY_IN_APPS_TMP/applications/icon_cache" "${4-}" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
installed, icons = set(sys.argv[2].split()), set(sys.argv[3].split())
ru = sys.argv[4] == "ru"
other = dict(a.split("=", 1) for a in sys.argv[6].split())
names = [("num", "NUM", "ru.yourok.num"), ("lampa", "Lampa", "top.rootu.lampa"),
         ("bylampa", "BYLAMPA", "top.rootu.bylumpa"), ("lampa_atv", "LAMPA ATV", "top.rootu.lumpa"),
         ("prisma", "Prisma", "top.rootu.prisma"), ("vokino", "VoKino", "ru.vokino.web"),
         ("lazymedia", "LazyMedia", "com.lazycatsoftware.lmd"), ("filmix_api", "Filmix", None),
         ("stremio", "Stremio", "com.stremio.one"), ("nuvio", "Nuvio", "com.nuvio.tv"),
         ("freezona", "FreeZona", "free.zona"), ("alpac", "ALPAC", "cc.alcopa.tv"),
         ("flux", "Flux", "app.flux.tv"), ("seasonhit", "SeasonHit", "com.jimdo.xakerd.season2hit"),
         ("bazinga", "Bazinga", None)]
items = []
for i, c, pkg in names:
    if i not in installed:
        c += " (не установлено)" if ru else " (not installed)"
    icon = "%s/icon_%s.png" % (sys.argv[5], pkg) if i in icons else "gui_skin://small_icons/apps.aai"
    icon = other.get(i, icon)
    items.append({"id": i, "caption": c, "icon_url": icon, "group_id": "apps"})
action = {"handler_string_id": "edit_list_config", "data": {
    "config_id": "play_in_apps",
    "title": "Пункты меню «Смотреть…»" if ru else 'Items of the "Play..." menu',
    "all_items": items,
    "checked_ids": [n[0] for n in names],
    "groups": [{"id": "apps", "caption": "Приложения" if ru else "Apps"}],
    "options": 2,
    "post_action": {"handler_string_id": "plugin_handle_user_input", "data": None,
                    "params": {"handler_id": "setup", "control_id": "list_apply"}}}}
want = {"has_data": True, "plugin_cookies": {"k": "v"}, "is_error": False, "error_action": None,
        "data_type": "gui_action", "data": action}
sys.exit(d != want)
EOF
    }

    icons="$PLAY_IN_APPS_TMP/applications/icon_cache"
    mkdir -p "$cfg" "$icons"
    : >"$icons/icon_ru.yourok.num.png"
    : >"$icons/icon_free.zona.png"
    # Filmix has no icon of its own even with a file of that name.
    : >"$icons/icon_.png"
    rm -f "$plugins/Filmix_api/dune_plugin.xml" "$plugins/Bazinga3/dune_plugin.xml"
    cp "$fx/app_data_no_lazymedia.json" "$apps"
    printf 'nuvio\nprisma\ngarbage\n' >"$data/hidden"
    press items
    check "items: exit 0" rc_is 0
    check "items: stderr has only own log lines" only_own_log
    check "items: dialog with all 15 items, not installed marked, icons" \
        items_is "num lampa prisma vokino stremio nuvio" "num freezona" en
    check "items: choice file from hidden, in item order" file_is "$lcfg" "$(printf '%s\n' -prisma -nuvio)"
    check "items: choice file 0644" mode_is "$lcfg" 644
    check "items: no temp files" listing_is "$cfg" lcfg_play_in_apps.txt
    rm -f "$data/hidden"
    press items
    check "items, nothing hidden: empty choice file" sh -c '[ -f "$1" ] && [ ! -s "$1" ]' _ "$lcfg"
    # shellcheck disable=SC2086 # one word per id
    printf '%s\n' $all >"$data/hidden"
    press items
    check "items, all hidden: all -id" file_is "$lcfg" "$(for i in $all; do echo "-$i"; done)"
    rm -f "$lcfg"
    ln -s "$work/lcfg_target" "$lcfg"
    printf 'stremio\n' >"$data/hidden"
    press items
    check "items, symlink at the choice file: replaced by a file" sh -c '[ ! -L "$1" ] && [ "$(cat "$1")" = -stremio ]' _ "$lcfg"
    check "items, symlink at the choice file: target untouched" file_is "$work/lcfg_target" keep
    rm -f "$lcfg"
    ln -s "$work/nowhere" "$lcfg"
    press items
    check "items, dangling symlink: target not created" no_file "$work/nowhere"
    rm -rf "${cfg:?}"
    press items
    check "items, no config dir: exit 0" rc_is 0
    check "items, no config dir: stderr has only own log lines" only_own_log
    check "items, no config dir: logged" grep -q 'could not write' "$o.err"
    check "items, no config dir: dialog still opens" items_is "num lampa prisma vokino stremio nuvio" "num freezona" en
    mkdir -p "$cfg"
    printf 'noncustom_interface_language = english\ninterface_language = russian\n' >"$cfg/settings.properties"
    press items
    check "items, Russian Dune: Russian texts" items_is "num lampa prisma vokino stremio nuvio" "num freezona" ru
    printf 'interface_language = custom\nnoncustom_interface_language = russian\n' >"$cfg/settings.properties"
    press items
    check "items, custom language over Russian: Russian" items_is "num lampa prisma vokino stremio nuvio" "num freezona" ru
    printf 'interface_language = ukrainian\n' >"$cfg/settings.properties"
    press items
    check "items, a language without translations: English" items_is "num lampa prisma vokino stremio nuvio" "num freezona" en
    rm -f "$cfg/settings.properties"
    ctx "$work/ui.json"
    T_NO_LCFG=1
    export T_NO_LCFG
    php_run "$work/ctx.json"
    unset T_NO_LCFG
    check "items, firmware without the dialog: exit 0" rc_is 0
    check "items, firmware without the dialog: message" out_is \
        "$(message_json 'The Dune firmware does not support the item choice dialog')"
    cp "$fx/app_data.json" "$apps"

    # Icons: Filmix, Bazinga — the logo of the installed Dune plugin; an app —
    # its "icon" in app_data.json (Android TV: in flashdata), else icon_cache.
    mkdir -p "$plugins/Filmix_api/icons" "$plugins/Bazinga3/icons" "$work/atv_icons"
    : >"$plugins/Filmix_api/dune_plugin.xml"
    : >"$plugins/Filmix_api/icons/logo.png"
    : >"$plugins/Bazinga3/dune_plugin.xml"
    : >"$plugins/Bazinga3/icons/logo.png"
    : >"$work/atv_icons/icon_ru.yourok.num.png"
    : >"$work/atv_icons/icon_com.nuvio.tv.png"
    # app_icons <package>=<icon JSON> ...: app_data.json with these "icon" values.
    app_icons() {
        python3 - "$fx/app_data.json" "$apps" "$@" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
icons = dict(a.split("=", 1) for a in sys.argv[3:])
for a in d["applications"]:
    if a["package_name"] in icons:
        a["icon"] = json.loads(icons[a["package_name"]])
open(sys.argv[2], "w").write(json.dumps(d, indent=2).replace("/", "\\/"))
EOF
    }
    # NUM: in flashdata; FreeZona: none there, icon_cache; Lampa: neither.
    app_icons "ru.yourok.num=\"$work/atv_icons/icon_ru.yourok.num.png\"" \
        "free.zona=\"$work/atv_icons/icon_free.zona.png\"" "top.rootu.lampa=\"$work/atv_icons/none.png\""
    press items
    check "items icons: stderr has only own log lines" only_own_log
    check "items icons: app_data icon, icon_cache, Filmix_API and Bazinga3 logos" items_is "$all" "num freezona" en \
        "num=$work/atv_icons/icon_ru.yourok.num.png filmix_api=$plugins/Filmix_api/icons/logo.png bazinga=$plugins/Bazinga3/icons/logo.png"
    rm -f "$plugins/Filmix_api/dune_plugin.xml" "$plugins/Bazinga3/dune_plugin.xml"
    press items
    check "items icons: plugin logos without their manifests: still the logos" items_is \
        "num lampa bylampa lampa_atv prisma vokino lazymedia stremio nuvio freezona alpac flux seasonhit" "num freezona" en \
        "num=$work/atv_icons/icon_ru.yourok.num.png filmix_api=$plugins/Filmix_api/icons/logo.png bazinga=$plugins/Bazinga3/icons/logo.png"
    : >"$plugins/Filmix_api/dune_plugin.xml"
    : >"$plugins/Bazinga3/dune_plugin.xml"
    rm -f "$plugins/Filmix_api/icons/logo.png" "$plugins/Bazinga3/icons/logo.png"
    press items
    check "items icons: no plugin logos: apps.aai" items_is "$all" "num freezona" en \
        "num=$work/atv_icons/icon_ru.yourok.num.png"
    # Not a usable path: relative, NUL, not a string, a directory.
    (cd "$work" && mkdir -p rel && : >rel/icon.png)
    app_icons 'ru.yourok.num="rel/icon.png"' 'com.nuvio.tv="/x\u0000/y"' 'com.stremio.one=7' \
        "free.zona=\"$work/atv_icons\""
    press items
    check "items icons, bad paths: stderr has only own log lines" only_own_log
    check "items icons, bad paths: icon_cache or apps.aai" items_is "$all" "num freezona" en
    printf '{"applications":[' >"$apps"
    press items
    check "items icons, app list cut short: stderr has only own log lines" only_own_log
    # Older Android: FS_PREFIX empty; the paths come from app_data.json and tmp_dir_path.
    app_icons "com.nuvio.tv=\"$work/atv_icons/icon_com.nuvio.tv.png\""
    printf '%s\n' '{"handler_id":"setup","control_id":"items"}' >"$work/ui.json"
    ctx "$work/ui.json"
    (
        FS_PREFIX=
        php_run "$work/ctx.json"
    )
    check "items icons, FS_PREFIX empty: exit 0" rc_is 0
    check "items icons, FS_PREFIX empty: stderr has only own log lines" only_own_log
    check "items icons, FS_PREFIX empty: app_data icon, icon_cache" items_is "$all" "num freezona" en \
        "nuvio=$work/atv_icons/icon_com.nuvio.tv.png"
    cp "$fx/app_data.json" "$apps"

    # Builds: after the fixed items, in name order, with their captions and
    # icons (apps.aai without one), checked by default.
    # items_builds_are <id>=<caption>=<icon or ""> ...: the dialog's items
    # after the 15 fixed ones, and checked_ids the same.
    items_builds_are() {
        python3 - "$o" "$@" <<'EOF'
import json, sys
a = json.load(open(sys.argv[1]))["data"]["data"]
want = []
for x in sys.argv[2:]:
    i, c, icon = x.split("=", 2)
    want.append({"id": i, "caption": c, "icon_url": icon or "gui_skin://small_icons/apps.aai", "group_id": "apps"})
ids = [w["id"] for w in want]
sys.exit(len(a["all_items"]) != 15 + len(want) or a["all_items"][15:] != want or a["checked_ids"][15:] != ids
         or len(a["checked_ids"]) != 15 + len(want))
EOF
    }
    build mirkino
    build kino 'Кино &amp; "Мир"' ''
    build zeta "$(printf 'bad \377')" 'plugin_file://img/logo_mirkino.png'
    build novod
    sed 's/"Json"/"None"/' "$fx/iptvce_mirkino/config.json" >"$plugins/novod/config.json"
    build iedem.tv 'iLook TV'
    build a..b
    printf 'iptvce_mirkino\nnuvio\niptvce_gone\niptvce_iedem.tv\niptvce_a..b\n' >"$data/hidden"
    press items
    check "items builds: exit 0" rc_is 0
    check "items builds: stderr has only own log lines" only_own_log
    check "items builds: after the fixed items, captions, icons" items_builds_are \
        "iptvce_iedem.tv=iLook TV=$plugins/iedem.tv/img/logo_mirkino.png" \
        'iptvce_kino=Кино & "Мир"=' "iptvce_mirkino=Mir Kino=$plugins/mirkino/img/logo_mirkino.png" \
        "iptvce_zeta=zeta=$plugins/zeta/img/logo_mirkino.png"
    check "items builds: choice file, fixed items then builds" file_is "$lcfg" \
        "$(printf '%s\n' -nuvio -iptvce_gone -iptvce_iedem.tv -iptvce_mirkino)"
    rm -rf "${plugins:?}/novod" "${plugins:?}/zeta" "${plugins:?}/mirkino" "${plugins:?}/kino" \
        "${plugins:?}/iedem.tv" "${plugins:?}/a..b"

    # Parity: bin/iptvce_builds.sh (sync.sh) and main.php (items dialog) find
    # the same builds, with the same captions and icons.
    build mirkino
    build two 'First</caption><caption>Second' \
        'plugin_file://img/logo_mirkino.png</icon_url><icon_url>plugin_file://img/other.png'
    : >"$plugins/two/img/other.png"
    build twoicon 'Two icons' 'plugin_file://img/none.png</icon_url><icon_url>plugin_file://img/logo_mirkino.png'
    build lt '&lt;b&gt;Mir&lt;/b&gt; Kino'
    build ltonly ' &lt;&gt; '
    build ltpct '&lt;%tr%plugin_caption'
    build ltspace '&lt; Mir &gt;'
    build multiline "$(printf 'Mir\nKino')"
    build long "$(printf 'Ж%.0s' $(seq 1 39))Юя"
    build badutf "$(printf 'Mir \377 Kino')"
    build vodnl
    printf '{\n  "vod_engine":\n  "Json"\n}\n' >"$plugins/vodnl/config.json"
    build vodnl2
    printf '{\n  "vod_engine": "Js\non"\n}\n' >"$plugins/vodnl2/config.json"
    build vodlow
    sed 's/"Json"/"none"/' "$fx/iptvce_mirkino/config.json" >"$plugins/vodlow/config.json"
    build vodup
    sed 's/"Json"/"NONE"/' "$fx/iptvce_mirkino/config.json" >"$plugins/vodup/config.json"
    build vodmixed
    sed 's/"Json"/"nOnE"/' "$fx/iptvce_mirkino/config.json" >"$plugins/vodmixed/config.json"
    build iedem.tv 'iLook TV'
    build fox-fun.tv
    build a..b
    build -x
    rm -f "$data/hidden"
    run sync.sh
    check "parity: sync exit 0" rc_is 0
    press items
    check "parity: items exit 0" rc_is 0
    check "parity: items stderr has only own log lines" only_own_log
    # parity_is <id>=<caption>=<icon in the build or ""> ...: these items, the
    # same in sync.sh's and in the dialog's.
    parity_is() {
        python3 - "$o" "$reg" "$plugins" "$@" <<'EOF'
import glob, json, os, sys
out, reg, plugins = sys.argv[1:4]
want = []
for x in sys.argv[4:]:
    i, c, icon = x.split("=", 2)
    want.append((i, c, "%s/%s/%s" % (plugins, i[7:], icon) if icon else ""))
sh = []
for f in sorted(glob.glob(reg + "/iptvce_*")):
    d = json.load(open(f, encoding="utf-8"))
    u = d.get("icon_url", "")
    name = os.path.basename(f)[7:]
    pre = "plugin_file://%%%s%%/" % name
    sh.append((os.path.basename(f), d["caption"], plugins + "/" + name + "/" + u[len(pre):] if u.startswith(pre) else u))
php = []
for it in json.load(open(out))["data"]["data"]["all_items"][15:]:
    u = it["icon_url"]
    php.append((it["id"], it["caption"], "" if u == "gui_skin://small_icons/apps.aai" else u))
if sh != want or php != want:
    print("sh:", sh, "\nphp:", php, "\nwant:", want, file=sys.stderr)
    sys.exit(1)
EOF
    }
    check "parity: builds, captions and icons the same in sync.sh and main.php" parity_is \
        'iptvce_badutf=badutf=img/logo_mirkino.png' \
        'iptvce_fox-fun.tv=Mir Kino=img/logo_mirkino.png' \
        'iptvce_iedem.tv=iLook TV=img/logo_mirkino.png' \
        "iptvce_long=$(printf 'Ж%.0s' $(seq 1 39))Ю=img/logo_mirkino.png" \
        'iptvce_lt=bMir/b Kino=img/logo_mirkino.png' \
        'iptvce_ltonly=ltonly=img/logo_mirkino.png' \
        'iptvce_ltpct=ltpct=img/logo_mirkino.png' \
        'iptvce_ltspace=Mir=img/logo_mirkino.png' \
        'iptvce_mirkino=Mir Kino=img/logo_mirkino.png' \
        'iptvce_multiline=Mir Kino=img/logo_mirkino.png' \
        'iptvce_two=First=img/logo_mirkino.png' \
        'iptvce_twoicon=Two icons='
    for b in mirkino two twoicon lt ltonly ltpct ltspace multiline long badutf vodnl vodnl2 vodlow vodup vodmixed \
        iedem.tv fox-fun.tv a..b -x; do
        rm -rf "${plugins:?}/$b"
    done
    run sync.sh

    # --- post_action of the dialog: list_apply

    # apply <list_config_changed JSON or none> <list_config_id JSON or none> [desc]
    apply() {
        python3 -c 'import json, sys
ui = {"handler_id": "setup", "control_id": "list_apply"}
for k, v in (("list_config_changed", sys.argv[1]), ("list_config_id", sys.argv[2])):
    if v != "none":
        ui[k] = json.loads(v)
print(json.dumps(ui))' "$1" "$2" >"$work/ui.json"
        handler "$work/ui.json" "list_apply $1 $2 ${3-}" none
    }
    hidden_is() { [ "$(cat "$data/hidden")" = "$1" ]; }

    rm -f "$data/hidden"
    printf '+num\n-lampa\n-nuvio\n+nuvio\n\n  -stremio  \n---\nnum\n-freezona\n' >"$lcfg"
    apply '"1"' '"play_in_apps"'
    check "list_apply: last sign of an id wins, order part ignored" hidden_is "$(printf 'lampa\nstremio')"
    check "list_apply: sync" shown num bylampa lampa_atv prisma vokino lazymedia filmix_api nuvio freezona alpac flux seasonhit bazinga
    press items
    check "list_apply then items: choice file from hidden" file_is "$lcfg" "$(printf '%s\n' -lampa -stremio)"
    printf '%s\n' -num >"$lcfg"
    apply '"0"' '"play_in_apps"' unchanged
    check "list_apply unchanged: hidden kept" hidden_is "$(printf 'lampa\nstremio')"
    for c in '"movies"' '"play_in_apps "' 'null' '["play_in_apps"]' none; do
        apply '"1"' "$c" foreign
        check "list_apply config id $c: hidden kept" hidden_is "$(printf 'lampa\nstremio')"
    done
    for v in 'null' '["1"]' '{"a":1}' '2' '""' none; do
        apply "$v" '"play_in_apps"' changed
        check "list_apply changed $v: hidden kept" hidden_is "$(printf 'lampa\nstremio')"
    done
    apply '1' '"play_in_apps"' 'number 1'
    check "list_apply changed 1 as a number: applied" hidden_is num
    # shellcheck disable=SC2016 # literal $(...) on purpose
    printf '%s\n' garbage -evil -../lampa '- vokino' '-prisma ' + - -filmix_api -NUM '$(reboot)' '-num;id' >"$lcfg"
    apply '"1"' '"play_in_apps"' garbage
    check "list_apply garbage: only known ids" hidden_is "$(printf 'prisma\nfilmix_api')"
    printf '%s\r\n' -lampa +prisma >"$lcfg"
    apply '"1"' '"play_in_apps"' CRLF
    check "list_apply CRLF lines" hidden_is lampa
    : >"$lcfg"
    apply '"1"' '"play_in_apps"' empty
    check "list_apply empty file: nothing hidden" hidden_is ''
    # shellcheck disable=SC2086 # one word per id
    check "list_apply empty file: all shown" shown $all
    printf 'nuvio\n' >"$data/hidden"
    rm -f "$lcfg"
    apply '"1"' '"play_in_apps"' 'no file'
    check "list_apply no file: hidden kept" hidden_is nuvio
    check "list_apply no file: logged" grep -q 'no choice file' "$o.err"
    printf '%s\n' -num >"$work/lcfg_target2"
    ln -s "$work/lcfg_target2" "$lcfg"
    apply '"1"' '"play_in_apps"' symlink
    check "list_apply symlink: not read" hidden_is nuvio
    rm -f "$lcfg"
    python3 -c 'import sys; open(sys.argv[1], "w").write("-num\n" * 20000)' "$lcfg"
    apply '"1"' '"play_in_apps"' 'big file'
    check "list_apply file over 64 KB: not read" hidden_is nuvio
    : >"$work/notadir"
    printf '%s\n' -vokino >"$lcfg"
    printf '%s\n' '{"handler_id":"setup","control_id":"list_apply","list_config_changed":"1","list_config_id":"play_in_apps"}' >"$work/ui.json"
    ctx "$work/ui.json"
    # PHP warnings are expected here, they go to the plugin log.
    T_DATA_DIR="$work/notadir/x"
    php_run "$work/ctx.json"
    unset T_DATA_DIR
    check "list_apply data dir not writable: err_save" out_is "$(error_json err_save)"
    # Builds: the ones found now by their -/+; a hidden build not installed
    # now stays hidden; garbage ids are dropped.
    build mirkino
    build kino
    build iedem.tv
    build a..b
    printf 'iptvce_gone\nnuvio\niptvce_kino\niptvce_a..b\n' >"$data/hidden"
    printf '%s\n' -iptvce_mirkino +iptvce_kino -iptvce_nosuch '-iptvce_../x' '-iptvce_mir kino' -IPTVCE_KINO -num \
        -iptvce_iedem.tv -iptvce_a..b >"$lcfg"
    apply '"1"' '"play_in_apps"' builds
    check "list_apply builds: hidden" hidden_is "$(printf '%s\n' num iptvce_gone iptvce_iedem.tv iptvce_mirkino)"
    # shellcheck disable=SC2046 # one word per id
    check "list_apply builds: sync" shown $(echo "$all" | sed 's/^num //') iptvce_kino
    : >"$lcfg"
    apply '"1"' '"play_in_apps"' 'builds, empty file'
    check "list_apply builds, empty file: the gone build stays hidden" hidden_is iptvce_gone
    # shellcheck disable=SC2086 # one word per id
    check "list_apply builds, empty file: all shown" shown $all iptvce_iedem.tv iptvce_kino iptvce_mirkino
    rm -rf "${plugins:?}/mirkino" "${plugins:?}/kino" "${plugins:?}/iedem.tv" "${plugins:?}/a..b"
    rm -f "$data/hidden" "$lcfg"
    run sync.sh

    # --- "Check": the report of diag.sh as a list

    # check_view_is <file with the expected lines>: view_regular 1x16 with a
    # scrollbar, a row per line, ENTER does nothing.
    check_view_is() {
        python3 - "$o" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
lines = open(sys.argv[2], encoding="utf-8").read().rstrip("\n").split("\n")
rows = [{"media_url": "line:%d" % i, "caption": l, "view_item_params": []} for i, l in enumerate(lines)]
rng = {"total": len(rows), "more_items_available": False, "from_ndx": 0, "count": len(rows), "items": rows}
view = {"multiple_views_supported": False, "view_kind": "view_regular", "data": {
    "view_params": {"num_cols": 1, "num_rows": 16, "paint_details": False, "paint_scrollbar": True,
                    "scroll_animation_enabled": True},
    "base_view_item_params": {"item_padding_top": 0, "item_padding_bottom": 0, "item_layout": 0,
                              "item_caption_width": 1650, "item_caption_font_size": 1},
    "not_loaded_view_item_params": [],
    "async_icon_loading": False,
    "actions": {"key_enter": {"handler_string_id": "plugin_handle_user_input", "data": None,
                              "params": {"handler_id": "check", "control_id": "line"}}},
    "initial_range": rng}}
want = {"has_data": True, "plugin_cookies": {"k": "v"}, "is_error": False, "error_action": None,
        "data_type": "plugin_folder_view", "data": view}
sys.exit(d != want)
EOF
    }

    diag english brief
    cp "$o" "$work/diag_en.txt"
    : >"$STUB_LOG"
    folder_view check
    check "check screen: exit 0" rc_is 0
    check "check screen: stderr has only own log lines" only_own_log
    check "check screen: the lines of the brief report as rows" check_view_is "$work/diag_en.txt"
    check "check screen: 16 rows, one screen" python3 -c 'import json, sys
sys.exit(len(json.load(open(sys.argv[1]))["data"]["data"]["initial_range"]["items"]) != 16)' "$o"
    check "check screen: no details" sh -c '! grep -qE "am start|intent|launch:|FS_PREFIX" "$1"' _ "$o"
    check "check screen: diag.sh ran from PHP" test "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 13
    folder_view check get_regular_folder_items
    check "check screen, get_regular_folder_items: the same rows" python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
n = len(open(sys.argv[2]).read().rstrip("\n").split("\n"))
sys.exit(d["data_type"] != "plugin_regular_folder_range" or d["data"]["total"] != n or len(d["data"]["items"]) != n)' "$o" "$work/diag_en.txt"
    folder_view setup get_regular_folder_items
    check "get_regular_folder_items of setup: nothing" out_is none
    press line check
    check "check screen ENTER on a line: nothing" out_is none
    press check
    check "Check button: opens the check screen" out_is \
        '{"handler_string_id":"plugin_open_folder","data":{"media_url":"check","caption":"Check"}}'
    printf 'interface_language = russian\n' >"$cfg/settings.properties"
    diag russian brief
    cp "$o" "$work/diag_ru.txt"
    folder_view check
    check "check screen, Russian Dune: Russian report" check_view_is "$work/diag_ru.txt"
    rm -f "$cfg/settings.properties"
    # Bad UTF-8 and a tab from a command, a line over 300 characters (the
    # owner of someone else's menu file).
    STUB_MODEL=$(printf 'Pro\377\376\t8K')
    export STUB_MODEL
    printf '{"plugin":"%0400d","bin":"sh %s/num.sh"}\n' 0 "$bin" >"$menu/num"
    folder_view check
    unset STUB_MODEL
    "$sh_bin" "$bin/sync.sh" >/dev/null 2>&1
    check "check screen, bad UTF-8: exit 0" rc_is 0
    check "check screen, bad UTF-8 and a tab: cleaned" python3 -c 'import json, sys
rows = json.load(open(sys.argv[1]))["data"]["data"]["initial_range"]["items"]
sys.exit(rows[0]["caption"] != "Pro?? 8K · r24 260827 · Android 11 · plugin " + sys.argv[2])' "$o" "$plugin_version"
    check "check screen, long line: cut at 300 characters" python3 -c 'import json, sys
rows = json.load(open(sys.argv[1]))["data"]["data"]["initial_range"]["items"]
long = [r["caption"] for r in rows if r["caption"].startswith("NUM ")]
sys.exit(len(long) != 1 or len(long[0]) != 300 or not long[0].endswith("…"))' "$o"

    # --- "Logs for the author": QR dialog, token for the CGI page

    pia_tmp="$PLAY_IN_APPS_TMP/plugins/play_in_apps"
    token_of() { cat "$pia_tmp/logs_token"; }
    # qr_dialog_is <host>: the dialog for the current token: title, the QR
    # picture of the page's address (no text but the title) and "Close".
    qr_dialog_is() {
        "$php_bin" "$work/qr_of.php" "$plugin/qrpng.php" \
            "http://$1/cgi-bin/plugins/play_in_apps/logs?t=$(token_of)" >"$work/qr_want.png" || return 1
        python3 - "$o" "$pia_tmp" "$work/qr_want.png" <<'EOF'
import glob, json, sys
d = json.load(open(sys.argv[1]))
tmp = sys.argv[2]
pngs = glob.glob(tmp + "/qr_*.png")
if len(pngs) != 1:
    sys.exit(1)
png = pngs[0]
data = open(png, "rb").read()
side = int.from_bytes(data[16:20], "big")
def inp(c):
    return {"handler_string_id": "plugin_handle_user_input", "data": None,
            "params": {"handler_id": "setup", "control_id": c}}
defs = [
    {"name": "", "title": None, "kind": "label",
     "specific_def": {"caption": '<icon width="%d" height="%d">%s</icon>' % (side, side, png)},
     "params": {"smart": 1}},
    {"name": "", "title": None, "kind": "vgap", "specific_def": {"vgap": side}},
    {"name": "close", "title": None, "kind": "button", "specific_def": {
        "caption": "Close", "width": 300, "push_action": {
            "handler_string_id": "close_dialog_and_run", "data": {"post_action": inp("logs_close")}}}}]
action = {"handler_string_id": "show_dialog", "data": {
    "title": "Download logs to phone", "defs": defs, "close_by_return": False, "preferred_width": 1500,
    "actions": {"key_return": inp("logs_return"), "timer": inp("logs_ttl")},
    "timer": {"delay_ms": 300000}}}
want = {"has_data": True, "plugin_cookies": {"k": "v"}, "is_error": False, "error_action": None,
        "data_type": "gui_action", "data": action}
import zlib
idat = data.find(b"IDAT")
n = int.from_bytes(data[idat - 4:idat], "big")
rows = zlib.decompress(data[idat + 4:idat + 4 + n])
ok = (d == want and data[:8] == b"\x89PNG\r\n\x1a\n" and side > 100 and data.endswith(b"IEND\xaeB`\x82")
      and len(rows) == side * (side + 1) and data == open(sys.argv[3], "rb").read())
sys.exit(not ok)
EOF
    }
    # no_token: neither the token nor a QR picture in tmp_dir.
    no_token() {
        [ ! -e "$pia_tmp/logs_token" ] && [ -z "$(find "$pia_tmp" -name 'qr_*')" ]
    }
    closes_json='{"handler_string_id":"close_dialog_and_run","data":{"post_action":null}}'

    rm -rf "${pia_tmp:?}"
    press logs
    check "logs: exit 0" rc_is 0
    check "logs: stderr has only own log lines" only_own_log
    check "logs: token of 32 hex" grep -qxE '[0-9a-f]{32}' "$pia_tmp/logs_token"
    check "logs: token 0600" mode_is "$pia_tmp/logs_token" 600
    check "logs: QR picture 0600" mode_is "$(find "$pia_tmp" -name 'qr_*.png' | head -n 1)" 600
    check "logs: dialog with the title, QR of the address, Close" qr_dialog_is 192.0.2.10
    qr_not() { ! qr_dialog_is "$1"; }
    check "logs: the QR holds the address (another host fails)" qr_not 192.0.2.11
    check "logs: token never logged" sh -c '! grep -qF "$(cat "$1")" "$2"' _ "$pia_tmp/logs_token" "$o.err"
    check "logs: no temp files" test -z "$(find "$pia_tmp" -name '*.tmp')"
    tok1=$(token_of)
    HD_HTTP_LOCAL_PORT=11080
    export HD_HTTP_LOCAL_PORT
    press logs
    check "logs, port not 80: in the address" qr_dialog_is 192.0.2.10:11080
    check "logs again: a new token" test "$(token_of)" != "$tok1"
    HD_HTTP_LOCAL_PORT=80
    press logs
    check "logs, port 80: not in the address" qr_dialog_is 192.0.2.10
    # The address: eth0, else wlan0, else the first but tun*, ppp*, wg*.
    for c in 'wlan0:192.0.2.20=192.0.2.20' \
        'tun0:198.51.100.1 wlan0:192.0.2.20 eth0:192.0.2.10=192.0.2.10' \
        'tun0:198.51.100.1 wlan0:192.0.2.20=192.0.2.20' \
        'tun0:198.51.100.1 ppp0:198.51.100.2 wg0:198.51.100.3 usb0:192.0.2.30 wlan1:192.0.2.40=192.0.2.30'; do
        STUB_IFCONFIG=${c%=*}
        export STUB_IFCONFIG
        press logs
        check "logs, ifconfig '$STUB_IFCONFIG': address ${c##*=}" qr_dialog_is "${c##*=}"
    done
    unset STUB_IFCONFIG
    unset HD_HTTP_LOCAL_PORT
    press logs_return
    check "logs RETURN: closes the dialog" out_is "$closes_json"
    check "logs RETURN: token and QR removed" no_token
    press logs
    press logs_close
    check "logs Close: nothing more" out_is none
    check "logs Close: token and QR removed" no_token
    press logs
    press logs_ttl
    check "logs timer: closes the dialog" out_is "$closes_json"
    check "logs timer: token and QR removed" no_token
    press logs_return
    check "logs RETURN without a token: still closes" out_is "$closes_json"
    printf '%s\n' '{"handler_id":"setup","control_id":"logs"}' >"$work/ui.json"
    ctx "$work/ui.json"
    # PHP warnings are expected here, they go to the plugin log.
    PIA_T_TMP="$work/notadir/x"
    php_run "$work/ctx.json"
    unset PIA_T_TMP
    check "logs, tmp dir not writable: message" out_is "$(message_json 'Could not create a link to the logs')"

    # Not ours: no action.
    for c in '"evil"' '"logs "' '0' '["items"]' 'null'; do
        python3 -c 'import json, sys; print(json.dumps({"handler_id": "setup", "control_id": json.loads(sys.argv[1])}))' "$c" >"$work/ui.json"
        handler "$work/ui.json" "control_id $c" none
    done
    printf '%s\n' '{"handler_id":"other","control_id":"items"}' >"$work/ui.json"
    handler "$work/ui.json" "other handler_id" none

    # --- cgi/logs.php through www/cgi-bin/logs, run as run_plugin_cgi runs it:
    # `sh <file>` as root, umask 0, cwd cgi-bin. Real php-cgi when there is one
    # (status and headers checked), else the PHP CLI through a stand-in (body only).
    check "www has only cgi-bin, cgi-bin only the sh wrapper" sh -c \
        '[ "$(ls -A "$1/www")" = cgi-bin ] && [ "$(ls -A "$1/www/cgi-bin")" = logs ]' _ "$src"
    mkdir -p "$work/empty_cwd"
    (cd "$work/empty_cwd" && env -i FS_PREFIX="$work/nofs" sh "$src/www/cgi-bin/logs" >/dev/null 2>&1)
    check "cgi-bin wrapper run elsewhere: creates nothing" dir_empty "$work/empty_cwd"

    php_cgi=${PHP_CGI-$(command -v php-cgi 2>/dev/null || true)}
    mkdir -p "$work/fs/firmware_ext/php"
    if [ -n "$php_cgi" ]; then
        cgi_mode=cgi
        ln -sf "$php_cgi" "$work/fs/firmware_ext/php/php-cgi"
    else
        cgi_mode=cli
        cat >"$work/cgi_cli.php" <<'EOF'
<?php
// php-cgi stand-in on the PHP CLI: $_GET from QUERY_STRING, then the page.
// Headers are lost in the CLI, so only the body is checked.
parse_str((string) getenv('QUERY_STRING'), $_GET);
require getenv('SCRIPT_FILENAME');
EOF
        printf '#!/bin/sh\nexec %s %s\n' "$(command -v "$php_bin")" "$work/cgi_cli.php" >"$work/fs/firmware_ext/php/php-cgi"
        chmod 755 "$work/fs/firmware_ext/php/php-cgi"
    fi
    echo "CGI checks with: $cgi_mode"

    # req <method> <query>: response -> $o, body -> $o.body, stderr -> $o.err
    req() {
        (cd "$plugin/www/cgi-bin" && umask 000 && env -i PATH="$sbin:$PATH" FS_PREFIX="$work/fs" STUB_RESOLVE="$STUB_RESOLVE" \
            PLUGIN_NAME=play_in_apps REQUEST_METHOD="$1" QUERY_STRING="$2" \
            REQUEST_URI="/cgi-bin/plugins/play_in_apps/logs?$2" HTTP_HOST=192.0.2.10 \
            GATEWAY_INTERFACE=CGI/1.1 SERVER_PROTOCOL=HTTP/1.1 REDIRECT_STATUS=200 \
            sh "$plugin/www/cgi-bin/logs") </dev/null >"$o" 2>"$o.err"
        if [ "$cgi_mode" = cgi ]; then
            python3 -c 'import sys
s = open(sys.argv[1], "rb").read()
p = s.find(b"\r\n\r\n")
open(sys.argv[2], "wb").write(b"" if p < 0 else s[p + 4:])' "$o" "$o.body"
        else
            cp "$o" "$o.body"
        fi
    }
    status_is() {
        [ "$cgi_mode" = cgi ] || return 0
        if [ "$1" = 200 ]; then
            ! grep -q '^Status:' "$o"
        else
            head -n 1 "$o" | grep -q "^Status: $1"
        fi
    }
    hdr() { [ "$cgi_mode" = cli ] || sed -n '1,/^\r$/p' "$o" | grep -qi -- "^$1"; }
    body_has() { grep -qF -- "$1" "$o.body"; }
    forbidden() { [ "$(cat "$o.body")" = '403 Forbidden' ] && status_is 403 && hdr 'Content-type: text/plain'; }
    quiet() { ! grep -q 'PHP ' "$o.err"; }
    age() { python3 -c 'import os, sys, time; t = time.time() - int(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$cgi_tok" "$1"; }

    cgi_tmp="$work/fs/tmp"
    cgi_tok="$cgi_tmp/plugins/play_in_apps/logs_token"
    tok=0123456789abcdef0123456789abcdef
    mkdir -p "$cgi_tmp/plugins/play_in_apps" "$cgi_tmp/run" "$cgi_tmp/plugins/shell_ext"
    rm -f "$cgi_tok"

    req GET ''
    check "cgi no token: 403" forbidden
    check "cgi no token: no PHP errors" quiet
    for qs in 't=xyz' 't%5B%5D=1' "t=$tok" "t=$tok&dl=1" "t=$(echo "$tok" | tr a-f A-F)"; do
        req GET "$qs"
        check "cgi '$qs', no token issued: same 403" forbidden
    done
    printf '%s' "$tok" >"$cgi_tok"
    for qs in 't=fedcba9876543210fedcba9876543210' 't=fedcba9876543210fedcba9876543210&dl=1' "t=${tok}0" "t=$tok%0a"; do
        req GET "$qs"
        check "cgi wrong token '$qs': same 403" forbidden
    done
    age 301
    req GET "t=$tok"
    check "cgi token of 301 s: same 403" forbidden
    age 290
    req GET "t=$tok"
    check "cgi token of 290 s: page" sh -c 'grep -qF "Download</a>" "$1"' _ "$o.body"
    rm -f "$cgi_tok"
    printf '%s' "$tok" >"$work/tok_elsewhere"
    ln -s "$work/tok_elsewhere" "$cgi_tok"
    req GET "t=$tok"
    check "cgi token file is a symlink: same 403" forbidden
    rm -f "$cgi_tok"
    printf '%s' "$tok" >"$cgi_tok"
    req POST "t=$tok"
    check "cgi POST: 405" status_is 405
    check "cgi POST: body" body_has '405 Method Not Allowed'
    # shellcheck disable=SC2016 # literal $(...) on purpose
    req GET 't=$(touch%20'"$work"'/pwned_cgi)&dl=1'
    check "cgi hostile query: 403, nothing run" sh -c '[ "$(cat "$1")" = "403 Forbidden" ] && [ ! -e "$2" ]' _ "$o.body" "$work/pwned_cgi"

    req GET "t=$tok"
    check "cgi page: 200" status_is 200
    check "cgi page: text/html utf-8" hdr 'Content-type: text/html; charset=utf-8'
    check "cgi page: no-store, no-referrer, nosniff" sh -c '[ "$1" = cli ] || { grep -qi "^Cache-Control: no-store" "$2" && grep -qi "^Referrer-Policy: no-referrer" "$2" && grep -qi "^X-Content-Type-Options: nosniff" "$2"; }' _ "$cgi_mode" "$o"
    check "cgi page: no X-Powered-By" sh -c '! grep -qi "^X-Powered-By" "$1"' _ "$o"
    check "cgi page: warning" body_has 'The logs may contain personal data. Do not post them publicly — on forums or in group chats.'
    check "cgi page: Download link with the token" body_has "<a class=\"btn\" href=\"logs?t=$tok&amp;dl=1\">Download</a>"
    check "cgi page: the link lives while the QR is open, at most 5 minutes" \
        body_has 'The link works while the QR code is open on the Dune, at most 5 minutes.'
    check "cgi page: no PHP errors" quiet
    printf 'interface_language = russian\n' >"$cfg/settings.properties"
    req GET "t=$tok"
    check "cgi page, Russian Dune: warning" body_has 'В логах могут быть личные данные. Не выкладывайте их в открытый доступ — на форумы и в общие чаты.'
    check "cgi page, Russian Dune: Скачать" body_has '&amp;dl=1">Скачать</a>'
    rm -f "$cfg/settings.properties"

    # Logs on the device: shell.log of 2 MB (only the last 1 MB goes out).
    awk 'BEGIN { print "SHELL_LOG_FIRST_LINE"; for (i = 0; i < 20000; i++)
        printf "[2026-10-06 12:00:00] shell line %06d %s\n", i, "................................................................................"
        print "SHELL_LOG_LAST_LINE" }' >"$cgi_tmp/run/shell.log"
    printf 'NUM_SUPPLIER_MARK\n' >"$cgi_tmp/run/num__supplier.log"
    printf 'FREEZONA_SUPPLIER_MARK\n' >"$cgi_tmp/run/freezona__supplier.log"
    printf 'ALPAC_SUPPLIER_MARK\n' >"$cgi_tmp/run/alpac__supplier.log"
    printf 'FLUX_SUPPLIER_MARK\n' >"$cgi_tmp/run/flux__supplier.log"
    printf 'SEASONHIT_SUPPLIER_MARK\n' >"$cgi_tmp/run/seasonhit__supplier.log"
    printf 'OTHER_SUPPLIER_MARK\n' >"$cgi_tmp/run/youtube__supplier.log"
    printf 'IPTVCE_SUPPLIER_MARK\n' >"$cgi_tmp/run/iptvce_mirkino__supplier.log"
    printf 'IPTVCE_DOT_MARK\n' >"$cgi_tmp/run/iptvce_iedem.tv__supplier.log"
    printf 'IPTVCE_BAD_NAME_MARK\n' >"$cgi_tmp/run/iptvce_a..b__supplier.log"
    printf 'IPTVCE_BAD_NAME_MARK\n' >"$cgi_tmp/run/iptvce_.x__supplier.log"
    printf 'IPTVCE_BAD_NAME_MARK\n' >"$cgi_tmp/run/iptvce_mir kino__supplier.log"
    printf 'PIA_LOG_MARK\n' >"$cgi_tmp/run/play_in_apps.log"
    printf 'SHELL_EXT_MARK\n' >"$cgi_tmp/run/shell_ext.log"
    printf 'ASYNC_MARK\n' >"$cgi_tmp/plugins/shell_ext/async_worker.log"
    printf 'firmware_version=260827_0003_r24\nproduct=tv188b\n' >"$cgi_tmp/run/versions.txt"
    # The CGI has no PLAY_IN_APPS_TMP: the items under $FS_PREFIX/tmp.
    mkdir -p "$cgi_tmp/applications"
    cp "$fx/app_data.json" "$cgi_tmp/applications/app_data.json"
    env -u PLAY_IN_APPS_TMP "$sh_bin" "$bin/sync.sh" >/dev/null
    req GET "t=$tok&dl=1"
    check "cgi download: 200" status_is 200
    check "cgi download: text/plain utf-8" hdr 'Content-type: text/plain; charset=utf-8'
    check "cgi download: attachment named by model and UTC time" sh -c '[ "$1" = cli ] || grep -qiE "^Content-Disposition: attachment; filename=\"play_in_apps-Pro_8K_Plus-[0-9]{8}-[0-9]{6}\\.txt\"" "$2"' _ "$cgi_mode" "$o"
    check "cgi download: no-store, nosniff" sh -c '[ "$1" = cli ] || { grep -qi "^Cache-Control: no-store" "$2" && grep -qi "^X-Content-Type-Options: nosniff" "$2"; }' _ "$cgi_mode" "$o"
    check "cgi download: version and warning first" sh -c 'head -n 1 "$1" | grep -q "^play_in_apps $2 logs, " && sed -n 2p "$1" | grep -qF "The logs may contain personal data."' _ "$o.body" "$plugin_version"
    check "cgi download: diag, supplier logs, play_in_apps.log, shell_ext.log, async_worker.log, shell.log, logcat, END" python3 - "$o.body" <<'EOF'
import sys
s = open(sys.argv[1], encoding="utf-8", errors="replace").read()
marks = ["Device: Pro 8K Plus, Android 11", "Firmware: 260827_0003_r24 (tv188b)", "NUM_SUPPLIER_MARK",
         "lampa__supplier.log: no file", "FREEZONA_SUPPLIER_MARK", "ALPAC_SUPPLIER_MARK", "FLUX_SUPPLIER_MARK",
         "SEASONHIT_SUPPLIER_MARK", "PIA_LOG_MARK", "SHELL_EXT_MARK",
         "ASYNC_MARK", "last 1048576 bytes", "SHELL_LOG_LAST_LINE", "LOGCAT_MARK"]
pos = [s.find(m) for m in marks]
sys.exit(-1 in pos or pos != sorted(pos) or not s.endswith("\nEND\n"))
EOF
    check "cgi download: diag report whole" sh -c 'grep -qx "NUM: OK" "$1" && grep -qx "FreeZona: OK" "$1"' _ "$o.body"
    check "cgi download: shell.log tail only" sh -c '! grep -q SHELL_LOG_FIRST_LINE "$1"' _ "$o.body"
    check "cgi download: other suppliers' logs left out" sh -c '! grep -q OTHER_SUPPLIER_MARK "$1"' _ "$o.body"
    check "cgi download: builds' supplier logs after the fixed ones, a name with a dot too" sh -c \
        'grep -q IPTVCE_SUPPLIER_MARK "$1" && [ "$(grep -n -e SEASONHIT_SUPPLIER_MARK -e IPTVCE_DOT_MARK -e IPTVCE_SUPPLIER_MARK -e PIA_LOG_MARK "$1" | cut -d: -f2 | tr "\n" " ")" = "SEASONHIT_SUPPLIER_MARK IPTVCE_DOT_MARK IPTVCE_SUPPLIER_MARK PIA_LOG_MARK " ]' _ "$o.body"
    check "cgi download: logs with bad build names left out" sh -c '! grep -q IPTVCE_BAD_NAME_MARK "$1"' _ "$o.body"
    check "cgi download: no PHP errors" quiet
    req GET "t=$tok&dl=1"
    check "cgi download again with the same token: whole" sh -c 'tail -n 1 "$1" | grep -qx END' _ "$o.body"
    if [ "$cgi_mode" = cgi ]; then
        req HEAD "t=$tok&dl=1"
        check "cgi HEAD: headers with attachment, no body" sh -c 'grep -qi "^Content-Disposition: attachment" "$1" && [ ! -s "$2" ]' _ "$o" "$o.body"
        req HEAD ''
        check "cgi HEAD without token: 403, no body" sh -c 'head -n 1 "$1" | grep -q "^Status: 403" && [ ! -s "$2" ]' _ "$o" "$o.body"
    fi
    check "cgi writes nothing" test "$(ls -A "$cgi_tmp/plugins/play_in_apps")" = logs_token

    # The token of the plugin's dialog opens the page; RETURN turns it off.
    rm -f "$cgi_tok"
    PIA_T_TMP="$cgi_tmp/plugins/play_in_apps"
    export PIA_T_TMP
    press logs
    req GET "t=$(cat "$cgi_tok")"
    check "cgi with the dialog's token: page" body_has 'Download</a>'
    old_tok=$(cat "$cgi_tok")
    press logs_return
    req GET "t=$old_tok"
    check "cgi after RETURN: same 403" forbidden
    unset PIA_T_TMP
fi

# --- build.sh: www/cgi-bin holds only the logs wrapper (the shell runs every
# file there as root). A copy of the repo whose test script fails: a build
# that passes the check stops at the tests.
br="$work/build_repo"
mkdir -p "$br/plugin" "$br/tests"
cp "$root/build.sh" "$br/"
cp -R "$src" "$br/plugin/play_in_apps"
echo 'exit 1' >"$br/tests/play_in_apps_test.sh"
cgi_msg='www/cgi-bin may hold only the file logs'
# build_cgi_is <ok|refused>: what build.sh says about www/cgi-bin.
build_cgi_is() {
    sh "$br/build.sh" play_in_apps >"$o" 2>"$o.err"
    rc=$?
    if [ "$1" = ok ]; then
        [ "$rc" != 0 ] && ! grep -qF "$cgi_msg" "$o.err"
    else
        [ "$rc" = 1 ] && grep -qF "$cgi_msg" "$o.err" && [ ! -d "$br/dist" ]
    fi
}
check "build.sh: www/cgi-bin with logs only passes" build_cgi_is ok
: >"$br/plugin/play_in_apps/www/cgi-bin/settings"
check "build.sh: another file in www/cgi-bin refused" build_cgi_is refused
check "build.sh: the extra file named" grep -qF 'it has: logs settings' "$o.err"
rm -f "$br/plugin/play_in_apps/www/cgi-bin/settings"
mkdir "$br/plugin/play_in_apps/www/cgi-bin/sub"
check "build.sh: a directory in www/cgi-bin refused" build_cgi_is refused
rmdir "$br/plugin/play_in_apps/www/cgi-bin/sub"
mv "$br/plugin/play_in_apps/www/cgi-bin/logs" "$br/plugin/play_in_apps/www/logs"
ln -s ../logs "$br/plugin/play_in_apps/www/cgi-bin/logs"
check "build.sh: logs as a symlink refused" build_cgi_is refused
rm -rf "$br"

# --- manifest and translations
check "manifest: php, suppliers, entry points, global actions, timeout" python3 - "$src/dune_plugin.xml" "$all" <<'EOF'
import copy, os, re, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
es = r.findall("entry_points/entry_point")
e = es[0]
icon = e.findtext("icon_url") or ""
# The same shortcut in Applications and in Settings -> Applications.
parents = [x.findtext("parent_media_url") for x in es]
def strip(x):
    x = copy.deepcopy(x)
    x.tail = None
    for t in ("parent_media_url", "media_url"):
        for c in x.findall(t):
            x.remove(c)
    return ET.tostring(x, "unicode")
ok = (r.findtext("name") == "play_in_apps"
      and r.findtext("type") == "php"
      and r.findtext("params/program") == "main.php"
      and r.findtext("params/movie_suppliers") == "-".join(sys.argv[2].split())
      and r.findtext("global_actions/uninstall/data/run_string") == "bin/uninstall.sh"
      and r.findtext("global_actions/early_gui_start/data/run_string") == "bin/sync.sh"
      and parents == ["root://applications", "setup://applications"]
      and strip(es[0]) == strip(es[1])
      and e.findtext("actions/key_enter/type") == "plugin_open_folder"
      and e.findtext("actions/key_enter/data/media_url") == "setup"
      and icon.startswith("plugin_file://")
      and os.path.isfile(os.path.join(os.path.dirname(sys.argv[1]), icon[len("plugin_file://"):]))
      and r.findtext("operation_timeout/default") == "60"
      and re.fullmatch(r"\d+\.\d+\.\d+", r.findtext("version") or "")
      and re.fullmatch(r"\d+", r.findtext("version_index") or ""))
sys.exit(not ok)
EOF
# The shell keys entry points by "<plugin>:<media_url>": with the same
# media_url the later one replaces the earlier, and the root:// shortcut
# drops out of Applications -> All.
check "manifest: entry point media_url values all differ" python3 - "$src/dune_plugin.xml" <<'EOF'
import sys, xml.etree.ElementTree as ET
es = ET.parse(sys.argv[1]).getroot().findall("entry_points/entry_point")
urls = [x.findtext("media_url") for x in es]
sys.exit(not (urls and all(urls) and len(set(urls)) == len(urls)))
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
    check "id $i: diag.sh" grep -q " $i:" "$src/bin/diag.sh"
    check "id $i: cgi/logs.php" grep -q "'$i'" "$src/cgi/logs.php"
done
scripts=$(for i in $all; do echo "$i.sh"; done)
# shellcheck disable=SC2086 # one word per script
check "no other item scripts" listing_is "$src/bin" diag.sh movie_suppliers_update.sh search.sh sync.sh uninstall.sh \
    iptvce.sh iptvce_builds.sh $scripts

keys="plugin_caption"
for i in $all; do
    keys="$keys ${i}_caption $(grep -ho 'fail err_[a-z_]*' "$src/bin/$i.sh" | sed "s/^fail /${i}_/" | sort -u)"
done
keys="$keys filmix_api_err_unsupported bazinga_err_unsupported iptvce_err_unsupported $(grep -o "%tr%[a-z_]*\|pia_error_action('[a-z_]*')\|pia_tr('[a-z_]*')\|play_in_apps_plugin_[a-z_0-9]*" "$src/main.php" |
    sed "s/^%tr%//; s/^pia_error_action('//; s/^pia_tr('//; s/')\$//; s/^play_in_apps_plugin_//" | sort -u)"
# diag.sh: $(t <key>); cgi/logs.php: lp_tr('<key>').
keys="$keys $(grep -o '(t [a-z_]*)' "$src/bin/diag.sh" | sed 's/^(t //; s/)$//' | sort -u)"
keys="$keys $(grep -o "lp_tr('[a-z_]*')" "$src/cgi/logs.php" | sed "s/^lp_tr('//; s/')\$//" | sort -u)"
for lang in english russian; do
    tr_file="$src/translations/dune_language_$lang.txt"
    for key in $keys; do
        check "translation $lang: $key" grep -q "^$key = ." "$tr_file"
    done
done
for lang in english russian; do
    check "translation $lang: screen_hint fits the right column (50 characters)" python3 -c 'import sys
t = [l for l in open(sys.argv[1], encoding="utf-8") if l.startswith("screen_hint = ")]
sys.exit(len(t) != 1 or len(t[0].rstrip("\n")) - len("screen_hint = ") > 50)' "$src/translations/dune_language_$lang.txt"
done
check "translations: same keys in both languages" test \
    "$(cut -d' ' -f1 "$src/translations/dune_language_english.txt" | sort)" = \
    "$(cut -d' ' -f1 "$src/translations/dune_language_russian.txt" | sort)"

if [ "$failed" -ne 0 ]; then
    echo "SOME TESTS FAILED"
    exit 1
fi
echo "ALL PASSED"
