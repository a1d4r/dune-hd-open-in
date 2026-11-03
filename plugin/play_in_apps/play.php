<?php
// The play_action handlers of the supplier items, included by main.php
// (pia_handle_user_input calls them, they use its helpers): Filmix, Bazinga
// and the iptvce_ items. PHP 5.3.6.

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

// A season or episode number, an integer or a string of digits, as a string of
// digits; '' if it is below 1 or anything else. 9 digits fit a 32-bit intval.
function pia_number($v)
{
    $s = is_int($v) ? strval($v) : $v;
    // \z: $ also matches before a trailing newline.
    if (!is_string($s) || !preg_match('/^[0-9]{1,9}\z/', $s))
        return '';
    $n = intval($s);
    return $n >= 1 ? strval($n) : '';
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
    {
        // Removed: the item must not outlive this press, as iptvce_play's.
        pia_sync();
        return pia_error_action('filmix_api_err_not_installed');
    }

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
    {
        pia_sync();
        return pia_error_action('bazinga_err_not_installed');
    }

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

// --- iptvce_: the press on an item iptvce_<name>; which plugins get one:
// iptvce_builds in main.php.

function iptvce_play($user_input, $name)
{
    $builds = iptvce_valid_name($name) ? iptvce_builds($name) : array();
    if (!isset($builds[$name]))
    {
        // No item is due now (the plugin removed or changed: VOD off, its
        // vod_search gone) or iptvce_list.sh failed: the item must not
        // outlive this press.
        pia_sync();
        // An invalid name never shown as is: our items only have valid ones.
        $shown = iptvce_valid_name($name) ? $name : preg_replace('/[^A-Za-z0-9_]/', '?', substr($name, 0, 40));
        return pia_message(sprintf(pia_tr('iptvce_err_not_installed'), $shown));
    }
    list($caption, , $h, $c) = $builds[$name];

    $movie = pia_movie($user_input);
    if ($h !== '')
    {
        // The plugin's own search entry. params: strings only, the shell
        // fails on the whole reply if one is an array.
        $search = array();
        foreach (array('title' => 'title', 'original_title' => 'native_title', 'year' => 'year') as $k => $f)
        {
            $v = pia_movie_field($movie, $f);
            if ($v !== '')
                $search[$k] = $v;
        }
        if (!isset($search['title']) && !isset($search['original_title']))
            return pia_message(sprintf(pia_tr('iptvce_err_no_title'), $caption));
        $json = json_encode($search);
        pia_log("iptvce $name vod_search: $json");
        $params = array('handler_id' => $h, 'control_id' => $c, 'search' => $json,
            'movie_str' => $user_input->movie_str);
        // Chosen through "Seasons" in the card; the main card sends -1. Only as
        // a pair: season 0 is the shell's "about the series", its items have
        // numbers too, and such a number alone would read as an episode.
        $season = isset($user_input->season) ? pia_number($user_input->season) : '';
        $episode = isset($user_input->episode) ? pia_number($user_input->episode) : '';
        if ($season !== '' && $episode !== '')
        {
            $params['season'] = $season;
            $params['episode'] = $episode;
        }
        return array(
            'handler_string_id' => PLUGIN_HANDLE_USER_INPUT_ACTION_ID,
            'plugin_name' => $name,
            'params' => $params);
    }

    $q = pia_movie_field($movie, 'title');
    if ($q === '')
        $q = pia_movie_field($movie, 'native_title');
    if ($q === '')
        return pia_message(sprintf(pia_tr('iptvce_err_no_title'), $caption));

    // The builder's own media_url after its search dialog:
    // Starnet_Vod_List_Screen::get_media_url_string(Vod_Category::FLAG_SEARCH, $q).
    pia_log("iptvce $name search: $q");
    return array(
        'handler_string_id' => PLUGIN_OPEN_FOLDER_ACTION_ID,
        'plugin_name' => $name,
        'data' => array(
            'media_url' => json_encode(array('screen_id' => 'vod_list',
                'category_id' => '##search##', 'genre_id' => $q)),
            'caption' => "$caption: $q"));
}
