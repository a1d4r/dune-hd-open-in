# Changelog

**English version**

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
