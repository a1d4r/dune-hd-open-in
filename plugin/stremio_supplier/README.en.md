# Open in Stremio for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds **Open in Stremio** to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Selecting it opens the same title in [Stremio](https://www.stremio.com/), with streams from your Stremio addons.

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24, and Stremio for Android TV 1.11.2 (`com.stremio.one`, Google Play).

### Install
1. Copy `dune_plugin_stremio_supplier_<version>.zip` to a USB drive or to the internal storage.
2. On the Dune open **Sources**, find the zip and press ENTER.
3. The item appears in the **Play...** menu within half a minute, no reboot needed. If it does not, uninstall the plugin and install it again.

### How it works
- The title is opened by IMDb ID (`stremio:///detail/movie/tt…`, `stremio:///detail/series/tt…`). If the card has no IMDb ID, it is opened by TMDB ID (`stremio:///detail/movie/tmdb:…`, `stremio:///detail/series/tmdb:…`); this works only if one of your Stremio addons understands TMDB IDs.
- Series open on the series page: Dune does not pass a season or episode.
- Press Back three times (or Home) to exit Stremio and return to the Dune card.
- If Stremio is not installed or the title has no IMDb/TMDB ID, Dune shows a message.
- The plugin makes no network requests and runs nothing in the background.

### Remove
Uninstall the plugin in the Dune plugin list. The item cannot be hidden from the Dune settings (**Settings → Applications → Movies → Extensions** lists only plugins from the Dune Store), so removing the plugin is the only way to turn it off.

### License
MIT, see `LICENSE`.
