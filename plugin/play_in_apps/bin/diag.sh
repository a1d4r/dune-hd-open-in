#!/bin/sh
# The "Check" report. Full (the logs file, cgi/logs.php): the device, then
# for every item a verdict line and its reasons (installed, hidden, the menu
# file, what the item script answers for a built-in movie and whether that
# intent resolves to an activity), then the shell's last lines about
# launching items. Brief (the plugin's check screen, main.php): 12 lines, one
# screen — the device, then one line per item with its verdict.
# Read only: the item scripts only print a command, and
# `cmd package query-activities` starts nothing.
# Usage: sh diag.sh [russian|english] [brief]; output is in that language.

name=play_in_apps
mydir=$(cd "$(dirname "$0")" && pwd)
tmp=${PLAY_IN_APPS_TMP:-$FS_PREFIX/tmp}
data="${PLAY_IN_APPS_FLASHDATA:-$FS_PREFIX/flashdata}/plugins_data/$name"
apps="$tmp/applications/app_data.json"
plugins=$(dirname "$(dirname "$mydir")")

lang=english
[ "${1-}" = russian ] && lang=russian
brief=0
[ "${2-}" = brief ] && brief=1
trf="$mydir/../translations/dune_language_$lang.txt"

# t <key>: the translation of a key (keys are [a-z0-9_] only).
t() {
    sed -n "s/^$1 = //p" "$trf" 2>/dev/null | head -n 1
}

say() {
    printf '%s\n' "$*"
}

# re <package>: the package as a regex.
re() {
    printf '%s' "$1" | sed 's/\./\\./g'
}

# field <name> <file>: first "name":"value" string of a JSON file.
field() {
    grep -o "\"$1\": *\"[^\"]*\"" "$2" 2>/dev/null | head -n 1 |
        sed 's/^[^:]*: *"//; s/"$//; s#\\/#/#g'
}

# app_version <package>: "version" of the app in the shell's app list.
# Records are split at "}" so field order and layout do not matter.
app_version() {
    tr '\n}' ' \n' <"$apps" 2>/dev/null | grep "\"package_name\": *\"$(re "$1")\"" |
        grep -o '"version": *"[^"]*"' | head -n 1 | sed 's/^[^:]*: *"//; s/"$//'
}

# The movie every item script gets: a real input of the device ("Cars") with
# TMDB, Kinopoisk and IMDb IDs and titles, so each item has what it needs.
movie() {
    cat <<'EOF'
{"movieInfo":{"movieExtId":"dunemdb:57163b80d56dbe3f63696ffc,kinopoisk:61249,imdb:tt0317219,tmdb:920","supplierId":"freezona","title":{"ru":"\u0422\u0430\u0447\u043a\u0438","en":"Cars"},"year":"2006","type":"single","videoType":"video"},"assType":0,"season":-1,"episode":-1,"fileId":null}
EOF
}

yes_=$(t diag_yes)
no_=$(t diag_no)
l_intent=$(t diag_intent)
l_no_data=$(t diag_no_data)

body=
add() {
    body="$body
  $*"
}

# query <command line of the item>: does its intent resolve to an activity
# of the item's package? Sets res to yes, no or nodata. The exit code of
# query-activities is 0 either way, only the text tells.
query() {
    # am start [--activity-clear-task] -a <action> -d '<uri>' -p <package>
    q=$(printf '%s\n' "$1" | sed -n "s/^am start \(--activity-clear-task \)*-a \([A-Za-z0-9._][A-Za-z0-9._]*\) -d '\([^']*\)' -p \([A-Za-z0-9._][A-Za-z0-9._]*\)\$/\2 \4 \3/p")
    if [ -n "$q" ]; then
        qa=${q%% *}
        q=${q#* }
        qp=${q%% *}
        set -- -a "$qa" -d "${q#* }" -p "$qp"
    else
        # LazyMedia: am start --activity-clear-task 'intent:#Intent;component=<pkg>/<class>;...;end'
        c=$(printf '%s\n' "$1" | sed -n "s/^am start --activity-clear-task 'intent:#Intent;component=\([A-Za-z0-9._][A-Za-z0-9._]*\/[A-Za-z0-9._][A-Za-z0-9._]*\);[^']*;end'\$/\1/p")
        if [ -z "$c" ]; then
            res=nodata
            add "$l_intent: $l_no_data ($(t diag_unknown_command))"
            return
        fi
        qp=${c%%/*}
        set -- -n "$c"
    fi
    if ! command -v cmd >/dev/null 2>&1; then
        res=nodata
        add "$l_intent: $l_no_data ($(t diag_no_cmd))"
        return
    fi
    out=$(cmd package query-activities --brief "$@" 2>&1 </dev/null)
    case "$out" in
        *'No activit'*)
            res=no
            add "$l_intent: $(t diag_not_resolves)"
            return
            ;;
    esac
    comp=$(printf '%s\n' "$out" | sed -n "s/^ *\($(re "$qp")\/[A-Za-z0-9._\$]*\) *\$/\1/p" | head -n 1)
    if [ -n "$comp" ] && printf '%s\n' "$out" | grep -q '^[0-9][0-9]* activities found'; then
        res=yes
        note=
        printf '%s\n' "$out" | grep -q 'isDefault=false' && note=' (isDefault=false)'
        add "$l_intent: $(t diag_resolves) -> $comp$note"
    else
        res=nodata
        first=$(printf '%s\n' "$out" | sed -n '/./{p;q;}' | cut -c 1-120)
        add "$l_intent: $l_no_data: ${first:-$(t diag_empty_output)}"
    fi
}

# --- The device.
model=$(getprop ro.product.model 2>/dev/null)
release=$(getprop ro.build.version.release 2>/dev/null)
fw=$(sed -n 's/^firmware_version=//p' "$tmp/run/versions.txt" 2>/dev/null | head -n 1)
product=$(sed -n 's/^product=//p' "$tmp/run/versions.txt" 2>/dev/null | head -n 1)
version=$(sed -n 's:.*<version>\(.*\)</version>.*:\1:p' "$mydir/../dune_plugin.xml" 2>/dev/null | head -n 1)
if [ "$brief" = 1 ]; then
    # 260827_0003_r24 -> r24 260827
    fw_short=$(printf '%s\n' "$fw" | sed -n 's/^\([0-9][0-9]*\)_[0-9][0-9]*_\(r[0-9][0-9]*\)$/\2 \1/p')
    say "${model:-?} · ${fw_short:-${fw:-?}} · Android ${release:-?} · $(t diag_brief_plugin) ${version:-?}"
else
    say "$(t diag_device): ${model:-?}, Android ${release:-?}"
    say "$(t diag_firmware): ${fw:-?} (${product:-?})"
    if [ -n "$FS_PREFIX" ]; then
        say "FS_PREFIX: $(t diag_set)"
    else
        say "FS_PREFIX: $(t diag_unset)"
    fi
    say "$(t diag_plugin): $name ${version:-?}"
fi

# --- The items. id:package; Filmix is the Filmix_API Dune plugin.
for app in num:ru.yourok.num lampa:top.rootu.lampa bylampa:top.rootu.bylumpa \
    lampa_atv:top.rootu.lumpa prisma:top.rootu.prisma vokino:ru.vokino.web \
    lazymedia:com.lazycatsoftware.lmd filmix_api: stremio:com.stremio.one \
    nuvio:com.nuvio.tv freezona:free.zona; do
    id=${app%%:*}
    pkg=${app#*:}
    body=
    res=
    v=

    if [ -z "$pkg" ]; then
        installed=0
        [ -f "$plugins/Filmix_api/dune_plugin.xml" ] && installed=1
        if [ "$installed" = 1 ]; then
            add "$(t diag_installed): $yes_ (Filmix_API)"
        else
            add "$(t diag_installed): $no_ (Filmix_API)"
        fi
    elif grep -q "\"package_name\": *\"$(re "$pkg")\"" "$apps" 2>/dev/null; then
        installed=1
        v=$(app_version "$pkg")
        add "$(t diag_installed): $yes_, $(t diag_version) ${v:-?} ($pkg)"
    else
        installed=0
        add "$(t diag_installed): $no_ ($pkg)"
    fi

    hidden=0
    grep -qxF "$id" "$data/hidden" 2>/dev/null && hidden=1
    if [ "$hidden" = 1 ]; then
        add "$(t diag_hidden): $yes_"
    else
        add "$(t diag_hidden): $no_"
    fi

    # The item's file the "Play..." menu reads.
    f="$tmp/movie_suppliers/$id"
    menu=none
    owner=
    if [ -f "$f" ]; then
        owner=$(field plugin "$f")
        script=$(field bin "$f")
        script=${script#sh }
        script=${script%% *}
        menu=nobin
        case "$script" in
            /*) [ -f "$script" ] && menu=ok ;;
        esac
        [ "$owner" = "$name" ] || menu=foreign
        if [ "$menu" = nobin ]; then
            add "$(t diag_menu): $yes_, plugin ${owner:-?}, $(t diag_bin_missing): ${script:-?}"
        else
            add "$(t diag_menu): $yes_, plugin ${owner:-?}"
        fi
    else
        add "$(t diag_menu): $no_"
    fi

    if [ -n "$pkg" ]; then
        reply=$(movie | sh "$mydir/$id.sh" start_playback_app 2>/dev/null)
        line=$(printf '%s\n' "$reply" | sed -n 's/^{"bin":"\([^"]*\)".*/\1/p')
        err=$(printf '%s\n' "$reply" | sed -n 's/.*<key_global>play_in_apps_plugin_\([a-z_]*\)<\/key_global>.*/\1/p')
        if [ -n "$line" ]; then
            add "$(t diag_launch): $line"
            query "$line"
        elif [ -n "$err" ]; then
            res=error
            add "$(t diag_launch): $(t diag_error): $(t "$err")"
        else
            res=error
            add "$(t diag_launch): $(t diag_no_reply)"
        fi
    else
        res=yes
        add "$(t diag_launch): $(t diag_play_action)"
    fi

    # mark: the full report's sign before the verdict.
    if [ "$installed" = 0 ]; then
        mark=--
        verdict=$(t diag_v_not_installed)
    elif [ "$hidden" = 1 ]; then
        mark=--
        verdict=$(t diag_v_hidden)
    elif [ "$menu" = none ]; then
        mark='!!'
        verdict=$(t diag_v_no_menu)
    elif [ "$menu" = foreign ]; then
        mark='!!'
        verdict="$(t diag_v_foreign) ${owner:-?}"
    elif [ "$menu" = nobin ]; then
        mark='!!'
        verdict=$(t diag_v_no_bin)
    elif [ "$res" = error ]; then
        mark='!!'
        verdict=$(t diag_v_launch_error)
    elif [ "$res" = no ]; then
        mark='!!'
        verdict=$(t diag_v_not_resolves)
    elif [ "$res" = nodata ]; then
        mark='??'
        verdict=$(t diag_v_no_data)
    else
        mark=
        verdict=OK
    fi
    if [ "$brief" = 1 ]; then
        if [ -z "$mark" ]; then
            verdict=$(t diag_v_ok)
            [ -n "$pkg" ] || verdict="$verdict ($(t diag_v_via_filmix_api))"
        fi
        say "$(t "${id}_caption")${v:+ $v} — $verdict"
    else
        say "$(t "${id}_caption"): ${mark:+$mark }$verdict$body"
    fi
done

[ "$brief" = 1 ] && exit 0

# --- What the shell logged about launching items (the check above does not
# see a launch timing out, only these lines do).
say "$(t diag_shell_log):"
lines=$(grep -E 'activity launch status|wait for shell app loosing focus timed-out' "$tmp/run/shell.log" 2>/dev/null | tail -n 5
    grep 'sup E:' "$tmp/run/shell_ext.log" 2>/dev/null | tail -n 5)
if [ -n "$lines" ]; then
    printf '%s\n' "$lines" | cut -c 1-300 | sed 's/^/  /'
else
    say "  $(t diag_none)"
fi
exit 0
