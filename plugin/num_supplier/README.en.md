# Open in NUM for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds **Open in NUM** to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Selecting it opens the same title in NUM, the torrent catalog and search app for Android TV by YouROK, where you can find torrents and send them to a torrent client such as TorrServe.

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24, and NUM 1.0.150 (`ru.yourok.num`).

### Install
1. Copy `dune_plugin_num_supplier_<version>.zip` to a USB drive or to the internal storage.
2. On the Dune open **Sources**, find the zip and press ENTER.
3. The item appears in the **Play...** menu within half a minute, no reboot needed. If it does not, uninstall the plugin and install it again.

### How it works
- The title is opened by its TMDB ID (`https://www.themoviedb.org/movie/…`, `https://www.themoviedb.org/tv/…`). NUM cannot open a title by IMDb ID or by name, so a card without a TMDB ID cannot be opened.
- Series open on the series page: Dune does not pass a season or episode.
- Each launch replaces what was open in NUM, so screens from earlier launches do not pile up.
- Press Back once to return from the NUM title page to the Dune card. After watching a torrent, press Back three times: torrent list, NUM title page, Dune card.
- If NUM is not installed or the title has no TMDB ID, Dune shows a message.
- The plugin makes no network requests and runs nothing in the background.

### Remove
Uninstall the plugin in the Dune plugin list. The item cannot be hidden from the Dune settings (**Settings → Applications → Movies → Extensions** lists only plugins from the Dune Store), so removing the plugin is the only way to turn it off.

### License
MIT, see `LICENSE`.
