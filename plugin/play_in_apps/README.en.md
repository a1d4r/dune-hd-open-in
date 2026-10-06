# Play in apps for Dune HD

[Русский](README.md) | **English**

A Dune HD plugin that adds items to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Each item opens the same title (or a search for it) in an Android TV app; the Filmix item opens it in the Filmix_API Dune plugin. An item appears only if its app is installed; any item can be hidden on the plugin screen, which also has a check of the items and logs for the author.

| Menu item | App | Opens the title by |
|---|---|---|
| NUM | NUM 1.0.150 (`ru.yourok.num`) | TMDB ID |
| Lampa | Lampa 1.13.1 (`top.rootu.lampa`) | TMDB ID |
| BYLAMPA | BYLAMPA 1.13.3 (`top.rootu.bylumpa`) | TMDB ID |
| LAMPA ATV | LAMPA ATV 1.13.3 (`top.rootu.lumpa`) | TMDB ID |
| Prisma | Prisma 1.3.4 (`top.rootu.prisma`) | TMDB ID |
| VoKino | VoKino 1.1.1 (`ru.vokino.web`) | IMDb ID, else search by title |
| LazyMedia | LazyMedia Deluxe 3.467 (`com.lazycatsoftware.lmd`) | no ID, search by title only |
| Filmix | Filmix_API 0.1.9 Dune plugin | no ID, search by title |
| Stremio | Stremio for Android TV 1.11.2 (`com.stremio.one`) | IMDb ID, else TMDB ID |
| Nuvio | Nuvio TV 1.0.0 (`com.nuvio.tv`) | IMDb ID, else TMDB ID |
| FreeZona | FreeZona 3.0.74 (`free.zona`) | Kinopoisk ID |

Made for Dune HD Pro 8K Plus, firmware 260827_0003_r24; the app versions in the table are the tested ones.

### Install
1. If you have the separate "Open in …" plugins (NUM, Lampa, Nuvio and others), uninstall them in the Dune plugin list: this plugin replaces them, and while an old one is installed its item cannot be hidden.
2. Copy `dune_plugin_play_in_apps_<version>.zip` to a USB drive or to the internal storage.
3. On the Dune open **Sources**, find the zip and press ENTER.
4. The items of the installed apps appear in the **Play...** menu within half a minute, no reboot needed.

If you install or remove an app later, its item appears or goes away after the Dune wakes from standby or reboots, or at once if you open **Settings → Applications → Play in apps**.

### Update
Since 0.3.0 the plugin supports online updates: after the Dune boots (waking from standby is not a boot) the firmware checks GitHub Pages for a new version and offers to install it. Install 0.3.0 itself by hand. If an update does not come, install the new zip over the old one, as before.

### Plugin screen
**Settings → Applications → Play in apps** is a short screen, like the Dune's own settings:
- **Items of the "Play..." menu: Configure…** — which items to show;
- **Check: Open…** — why an item does not start;
- **Logs: Download to phone…** — the logs as one file to send to the author.

### Hide an item
**Items of the "Play..." menu: Configure…** opens the Dune's own dialog with a list of the apps and checkmarks. Uncheck an item to hide it, check it to show it; the **Apps** line switches all of them. All may be unchecked. The choice applies when the dialog closes ("Close" or Back): the item leaves the menu or comes back and stays so after a reboot. **POP UP → "Reset to Default Values"** turns all items on again. Apps that are not installed are marked "(not installed)"; the choice is kept for when the app appears. A choice made in earlier versions of the plugin is kept.

### Check
**Check: Open…** fits on one screen: the first line is the Dune model, firmware, Android and the plugin version, then one line per item: the app name, its version (if installed) and the verdict, for example "NUM 2.1 — OK", "Lampa 1.13.1 — hidden", "Prisma — not installed", "Filmix — OK (through the Filmix_API plugin)", "FreeZona 3.0.74 — the app will not take the link".

The check looks at whether the app is installed, whether the item is hidden, whether it is in the menu and not another plugin's (for example, an old "Open in …" one), what the item answers for the movie "Cars" and whether the app takes that link (Android is asked which app would open it; the app itself is not started). The details — the launch command, Android's answer, the Dune's last records about launching items — go to the logs only. An app that takes too long to open or closes at once is not seen by the check, only in the logs.

### Logs for the author
If an item says "Failed to start playback" or misbehaves, send the logs to the author:
1. **Right after the error, without rebooting the Dune** (a reboot erases part of the logs), open **Logs: Download to phone…**.
2. Scan the QR code with a phone on the same home network (or type the address under it) and tap **Download**: one `.txt` file arrives.
3. The link works while the QR code is open on the Dune, at most 5 minutes: **Close** or Back on the remote turns it off at once.

**The logs may contain personal data. Do not post them publicly — on forums or in group chats.**

### How the items work
For all items:
- Series open on the series page: Dune does not pass a season or episode.
- If the card has no ID the app needs (or no title, for a search), Dune shows a message.
- The plugin itself makes no network requests and runs nothing in the background. The Dune checks for its updates on GitHub Pages (`a1d4r.github.io`).

**NUM** is the torrent catalog and search app for Android TV by YouROK, where you can find torrents and send them to a torrent client such as TorrServe.
- The title is opened by its TMDB ID (`https://www.themoviedb.org/movie/…`, `https://www.themoviedb.org/tv/…`). NUM cannot open a title by IMDb ID or by name.
- Each launch replaces what was open in NUM, so screens from earlier launches do not pile up.
- Press Back once to return from the NUM title page to the Dune card. After watching a torrent, press Back three times: torrent list, NUM title page, Dune card.

**Lampa** is a movie and series catalog app: [github.com/lampa-app/LAMPA](https://github.com/lampa-app/LAMPA), APK in [Releases](https://github.com/lampa-app/LAMPA/releases/latest).
- The title is opened by its TMDB ID (`https://www.themoviedb.org/movie/…`, `https://www.themoviedb.org/tv/…`). Lampa cannot reliably open a title from outside by IMDb ID or by name.
- Each launch replaces what was open in Lampa. Lampa reloads for about a second.
- Back in Lampa starts working only after you press any arrow key once — Lampa behaves like this on every start. To return to the Dune card right away, long-press Back → "Quit the Application".
- If Lampa does not know the TMDB ID (Dune has a wrong ID), Lampa shows an endless loading spinner instead of a message.
- Tested with the `http://lampa.mx` server. A self-hosted Lampa server (such as Lampac) has not been tested.

**BYLAMPA** is an unofficial Lampa fork with its own server.
- The title is opened by its TMDB ID (`https://www.themoviedb.org/movie/…`, `https://www.themoviedb.org/tv/…`), as in Lampa.
- Each launch replaces what was open in BYLAMPA.

**LAMPA ATV** is an unofficial Lampa build.
- The title is opened by its TMDB ID (`https://www.themoviedb.org/movie/…`, `https://www.themoviedb.org/tv/…`), as in Lampa.

**Prisma** is a Lampa fork: [prisma.ws](https://prisma.ws), APK in [Releases](https://github.com/Sheinices/Prisma_TV/releases/latest).
- The title is opened by its TMDB ID, as in Lampa: opening by IMDb ID or by name is unreliable there.
- Each launch replaces what was open in Prisma. Prisma reloads for about a second.
- Back starts working only after you press any arrow key once. To return to the Dune card right away, long-press Back → "Quit the Application".
- If Prisma does not know the TMDB ID, Prisma shows an empty placeholder card (grey blocks) instead of a message.
- Tested with the `http://prisma.ws` server that Prisma suggests on first start.

**VoKino** is an online cinema app for Android TV.
- If the card has an IMDb ID, the VoKino title page opens right away (`vokino://ru.vokino.web/view/tt…`). VoKino does not understand TMDB or Kinopoisk IDs.
- Without an IMDb ID, VoKino search opens with the card's title in the Dune UI language, or with the original title if there is none. The search ignores the year, so pick the right title from the list.
- Rarely VoKino has a title but does not know its IMDb ID (for example, House of the Dragon): VoKino then shows "Failed to load data". Find the title with VoKino's own search.
- Each launch replaces what was open in VoKino.
- To return to the Dune card, press Back: VoKino opens its own menu. Then go down to "Exit the app" ("Выйти из приложения") and press ENTER. This is how VoKino itself works.

**LazyMedia** is LazyMedia Deluxe, an app that collects movies from online cinemas.
- LazyMedia **search** opens with the card's title in the Dune UI language, or with the original title if there is none. A title page cannot be opened directly: LazyMedia has no IDs of its own, a title page belongs to one of its source sites.
- Pick the right title from the results. What is found depends on the sources enabled in LazyMedia and on the title: for example, "Гладиатор 2" from Dune finds worse than "Гладиатор II". The year is not passed to the search.
- Some sources return adult films, even for an ordinary query.
- Every launch is added to the LazyMedia search history and replaces what was open in LazyMedia.

**Filmix** searches in **Filmix_API**, a Dune plugin for Filmix by ddaaff ([forum.mydune.ru thread](https://forum.mydune.ru/viewtopic.php?t=246)). It is not an Android app: Filmix_API is installed into Dune, like this plugin, and is not included in this zip.
- The Filmix_API **search** screen opens with the card's title in the Dune UI language, or with the original title if there is none. Filmix_API knows no IMDb, TMDB or Kinopoisk IDs. The year is not passed to the search; it shows up to 5 titles.
- From there it is Filmix_API as usual: pick the title and watch. Back from the search screen returns to the Dune card.
- Tested without a Filmix account (Filmix_API plays 720p). How a PRO account behaves is not tested yet — please report in Issues.

**Stremio**, with streams from your Stremio addons ([stremio.com](https://www.stremio.com/)).
- The title is opened by IMDb ID (`stremio:///detail/movie/tt…`, `stremio:///detail/series/tt…`). Without an IMDb ID, by TMDB ID (`stremio:///detail/movie/tmdb:…`); this works only if one of your Stremio addons understands TMDB IDs.
- Press Back three times (or Home) to exit Stremio and return to the Dune card.

**Nuvio** is [Nuvio TV](https://github.com/NuvioMedia/NuvioTV), with streams from your Nuvio addons.
- The title is opened by IMDb ID (`nuvio://movie/tt…`, `nuvio://series/tt…`). Without an IMDb ID, by TMDB ID (`nuvio://tmdb/movie/…`, `nuvio://tmdb/series/…`).
- Back from the Nuvio title page leads to the Nuvio home screen; press Back a few more times (or Home) to exit Nuvio and return to the Dune card.

**FreeZona** is an unofficial build of the Zona online cinema client, not made by the Zona authors.
- Movies and series are opened by Kinopoisk ID (`https://www.kinopoisk.ru/film/…`). FreeZona does not understand IMDb or TMDB IDs, and a search by title cannot be started from outside: if the card has no Kinopoisk ID, the Dune shows a message.
- Not every card in the Dune catalog has a Kinopoisk ID. Movies usually have one, series more often don't: for example, Game of Thrones has one, while newer series such as Shōgun, Fallout and House of the Dragon don't.
- FreeZona looks the title up on the Zona server. If Zona does not know the title or there is no network, the FreeZona home screen opens with no message; find the title with FreeZona's own search.
- Each launch replaces what was open in FreeZona.
- Back from the FreeZona title page leads to the FreeZona home screen; press Back once more to return to the Dune card.

### Remove
Uninstall the plugin in the Dune plugin list — all its items go away.

### License
MIT, see `LICENSE`. The QR code is drawn by [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator) by Kazuhiko Arase (MIT, `qrcode/LICENSE`).
