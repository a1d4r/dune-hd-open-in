# For plugin developers

[← Back to README](../README.en.md)

Any Dune plugin can get an item of its own in the **Play...** menu of a movie card and search for that title itself. All it needs is the `vod_search` entry in the manifest; the IPTV Channel Editor template files are not needed. The item shows the name and icon from `<caption>` and `<icon_url>` of the manifest.

## How to declare
Add the `vod_search` action to `dune_plugin.xml`:
```xml
<public_actions>
  <action id="vod_search">
    <type>plugin_handle_user_input</type>
    <params>
      <handler_id>entry_handler</handler_id>
      <control_id>external_search</control_id>
    </params>
  </action>
</public_actions>
```

Requirements:
- The plugin's folder name: 1–40 characters of `A-Z a-z 0-9 _ . -`, not starting with `.` or `-`, no `..`. `dune_plugin.xml`: at most 32 KB (32768 bytes).
- `<public_actions>` without attributes: `vod_search` is not read from a node that has them.
- `type`: only `plugin_handle_user_input`.
- `handler_id` and `control_id` are yours, 1–64 characters of `A-Z a-z 0-9 _ . -` each. `handler_id` must not match the play_in_apps handlers: `setup`, `check`, `filmix_api`, `bazinga`, `iptvce_…`.
- Only the first `vod_search` action inside `<public_actions>` counts.

For IPTV Channel Editor builds, `<public_actions>` decides: the node is empty or has no working `vod_search` — there is no item; there is no node at all (an older template version) — the item searches the same way as for other IPTV Channel Editor builds, by the title alone.

The item usually appears about half a minute after the plugin is installed. If it does not, it appears after the Dune wakes from standby or reboots, or when the **Play in apps** screen is opened. If the entry is declared with an error, the [check](screen.en.md#check) on the plugin screen shows the line "the vod_search entry is turned down" and the reason; for an accepted entry the check shows `vod_search`.

## What the plugin receives
When the item is chosen, the Dune calls your plugin's `handle_user_input` with your `handler_id` and `control_id`. `$user_input` also gets these fields:

| Field | What it holds |
|---|---|
| `search` | A JSON string: `{"title":"…","original_title":"…","year":"…"}`. `title` is the card's title in the Dune UI language, `original_title` the original one, `year` the year. Empty fields are left out; at least one of the titles is always there. All values are strings, without spaces at the ends; non-ASCII as `\uXXXX`, parse it with `json_decode`. |
| `movie_str` | The movie card from the Dune shell as is, a JSON string (`json_decode`). The firmware sets its fields and their types: values may be non-strings and `null`, any field may be empty or missing, the set of fields may change with the firmware. Besides the titles and the year it has, for example, `id`, `kp_id`, `imdb_id`, `tmdb_id`, `tmdbtv_id` (a series' TMDB ID), `series_type`, `description`, `poster_url`. There is no list of episodes (a series has `season_numbers` instead of `seasons`), and no chosen season or episode either. |
| `season`, `episode` | Only if the episode was chosen through **Seasons** in the card: strings of digits, both fields together, the numbers as in the Dune catalog. From the main card they are not there. Nor are they for the **About TV series** section in **Seasons**, for seasons without a number in the catalog, or for numbers below 1. |

Take the titles for searching from `search`; `movie_str` is for the rest, for example the IDs. The other fields of `$user_input` come from the Dune shell.

How to search — by one title or both, whether to open the title page right away when there is just one — is up to your plugin.

## Response
The Dune runs the handler's response (a folder, a dialog) as your plugin's. Back from your folder returns to the Dune card.
