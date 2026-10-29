<?php
// The plugin screens and the play_action handlers of the Filmix and Bazinga
// items and of the items of IPTV Channel Editor builds:
//  - "setup": a short controls screen with three buttons — the item choice
//    (the shell's dialog with checkmarks), "Check" and logs for the author;
//  - "check": the brief report of bin/diag.sh (a line per item) as a list.
// The logs page itself is cgi/logs.php. Only the firmware PHP API is used
// (/firmware_ext/php/), PHP 5.3.6.

class PlayInApps
{
    // id => array(caption, Android package; null: a Dune plugin, its folder
    // name third). Same ids and packages as bin/sync.sh.
    public static $apps = array(
        'num' => array('NUM', 'ru.yourok.num'),
        'lampa' => array('Lampa', 'top.rootu.lampa'),
        'bylampa' => array('BYLAMPA', 'top.rootu.bylumpa'),
        'lampa_atv' => array('LAMPA ATV', 'top.rootu.lumpa'),
        'prisma' => array('Prisma', 'top.rootu.prisma'),
        'vokino' => array('VoKino', 'ru.vokino.web'),
        'lazymedia' => array('LazyMedia', 'com.lazycatsoftware.lmd'),
        'filmix_api' => array('Filmix', null, 'Filmix_api'),
        'stremio' => array('Stremio', 'com.stremio.one'),
        'nuvio' => array('Nuvio', 'com.nuvio.tv'),
        'freezona' => array('FreeZona', 'free.zona'),
        'alpac' => array('ALPAC', 'cc.alcopa.tv'),
        'flux' => array('Flux', 'app.flux.tv'),
        'seasonhit' => array('SeasonHit', 'com.jimdo.xakerd.season2hit'),
        'bazinga' => array('Bazinga', null, 'Bazinga3'));

    // Per call: the Dune's language. Per php_server: translations by
    // language, the rows of the last check.
    public static $lang = null;
    public static $tr = array();
    public static $check_rows = null;
}

function pia_log($msg)
{
    hd_print("play_in_apps: $msg");
}

function pia_prop($key)
{
    return isset(DuneSystem::$properties[$key]) ?
        strval(DuneSystem::$properties[$key]) : '';
}

function pia_plugins_dir()
{
    return dirname(dirname(__FILE__));
}

function pia_error_action($key)
{
    pia_log("error: $key");
    return array(
        'handler_string_id' => PLUGIN_SHOW_ERROR_ACTION_ID,
        'data' => array('fatal' => false, 'title' => "%tr%$key"));
}

// --- play_action of the supplier: the shell passes the whole movie in
// user_input.movie_str.

// movie_str as an array; empty if there is none or it is not a JSON object.
// Arrays, not objects: before PHP 7.1 a key starting with "\0" is a fatal
// error in json_decode to objects.
function pia_movie($user_input)
{
    $movie = isset($user_input->movie_str) && is_string($user_input->movie_str) ?
        json_decode($user_input->movie_str, true) : null;
    return is_array($movie) ? $movie : array();
}

// A trimmed scalar field of the movie; '' if there is none or it is not valid
// UTF-8: json_decode turns a lone \ud800 into invalid UTF-8; json_encode then
// fails: false on PHP 5.5+, null in place of the string on PHP 5.3.
function pia_movie_field($movie, $k)
{
    if (!isset($movie[$k]) || !is_scalar($movie[$k]))
        return '';
    $s = trim(strval($movie[$k]));
    $json = json_encode($s);
    return $json === false || json_last_error() !== JSON_ERROR_NONE ? '' : $s;
}

// --- Filmix: play_action of the supplier. The shell calls it when "Filmix" is
// chosen in the "Play..." menu and passes the whole movie in
// user_input.movie_str. Replies with a GUI action that opens Filmix_API's
// search results for the title.

// Filmix_API's own media_url after its search dialog:
// SmartVodListScreen::get_media_url_str('search', <text>).
function filmix_search_action($title, $media_url)
{
    // Filmix_API loads its account token only in its main menu handler, on
    // any control_id but login ones; an unknown one then returns null. Without
    // this step a fresh Filmix_API process searches without the token.
    $load_token = array(
        'handler_string_id' => PLUGIN_HANDLE_USER_INPUT_ACTION_ID,
        'plugin_name' => 'Filmix_api',
        'params' => array('handler_id' => 'main_menu', 'control_id' => 'fx_token'));
    $open = array(
        'handler_string_id' => PLUGIN_OPEN_FOLDER_ACTION_ID,
        'plugin_name' => 'Filmix_api',
        'data' => array('media_url' => $media_url, 'caption' => $title));
    return array(
        'handler_string_id' => COMPOSITE_ACTION_ID,
        'data' => array('actions' => array($load_token, $open)));
}

function filmix_play($user_input)
{
    if (!is_file(pia_plugins_dir() . '/Filmix_api/dune_plugin.xml'))
        return pia_error_action('filmix_api_err_not_installed');

    $movie = pia_movie($user_input);
    // "title" is in the Dune UI language, "native_title" is the original one.
    foreach (array('title', 'native_title') as $k)
    {
        $title = pia_movie_field($movie, $k);
        if ($title === '')
            continue;
        $media_url = json_encode(array(
            'screen_id' => 'vod_list', 'category_id' => 'search', 'genre_id' => $title));
        pia_log("filmix search: $title");
        return filmix_search_action($title, $media_url);
    }
    return pia_error_action('filmix_api_err_no_title');
}

// --- Bazinga: play_action of the supplier, as Filmix's. Opens the Bazinga3
// Dune plugin: its Kinopoisk card by kp_id, else its Kinopoisk search by
// title. Bazinga3 json_decodes media_url, so key order does not matter.

function bazinga_open($media_url, $caption)
{
    return array(
        'handler_string_id' => PLUGIN_OPEN_FOLDER_ACTION_ID,
        'plugin_name' => 'Bazinga3',
        'data' => array('media_url' => json_encode($media_url), 'caption' => $caption));
}

function bazinga_play($user_input)
{
    if (!is_file(pia_plugins_dir() . '/Bazinga3/dune_plugin.xml'))
        return pia_error_action('bazinga_err_not_installed');

    $movie = pia_movie($user_input);
    $title = pia_movie_field($movie, 'title');
    $native = pia_movie_field($movie, 'native_title');
    $kp = isset($movie['kp_id']) && (is_string($movie['kp_id']) || is_int($movie['kp_id'])) ?
        trim(strval($movie['kp_id'])) : '';

    if (preg_match('/^[1-9][0-9]{0,9}$/D', $kp))
    {
        // The card shows these titles when kinopoiskapiunofficial does not answer.
        $caption = $title !== '' ? $title : ($native !== '' ? $native : $kp);
        $url = array('movie_id' => $kp, 'screen_id' => 'vod_movie',
            'class_name' => 'Kinopoisk_Class', 'caption' => $caption);
        if ($native !== '')
            $url['caption_original'] = $native;
        $year = pia_movie_field($movie, 'year');
        if ($year !== '')
            $url['year'] = $year;
        pia_log("bazinga card: $kp");
        return bazinga_open($url, $caption);
    }

    $caption = $title !== '' ? $title : $native;
    if ($caption === '')
        return pia_error_action('bazinga_err_no_title');
    pia_log("bazinga search: $caption");
    return bazinga_open(array('searchStr' => $caption, 'screen_id' => 'vod_list',
        'class_name' => 'Kinopoisk_Class'), $caption);
}

// --- IPTV Channel Editor builds: Dune plugins made by its builder that have
// VOD. bin/sync.sh shows an item iptvce_<name> for each, with play_action
// handler_id iptvce_<name>; the handler opens the build's search results for
// the title. The same checks as bin/iptvce_builds.sh; everything read from a
// build is untrusted.

// 1-40 of [A-Za-z0-9_.-], not starting with . or -, no "..". The same
// pattern as in bin/iptvce_builds.sh and cgi/logs.php.
function iptvce_valid_name($name)
{
    return is_string($name) && preg_match('/^[A-Za-z0-9_][A-Za-z0-9_.-]{0,39}$/D', $name) === 1 &&
        strpos($name, '..') === false;
}

// The <name> of an item id iptvce_<name>, not checked; '' if $id is not one.
function iptvce_name_of($id)
{
    return is_string($id) && strpos($id, 'iptvce_') === 0 ? (string) substr($id, 7) : '';
}

// The builder's files and VOD on ("vod_engine" in config.json, other than
// "None" in any case).
function iptvce_is_build($name)
{
    if (!iptvce_valid_name($name))
        return false;
    $d = pia_plugins_dir() . "/$name";
    if (!is_file("$d/starnet_plugin.php") || !is_file("$d/screens_vod/starnet_vod_list_screen.php") ||
        !is_file("$d/config.json"))
        return false;
    $text = file_get_contents("$d/config.json");
    return is_string($text) && preg_match('/"vod_engine": *"([^"\n]*)"/', $text, $m) === 1 &&
        strcasecmp($m[1], 'None') !== 0;
}

// array(caption, icon file or '') of a build, from its dune_plugin.xml: the
// first <caption> (entities decoded, then < and > dropped, spaces trimmed, at
// most 40 characters; the name if there is none or it has control
// characters, bad UTF-8 or a leading %) and the first <icon_url> if it is
// plugin_file://<safe path> of an existing file. One line each, as grep reads
// them in iptvce_builds.sh.
function iptvce_info($name)
{
    $f = pia_plugins_dir() . "/$name/dune_plugin.xml";
    $xml = is_file($f) ? file_get_contents($f) : false;
    if (!is_string($xml))
        $xml = '';
    $caption = $name;
    if (preg_match('/<caption>([^<\n]*)<\/caption>/', $xml, $m))
    {
        $c = strtr($m[1], array('&lt;' => '<', '&gt;' => '>', '&quot;' => '"', '&apos;' => "'",
            '&amp;' => '&'));
        $c = trim(str_replace(array('<', '>'), '', $c), ' ');
        if ($c !== '' && $c[0] !== '%' && !preg_match('/[\x00-\x1f\x7f]/', $c) && pia_utf8_clean($c) === $c)
            $caption = mb_substr($c, 0, 40, 'UTF-8');
    }
    $icon = '';
    if (preg_match('/<icon_url>([^<\n]*)<\/icon_url>/', $xml, $m) &&
        preg_match('#^plugin_file://([A-Za-z0-9/._-]+)$#D', $m[1], $p) &&
        $p[1][0] !== '/' && strpos($p[1], '..') === false &&
        is_file(pia_plugins_dir() . "/$name/{$p[1]}"))
        $icon = pia_plugins_dir() . "/$name/{$p[1]}";
    return array($caption, $icon);
}

// name => iptvce_info() of every build, in name order.
function iptvce_builds()
{
    $builds = array();
    foreach ((array) glob(pia_plugins_dir() . '/*', GLOB_ONLYDIR) as $d)
    {
        $name = is_string($d) ? basename($d) : '';
        if (iptvce_is_build($name))
            $builds[$name] = iptvce_info($name);
    }
    ksort($builds, SORT_STRING);
    return $builds;
}

function iptvce_play($user_input, $name)
{
    if (!iptvce_is_build($name))
    {
        // An invalid name never shown as is: our items only have valid ones.
        if (iptvce_valid_name($name))
            $info = iptvce_info($name);
        else
            $info = array(preg_replace('/[^A-Za-z0-9_]/', '?', substr($name, 0, 40)));
        return pia_message(sprintf(pia_tr('iptvce_err_not_installed'), $info[0]));
    }
    $info = iptvce_info($name);

    $movie = pia_movie($user_input);
    $q = pia_movie_field($movie, 'title');
    if ($q === '')
        $q = pia_movie_field($movie, 'native_title');
    if ($q === '')
        return pia_message(sprintf(pia_tr('iptvce_err_no_title'), $info[0]));

    // The builder's own media_url after its search dialog:
    // Starnet_Vod_List_Screen::get_media_url_string(Vod_Category::FLAG_SEARCH, $q).
    pia_log("iptvce $name search: $q");
    return array(
        'handler_string_id' => PLUGIN_OPEN_FOLDER_ACTION_ID,
        'plugin_name' => $name,
        'data' => array(
            'media_url' => json_encode(array('screen_id' => 'vod_list',
                'category_id' => '##search##', 'genre_id' => $q)),
            'caption' => "{$info[0]}: $q"));
}

// --- Translations.

// The Dune's interface language, as the vendor's ConfigUtils::load_config()
// reads it. PHP adds FS_PREFIX to /config itself; an empty one is the root.
function pia_lang()
{
    if (is_null(PlayInApps::$lang))
    {
        $lang = 'english';
        $other = 'english';
        $path = getenv('FS_PREFIX') . '/config/settings.properties';
        $text = is_file($path) ? file_get_contents($path) : false;
        if (is_string($text))
        {
            if (preg_match('/^interface_language[ \t]*=[ \t]*(\w+)/m', $text, $m))
                $lang = $m[1];
            if (preg_match('/^noncustom_interface_language[ \t]*=[ \t]*(\w+)/m', $text, $m))
                $other = $m[1];
        }
        if ($lang === 'custom')
            $lang = $other;
        // The plugin has these two translation files only.
        PlayInApps::$lang = $lang === 'russian' ? 'russian' : 'english';
    }
    return PlayInApps::$lang;
}

// Text of a key of translations/ in the Dune's language. Used where the shell
// is not known to expand %tr%: the item choice dialog, dialogs, the check
// screen. The controls screen keeps %tr%.
function pia_tr($key)
{
    $lang = pia_lang();
    if (!isset(PlayInApps::$tr[$lang]))
    {
        $tr = array();
        $f = dirname(__FILE__) . "/translations/dune_language_$lang.txt";
        $text = is_file($f) ? file_get_contents($f) : false;
        if (is_string($text) && preg_match_all('/^([a-z0-9_]+) = (.*)$/m', $text, $m))
            $tr = array_combine($m[1], $m[2]);
        PlayInApps::$tr[$lang] = $tr;
    }
    return isset(PlayInApps::$tr[$lang][$key]) ? PlayInApps::$tr[$lang][$key] : $key;
}

// --- Shared helpers.

function pia_input($control_id, $handler = 'setup')
{
    return array(
        GuiAction::handler_string_id => PLUGIN_HANDLE_USER_INPUT_ACTION_ID,
        GuiAction::data => null,
        GuiAction::params => array('handler_id' => $handler, 'control_id' => $control_id));
}

// A non-fatal message with an already translated text.
function pia_message($text)
{
    pia_log("message: $text");
    return array(
        GuiAction::handler_string_id => PLUGIN_SHOW_ERROR_ACTION_ID,
        GuiAction::data => array(
            PluginShowErrorActionData::fatal => false,
            PluginShowErrorActionData::title => $text));
}

function pia_close_dialog_and($post_action)
{
    return array(
        GuiAction::handler_string_id => CLOSE_DIALOG_AND_RUN_ACTION_ID,
        GuiAction::data => array(CloseDialogAndRunActionData::post_action => $post_action));
}

// <FS_PREFIX>/tmp: tmp_dir_path is <FS_PREFIX>/tmp/plugins/<name>.
function pia_tmp_root()
{
    $tmp = pia_prop('tmp_dir_path');
    return $tmp === '' ? '/tmp' : dirname(dirname($tmp));
}

// The shell's list of Android apps, false if there is none.
function pia_app_list()
{
    $path = pia_tmp_root() . '/applications/app_data.json';
    return is_file($path) ? file_get_contents($path) : false;
}

// Valid UTF-8 kept, every other byte -> "?": json_encode() gives null for a
// string with bad UTF-8, and a null caption breaks the screen.
function pia_utf8_clean($s)
{
    return preg_replace_callback('/((?:[\x00-\x7f]|[\xc2-\xdf][\x80-\xbf]|\xe0[\xa0-\xbf][\x80-\xbf]|' .
        '[\xe1-\xec\xee\xef][\x80-\xbf]{2}|\xed[\x80-\x9f][\x80-\xbf]|\xf0[\x90-\xbf][\x80-\xbf]{2}|' .
        '[\xf1-\xf3][\x80-\xbf]{3}|\xf4[\x80-\x8f][\x80-\xbf]{2})+)|[\x80-\xff]/',
        'pia_utf8_keep', (string) $s);
}

function pia_utf8_keep($m)
{
    return isset($m[1]) && $m[1] !== '' ? $m[1] : '?';
}

// --- The hidden items.

// Ids of the fixed items and of the builds' ones (iptvce_<name>, also of a
// build not installed now: hidden stays hidden if it comes back).
function pia_item_id($id)
{
    return isset(PlayInApps::$apps[$id]) ||
        iptvce_valid_name(iptvce_name_of($id));
}

// The ids of $hidden that are item ids: the fixed items in their order, then
// the builds' ones in name order.
function pia_hidden_ids($hidden)
{
    $ids = array();
    foreach (PlayInApps::$apps as $id => $app)
    {
        if (isset($hidden[$id]))
            $ids[] = $id;
    }
    $builds = array();
    foreach ($hidden as $id => $on)
    {
        $id = (string) $id;
        if (!isset(PlayInApps::$apps[$id]) && pia_item_id($id))
            $builds[] = $id;
    }
    sort($builds, SORT_STRING);
    return array_merge($ids, $builds);
}

// Hidden ids, one per line in data_dir/hidden; bin/sync.sh reads the same
// file. Any other line is ignored.
function pia_read_hidden()
{
    $hidden = array();
    $path = pia_prop('data_dir_path') . '/hidden';
    $text = is_file($path) ? file_get_contents($path) : false;
    if (!is_string($text))
        return $hidden;
    foreach (explode("\n", $text) as $line)
    {
        if (pia_item_id($line))
            $hidden[$line] = true;
    }
    return $hidden;
}

function pia_write_hidden($hidden)
{
    $dir = pia_prop('data_dir_path');
    if ($dir === '' || (!is_dir($dir) && !mkdir($dir, 0755, true)))
        return false;
    $text = '';
    foreach (pia_hidden_ids($hidden) as $id)
        $text .= "$id\n";
    // tmp + rename: never a half-written file.
    $path = "$dir/hidden";
    return file_put_contents("$path.tmp", $text) !== false && rename("$path.tmp", $path);
}

// Shows and hides the menu items to match the apps and the hidden list.
function pia_sync()
{
    $out = array();
    $rc = -1;
    exec('sh ' . escapeshellarg(dirname(__FILE__) . '/bin/sync.sh') . ' 2>&1', $out, $rc);
    if ($rc !== 0)
        pia_log("sync.sh failed ($rc): " . implode(' | ', $out));
}

function pia_installed($app, $app_list)
{
    $pkg = $app[1];
    if (is_null($pkg))
        return is_file(pia_plugins_dir() . "/{$app[2]}/dune_plugin.xml");
    // Same check as bin/sync.sh and the item scripts.
    return is_string($app_list) &&
        preg_match('/"package_name": *"' . preg_quote($pkg, '/') . '"/', $app_list) === 1;
}

// --- The screen "setup": a short controls screen, as the Dune's own settings.

function pia_label($caption)
{
    return array(
        GuiControlDef::name => '',
        GuiControlDef::title => null,
        GuiControlDef::kind => GUI_CONTROL_LABEL,
        GuiControlDef::specific_def => array(GuiLabelDef::caption => $caption));
}

function pia_button($name, $title, $caption)
{
    return array(
        GuiControlDef::name => $name,
        GuiControlDef::title => $title,
        GuiControlDef::kind => GUI_CONTROL_BUTTON,
        GuiControlDef::specific_def => array(
            GuiButtonDef::caption => $caption,
            GuiButtonDef::width => 400,
            GuiButtonDef::push_action => pia_input($name)));
}

function pia_control_defs()
{
    $defs = array(pia_label('%tr%screen_hint'));

    // A separate "Open in <app>" plugin registers the same id and the shell
    // copies its file back on every boot, so hiding would not stick. Two
    // lines: the "Open in …" caption, then the app names, so the real
    // Filmix_API plugin is not taken for one to remove.
    $old = array();
    foreach (PlayInApps::$apps as $id => $app)
    {
        if (is_file(pia_plugins_dir() . "/{$id}_supplier/dune_plugin.xml"))
            $old[] = $app[0];
    }
    if ($old)
    {
        $defs[] = pia_label('%tr%old_plugins');
        $defs[] = pia_label(implode(', ', $old));
    }

    $defs[] = pia_button('items', '%tr%items_title', '%tr%items_button');
    $defs[] = pia_button('check', '%tr%check_title', '%tr%check_button');
    $defs[] = pia_button('logs', '%tr%logs_title', '%tr%logs_button');
    return $defs;
}

function pia_setup_view()
{
    pia_sync();
    return array(
        PluginFolderView::view_kind => PLUGIN_FOLDER_VIEW_CONTROLS,
        PluginFolderView::multiple_views_supported => false,
        PluginFolderView::data => array(
            PluginControlsFolderView::defs => pia_control_defs(),
            PluginControlsFolderView::initial_sel_ndx => -1));
}

// --- The item choice: the shell's dialog with checkmarks (edit_list_config),
// as in Settings -> Applications -> Movies. Its own state is the file
// <FS_PREFIX>/config/lcfg_<config_id>.txt: "+id"/"-id" against checked_ids,
// then "---" and an order (shell_ext/lib/list_utils.php). Our hidden file
// stays the source of truth: the shell's file is written from it before the
// dialog opens and read back when it closes.

function pia_lcfg_path()
{
    return getenv('FS_PREFIX') . '/config/lcfg_play_in_apps.txt';
}

// One "-id" line per hidden item. A fresh file next to it, then rename: a
// symlink at the path is replaced, never followed.
function pia_write_lcfg($hidden)
{
    $path = pia_lcfg_path();
    $dir = dirname($path);
    if (!is_dir($dir))
        return false;
    $text = '';
    foreach (pia_hidden_ids($hidden) as $id)
        $text .= "-$id\n";
    $tmp = "$dir/.lcfg_play_in_apps." . substr(md5(uniqid('', true)), 0, 8) . '.tmp';
    $fp = @fopen($tmp, 'x');
    if (!$fp)
        return false;
    $ok = fwrite($fp, $text) === strlen($text);
    $ok = fclose($fp) && $ok && chmod($tmp, 0644) && rename($tmp, $path);
    if (!$ok && is_file($tmp))
        unlink($tmp);
    return $ok;
}

// package => "icon" of the app in the shell's app list: the path its
// Applications menu shows (on Android TV the cache is in flashdata).
function pia_app_icons($app_list)
{
    $icons = array();
    $d = is_string($app_list) ? json_decode($app_list, true) : null;
    if (!is_array($d) || !isset($d['applications']) || !is_array($d['applications']))
        return $icons;
    foreach ($d['applications'] as $a)
    {
        if (is_array($a) && isset($a['package_name'], $a['icon']) &&
            is_string($a['package_name']) && is_string($a['icon']))
            $icons[$a['package_name']] = $a['icon'];
    }
    return $icons;
}

// The item's icon in the dialog: the app's from the app list, else the
// shell's icon cache under tmp; a Dune plugin's item: the plugin's logo.
function pia_icon($app, $icons)
{
    $pkg = $app[1];
    if (is_null($pkg))
        $paths = array(pia_plugins_dir() . "/{$app[2]}/icons/logo.png");
    else
        $paths = array(isset($icons[$pkg]) ? $icons[$pkg] : '',
            pia_tmp_root() . "/applications/icon_cache/icon_$pkg.png");
    foreach ($paths as $p)
    {
        if (substr($p, 0, 1) === '/' && strpos($p, "\0") === false && is_file($p))
            return $p;
    }
    return 'gui_skin://small_icons/apps.aai';
}

function pia_items_dialog()
{
    // r22 and r24 have it; older firmware has no such dialog.
    if (!class_exists('EditListConfigActionData') || !defined('EDIT_LIST_CONFIG_ACTION_ID') ||
        !defined('EDIT_LIST_CONFIG_OPT_ALLOW_EMPTY'))
        return pia_message(pia_tr('err_no_list_dialog'));

    $app_list = pia_app_list();
    $icons = pia_app_icons($app_list);
    $items = array();
    foreach (PlayInApps::$apps as $id => $app)
    {
        $items[] = array(
            GuiItem::id => $id,
            GuiItem::caption => pia_installed($app, $app_list) ?
                $app[0] : $app[0] . ' (' . pia_tr('not_installed') . ')',
            GuiItem::icon_url => pia_icon($app, $icons),
            GuiItem::group_id => 'apps');
    }
    // The builds found now, after the fixed items, with their own icons.
    $checked = array_keys(PlayInApps::$apps);
    foreach (iptvce_builds() as $name => $b)
    {
        $items[] = array(
            GuiItem::id => "iptvce_$name",
            GuiItem::caption => $b[0],
            GuiItem::icon_url => $b[1] !== '' ? $b[1] : 'gui_skin://small_icons/apps.aai',
            GuiItem::group_id => 'apps');
        $checked[] = "iptvce_$name";
    }
    if (!pia_write_lcfg(pia_read_hidden()))
        pia_log('could not write ' . pia_lcfg_path());

    // No close_item_params, dialog_params or item params: r22 has none.
    // checked_ids are the defaults ("Reset to defaults" in POP UP): all shown.
    return array(
        GuiAction::handler_string_id => EDIT_LIST_CONFIG_ACTION_ID,
        GuiAction::data => array(
            EditListConfigActionData::config_id => 'play_in_apps',
            EditListConfigActionData::title => pia_tr('items_dialog_title'),
            EditListConfigActionData::all_items => $items,
            EditListConfigActionData::checked_ids => $checked,
            EditListConfigActionData::groups => array(array(
                GuiItem::id => 'apps', GuiItem::caption => pia_tr('items_group'))),
            EditListConfigActionData::options => EDIT_LIST_CONFIG_OPT_ALLOW_EMPTY,
            EditListConfigActionData::post_action => pia_input('list_apply')));
}

// post_action of the dialog, on every close. The shell has written its file
// by now; "+id"/"-id" before "---" give the state, the last line of an id
// wins, the order after "---" is not ours to use.
function pia_list_apply($in)
{
    $changed = isset($in->list_config_changed) && is_scalar($in->list_config_changed) ?
        strval($in->list_config_changed) : '';
    if ($changed !== '1' || !isset($in->list_config_id) || $in->list_config_id !== 'play_in_apps')
        return null;

    $path = pia_lcfg_path();
    clearstatcache();
    if (is_link($path) || !is_file($path) || filesize($path) > 65536)
    {
        pia_log('list_apply: no choice file, nothing changed');
        return null;
    }
    $text = file_get_contents($path);
    // The dialog's items: the fixed ones and the builds found now. A hidden
    // build that is not installed now stays hidden.
    $known = PlayInApps::$apps;
    foreach (iptvce_builds() as $name => $b)
        $known["iptvce_$name"] = true;
    $hidden = array();
    foreach (pia_read_hidden() as $id => $on)
    {
        if (!isset($known[$id]))
            $hidden[$id] = true;
    }
    $state = array();
    foreach (explode("\n", is_string($text) ? $text : '') as $line)
    {
        $line = trim($line);
        if ($line === '')
            continue;
        if (strpos($line, '---') === 0)
            break;
        $id = (string) substr($line, 1);
        if (($line[0] === '+' || $line[0] === '-') && isset($known[$id]))
            $state[$id] = $line[0];
    }
    foreach ($state as $id => $sign)
    {
        if ($sign === '-')
            $hidden[$id] = true;
    }
    if (!pia_write_hidden($hidden))
        return pia_error_action('err_save');
    pia_log('hidden: ' . ($hidden ? implode(' ', array_keys($hidden)) : '-'));
    pia_sync();
    return null;
}

// --- The screen "check": the brief report of bin/diag.sh (the device, then a
// line per item), one row per line; the full one is in the logs file.

function pia_screen_text($line)
{
    $s = preg_replace('/[\x00-\x1f\x7f]/', ' ', pia_utf8_clean($line));
    // The focused row scrolls, so long lines stay; this only bounds them.
    return mb_strlen($s, 'UTF-8') > 300 ? mb_substr($s, 0, 299, 'UTF-8') . '…' : $s;
}

function pia_check_rows()
{
    $out = array();
    $rc = -1;
    exec('sh ' . escapeshellarg(dirname(__FILE__) . '/bin/diag.sh') . ' ' . pia_lang() . ' brief 2>&1', $out, $rc);
    if (!$out)
        $out = array(pia_tr('check_failed') . " ($rc)");
    $rows = array();
    foreach ($out as $i => $line)
    {
        $rows[] = array(
            PluginRegularFolderItem::media_url => "line:$i",
            PluginRegularFolderItem::caption => pia_screen_text($line),
            PluginRegularFolderItem::view_item_params => array());
    }
    PlayInApps::$check_rows = $rows;
    return $rows;
}

function pia_range($rows)
{
    return array(
        PluginRegularFolderRange::total => count($rows),
        PluginRegularFolderRange::more_items_available => false,
        PluginRegularFolderRange::from_ndx => 0,
        PluginRegularFolderRange::count => count($rows),
        PluginRegularFolderRange::items => $rows);
}

// As Melange's list of lines (lines of ~100 characters fit; the focused one
// scrolls). ENTER on a line does nothing.
function pia_check_view()
{
    return array(
        PluginFolderView::multiple_views_supported => false,
        PluginFolderView::view_kind => PLUGIN_FOLDER_VIEW_REGULAR,
        PluginFolderView::data => array(
            PluginRegularFolderView::view_params => array(
                ViewParams::num_cols => 1,
                // The device line and a line per item: the whole report on one screen.
                ViewParams::num_rows => count(PlayInApps::$apps) + 1,
                ViewParams::paint_details => false,
                ViewParams::paint_scrollbar => true,
                ViewParams::scroll_animation_enabled => true),
            PluginRegularFolderView::base_view_item_params => array(
                ViewItemParams::item_padding_top => 0,
                ViewItemParams::item_padding_bottom => 0,
                ViewItemParams::item_layout => HALIGN_LEFT,
                ViewItemParams::item_caption_width => 1650,
                ViewItemParams::item_caption_font_size => FONT_SIZE_SMALL),
            PluginRegularFolderView::not_loaded_view_item_params => array(),
            PluginRegularFolderView::async_icon_loading => false,
            PluginRegularFolderView::actions => array(
                GUI_EVENT_KEY_ENTER => pia_input('line', 'check')),
            PluginRegularFolderView::initial_range => pia_range(pia_check_rows())));
}

function pia_open_check()
{
    return array(
        GuiAction::handler_string_id => PLUGIN_OPEN_FOLDER_ACTION_ID,
        GuiAction::data => array(
            PluginOpenFolderActionData::media_url => 'check',
            PluginOpenFolderActionData::caption => pia_tr('check_caption')));
}

// --- Logs for the author: a QR of the CGI page (cgi/logs.php) that gives
// them as one file. The page needs the token of tmp_dir/logs_token: 32 hex,
// 5 minutes by its mtime, removed when the dialog closes.

define('PIA_TOKEN_TTL', 300);   // the same in cgi/logs.php

function pia_new_token()
{
    $b = is_readable('/dev/urandom') ? (string) file_get_contents('/dev/urandom', false, null, 0, 16) : '';
    if (strlen($b) !== 16 && function_exists('openssl_random_pseudo_bytes'))
        $b = (string) openssl_random_pseudo_bytes(16);
    return strlen($b) === 16 ? bin2hex($b) : '';
}

// Atomic 0600 write: a fresh file next to it, then rename (a symlink at the
// path is replaced, never followed).
function pia_write_0600($path, $data)
{
    $tmp = $path . '.' . substr(md5(uniqid('', true)), 0, 8) . '.tmp';
    $fp = @fopen($tmp, 'x');
    if (!$fp)
        return false;
    $ok = chmod($tmp, 0600) && fwrite($fp, $data) === strlen($data);
    $ok = fclose($fp) && $ok && rename($tmp, $path);
    if (!$ok && is_file($tmp))
        unlink($tmp);
    return $ok;
}

// The Dune's LAN address from ifconfig: eth0, else wlan0, else the first
// other interface but loopback and VPNs (tun*, ppp*, wg*); without ifconfig
// the source address of a UDP socket (connect sends nothing).
function pia_ip()
{
    $o = array();
    exec('ifconfig 2>/dev/null', $o);
    $ips = array();
    $if = '';
    foreach ($o as $line)
    {
        // A block starts with the interface name at the line start.
        if (preg_match('/^([^\s:]+)/', $line, $m))
            $if = $m[1];
        if ($if !== '' && !isset($ips[$if]) &&
            preg_match('/inet addr: ?([0-9]{1,3}(?:\.[0-9]{1,3}){3})/', $line, $m) && strpos($m[1], '127.') !== 0)
            $ips[$if] = $m[1];
    }
    foreach (array('eth0', 'wlan0') as $if)
    {
        if (isset($ips[$if]))
            return $ips[$if];
    }
    foreach ($ips as $if => $ip)
    {
        if (!preg_match('/^(tun|ppp|wg)/', $if))
            return $ip;
    }
    if (!function_exists('socket_create'))
        return '';
    hd_silence_warnings();
    $s = socket_create(AF_INET, SOCK_DGRAM, 0);
    $ip = '';
    if (is_resource($s))
    {
        if (!socket_connect($s, '8.8.8.8', 53) || !socket_getsockname($s, $ip))
            $ip = '';
        socket_close($s);
    }
    hd_restore_warnings();
    return preg_match('/^[0-9]{1,3}(\.[0-9]{1,3}){3}$/', (string) $ip) && $ip !== '0.0.0.0' ? $ip : '';
}

function pia_drop_token()
{
    $dir = pia_prop('tmp_dir_path');
    if ($dir === '')
        return;
    clearstatcache();
    if (is_file("$dir/logs_token") || is_link("$dir/logs_token"))
        unlink("$dir/logs_token");
    foreach ((array) glob("$dir/qr_*.png") as $p)
    {
        if (is_string($p) && (is_file($p) || is_link($p)))
            unlink($p);
    }
}

function pia_logs_dialog()
{
    $dir = pia_prop('tmp_dir_path');
    if ($dir !== '' && !is_dir($dir))
        mkdir($dir, 0755, true);
    if ($dir === '' || !is_dir($dir) || !is_writable($dir))
        return pia_message(pia_tr('err_logs_link'));
    $ip = pia_ip();
    if ($ip === '')
        return pia_message(pia_tr('err_no_ip'));
    $token = pia_new_token();
    pia_drop_token();
    if ($token === '' || !pia_write_0600("$dir/logs_token", $token))
        return pia_message(pia_tr('err_logs_link'));

    // Not 80 on Android TV models (HD_HTTP_LOCAL_PORT, by the SDK).
    $port = getenv('HD_HTTP_LOCAL_PORT');
    $host = is_string($port) && $port !== '80' && ctype_digit($port) ? "$ip:$port" : $ip;
    $url = "http://$host/cgi-bin/plugins/play_in_apps/logs?t=$token";
    require_once dirname(__FILE__) . '/qrpng.php';
    $qr = PiaQrPng::make($url, 8, 4);
    // A fresh name each time: the shell caches pictures by path.
    $png = "$dir/qr_" . substr(md5($url), 0, 8) . '.png';
    if (!pia_write_0600($png, $qr['png']))
    {
        pia_drop_token();
        return pia_message(pia_tr('err_logs_link'));
    }
    // The token and the URL are never logged.
    pia_log('logs link made');

    $side = $qr['size'];
    $defs = array(
        array(
            GuiControlDef::name => '',
            GuiControlDef::title => null,
            GuiControlDef::kind => GUI_CONTROL_LABEL,
            GuiControlDef::specific_def => array(GuiLabelDef::caption =>
                '<icon width="' . $side . '" height="' . $side . '">' . $png . '</icon>'),
            GuiControlDef::params => array('smart' => 1)),
        array(
            GuiControlDef::name => '',
            GuiControlDef::title => null,
            GuiControlDef::kind => GUI_CONTROL_VGAP,
            GuiControlDef::specific_def => array(GuiVGapDef::vgap => $side)),
        // Only the QR: the shell cuts long labels in the middle; the page
        // itself warns about personal data.
        array(
            GuiControlDef::name => 'close',
            GuiControlDef::title => null,
            GuiControlDef::kind => GUI_CONTROL_BUTTON,
            GuiControlDef::specific_def => array(
                GuiButtonDef::caption => pia_tr('logs_close'),
                GuiButtonDef::width => 300,
                GuiButtonDef::push_action => pia_close_dialog_and(pia_input('logs_close')))));
    return array(
        GuiAction::handler_string_id => SHOW_DIALOG_ACTION_ID,
        GuiAction::data => array(
            ShowDialogActionData::title => pia_tr('logs_dialog_title'),
            ShowDialogActionData::defs => $defs,
            // RETURN comes to logs_return, which turns the link off.
            ShowDialogActionData::close_by_return => false,
            ShowDialogActionData::preferred_width => 1500,
            ShowDialogActionData::actions => array(
                GUI_EVENT_KEY_RETURN => pia_input('logs_return'),
                GUI_EVENT_TIMER => pia_input('logs_ttl')),
            ShowDialogActionData::timer => array(GuiTimerDef::delay_ms => PIA_TOKEN_TTL * 1000)));
}

// The dialog is closing: "Close" (already closed), RETURN or the timer.
function pia_logs_closed($control_id)
{
    pia_drop_token();
    pia_log("logs link off ($control_id)");
    return $control_id === 'logs_close' ? null : pia_close_dialog_and(null);
}

// --- Dispatch.

function pia_folder_view($media_url)
{
    return $media_url === 'check' ? pia_check_view() : pia_setup_view();
}

function pia_handle_user_input($user_input)
{
    $handler = isset($user_input->handler_id) ? $user_input->handler_id : null;
    if ($handler === 'filmix_api')
        return filmix_play($user_input);
    if ($handler === 'bazinga')
        return bazinga_play($user_input);
    if (iptvce_name_of($handler) !== '')
        return iptvce_play($user_input, iptvce_name_of($handler));

    $id = isset($user_input->control_id) ? $user_input->control_id : null;
    if ($handler !== 'setup' || !is_string($id))
        return null;
    switch ($id)
    {
        case 'items':
            return pia_items_dialog();
        case 'list_apply':
            return pia_list_apply($user_input);
        case 'check':
            return pia_open_check();
        case 'logs':
            return pia_logs_dialog();
        case 'logs_close':
        case 'logs_return':
        case 'logs_ttl':
            return pia_logs_closed($id);
    }
    return null;
}

class PlayInAppsFw extends DunePluginFw
{
    public function call_plugin($call_ctx_json)
    {
        // The language may change between calls.
        PlayInApps::$lang = null;
        $ctx = json_decode($call_ctx_json);
        $op = is_object($ctx) && isset($ctx->op_type_code) ? $ctx->op_type_code : null;
        $in = is_object($ctx) && isset($ctx->input_data) && is_object($ctx->input_data) ?
            $ctx->input_data : null;
        $media_url = $in && isset($in->media_url) && is_string($in->media_url) ? $in->media_url : '';
        $type = null;
        $data = null;
        if ($op === PLUGIN_OP_GET_FOLDER_VIEW)
        {
            $type = PLUGIN_OUT_DATA_PLUGIN_FOLDER_VIEW;
            $data = pia_folder_view($media_url);
        }
        else if ($op === PLUGIN_OP_GET_REGULAR_FOLDER_ITEMS && $media_url === 'check')
        {
            $type = PLUGIN_OUT_DATA_PLUGIN_REGULAR_FOLDER_RANGE;
            $data = pia_range(is_null(PlayInApps::$check_rows) ? pia_check_rows() : PlayInApps::$check_rows);
        }
        else if ($op === PLUGIN_OP_HANDLE_USER_INPUT && $in)
        {
            $type = PLUGIN_OUT_DATA_GUI_ACTION;
            $data = pia_handle_user_input($in);
        }

        $out = array(
            PluginOutputData::has_data => !is_null($data),
            PluginOutputData::plugin_cookies =>
                isset($ctx->plugin_cookies) ? $ctx->plugin_cookies : null,
            PluginOutputData::is_error => false,
            PluginOutputData::error_action => null);
        if (!is_null($data))
        {
            $out[PluginOutputData::data_type] = $type;
            $out[PluginOutputData::data] = $data;
        }
        return json_encode($out);
    }
}

DunePluginFw::$instance = new PlayInAppsFw();
