# Open in Lampa for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds **Lampa** to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Selecting it opens the same title in Lampa, a movie and series catalog app for Android TV.

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24, and Lampa 1.13.1 (`top.rootu.lampa`, server `http://lampa.mx`). Lampa: [github.com/lampa-app/LAMPA](https://github.com/lampa-app/LAMPA), APK in [Releases](https://github.com/lampa-app/LAMPA/releases/latest).

### Install
1. Copy `dune_plugin_lampa_supplier_<version>.zip` to a USB drive or to the internal storage.
2. On the Dune open **Sources**, find the zip and press ENTER.
3. The item appears in the **Play...** menu within half a minute, no reboot needed. If it does not, uninstall the plugin and install it again.

### How it works
- The title is opened by its TMDB ID (`https://www.themoviedb.org/movie/…`, `https://www.themoviedb.org/tv/…`). Lampa cannot reliably open a title from outside by IMDb ID or by name, so a card without a TMDB ID cannot be opened.
- Series open on the series page: Dune does not pass a season or episode.
- Each launch replaces what was open in Lampa, so screens from earlier launches do not pile up. Lampa reloads for about a second.
- Back in Lampa starts working only after you press any arrow key once — Lampa behaves like this on every start, from the Apps menu too. To return to the Dune card right away, long-press Back → "Quit the Application".
- If Lampa is not installed or the title has no TMDB ID, Dune shows a message.
- If Lampa does not know the TMDB ID (Dune has a wrong ID), Lampa shows an endless loading spinner instead of a message.
- Tested with the `http://lampa.mx` server. A self-hosted Lampa server (such as Lampac) has not been tested.
- The plugin makes no network requests and runs nothing in the background.

### Remove
Uninstall the plugin in the Dune plugin list. The item cannot be hidden from the Dune settings (**Settings → Applications → Movies → Extensions** lists only plugins from the Dune Store), so removing the plugin is the only way to turn it off.

### License
MIT, see `LICENSE`.
