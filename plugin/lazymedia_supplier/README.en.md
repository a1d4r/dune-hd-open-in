# Open in LazyMedia for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds **LazyMedia** to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Selecting it searches for the same title in LazyMedia Deluxe, an Android TV app that collects movies from online cinemas.

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24, and LazyMedia Deluxe 3.467 (`com.lazycatsoftware.lmd`).

### Install
1. Copy `dune_plugin_lazymedia_supplier_<version>.zip` to a USB drive or to the internal storage.
2. On the Dune open **Sources**, find the zip and press ENTER.
3. The item appears in the **Play...** menu within half a minute, no reboot needed. If it does not, uninstall the plugin and install it again.

### How it works
- LazyMedia **search** opens with the card's title in the Dune UI language, or with the original title if there is none. A title page cannot be opened directly: LazyMedia has no IDs of its own (IMDb, TMDB, Kinopoisk), a title page belongs to one of its source sites.
- Pick the right title from the results. What is found depends on the sources enabled in LazyMedia and on the title: for example, "Гладиатор 2" from Dune finds worse than "Гладиатор II", and for "Game of Thrones" documentaries about the series come first. The year is not passed to the search.
- Some sources return adult films, even for an ordinary query.
- Every launch is added to the LazyMedia search history.
- Each launch replaces what was open in LazyMedia, so screens from earlier launches do not pile up.
- If LazyMedia Deluxe is not installed, Dune shows a message.
- The plugin makes no network requests and runs nothing in the background.

### Remove
Uninstall the plugin in the Dune plugin list. The item cannot be hidden from the Dune settings (**Settings → Applications → Movies → Extensions** lists only plugins from the Dune Store), so removing the plugin is the only way to turn it off.

### License
MIT, see `LICENSE`.
