# Open in Prisma for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds **Prisma** to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Selecting it opens the same title in Prisma, a movie and series catalog app for Android TV (a Lampa fork).

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24, and Prisma 1.3.4 (`top.rootu.prisma`, server `http://prisma.ws`). Prisma: [prisma.ws](https://prisma.ws), APK in [Releases](https://github.com/Sheinices/Prisma_TV/releases/latest).

### Install
1. Copy `dune_plugin_prisma_supplier_<version>.zip` to a USB drive or to the internal storage.
2. On the Dune open **Sources**, find the zip and press ENTER.
3. The item appears in the **Play...** menu within half a minute, no reboot needed. If it does not, uninstall the plugin and install it again.

### How it works
- The title is opened by its TMDB ID (`https://www.themoviedb.org/movie/…`, `https://www.themoviedb.org/tv/…`). The plugin does not open a card without a TMDB ID: in Lampa, which Prisma is based on, opening by IMDb ID or by name is unreliable.
- Series open on the series page: Dune does not pass a season or episode.
- Each launch replaces what was open in Prisma, so screens from earlier launches do not pile up. Prisma reloads for about a second.
- Back in Prisma starts working only after you press any arrow key once — this is how the app behaves, Lampa does the same. To return to the Dune card right away, long-press Back → "Quit the Application".
- If Prisma is not installed or the title has no TMDB ID, Dune shows a message.
- If Prisma does not know the TMDB ID (Dune has a wrong ID), Prisma shows an empty placeholder card (grey blocks) instead of a message.
- Tested with the `http://prisma.ws` server that Prisma suggests on first start. Other server addresses have not been tested.
- The plugin makes no network requests and runs nothing in the background.

### Remove
Uninstall the plugin in the Dune plugin list. The item cannot be hidden from the Dune settings (**Settings → Applications → Movies → Extensions** lists only plugins from the Dune Store), so removing the plugin is the only way to turn it off.

### License
MIT, see `LICENSE`.
