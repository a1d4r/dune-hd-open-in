# Open in NUM / Lampa / Prisma / VoKino / LazyMedia / Filmix / Stremio / Nuvio for Dune HD

[Русский](README.md) | **English**

Dune HD plugins that add items to the **Play...** menu of a movie or series card in the Dune **Movies** catalog. Each item opens the same title (or a search for it) in an Android TV app; the Filmix item opens it in the Filmix_API Dune plugin.

![Play... menu with the plugin items](screenshots/play-menu.png)

| Plugin | Menu item | Opens the title by | Details |
|---|---|---|---|
| `num_supplier` | NUM | TMDB ID | [README](plugin/num_supplier/README.en.md) |
| `lampa_supplier` | Lampa | TMDB ID | [README](plugin/lampa_supplier/README.en.md) |
| `prisma_supplier` | Prisma | TMDB ID | [README](plugin/prisma_supplier/README.en.md) |
| `vokino_supplier` | VoKino | IMDb ID, else search by title | [README](plugin/vokino_supplier/README.en.md) |
| `lazymedia_supplier` | LazyMedia | no ID, search by title only | [README](plugin/lazymedia_supplier/README.en.md) |
| `filmix_api_supplier` | Filmix | no ID, search by title in the Filmix_API Dune plugin | [README](plugin/filmix_api_supplier/README.en.md) |
| `stremio_supplier` | Stremio | IMDb ID, else TMDB ID | [README](plugin/stremio_supplier/README.en.md) |
| `nuvio_supplier` | Nuvio | IMDb ID, else TMDB ID | [README](plugin/nuvio_supplier/README.en.md) |

Each plugin is independent: install only the ones you need. The app itself (for Filmix, the Filmix_API plugin) must be installed and set up (addons, accounts) separately.

Tested only on Dune HD Pro 8K Plus, firmware 260827_0003_r24. Other Android Dune models with r24 firmware may work, but this is not tested.

## Install
1. Download `dune_plugin_<name>_<version>.zip` from [Releases](https://github.com/a1d4r/dune-hd-open-in/releases/latest).
2. Copy it to a USB drive or to the internal storage.
3. On the Dune open **Sources**, find the zip and press ENTER.
4. The item appears in the **Play...** menu within half a minute, no reboot needed.

To update, install the new zip over the old one. To remove, uninstall the plugin in the Dune plugin list.

The plugins make no network requests and run nothing in the background.

## Build from source
`sh build.sh <name>` runs shellcheck and the tests, then writes `dist/dune_plugin_<name>_<version>.zip`. Needs `shellcheck`, `dash`, `zip` and `python3`, plus `php` for `filmix_api_supplier` (`PHP=…` for another path; the Dune runs PHP 5.6); `mksh`, if installed, is used for a second test run. The zips in Releases are built by GitHub Actions with the same script.

## Feedback
Made for my own Dune and shared as is. Bug reports are welcome in [Issues](https://github.com/a1d4r/dune-hd-open-in/issues); fixes are best effort.

## License
MIT, see `LICENSE`.
