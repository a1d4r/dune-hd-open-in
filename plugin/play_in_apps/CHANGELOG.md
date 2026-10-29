# Changelog

**English version**

## 0.10.1
- Fixed: IPTV Channel Editor plugins with a dot or a hyphen in their name (for example iEdem/iLook TV — `iedem.tv`) did not show up in the "Play..." menu.

## 0.10.0
- Items of IPTV Channel Editor plugins: every installed Dune plugin made with IPTV Channel Editor that has movies (VOD), for example Mir Kino, is an item of its own in the "Play..." menu, with that plugin's name and icon. It opens that plugin's search results for the title (in the Dune UI language, else the original one). Sign in to your provider's account in that plugin first. If the results are empty, open the plugin once and try again. A plugin installed later shows up after standby or a reboot, or at once when the plugin screen is opened. These items can be hidden and are shown in "Check", like the others.

## 0.9.0
- Bazinga item: opens the title in the Bazinga Dune plugin (`Bazinga3`): its Kinopoisk title page by Kinopoisk ID; without one, Bazinga's Kinopoisk search by title. Bazinga is installed separately, for example from the "Plugin collection" of Dune BackUp.

## 0.8.1
- Fixed: the plugin screen was missing from Applications → All, it was only in Applications → Dune HD.

## 0.8.0
- SeasonHit item: opens SeasonHit (`com.jimdo.xakerd.season2hit`) search by the title; it finds seasonvar series, movies are rarely found. On models where the Dune runs as an app on Android TV it will most likely not open (not checked).
- The plugin screen is also in Applications → Dune HD, not only in Settings → Applications.

## 0.7.0
- Flux item: opens the movie or series in Flux (`app.flux.tv`) by TMDB ID; without one, the Dune shows a message.

## 0.6.0
- ALPAC item: opens the movie or series in ALPAC (`cc.alcopa.tv`) by TMDB ID; without one, ALPAC search by title.

## 0.5.1
- Fixed: items did not start on older firmware (e.g. r24 260214) — "Failed to start playback". The items now name the app inside the link instead of the `-p` option that firmware does not understand.
- Nuvio and Stremio: the chosen movie opens even if the app already shows another card.

## 0.5.0
- New plugin screen, like the Dune's own settings: three buttons instead of a line per app, so it no longer runs off the screen.
- Items of the "Play..." menu are chosen in the Dune's own dialog with checkmarks: the "Apps" line switches all of them, all may be unchecked, POP UP → "Reset to Default Values" turns all on. A choice made in earlier versions is kept.
- "Check": one screen — the Dune model, firmware, Android and the plugin version, then a line per item with the app version and the verdict: OK, hidden, not installed or what is wrong (not in the menu, another plugin's item, the item script is missing, the item answers with an error, the app will not take the link, could not check the launch — on Android TV models this may be so for every installed app). It looks at whether the app is installed, whether the item is hidden and in the menu, what it answers for a sample movie and whether the app takes that link. The details go to the logs.
- "Logs: Download to phone…": a QR code opens a page on a phone in the same network that warns about personal data and downloads the logs as one `.txt` file. Download them right after an error, without rebooting the Dune. The link works while the QR code is open on the Dune, at most 5 minutes; "Close" or Back turns it off. The logs may contain personal data: do not post them publicly — on forums or in group chats.

## 0.4.0
- BYLAMPA item: opens the movie or series in BYLAMPA (`top.rootu.bylumpa`) by TMDB ID.
- LAMPA ATV item: opens the movie or series in LAMPA ATV (`top.rootu.lumpa`) by TMDB ID.

## 0.3.0
- Online updates: after the Dune boots (waking from standby is not a boot) the firmware checks GitHub Pages for a new version of the plugin and offers to install it. Install 0.3.0 itself by hand; if an update does not come, install the new zip over the old one, as before.

## 0.2.1
- Filmix: the item first makes Filmix_API load its account token, then opens the search. Before, right after power-on or standby Filmix_API searched without the token until one entered a section of its main menu, and a PRO account was treated as none.

## 0.2.0
- FreeZona item: opens the movie or series in FreeZona (`free.zona`) by Kinopoisk ID.

## 0.1.1
- The "Play in apps" screen moved from Applications to Settings → Applications.
- Own icon for the plugin screen.

## 0.1.0
- First version: all items of the separate "Open in …" plugins in one plugin — NUM, Lampa, Prisma, VoKino, LazyMedia, Filmix, Stremio and Nuvio in the "Play..." menu of the Movies catalog card. Replaces `num_supplier` 0.1.4, `lampa_supplier` 0.1.3, `prisma_supplier` 0.1.3, `vokino_supplier` 0.1.3, `lazymedia_supplier` 0.1.3, `filmix_api_supplier` 0.1.3, `stremio_supplier` 0.1.4 and `nuvio_supplier` 0.2.4; the items work the same way.
- Items appear only for installed apps (for Filmix, the Filmix_API plugin). An app installed or removed later is picked up after standby or a reboot, or at once when the plugin screen is opened.
- "Play in apps" screen in Applications: any item can be hidden without removing the app.

---

**Russian version**

## 0.10.1
- Исправлено: плагины IPTV Channel Editor с точкой или дефисом в имени (например, iEdem/iLook TV — `iedem.tv`) не появлялись в меню «Смотреть…».

## 0.10.0
- Пункты плагинов IPTV Channel Editor: каждый установленный плагин Дюны, собранный в IPTV Channel Editor, в котором есть фильмы (VOD), например Mir Kino, — отдельный пункт меню «Смотреть…» с названием и иконкой этого плагина. Пункт открывает в нём выдачу поиска по названию карточки (на языке интерфейса Дюны, а если его нет — по оригинальному). Сначала войдите в аккаунт провайдера в самом плагине. Если выдача пустая — откройте плагин один раз и повторите. Плагин, поставленный позже, появится в меню после выхода из режима ожидания или перезагрузки, а сразу — если открыть экран плагина. Такие пункты можно скрыть, они есть в «Проверке», как и остальные.

## 0.9.0
- Пункт Bazinga: открывает фильм или сериал в плагине Дюны Bazinga (`Bazinga3`) — карточку Кинопоиска по ID Кинопоиска, а если его нет — поиск Кинопоиска в Bazinga по названию. Bazinga ставится отдельно, например из «Коллекции плагинов» Dune BackUp.

## 0.8.1
- Исправлено: экрана плагина не было в «Приложения» → «Все», только в «Приложения» → «Dune HD».

## 0.8.0
- Пункт SeasonHit: открывает поиск SeasonHit (`com.jimdo.xakerd.season2hit`) по названию; находит сериалы seasonvar, фильмы — редко. На моделях, где Дюна стоит приложением на Android TV, скорее всего, не откроется (не проверено).
- Экран плагина — ещё и в «Приложения» → «Dune HD», не только в «Настройки» → «Приложения».

## 0.7.0
- Пункт Flux: открывает фильм или сериал во Flux (`app.flux.tv`) по TMDB ID, а если его нет — Дюна покажет сообщение.

## 0.6.0
- Пункт ALPAC: открывает фильм или сериал в ALPAC (`cc.alcopa.tv`) по TMDB ID, а если его нет — поиск ALPAC по названию.

## 0.5.1
- Исправлено: на старых прошивках (например, r24 260214) пункты не запускались — «Не удалось запустить воспроизведение». Теперь пункты указывают приложение в самой ссылке, а не опцией `-p`, которую такие прошивки не понимают.
- Nuvio и Stremio: открывается выбранный фильм, даже если в приложении уже открыта другая карточка.

## 0.5.0
- Новый экран плагина — как настройки самой Дюны: три кнопки вместо строки на каждое приложение, экран больше не уходит за край.
- Пункты меню «Смотреть…» выбираются в штатном диалоге Дюны с галочками: строка «Приложения» переключает все, можно снять все, POP UP → «Сброс к значениям по умолчанию» включает все. Выбор из прошлых версий сохраняется.
- «Проверка»: один экран — модель Дюны, прошивка, Android и версия плагина, затем строка на каждый пункт с версией приложения и итогом: ОК, скрыт, не установлено или что не так (пункта нет в меню, пункт от другого плагина, нет скрипта пункта, пункт отвечает ошибкой, приложение не примет ссылку, не удалось проверить запуск — на моделях с Android TV так может быть у всех установленных). Проверяется, установлено ли приложение, скрыт ли пункт и есть ли он в меню, что он отвечает на пример фильма и примет ли приложение эту ссылку. Подробности — в логах.
- «Логи: Скачать на телефон…»: QR-код открывает на телефоне в той же сети страницу с предупреждением о личных данных, с которой логи скачиваются одним файлом `.txt`. Качайте сразу после ошибки, не перезагружая Дюну. Ссылка работает, пока на Дюне открыт QR-код, но не дольше 5 минут; «Закрыть» или Back её гасят. В логах могут быть личные данные: не выкладывайте их в открытый доступ — на форумы и в общие чаты.

## 0.4.0
- Пункт BYLAMPA: открывает фильм или сериал в BYLAMPA (`top.rootu.bylumpa`) по TMDB ID.
- Пункт LAMPA ATV: открывает фильм или сериал в LAMPA ATV (`top.rootu.lumpa`) по TMDB ID.

## 0.3.0
- Онлайн-обновление: после загрузки Дюны (выход из режима ожидания — не загрузка) прошивка проверяет новую версию плагина на GitHub Pages и предлагает её поставить. Саму 0.3.0 ставьте вручную; если обновление не пришло — поставьте новый zip поверх старого, как раньше.

## 0.2.1
- Filmix: пункт сначала даёт Filmix_API подгрузить токен аккаунта, потом открывает поиск. Раньше сразу после включения или сна Filmix_API искал без токена, пока не войдёшь в какой-нибудь раздел его главного меню, и PRO-аккаунт не учитывался.

## 0.2.0
- Пункт FreeZona: открывает фильм или сериал в FreeZona (`free.zona`) по ID Кинопоиска.

## 0.1.1
- Экран «Смотреть в приложениях» перенесён из «Приложений» в «Настройки» → «Приложения».
- Своя иконка экрана плагина.

## 0.1.0
- Первая версия: все пункты отдельных плагинов «Открыть в …» в одном плагине — NUM, Lampa, Prisma, VoKino, LazyMedia, Filmix, Stremio и Nuvio в меню «Смотреть…» карточки каталога «Фильмы». Заменяет `num_supplier` 0.1.4, `lampa_supplier` 0.1.3, `prisma_supplier` 0.1.3, `vokino_supplier` 0.1.3, `lazymedia_supplier` 0.1.3, `filmix_api_supplier` 0.1.3, `stremio_supplier` 0.1.4 и `nuvio_supplier` 0.2.4; пункты работают так же.
- Пункты появляются только для установленных приложений (для Filmix — плагина Filmix_API). Приложение, поставленное или удалённое позже, подхватывается после выхода из режима ожидания или перезагрузки, а сразу — при открытии экрана плагина.
- Экран «Смотреть в приложениях» в «Приложениях»: любой пункт можно скрыть, не удаляя приложение.
