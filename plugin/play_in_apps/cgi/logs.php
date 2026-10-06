<?php
// The logs page (www/cgi-bin/logs -> php-cgi). It runs as root on the device
// and is open to the whole LAN without a password: without the token of
// <FS_PREFIX>/tmp/plugins/play_in_apps/logs_token (32 hex, 5 minutes by its
// mtime; main.php removes it when its dialog closes) every request gets the
// same 403, with no diagnostics.
//   GET ?t=<token>       -> a page: warning about personal data + "Download";
//   GET ?t=<token>&dl=1  -> one text/plain attachment, streamed, "END" last;
//   HEAD                 -> the same headers, no body.
// The token is only compared: input never reaches a command or a path.
// Nothing is written here. PHP 5.3 syntax.

define('LP_TTL', 300);          // PIA_TOKEN_TTL of main.php
define('LP_TAIL', 1048576);     // the last 1 MB of shell.log

date_default_timezone_set('UTC');

// The ids of the items, as in main.php.
$GLOBALS['lp_ids'] = array('num', 'lampa', 'bylampa', 'lampa_atv', 'prisma', 'vokino', 'lazymedia',
    'filmix_api', 'stremio', 'nuvio', 'freezona');

// The plugin's install dir: this file is <plugin>/cgi/logs.php.
function lp_plugin_dir()
{
    return dirname(dirname(__FILE__));
}

// <FS_PREFIX>/tmp; with an empty FS_PREFIX (older models) /tmp.
function lp_tmp()
{
    return getenv('FS_PREFIX') . '/tmp';
}

// The Dune's interface language, as in main.php.
function lp_lang()
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
    return $lang === 'russian' ? 'russian' : 'english';
}

function lp_tr($key)
{
    static $tr = null;
    if (is_null($tr))
    {
        $tr = array();
        $f = lp_plugin_dir() . '/translations/dune_language_' . lp_lang() . '.txt';
        $text = is_file($f) ? file_get_contents($f) : false;
        if (is_string($text) && preg_match_all('/^([a-z0-9_]+) = (.*)$/m', $text, $m))
            $tr = array_combine($m[1], $m[2]);
    }
    return isset($tr[$key]) ? $tr[$key] : $key;
}

function lp_h($s)
{
    return htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
}

function lp_param($key)
{
    // magic_quotes_gpc is off in cgi/php.ini.
    return isset($_GET[$key]) && is_string($_GET[$key]) ? $_GET[$key] : '';
}

function lp_headers($code, $type)
{
    $reasons = array(403 => 'Forbidden', 405 => 'Method Not Allowed');
    // php-cgi turns it into a first-line "Status:", the one busybox httpd reads.
    if (isset($reasons[$code]))
        header("HTTP/1.0 $code " . $reasons[$code]);
    header("Content-Type: $type; charset=utf-8");
    header('Cache-Control: no-store');
    // The token is in the URL.
    header('Referrer-Policy: no-referrer');
    header('X-Content-Type-Options: nosniff');
}

function lp_send($code, $type, $body)
{
    lp_headers($code, $type);
    if (getenv('REQUEST_METHOD') !== 'HEAD')
        echo $body;
    exit(0);
}

function lp_forbidden()
{
    lp_send(403, 'text/plain', "403 Forbidden\n");
}

// Compares in a time that does not depend on where they differ.
function lp_same($a, $b)
{
    if (strlen($a) !== strlen($b))
        return false;
    $d = 0;
    for ($i = 0; $i < strlen($a); $i++)
        $d |= ord($a[$i]) ^ ord($b[$i]);
    return $d === 0;
}

function lp_token_ok($given)
{
    if (!preg_match('/^[0-9a-f]{32}\z/', $given))
        return false;
    $f = lp_tmp() . '/plugins/play_in_apps/logs_token';
    clearstatcache();
    if (is_link($f) || !is_file($f))
        return false;
    $age = time() - filemtime($f);
    if ($age < -60 || $age > LP_TTL)
        return false;
    $t = trim((string) file_get_contents($f, false, null, 0, 64));
    return preg_match('/^[0-9a-f]{32}\z/', $t) && lp_same($t, $given);
}

// Echo and flush: the body goes out as it is made.
function lp_out($s)
{
    echo $s;
    flush();
}

function lp_section($title)
{
    lp_out("\n===== $title =====\n");
}

// A command through sh, its output streamed, then its exit code.
function lp_cmd($title, $cmd)
{
    lp_section($title);
    $p = popen("$cmd 2>&1 </dev/null; echo \"[rc=\$?]\"", 'r');
    if (!$p)
    {
        lp_out("popen failed\n");
        return;
    }
    while (!feof($p))
    {
        $s = fread($p, 65536);
        if ($s === false || $s === '')
            continue;
        lp_out($s);
    }
    pclose($p);
}

// A file (or its last $tail bytes) read by PHP, streamed.
function lp_file($path, $tail = 0)
{
    clearstatcache();
    if (!is_file($path))
    {
        lp_section("$path: no file");
        return;
    }
    $size = filesize($path);
    lp_section(sprintf('%s (%d bytes, mtime %s UTC)%s', $path, $size, gmdate('Y-m-d H:i:s', filemtime($path)),
        $tail > 0 && $size > $tail ? ", last $tail bytes" : ''));
    $fp = fopen($path, 'rb');
    if (!$fp)
    {
        lp_out("cannot open\n");
        return;
    }
    if ($tail > 0 && $size > $tail)
        fseek($fp, -$tail, SEEK_END);
    while (!feof($fp))
    {
        $s = fread($fp, 65536);
        if ($s === false || $s === '')
            break;
        lp_out($s);
    }
    fclose($fp);
    lp_out("\n");
}

function lp_model()
{
    $m = trim((string) shell_exec('getprop ro.product.model 2>/dev/null'));
    $m = preg_replace('/[^A-Za-z0-9._-]+/', '_', $m);
    return $m === '' ? 'dune' : substr($m, 0, 40);
}

function lp_download()
{
    set_time_limit(300);
    $name = 'play_in_apps-' . lp_model() . '-' . gmdate('Ymd-His') . '.txt';
    lp_headers(200, 'text/plain');
    header('Content-Disposition: attachment; filename="' . $name . '"');
    if (getenv('REQUEST_METHOD') === 'HEAD')
        exit(0);

    $dir = lp_plugin_dir();
    $tmp = lp_tmp();
    $xml = is_file("$dir/dune_plugin.xml") ? file_get_contents("$dir/dune_plugin.xml") : '';
    $version = preg_match('/<version>([^<]*)<\/version>/', (string) $xml, $m) ? $m[1] : '?';
    lp_out("play_in_apps $version logs, " . gmdate('Y-m-d H:i:s') . " UTC\n" . lp_tr('logs_warning') . "\n");
    lp_cmd('bin/diag.sh', 'sh ' . escapeshellarg("$dir/bin/diag.sh") . ' ' . lp_lang());
    foreach ($GLOBALS['lp_ids'] as $id)
        lp_file("$tmp/run/{$id}__supplier.log");
    lp_file("$tmp/run/play_in_apps.log");
    lp_file("$tmp/run/shell_ext.log");
    lp_file("$tmp/plugins/shell_ext/async_worker.log");
    lp_file("$tmp/run/shell.log", LP_TAIL);
    lp_cmd('logcat -d -v threadtime', 'logcat -d -v threadtime');
    lp_out("END\n");
    exit(0);
}

function lp_page($t)
{
    return '<!DOCTYPE html><html lang="' . (lp_lang() === 'russian' ? 'ru' : 'en') . '"><head>' .
        '<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">' .
        '<meta name="referrer" content="no-referrer"><title>' . lp_h(lp_tr('page_title')) . '</title><style>' .
        'body{font:16px/1.4 -apple-system,Roboto,sans-serif;margin:0;padding:16px;background:#111;color:#eee}' .
        'main{max-width:480px;margin:0 auto}h1{font-size:20px;margin:0 0 16px}' .
        '.warn{background:#4a3a10;padding:12px;border-radius:8px}' .
        'a.btn{display:block;margin-top:20px;padding:14px;font-size:17px;border-radius:8px;' .
        'background:#2d7ff9;color:#fff;text-align:center;text-decoration:none}' .
        '</style></head><body><main><h1>' . lp_h(lp_tr('page_title')) . '</h1>' .
        '<p class="warn">' . lp_h(lp_tr('logs_warning')) . '</p>' .
        '<p>' . lp_h(lp_tr('page_note')) . '</p>' .
        '<a class="btn" href="logs?t=' . lp_h($t) . '&amp;dl=1">' . lp_h(lp_tr('page_download')) . '</a>' .
        '</main></body></html>';
}

$method = (string) getenv('REQUEST_METHOD');
if ($method !== 'GET' && $method !== 'HEAD')
    lp_send(405, 'text/plain', "405 Method Not Allowed\n");
$t = lp_param('t');
if (!lp_token_ok($t))
    lp_forbidden();
if (lp_param('dl') === '1')
    lp_download();
lp_send(200, 'text/html', lp_page($t));
