# Фикстуры

Общие для всех плагинов. Входы bin поставщика (`start_playback_app`, stdin) и список приложений оболочки.

| Файл | Откуда |
|---|---|
| `movie.json` | реальный вход с устройства, `shell_ext.log` 01.10.2026 («Гладиатор 2») |
| `series.json` | реальный вход с устройства, `shell_ext.log` 01.10.2026 («Дом Дракона») |
| `series_no_ids.json` | реальный вход с устройства, `shell_ext.log` 01.10.2026 («Мастера меча онлайн: Алисизация»: только `dunemdb:`, нет `year`) |
| `movie_tmdb_only.json` | `movie.json` без `imdb:` |
| `series_tmdbtv_only.json` | `series.json` без `imdb:` |
| `movie_no_ids.json` | `movie.json` только с `dunemdb:` |
| `series_movie_tmdb_only.json` | `series.json` без `imdb:`, `tmdbtv:` → `tmdb:` |
| `app_data.json` | `/tmp/applications/app_data.json` с устройства, оставлены «Настройки», Nuvio, Stremio и NUM (запись NUM — 02.10.2026) |
| `app_data_no_nuvio.json` | только «Настройки» |
| `app_data_no_stremio.json` | «Настройки» и Nuvio |
| `app_data_no_num.json` | «Настройки», Nuvio и Stremio |

Пустой stdin, мусор и враждебные входы генерирует сам тест.
