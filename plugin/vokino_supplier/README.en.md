# Open in VoKino for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds **VoKino** to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Selecting it opens the same title in VoKino, an online cinema app for Android TV.

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24, and VoKino 1.1.1 (`ru.vokino.web`).

### Install
1. Copy `dune_plugin_vokino_supplier_<version>.zip` to a USB drive or to the internal storage.
2. On the Dune open **Sources**, find the zip and press ENTER.
3. The item appears in the **Play...** menu within half a minute, no reboot needed. If it does not, uninstall the plugin and install it again.

### How it works
- If the card has an IMDb ID, the VoKino title page opens right away (`vokino://ru.vokino.web/view/tt…`). VoKino does not understand TMDB or Kinopoisk IDs.
- Without an IMDb ID, VoKino search opens with the card's title in the Dune UI language, or with the original title if there is none. The search ignores the year, so pick the right title from the list.
- Rarely VoKino has a title but does not know its IMDb ID (for example, House of the Dragon): VoKino then shows "Failed to load data". Find the title with VoKino's own search.
- Series open on the series page: Dune does not pass a season or episode.
- Each launch replaces what was open in VoKino, so screens from earlier launches do not pile up.
- If VoKino is not installed, Dune shows a message.
- The plugin makes no network requests and runs nothing in the background.

### Remove
Uninstall the plugin in the Dune plugin list. The item cannot be hidden from the Dune settings (**Settings → Applications → Movies → Extensions** lists only plugins from the Dune Store), so removing the plugin is the only way to turn it off.

### License
MIT, see `LICENSE`.
