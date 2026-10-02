# Open in Nuvio for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds **Nuvio** to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Selecting it opens the same title in [Nuvio TV](https://github.com/NuvioMedia/NuvioTV), with streams from your Nuvio addons.

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24, and Nuvio TV 1.0.0 (`com.nuvio.tv`).

### Install
1. Copy `dune_plugin_nuvio_supplier_<version>.zip` to a USB drive or to the internal storage.
2. On the Dune open **Sources**, find the zip and press ENTER.
3. The item appears in the **Play...** menu within half a minute, no reboot needed. If it does not, uninstall the plugin and install it again.

### How it works
- The title is opened by IMDb ID (`nuvio://movie/tt…`, `nuvio://series/tt…`). If the card has no IMDb ID, it is opened by TMDB ID (`nuvio://tmdb/movie/…`, `nuvio://tmdb/series/…`).
- Series open on the series page: Dune does not pass a season or episode.
- Back from the Nuvio title page leads to the Nuvio home screen; press Back a few more times (or Home) to exit Nuvio and return to the Dune card.
- If Nuvio is not installed or the title has no IMDb/TMDB ID, Dune shows a message.
- The plugin makes no network requests and runs nothing in the background.

### Remove
Uninstall the plugin in the Dune plugin list. The item cannot be hidden from the Dune settings (**Settings → Applications → Movies → Extensions** lists only plugins from the Dune Store), so removing the plugin is the only way to turn it off.

### License
MIT, see `LICENSE`.
