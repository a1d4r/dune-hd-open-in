<?php
// QR code -> PNG without GD: matrix from qrcode/qrcode.php (MIT, Kazuhiko
// Arase), PNG written by hand (8-bit grayscale, filter 0, zlib via
// gzcompress). PHP 5.3 syntax.

require_once dirname(__FILE__) . '/qrcode/qrcode.php';

class PiaQrPng
{
    // Returns array('png' => bytes, 'size' => px, 'modules' => n, 'version' => v).
    public static function make($text, $scale = 8, $quiet = 4)
    {
        $qr = QRCode::getMinimumQRCode($text, QR_ERROR_CORRECT_LEVEL_M);
        $n = $qr->getModuleCount();
        $side = ($n + 2 * $quiet) * $scale;

        $white_row = "\0" . str_repeat("\xff", $side);
        $margin = str_repeat("\xff", $quiet * $scale);
        $dark = str_repeat("\x00", $scale);
        $light = str_repeat("\xff", $scale);

        $raw = str_repeat($white_row, $quiet * $scale);
        for ($r = 0; $r < $n; $r++)
        {
            $line = "\0" . $margin;
            for ($c = 0; $c < $n; $c++)
                $line .= $qr->isDark($r, $c) ? $dark : $light;
            $line .= $margin;
            $raw .= str_repeat($line, $scale);
        }
        $raw .= str_repeat($white_row, $quiet * $scale);

        $png = "\x89PNG\r\n\x1a\n"
            . self::chunk('IHDR', pack('NNCCCCC', $side, $side, 8, 0, 0, 0, 0))
            . self::chunk('IDAT', gzcompress($raw, 9))
            . self::chunk('IEND', '');
        return array('png' => $png, 'size' => $side, 'modules' => $n,
            'version' => $qr->getTypeNumber());
    }

    private static function chunk($type, $data)
    {
        // crc32() may be negative on 32-bit PHP; pack('N') keeps the low 32 bits.
        return pack('N', strlen($data)) . $type . $data . pack('N', crc32($type . $data));
    }
}
