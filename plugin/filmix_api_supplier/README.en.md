# Open in Filmix for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds **Filmix** to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Selecting it searches for the same title in **Filmix_API**, a Dune plugin for Filmix by ddaaff ([forum.mydune.ru thread](https://forum.mydune.ru/viewtopic.php?t=246)). It is not an Android app: Filmix_API is installed into Dune, like this plugin.

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24, and Filmix_API 0.1.9.

### Install
1. Install Filmix_API (the zip is in the first post of the forum thread).
2. Copy `dune_plugin_filmix_api_supplier_<version>.zip` to a USB drive or to the internal storage.
3. On the Dune open **Sources**, find the zip and press ENTER.
4. The item appears in the **Play...** menu within half a minute, no reboot needed. If it does not, uninstall the plugin and install it again.

### How it works
- The Filmix_API **search** screen opens with the card's title in the Dune UI language, or with the original title if there is none. A title page cannot be opened directly: Filmix_API knows no IMDb, TMDB or Kinopoisk IDs. The year is not passed to the search; it shows up to 5 titles.
- From there it is Filmix_API as usual: pick the title and watch. Back from the search screen returns to the Dune card.
- Tested without a Filmix account (Filmix_API plays 720p). How a PRO account behaves when opened through this item is not tested yet — please report in Issues.
- If Filmix_API is not installed, Dune shows a message.
- The plugin makes no network requests and runs nothing in the background: the search is done by Filmix_API itself.

### Remove
Uninstall the plugin in the Dune plugin list. The item cannot be hidden from the Dune settings (**Settings → Applications → Movies → Extensions** lists only plugins from the Dune Store), so removing the plugin is the only way to turn it off.

### License
MIT, see `LICENSE`. Filmix_API is a separate plugin by another author and is not included in this zip.
