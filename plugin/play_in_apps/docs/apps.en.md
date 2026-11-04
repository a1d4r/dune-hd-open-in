# Apps

[← Back to README](../README.en.md)

What each item of the **Play...** menu can do and what to do if the title did not open. The apps are installed and set up separately; an item appears only if its app is installed.

## How each item opens a title
| Item | Opens | App it was tested with |
|---|---|---|
| [NUM](#num) | by TMDB ID | NUM 1.0.150 (`ru.yourok.num`) |
| [Lampa](#lampa) | by TMDB ID | Lampa 1.13.1 (`top.rootu.lampa`) |
| [BYLAMPA](#bylampa) | by TMDB ID | BYLAMPA 1.13.3 (`top.rootu.bylumpa`) |
| [LAMPA ATV](#lampa-atv) | by TMDB ID | LAMPA ATV 1.13.3 (`top.rootu.lumpa`) |
| [Prisma](#prisma) | by TMDB ID | Prisma 1.3.4 (`top.rootu.prisma`) |
| [VoKino](#vokino) | by IMDb ID, without it — search by title | VoKino 1.1.1 (`ru.vokino.web`) |
| [LazyMedia](#lazymedia) | search by title only | LazyMedia Deluxe 3.467 (`com.lazycatsoftware.lmd`) |
| [Filmix](#filmix) | search by title only | Filmix_API 0.1.9 Dune plugin |
| [Stremio](#stremio) | by IMDb ID, without it — by TMDB ID | Stremio for Android TV 1.11.2 (`com.stremio.one`) |
| [Nuvio](#nuvio) | by IMDb ID, without it — by TMDB ID | Nuvio TV 1.0.0 (`com.nuvio.tv`) |
| [FreeZona](#freezona) | by Kinopoisk ID | FreeZona 3.0.74 (`free.zona`) |
| [ALPAC](#alpac) | by TMDB ID, without it — search by title | ALPAC 1.0.96 (`cc.alcopa.tv`) |
| [Flux](#flux) | by TMDB ID | Flux 1.63 (`app.flux.tv`) |
| [SeasonHit](#seasonhit) | search by title only | SeasonHit 2.4.4.2 (`com.jimdo.xakerd.season2hit`) |
| [Bazinga](#bazinga) | by Kinopoisk ID, without it — search by title | Bazinga Dune plugin (`Bazinga3`) 2023031100_patch |
| [IPTV Channel Editor plugin](#iptv-channel-editor-plugins), for example Mir Kino | search by title in the plugin itself | Mir Kino 9.4.2548 |

## Common to all items
- The ID is taken from the Dune card. If the card has no ID the app needs (or no title, for a search), the Dune shows a message.
- The search uses the title in the Dune UI language, or the original title if there is none. The year is not passed: pick the right title from the results. The exception is plugins with the `vod_search` entry, which get more (see [below](#iptv-channel-editor-plugins)).
- A series opens on the series page: the app does not get the season and episode.
- NUM, Lampa, BYLAMPA, Prisma, VoKino, LazyMedia and FreeZona replace what was open on every launch, so screens from earlier launches do not pile up. Lampa and Prisma reload for about a second when this happens.

## How to return to the Dune
| App | How to return to the Dune card |
|---|---|
| NUM | Back. After watching a torrent — three times: torrent list, NUM card, Dune card. |
| Lampa, Prisma | Back starts working only after you press any arrow key once — these apps behave like this on every start. Right away: long-press Back → "Quit the Application". |
| VoKino | Back — VoKino opens its menu — then go down to "Выйти из приложения" (Exit the app) and press ENTER. This is how VoKino itself works. |
| Stremio | Back three times (or Home). |
| Nuvio | Back leads to the Nuvio home screen, then Back a few more times (or Home). |
| FreeZona | Back twice: first to the FreeZona home screen, then to the Dune card. |
| Filmix | Back from the Filmix_API search screen. |
| IPTV Channel Editor plugins | Back from the results. |

## If the title was not found
If the app does not know the title, it usually does not report an error but shows something of its own. Find the title with the app's own search.

| App | What you see |
|---|---|
| Lampa | endless loading (happens when the Dune card has a wrong TMDB ID) |
| Prisma | an empty placeholder card with grey blocks |
| VoKino | "Не удалось загрузить данные" (Failed to load data) — rarely VoKino does not know the IMDb ID of a title it has (for example, House of the Dragon) |
| FreeZona | the FreeZona home screen; the same when there is no network |
| ALPAC | an empty card "Источники не найдены" (No sources found) |

## NUM
A torrent catalog and search app for Android TV by YouROK: you can find a torrent in it and send it to a torrent client such as TorrServe. Opens the title page by TMDB ID; NUM cannot open a title page by IMDb ID or by title.

## Lampa
A movie and series catalog app: [github.com/lampa-app/LAMPA](https://github.com/lampa-app/LAMPA), APK in [Releases](https://github.com/lampa-app/LAMPA/releases/latest).
- Opens the title page by TMDB ID. Lampa cannot be reliably opened from outside by IMDb ID or by title.
- Tested with the `http://lampa.mx` server. A Lampa server of your own (for example, Lampac) has not been tested.

## BYLAMPA
An unofficial Lampa fork with its own server. Opens the title page by TMDB ID, like Lampa.

## LAMPA ATV
An unofficial Lampa build. Opens the title page by TMDB ID, like Lampa.

## Prisma
A Lampa fork: [prisma.ws](https://prisma.ws), APK in [Releases](https://github.com/Sheinices/Prisma_TV/releases/latest).
- Opens the title page by TMDB ID: by IMDb ID or by title Prisma opens titles unreliably.
- Tested with the `http://prisma.ws` server that Prisma suggests on first start.

## VoKino
An online cinema app for Android TV.
- With an IMDb ID, the VoKino title page opens right away. VoKino does not understand TMDB or Kinopoisk IDs.
- Without an IMDb ID, VoKino search by title opens.

## LazyMedia
LazyMedia Deluxe is an app that collects movies from online cinemas.
- Only a **search** by title opens. The title page cannot be opened directly: LazyMedia has no IDs of its own, a title page belongs to one of the source sites.
- What is found depends on the sources enabled in LazyMedia and on the title: for example, "Гладиатор 2" from the Dune is found worse than "Гладиатор II".
- Some sources return adult films in the results, even for an ordinary query.
- Every launch is added to the LazyMedia search history.

## Filmix
A search in **Filmix_API**, a Dune plugin for Filmix by ddaaff ([forum.mydune.ru thread](https://forum.mydune.ru/viewtopic.php?t=246)). It is not an Android app: Filmix_API is installed into the Dune separately, like this plugin.
- The Filmix_API search screen opens with the title. Filmix_API knows no IMDb, TMDB or Kinopoisk IDs. The results show up to 5 titles.
- From there it is Filmix_API as usual: pick the title and watch.
- Tested without a Filmix account (Filmix_API plays 720p). How a PRO account behaves has not been tested yet — please report in [Issues](https://github.com/a1d4r/dune-hd-open-in/issues).

## Stremio
Stremio with streams from your addons ([stremio.com](https://www.stremio.com/)). Opens the title page by IMDb ID. Without it — by TMDB ID, but this works only if one of your addons understands TMDB IDs.

## Nuvio
[Nuvio TV](https://github.com/NuvioMedia/NuvioTV) with streams from your Nuvio addons. Opens the title by IMDb ID, without it — by TMDB ID.

## FreeZona
An unofficial build of the Zona online cinema client, not made by the Zona authors.
- Opens movies and series by Kinopoisk ID only. FreeZona does not understand IMDb or TMDB IDs, and a search by title cannot be started from outside: without a Kinopoisk ID the Dune shows a message.
- Not every card in the Dune catalog has a Kinopoisk ID. Movies usually have one, series more often don't: for example, Game of Thrones has one, while the newer Shōgun, Fallout and House of the Dragon don't.
- FreeZona looks the title up on the Zona server. If Zona does not know the title or there is no network, the FreeZona home screen opens with no message.

## ALPAC
An online cinema client for Android TV. You need to be signed in to your ALPAC account.
- If the card has a TMDB ID of the right type (a movie ID for a movie, a series ID for a series), the ALPAC title page opens right away. ALPAC does not understand IMDb or Kinopoisk IDs.
- Otherwise ALPAC search by title opens.

## Flux
A media center for Android TV: a movie and series catalog, torrents, its own player. No account needed.
- Opens the title page by a TMDB ID of the right type (a movie ID for a movie, a series ID for a series). Flux does not understand IMDb or Kinopoisk IDs.
- A search by title cannot be started from outside: without such a TMDB ID the Dune shows a message.

## SeasonHit
An unofficial seasonvar.ru client: series, its own player. No account needed.
- Only a **search** by title opens. The series page cannot be opened directly: SeasonHit knows only its own seasonvar IDs (one per season), not TMDB, IMDb or Kinopoisk.
- The search finds seasonvar series; movies are usually not found, look for them in the "Фильмы" (Movies) section of SeasonHit itself.
- The results open in SeasonHit's mobile search screen, not in its TV interface.
- On models where the Dune runs as an app on Android TV, SeasonHit will most likely not open (not tested).

## Bazinga
The Bazinga Dune plugin (`Bazinga3`, by TrippyCat): the Kinopoisk catalog, with sources for a title (trackers, Jackett and others). It is not an Android app: Bazinga is installed into the Dune separately, for example from the "Plugin collection" of Dune BackUp.
- With a Kinopoisk ID, the movie or series page opens in Bazinga right away.
- Without it, Bazinga's Kinopoisk search by title opens.
- Watch through "Источники" (Sources) on the Bazinga title page. Which sources there are and whether they work depends on Bazinga itself and its settings.

## IPTV Channel Editor plugins
IPTV Channel Editor is a builder of Dune plugins for IPTV providers. If such a plugin has movies (VOD), for example Mir Kino, it gets an item of its own in **Play...**, with the plugin's name and icon. The plugins themselves come from the providers.
- The item opens the plugin's search results for the title. IDs are not passed.
- Sign in to the provider's account in the plugin first: without it there are no results.
- The results are empty although the provider has the title: open the plugin once and try again — with some providers the search looks only through a list already loaded. Results are also empty when the provider spells the title differently; then search in the plugin itself.
- A plugin installed later shows up in the menu, and a removed one goes away, usually in about half a minute. If not, that happens after the Dune wakes from standby or reboots, or at once if you open the **Play in apps** plugin screen.
- Plugins with the `vod_search` search entry get the card's title, the original title, the year and the whole movie card, and, if the episode was chosen through **Seasons** in the card, also the season and episode numbers. How to search and what to show is up to the plugin itself. Any Dune plugin can get such an item, not only one made with IPTV Channel Editor — see [For plugin developers](developers.en.md). The check shows `vod_search` for such an item.
- Tested with Mir Kino; plugins of other providers have not been tested.

## Missing items and why
- **Kino.pub (KinoWatch)** — the app opens a title only by its internal kino.pub number. It cannot be opened by IMDb, TMDB or title, and a search cannot be started from outside either: the item could only open the app's home screen.
- **Lift** — the app opens a title only by its internal number, and a search cannot be started from outside: the item could only open the app's home screen.
- **LostFilm.TV (`ru.twicker.lostfilmtv`)** — the app opens a series only by its internal LostFilm number. It cannot be opened by IMDb, TMDB, Kinopoisk or title, and a search cannot be started from outside either: the item could only open the app's home screen.
- **Lampa TV 7.7.9 (`ru.twicker.lampa`, the "Un" build)** — the title page opens only if the link is sent again about a second after the app starts. The workaround is fragile (on a slow network you get the home screen), and the build itself is no longer updated. The Lampa item works with the official LAMPA (`top.rootu.lampa`).
