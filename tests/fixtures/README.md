# Фикстуры

Общие для всех плагинов. Входы bin поставщика (`start_playback_app`, stdin) и список приложений оболочки; для `filmix_api_supplier` — `user_input` обработчика `play_action`.

| Файл | Откуда |
|---|---|
| `movie.json` | реальный вход с устройства, `shell_ext.log` 01.10.2026 («Гладиатор 2») |
| `series.json` | реальный вход с устройства, `shell_ext.log` 01.10.2026 («Дом Дракона») |
| `series_no_ids.json` | реальный вход с устройства, `shell_ext.log` 01.10.2026 («Мастера меча онлайн: Алисизация»: только `dunemdb:`, нет `year`) |
| `movie_tmdb_only.json` | `movie.json` без `imdb:` |
| `series_tmdbtv_only.json` | `series.json` без `imdb:` |
| `movie_no_ids.json` | `movie.json` только с `dunemdb:` |
| `series_movie_tmdb_only.json` | `series.json` без `imdb:`, `tmdbtv:` → `tmdb:` |
| `app_data.json` | `/tmp/applications/app_data.json` с устройства, оставлены «Настройки», Nuvio, Stremio, NUM, VoKino, Lampa, Prisma и LazyMedia Deluxe (запись NUM — 02.10.2026, VoKino, Lampa, Prisma и LazyMedia Deluxe — 03.10.2026) |
| `app_data_no_nuvio.json` | только «Настройки» |
| `app_data_no_stremio.json` | «Настройки» и Nuvio |
| `app_data_no_num.json` | «Настройки», Nuvio и Stremio |
| `app_data_no_vokino.json` | «Настройки», Nuvio, Stremio и NUM |
| `app_data_no_lampa.json` | «Настройки», Nuvio, Stremio, NUM и VoKino |
| `app_data_no_prisma.json` | «Настройки», Nuvio, Stremio, NUM, VoKino и Lampa |
| `app_data_no_lazymedia.json` | «Настройки», Nuvio, Stremio, NUM, VoKino, Lampa и Prisma |
| `play_action_movie.json` | `user_input` обработчика `play_action` («Прошлой ночью в Сохо»): ключи и поля фильма — из лога пробника на устройстве 03.10.2026; значения полей, которые лог не писал, — `null` |
| `play_action_series.json` | то же для сериала («Дом Дракона», нет `kp_id`/`tmdb_id`) |

Пустой stdin, мусор и враждебные входы генерирует сам тест.
