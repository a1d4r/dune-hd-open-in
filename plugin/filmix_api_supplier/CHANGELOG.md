# Changelog

**English version**

## 0.1.3
- A title with a broken character (a lone UTF-16 surrogate) opened the Filmix_API search with an empty query on Dune HD (PHP 5.3). Now it shows the "no title" error, as on newer PHP.

## 0.1.2
- On Dune HD Media Center installed as an app on Android TV devices (e.g. Homatics), the menu item stayed after uninstalling the plugin until reboot. Fixed.

## 0.1.1
- The menu item did not appear on older Android-based Dune models (Realtek RTD1619/RTD1395/RTD1295, Amlogic S905X3 and others, where FS_PREFIX is not set). Fixed: install the new version over the old one.

## 0.1.0
- First version: "Filmix" item with the Filmix_API icon in the "Play..." menu of the Movies catalog card.
- Opens the search of the Filmix_API Dune plugin with the card's title (Filmix_API cannot open a title by IMDb or TMDB ID).
- Clear error messages when Filmix_API is not installed or the card has no title.

---

**Russian version**

## 0.1.3
- Название с битым символом (одиночный суррогат UTF-16) открывало поиск Filmix_API с пустым запросом на Dune HD (PHP 5.3). Теперь — ошибка «нет названия», как на новых PHP.

## 0.1.2
- На Dune HD Media Center, установленном приложением на Android TV (например, Homatics), пункт меню оставался после удаления плагина до перезагрузки. Исправлено.

## 0.1.1
- Пункт меню не появлялся на старых Android-моделях Дюны (Realtek RTD1619/RTD1395/RTD1295, Amlogic S905X3 и др., где не задан FS_PREFIX). Исправлено: установите новую версию поверх старой.

## 0.1.0
- Первая версия: пункт «Filmix» с иконкой Filmix_API в меню «Смотреть…» карточки каталога «Фильмы».
- Открывает поиск плагина Дюны Filmix_API по названию карточки (открыть фильм по IMDb или TMDB Filmix_API не умеет).
- Понятные сообщения, если Filmix_API не установлен или у карточки нет названия.
