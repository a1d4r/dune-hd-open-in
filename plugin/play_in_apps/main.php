<?php
// The plugin screen, where each "Play..." item can be shown or hidden, and
// the play_action handler of the Filmix item. Only the firmware PHP API is
// used (/firmware_ext/php/), PHP 5.3.6.

class PlayInApps
{
    // id => array(caption, Android package; null: the Filmix_API Dune plugin).
    // Same ids and packages as bin/sync.sh.
    public static $apps = array(
        'num' => array('NUM', 'ru.yourok.num'),
        'lampa' => array('Lampa', 'top.rootu.lampa'),
        'prisma' => array('Prisma', 'top.rootu.prisma'),
        'vokino' => array('VoKino', 'ru.vokino.web'),
        'lazymedia' => array('LazyMedia', 'com.lazycatsoftware.lmd'),
        'filmix_api' => array('Filmix', null),
        'stremio' => array('Stremio', 'com.stremio.one'),
        'nuvio' => array('Nuvio', 'com.nuvio.tv'));
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

// --- Filmix: play_action of the supplier. The shell calls it when "Filmix" is
// chosen in the "Play..." menu and passes the whole movie in
// user_input.movie_str. Replies with a GUI action that opens Filmix_API's
// search results for the title.

// Filmix_API's own media_url after its search dialog:
// SmartVodListScreen::get_media_url_str('search', <text>).
function filmix_search_action($title, $media_url)
{
    return array(
        'handler_string_id' => PLUGIN_OPEN_FOLDER_ACTION_ID,
        'plugin_name' => 'Filmix_api',
        'data' => array('media_url' => $media_url, 'caption' => $title));
}

function filmix_play($user_input)
{
    if (!is_file(pia_plugins_dir() . '/Filmix_api/dune_plugin.xml'))
        return pia_error_action('filmix_api_err_not_installed');

    // Arrays, not objects: before PHP 7.1 a key starting with "\0" is a fatal
    // error in json_decode to objects.
    $movie = isset($user_input->movie_str) && is_string($user_input->movie_str) ?
        json_decode($user_input->movie_str, true) : null;
    // "title" is in the Dune UI language, "native_title" is the original one.
    foreach (array('title', 'native_title') as $k)
    {
        if (!is_array($movie) || !isset($movie[$k]) || !is_scalar($movie[$k]))
            continue;
        $title = trim(strval($movie[$k]));
        if ($title === '')
            continue;
        // json_decode turns a lone \ud800 into invalid UTF-8; json_encode then
        // fails: false on PHP 5.5+, null in place of the string on PHP 5.3.
        $media_url = json_encode(array(
            'screen_id' => 'vod_list', 'category_id' => 'search', 'genre_id' => $title));
        if ($media_url === false || json_last_error() !== JSON_ERROR_NONE)
            continue;

        pia_log("filmix search: $title");
        return filmix_search_action($title, $media_url);
    }
    return pia_error_action('filmix_api_err_no_title');
}

// --- The screen.

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
        if (isset(PlayInApps::$apps[$line]))
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
    foreach (PlayInApps::$apps as $id => $app)
    {
        if (isset($hidden[$id]))
            $text .= "$id\n";
    }
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

function pia_installed($pkg, $app_list)
{
    if (is_null($pkg))
        return is_file(pia_plugins_dir() . '/Filmix_api/dune_plugin.xml');
    // Same check as bin/sync.sh and the item scripts.
    return is_string($app_list) &&
        preg_match('/"package_name": *"' . preg_quote($pkg, '/') . '"/', $app_list) === 1;
}

function pia_control_defs()
{
    // tmp_dir_path is <FS_PREFIX>/tmp/plugins/<name>; the shell's app list
    // is in <FS_PREFIX>/tmp/applications.
    $tmp = pia_prop('tmp_dir_path');
    $path = ($tmp === '' ? '/tmp' : dirname(dirname($tmp))) . '/applications/app_data.json';
    $app_list = is_file($path) ? file_get_contents($path) : false;
    $hidden = pia_read_hidden();

    $defs = array(array(
        GuiControlDef::name => '',
        GuiControlDef::title => null,
        GuiControlDef::kind => GUI_CONTROL_LABEL,
        GuiControlDef::specific_def => array(GuiLabelDef::caption => '%tr%screen_hint')));

    // A separate "Open in <app>" plugin registers the same id and the shell
    // copies its file back on every boot, so hiding would not stick. One line
    // for all of them: the controls screen does not scroll on r24.
    $old = array();
    foreach (PlayInApps::$apps as $id => $app)
    {
        if (is_file(pia_plugins_dir() . "/{$id}_supplier/dune_plugin.xml"))
            $old[] = $app[0];
    }
    if ($old)
    {
        $defs[] = array(
            GuiControlDef::name => '',
            GuiControlDef::title => null,
            GuiControlDef::kind => GUI_CONTROL_LABEL,
            GuiControlDef::specific_def => array(GuiLabelDef::caption =>
                '%ext%<key_global>play_in_apps_plugin_old_plugins__1<p>' .
                implode(', ', $old) . '</p></key_global>'));
    }

    foreach (PlayInApps::$apps as $id => $app)
    {
        $defs[] = array(
            GuiControlDef::name => $id,
            GuiControlDef::title => $app[0],
            GuiControlDef::kind => GUI_CONTROL_COMBOBOX,
            GuiControlDef::specific_def => array(
                GuiComboboxDef::initial_value => isset($hidden[$id]) ? 'hide' : 'show',
                GuiComboboxDef::value_caption_pairs => array(
                    'show' => '%tr%choice_show', 'hide' => '%tr%choice_hide'),
                GuiComboboxDef::width => 400,
                GuiComboboxDef::apply_action => array(
                    GuiAction::handler_string_id => PLUGIN_HANDLE_USER_INPUT_ACTION_ID,
                    GuiAction::params => array('handler_id' => 'setup', 'control_id' => $id))),
            GuiControlDef::params => pia_installed($app[1], $app_list) ?
                null : array('text_right' => '%tr%not_installed'));
    }
    return $defs;
}

function pia_folder_view()
{
    pia_sync();
    return array(
        PluginFolderView::view_kind => PLUGIN_FOLDER_VIEW_CONTROLS,
        PluginFolderView::multiple_views_supported => false,
        PluginFolderView::data => array(
            PluginControlsFolderView::defs => pia_control_defs(),
            PluginControlsFolderView::initial_sel_ndx => -1));
}

// A combobox changed: the new value is in user_input-><control name>.
function pia_set_shown($user_input, $id)
{
    $value = isset($user_input->$id) ? $user_input->$id : null;
    if ($value !== 'show' && $value !== 'hide')
        return null;

    $hidden = pia_read_hidden();
    if ($value === 'hide')
        $hidden[$id] = true;
    else
        unset($hidden[$id]);
    if (!pia_write_hidden($hidden))
        return pia_error_action('err_save');
    pia_log("$id: $value");
    pia_sync();
    return null;
}

function pia_handle_user_input($user_input)
{
    $handler = isset($user_input->handler_id) ? $user_input->handler_id : null;
    if ($handler === 'filmix_api')
        return filmix_play($user_input);

    $id = isset($user_input->control_id) ? $user_input->control_id : null;
    if ($handler === 'setup' && is_string($id) && isset(PlayInApps::$apps[$id]))
        return pia_set_shown($user_input, $id);
    return null;
}

class PlayInAppsFw extends DunePluginFw
{
    public function call_plugin($call_ctx_json)
    {
        $ctx = json_decode($call_ctx_json);
        $type = null;
        $data = null;
        if (is_object($ctx) && isset($ctx->op_type_code))
        {
            if ($ctx->op_type_code === PLUGIN_OP_GET_FOLDER_VIEW)
            {
                $type = PLUGIN_OUT_DATA_PLUGIN_FOLDER_VIEW;
                $data = pia_folder_view();
            }
            else if ($ctx->op_type_code === PLUGIN_OP_HANDLE_USER_INPUT &&
                isset($ctx->input_data) && is_object($ctx->input_data))
            {
                $type = PLUGIN_OUT_DATA_GUI_ACTION;
                $data = pia_handle_user_input($ctx->input_data);
            }
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
