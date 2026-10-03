# «Открыть в NUM / Lampa / Prisma / VoKino / LazyMedia / Stremio / Nuvio» для Dune HD

**Русский** | [English](README.en.md)

Плагины для Dune HD: добавляют пункты в меню **«Смотреть…»** карточки фильма или сериала в каталоге **«Фильмы»** Дюны. Каждый пункт открывает тот же фильм или сериал (или его поиск) в приложении для Android TV.

![Меню «Смотреть…» с пунктами плагинов](screenshots/play-menu.png)

| Плагин | Пункт меню | По какому ID открывает | Подробнее |
|---|---|---|---|
| `num_supplier` | NUM | TMDB | [README](plugin/num_supplier/README.md) |
| `lampa_supplier` | Lampa | TMDB | [README](plugin/lampa_supplier/README.md) |
| `prisma_supplier` | Prisma | TMDB | [README](plugin/prisma_supplier/README.md) |
| `vokino_supplier` | VoKino | IMDb, если нет — поиск по названию | [README](plugin/vokino_supplier/README.md) |
| `lazymedia_supplier` | LazyMedia | не открывает по ID, только поиск по названию | [README](plugin/lazymedia_supplier/README.md) |
| `stremio_supplier` | Stremio | IMDb, если нет — TMDB | [README](plugin/stremio_supplier/README.md) |
| `nuvio_supplier` | Nuvio | IMDb, если нет — TMDB | [README](plugin/nuvio_supplier/README.md) |

Плагины независимы: ставьте только нужные. Само приложение нужно установить и настроить (аддоны, аккаунты) отдельно.

Проверено только на Dune HD Pro 8K Plus, прошивка 260827_0003_r24. На других Android-моделях Дюны с прошивкой r24 может работать, но не проверялось.

## Установка
1. Скачайте `dune_plugin_<имя>_<версия>.zip` из [Releases](https://github.com/a1d4r/dune-hd-open-in/releases/latest).
2. Скопируйте его на флешку или во внутреннюю память.
3. На Дюне откройте **«Источники»**, найдите zip и нажмите ENTER.
4. Примерно через полминуты пункт появится в меню **«Смотреть…»**, перезагрузка не нужна.

Обновление — новый zip поверх старого. Удаление — в списке плагинов Дюны.

Плагины не ходят в сеть и ничего не запускают в фоне.

## Сборка из исходников
`sh build.sh <имя>` прогоняет shellcheck и тесты и собирает `dist/dune_plugin_<имя>_<версия>.zip`. Нужны `shellcheck`, `dash` и `zip`; `mksh`, если установлен, используется для второго прогона тестов. Zip в Releases собирает GitHub Actions тем же скриптом.

## Обратная связь
Сделано для своей Дюны и выложено как есть. Об ошибках пишите в [Issues](https://github.com/a1d4r/dune-hd-open-in/issues); исправления — по возможности.

## Лицензия
MIT, см. `LICENSE`.
