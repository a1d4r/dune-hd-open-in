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

android="num lampa bylampa lampa_atv prisma vokino lazymedia stremio nuvio freezona"
all="num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona"
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
# LazyMedia the argument is the percent-encoded search query. The other apps
# get the URI as an intent: URI with the package (no -p: the shell's command
# parser on some firmware rejects it); it is parsed back the way
# Intent.parseUri does to the scheme, data, action and package.
launch_is() {
    python3 - "$o" "$id" "$1" <<'EOF'
import json, re, sys
d = json.load(open(sys.argv[1]))
app, arg = sys.argv[2], sys.argv[3]
pkg, title, flags = {
    "nuvio": ("com.nuvio.tv", "Nuvio", ""),
    "stremio": ("com.stremio.one", "Stremio", ""),
    "num": ("ru.yourok.num", "NUM", "--activity-clear-task "),
    "lampa": ("top.rootu.lampa", "Lampa", "--activity-clear-task "),
    "bylampa": ("top.rootu.bylumpa", "BYLAMPA", "--activity-clear-task "),
    "lampa_atv": ("top.rootu.lumpa", "LAMPA ATV", "--activity-clear-task "),
    "prisma": ("top.rootu.prisma", "Prisma", "--activity-clear-task "),
    "vokino": ("ru.vokino.web", "VoKino", "--activity-clear-task "),
    "lazymedia": ("com.lazycatsoftware.lmd", "LazyMedia", "--activity-clear-task "),
    "freezona": ("free.zona", "FreeZona", "--activity-clear-task "),
}[app]
if app == "lazymedia":
    cmd = ("am start --activity-clear-task 'intent:#Intent;component=com.lazycatsoftware.lmd/"
           "com.lazycatsoftware.lazymediadeluxe.ui.tv.activities.ActivityTvSearch;S.query=%s;end'" % arg)
else:
    scheme, rest = arg.split(":", 1)
    cmd = ("am start %s'intent:%s#Intent;scheme=%s;action=android.intent.action.VIEW;package=%s;end'"
           % (flags, rest, scheme, pkg))
if d != {"bin": cmd, "package": pkg, "title": title, "wait_app_start_delay": 10}:
    sys.exit(1)
if " -p " in d["bin"] + " ":
    sys.exit("-p in the command")
if app != "lazymedia":
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
       "lampa": "top.rootu.lampa", "bylampa": "top.rootu.bylumpa", "lampa_atv": "top.rootu.lumpa",
       "prisma": "top.rootu.prisma", "vokino": "ru.vokino.web",
       "lazymedia": "com.lazycatsoftware.lmd", "freezona": "free.zona"}.get(app)
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
opens_series bylampa launch_is "$t/tv/94997"
opens_series lampa_atv launch_is "$t/tv/94997"
opens_series prisma launch_is "$t/tv/94997"
opens_series vokino launch_is "$v/tt11198330"
opens_series lazymedia search_is 'Дом Дракона'
# series.json has no Kinopoisk ID; the error key shows bin/freezona.sh ran.
opens_series freezona error_is err_no_id

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
check "sync hidden: nuvio and filmix_api removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia stremio freezona
printf 'freezona\n' >"$data/hidden"
run sync.sh
check "sync hidden: freezona removed" shown num lampa bylampa lampa_atv prisma vokino lazymedia filmix_api stremio nuvio
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
check "sync garbage in hidden: only prisma hidden" shown num lampa bylampa lampa_atv vokino lazymedia filmix_api stremio nuvio freezona
check "sync garbage in hidden: no stray files" listing_is "$data" hidden movie_suppliers
rm -f "$data/hidden"

# --- sync: an app not installed (or uninstalled later)
cp "$fx/app_data_no_lazymedia.json" "$apps"
run sync.sh
check "sync LazyMedia not installed: item removed" shown num lampa prisma vokino filmix_api stremio nuvio
cp "$fx/app_data_no_freezona.json" "$apps"
run sync.sh
check "sync FreeZona not installed: item removed" shown num lampa prisma vokino lazymedia filmix_api stremio nuvio
cp "$fx/app_data_no_bylampa.json" "$apps"
run sync.sh
check "sync BYLAMPA not installed: item removed, Lampa shown" shown num lampa prisma vokino lazymedia filmix_api stremio nuvio freezona
cp "$work/app_data_only_bylampa.json" "$apps"
run sync.sh
check "sync Lampa not installed: item removed, BYLAMPA shown" shown num bylampa prisma vokino lazymedia filmix_api stremio nuvio freezona
cp "$fx/app_data_no_lampa_atv.json" "$apps"
run sync.sh
check "sync LAMPA ATV not installed: item removed" shown num lampa bylampa prisma vokino lazymedia filmix_api stremio nuvio freezona
cp "$work/app_data_only_lampa_atv.json" "$apps"
run sync.sh
check "sync only LAMPA ATV of the Lampa apps: its item shown" shown num lampa_atv prisma vokino lazymedia filmix_api stremio nuvio freezona
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
check "sync no app_data.json: Android items unchanged, Filmix removed" shown num lampa bylampa lampa_atv prisma vokino stremio nuvio freezona
for content in '' '{}' 'garbage' '{"applications":['; do
    printf '%s' "$content" >"$apps"
    run sync.sh
    check "sync app_data.json '$content': Android items unchanged" shown num lampa bylampa lampa_atv prisma vokino stremio nuvio freezona
done
# Read while the shell rewrites it: cut short, most apps missing.
head -c 1500 "$fx/app_data.json" >"$apps"
run sync.sh
check "sync app_data.json cut short: Android items unchanged" shown num lampa bylampa lampa_atv prisma vokino stremio nuvio freezona
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
       "lampa": "top.rootu.lampa", "bylampa": "top.rootu.bylumpa", "lampa_atv": "top.rootu.lumpa",
       "prisma": "top.rootu.prisma", "vokino": "ru.vokino.web",
       "lazymedia": "com.lazycatsoftware.lmd", "freezona": "free.zona"}
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
all_pkgs="ru.yourok.num top.rootu.lampa top.rootu.bylumpa top.rootu.lumpa top.rootu.prisma ru.vokino.web com.lazycatsoftware.lmd com.stremio.one com.nuvio.tv free.zona"
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
# verdicts_are <verdict> [<caption>=<verdict>...]: the 11 verdict lines, in
# the order of the items, after the 4 lines about the device.
verdicts_are() {
    python3 - "$o" "$@" <<'EOF'
import sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
caps = ["NUM", "Lampa", "BYLAMPA", "LAMPA ATV", "Prisma", "VoKino", "LazyMedia", "Filmix",
        "Stremio", "Nuvio", "FreeZona"]
want = dict((c, sys.argv[2]) for c in caps)
for a in sys.argv[3:]:
    c, v = a.split("=", 1)
    want[c] = v
got = [l for l in lines if l and not l.startswith(" ")][4:4 + len(caps)]
sys.exit(got != ["%s: %s" % (c, want[c]) for c in caps])
EOF
}

# brief_is <en|ru> [<caption>=<verdict>...]: the brief report is exactly 12
# lines: the device, then "<caption> <version> — <verdict>" per item, OK by
# default.
brief_is() {
    python3 - "$o" "$plugin_version" "$@" <<'EOF'
import sys
lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().split("\n")
ver, ru = sys.argv[2], sys.argv[3] == "ru"
items = [("NUM", "1.0.150"), ("Lampa", "1.13.1"), ("BYLAMPA", "1.13.3"), ("LAMPA ATV", "1.13.3"),
         ("Prisma", "1.3.4"), ("VoKino", "1.1.1-android"), ("LazyMedia", "3.467"), ("Filmix", ""),
         ("Stremio", "1.11.2"), ("Nuvio", "1.0.0"), ("FreeZona", "3.0.74")]
ok = "ОК" if ru else "OK"
verdict = dict((c, ok) for c, _ in items)
verdict["Filmix"] = ok + (" (через плагин Filmix_API)" if ru else " (through the Filmix_API plugin)")
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
        LazyMedia="$v" Stremio="$v" Nuvio="$v" FreeZona="$v" "$@"
}
# no_details: none of the full report's details.
no_details() { ! grep -qE 'am start|intent|menu item|installed:|launch:|FS_PREFIX|records|movie_suppliers' "$o"; }

mkdir -p "$plugins/Filmix_api" "$PLAY_IN_APPS_TMP/run"
: >"$plugins/Filmix_api/dune_plugin.xml"
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
check "diag Filmix: not checked" in_item Filmix "  launch: through the Filmix_API plugin, not checked"
check "diag: no shell log lines" has_line "  none"
check "diag: no empty lines" sh -c '! grep -q "^\$" "$1"' _ "$o"
check "diag: 10 queries, Filmix none" test "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 10
ifr='#Intent;scheme=https;action=android.intent.action.VIEW;package'
check "diag query NUM: the intent: URI of the item" grep -qxF \
    "$q intent://www.themoviedb.org/movie/920$ifr=ru.yourok.num;end" "$STUB_LOG"
check "diag query FreeZona: Kinopoisk link" grep -qxF \
    "$q intent://www.kinopoisk.ru/film/61249$ifr=free.zona;end" "$STUB_LOG"
check "diag query VoKino" grep -qxF \
    "$q intent://ru.vokino.web/view/tt0317219#Intent;scheme=vokino;action=android.intent.action.VIEW;package=ru.vokino.web;end" "$STUB_LOG"
check "diag query Stremio" grep -qxF \
    "$q intent:///detail/movie/tt0317219#Intent;scheme=stremio;action=android.intent.action.VIEW;package=com.stremio.one;end" "$STUB_LOG"
check "diag query Nuvio" grep -qxF \
    "$q intent://movie/tt0317219#Intent;scheme=nuvio;action=android.intent.action.VIEW;package=com.nuvio.tv;end" "$STUB_LOG"
check "diag query LazyMedia: the intent: URI with the component" grep -qxF \
    "$q intent:#Intent;component=com.lazycatsoftware.lmd/com.lazycatsoftware.lazymediadeluxe.ui.tv.activities.ActivityTvSearch;S.query=%D0%A2%D0%B0%D1%87%D0%BA%D0%B8;end" "$STUB_LOG"
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
check "diag brief: the same 10 queries" test "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 10
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
check "diag none resolves: verdicts" verdicts_are "!! the app will not take the link" Filmix=OK
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
check "diag cmd refuses: no data" verdicts_are "?? could not check the launch" Filmix=OK
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
check "diag uid 10123, No activities found: no data" verdicts_are "?? could not check the launch" Filmix=OK
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
    check "diag uid $u (not an ordinary app): does not resolve" verdicts_are "!! the app will not take the link" Filmix=OK
done
STUB_UID=10000
diag
check "diag uid 10000 (an ordinary app): no data" verdicts_are "?? could not check the launch" Filmix=OK
STUB_RESOLVE=$all_pkgs
unset STUB_UID
if ! command -v cmd >/dev/null 2>&1; then
    PATH="$work/sbin_nocmd:$PATH" "$sh_bin" "$bin/diag.sh" >"$o" 2>"$o.err"
    check "diag no cmd: no data" verdicts_are "?? could not check the launch" Filmix=OK
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
printf 'num\nfilmix_api\n' >"$data/hidden"
run sync.sh
diag
check "diag hidden: verdicts" verdicts_are OK NUM="-- hidden" Filmix="-- hidden"
check "diag hidden: reason" in_item NUM "  hidden: yes"
check "diag hidden: no menu file" in_item NUM "  menu item: no"
diag english brief
check "diag brief hidden" brief_is en NUM=hidden Filmix=hidden
diag russian brief
check "diag brief russian hidden" brief_is ru NUM=скрыт Filmix=скрыт
cp "$fx/app_data_no_vokino.json" "$apps"
diag
check "diag VoKino not installed: verdict" in_item VoKino "VoKino: -- not installed"
check "diag VoKino not installed: reason" in_item VoKino "  installed: no (ru.vokino.web)"
check "diag VoKino not installed: what the item says" in_item VoKino "  launch: error: VoKino is not installed"
diag english brief
check "diag brief VoKino not installed: no version" sh -c 'grep -qxF "VoKino — not installed" "$1" && grep -qxF "NUM 1.0.150 — hidden" "$1"' _ "$o"
rm -f "$plugins/Filmix_api/dune_plugin.xml"
diag russian brief
check "diag brief Filmix_API not installed" grep -qxF "Filmix — не установлено" "$o"
: >"$plugins/Filmix_api/dune_plugin.xml"
rm -f "$data/hidden"
cp "$fx/app_data.json" "$apps"
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
check "diag brief: 12 lines with a long version" test "$(wc -l <"$o" | tr -d ' ')" = 12
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
         ("stremio", "Stremio"), ("nuvio", "Nuvio"), ("freezona", "FreeZona")]
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
         ("freezona", "FreeZona", "free.zona")]
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
    rm -f "$plugins/Filmix_api/dune_plugin.xml"
    cp "$fx/app_data_no_lazymedia.json" "$apps"
    printf 'nuvio\nprisma\ngarbage\n' >"$data/hidden"
    press items
    check "items: exit 0" rc_is 0
    check "items: stderr has only own log lines" only_own_log
    check "items: dialog with all 11 items, not installed marked, icons" \
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

    # Icons: Filmix — the logo of the installed Filmix_API plugin; an app —
    # its "icon" in app_data.json (Android TV: in flashdata), else icon_cache.
    mkdir -p "$plugins/Filmix_api/icons" "$work/atv_icons"
    : >"$plugins/Filmix_api/dune_plugin.xml"
    : >"$plugins/Filmix_api/icons/logo.png"
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
    check "items icons: app_data icon, icon_cache, Filmix_API logo" items_is "$all" "num freezona" en \
        "num=$work/atv_icons/icon_ru.yourok.num.png filmix_api=$plugins/Filmix_api/icons/logo.png"
    rm -f "$plugins/Filmix_api/dune_plugin.xml"
    press items
    check "items icons: Filmix_API logo without its manifest: still the logo" items_is \
        "num lampa bylampa lampa_atv prisma vokino lazymedia stremio nuvio freezona" "num freezona" en \
        "num=$work/atv_icons/icon_ru.yourok.num.png filmix_api=$plugins/Filmix_api/icons/logo.png"
    : >"$plugins/Filmix_api/dune_plugin.xml"
    rm -f "$plugins/Filmix_api/icons/logo.png"
    press items
    check "items icons: no Filmix_API logo: apps.aai" items_is "$all" "num freezona" en \
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
    check "list_apply: sync" shown num bylampa lampa_atv prisma vokino lazymedia filmix_api nuvio freezona
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
    rm -f "$data/hidden" "$lcfg"
    run sync.sh

    # --- "Check": the report of diag.sh as a list

    # check_view_is <file with the expected lines>: view_regular 1x12 with a
    # scrollbar, a row per line, ENTER does nothing.
    check_view_is() {
        python3 - "$o" "$1" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
lines = open(sys.argv[2], encoding="utf-8").read().rstrip("\n").split("\n")
rows = [{"media_url": "line:%d" % i, "caption": l, "view_item_params": []} for i, l in enumerate(lines)]
rng = {"total": len(rows), "more_items_available": False, "from_ndx": 0, "count": len(rows), "items": rows}
view = {"multiple_views_supported": False, "view_kind": "view_regular", "data": {
    "view_params": {"num_cols": 1, "num_rows": 12, "paint_details": False, "paint_scrollbar": True,
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
    check "check screen: 12 rows, one screen" python3 -c 'import json, sys
sys.exit(len(json.load(open(sys.argv[1]))["data"]["data"]["initial_range"]["items"]) != 12)' "$o"
    check "check screen: no details" sh -c '! grep -qE "am start|intent|launch:|FS_PREFIX" "$1"' _ "$o"
    check "check screen: diag.sh ran from PHP" test "$(wc -l <"$STUB_LOG" | tr -d ' ')" = 10
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
    printf 'OTHER_SUPPLIER_MARK\n' >"$cgi_tmp/run/youtube__supplier.log"
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
         "lampa__supplier.log: no file", "FREEZONA_SUPPLIER_MARK", "PIA_LOG_MARK", "SHELL_EXT_MARK",
         "ASYNC_MARK", "last 1048576 bytes", "SHELL_LOG_LAST_LINE", "LOGCAT_MARK"]
pos = [s.find(m) for m in marks]
sys.exit(-1 in pos or pos != sorted(pos) or not s.endswith("\nEND\n"))
EOF
    check "cgi download: diag report whole" sh -c 'grep -qx "NUM: OK" "$1" && grep -qx "FreeZona: OK" "$1"' _ "$o.body"
    check "cgi download: shell.log tail only" sh -c '! grep -q SHELL_LOG_FIRST_LINE "$1"' _ "$o.body"
    check "cgi download: other suppliers' logs left out" sh -c '! grep -q OTHER_SUPPLIER_MARK "$1"' _ "$o.body"
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
check "manifest: php, suppliers, entry point, global actions, timeout" python3 - "$src/dune_plugin.xml" "$all" <<'EOF'
import os, re, sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
e = r.find("entry_points/entry_point")
icon = e.findtext("icon_url") or ""
ok = (r.findtext("name") == "play_in_apps"
      and r.findtext("type") == "php"
      and r.findtext("params/program") == "main.php"
      and r.findtext("params/movie_suppliers") == "-".join(sys.argv[2].split())
      and r.findtext("global_actions/uninstall/data/run_string") == "bin/uninstall.sh"
      and r.findtext("global_actions/early_gui_start/data/run_string") == "bin/sync.sh"
      and e.findtext("parent_media_url") == "setup://applications"
      and e.findtext("actions/key_enter/type") == "plugin_open_folder"
      and icon.startswith("plugin_file://")
      and os.path.isfile(os.path.join(os.path.dirname(sys.argv[1]), icon[len("plugin_file://"):]))
      and r.findtext("operation_timeout/default") == "60"
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
    check "id $i: diag.sh" grep -q " $i:" "$src/bin/diag.sh"
    check "id $i: cgi/logs.php" grep -q "'$i'" "$src/cgi/logs.php"
done
scripts=$(for i in $all; do echo "$i.sh"; done)
# shellcheck disable=SC2086 # one word per script
check "no other item scripts" listing_is "$src/bin" diag.sh movie_suppliers_update.sh sync.sh uninstall.sh $scripts

keys="plugin_caption"
for i in $all; do
    keys="$keys ${i}_caption $(grep -ho 'fail err_[a-z_]*' "$src/bin/$i.sh" | sed "s/^fail /${i}_/" | sort -u)"
done
keys="$keys filmix_api_err_unsupported $(grep -o "%tr%[a-z_]*\|pia_error_action('[a-z_]*')\|pia_tr('[a-z_]*')\|play_in_apps_plugin_[a-z_0-9]*" "$src/main.php" |
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
