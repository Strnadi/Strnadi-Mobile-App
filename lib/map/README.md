# Map feature

Start with `screens/map_screen.dart` for map composition and
`state/map_state_controller.dart` for viewport requests and filter changes.
`screens/recording_detail_page.dart` composes the recording detail view.

| Folder | Owns |
| --- | --- |
| `screens` | Page composition, navigation and platform lifecycle |
| `state` | Viewport loading, request identity and camera animation |
| `filters` | User choices, shared defaults and settings UI |
| `layers` | Base-map tiles, grid and server-feature rendering |
| `widgets` | Map controls, legend and cluster picker |
| `search` | Search presentation and coordinate parsing |
| `recording_detail` | Recording playback/download state and detail components |
| `data` | Retained recording parsers and cache helpers |

All startup/reset defaults are defined in `filters/map_filter_defaults.dart`.
HTTP transport and response decoding live in `lib/api`; map widgets receive
typed data from those services. API request/response types are in
`lib/api/models` and do not import the map feature.

Mapy tiles and reverse geocoding use the active Tenant API's `/map` proxy.
The app does not need a Mapy key. Search continues to use Nominatim through
the API client layer.

The viewport endpoint returns partial server features. Do not treat a cached
viewport as a complete offline map. Keep request, account and environment
guards when changing map state or cluster navigation. Recording detail uses
injected repository/audio boundaries so tests do not open SQLite or contact APIs.
