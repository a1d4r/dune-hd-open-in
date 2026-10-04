<?php
// Handler of the supplier's play_action: the shell calls it when "Filmix" is
// chosen in the "Play..." menu and passes the whole movie in user_input.movie_str.
// Replies with a GUI action that opens Filmix_API's search results for the
// title. Only the firmware PHP API is used (/firmware_ext/php/), PHP 5.3.6.

// Filmix_API's own media_url after its search dialog:
// SmartVodListScreen::get_media_url_str('search', <text>).
function filmix_search_action($title, $media_url)
{
    return array(
        'handler_string_id' => PLUGIN_OPEN_FOLDER_ACTION_ID,
        'plugin_name' => 'Filmix_api',
        'data' => array('media_url' => $media_url, 'caption' => $title));
}

function filmix_error_action($key)
{
    hd_print("filmix_api_supplier: error: $key");
    return array(
        'handler_string_id' => PLUGIN_SHOW_ERROR_ACTION_ID,
        'data' => array('fatal' => false, 'title' => "%tr%$key"));
}

function filmix_play($user_input, $plugins_dir)
{
    if (!is_file("$plugins_dir/Filmix_api/dune_plugin.xml"))
        return filmix_error_action('err_not_installed');

    $movie = isset($user_input->movie_str) && is_string($user_input->movie_str) ?
        json_decode($user_input->movie_str) : null;
    // "title" is in the Dune UI language, "native_title" is the original one.
    $title = '';
    foreach (array('title', 'native_title') as $k)
    {
        if ($title === '' && is_object($movie) && isset($movie->$k) &&
            is_scalar($movie->$k))
            $title = trim(strval($movie->$k));
    }
    // json_decode turns a lone \ud800 into invalid UTF-8; json_encode then
    // fails: false on PHP 5.5+, null in place of the string on PHP 5.3.
    $media_url = $title === '' ? false : json_encode(array(
        'screen_id' => 'vod_list', 'category_id' => 'search', 'genre_id' => $title));
    if ($media_url === false || json_last_error() !== JSON_ERROR_NONE)
        return filmix_error_action('err_no_title');

    hd_print("filmix_api_supplier: search: $title");
    return filmix_search_action($title, $media_url);
}

class FilmixSupplierFw extends DunePluginFw
{
    public function call_plugin($call_ctx_json)
    {
        $ctx = json_decode($call_ctx_json);
        $action = null;
        if (is_object($ctx) && isset($ctx->op_type_code, $ctx->input_data) &&
            $ctx->op_type_code === PLUGIN_OP_HANDLE_USER_INPUT &&
            is_object($ctx->input_data) &&
            isset($ctx->input_data->handler_id) &&
            $ctx->input_data->handler_id === 'filmix_api')
        {
            $action = filmix_play($ctx->input_data, dirname(dirname(__FILE__)));
        }

        $out = array(
            PluginOutputData::has_data => !is_null($action),
            PluginOutputData::plugin_cookies =>
                isset($ctx->plugin_cookies) ? $ctx->plugin_cookies : null,
            PluginOutputData::is_error => false,
            PluginOutputData::error_action => null);
        if (!is_null($action))
        {
            $out[PluginOutputData::data_type] = PLUGIN_OUT_DATA_GUI_ACTION;
            $out[PluginOutputData::data] = $action;
        }
        return json_encode($out);
    }
}

DunePluginFw::$instance = new FilmixSupplierFw();
