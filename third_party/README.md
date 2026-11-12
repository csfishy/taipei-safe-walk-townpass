# Reviewed offline map dependency patches

These are source copies of two fixed pub releases. They are path dependencies,
not dependency overrides. Flutter, flutter_map, latlong2, the renderer and all
other locked versions remain unchanged. No examples, fixtures or API keys are
included. Original LICENSE files are retained and collected by Flutter.

| Package | Version | Original pub archive SHA-256 | License |
|---|---|---|---|
| vector_map_tiles | 9.0.0-beta.13 | 42dce00e0f69352663f4c9c78fe5cc900704f6dd46019640ebda0d84cc14ce68 | BSD-3-Clause |
| vector_map_tiles_mbtiles | 1.2.2 | d0ba9f28583eee8c7f6e224c2e0aec7df6472aefe329ed46c497de9839545bb5 | MIT |

Upstream archives:

- https://pub.dev/api/archives/vector_map_tiles-9.0.0-beta.13.tar.gz
- https://pub.dev/api/archives/vector_map_tiles_mbtiles-1.2.2.tar.gz

The adapter library is unchanged. Its pubspec points to the adjacent patched
vector_map_tiles package so both the adapter and App use the same source.

Only these six vector_map_tiles library files differ from the original release:

- `src/cache/storage_cache.dart`: max-size zero disables reads, writes, existence
  checks and maintenance. The verified local MBTiles is already persistent;
  old unversioned cached tile bytes must not survive a snapshot update.
- `src/cache/vector_tile_loading_cache.dart`: observe all initialization worker
  futures together; cancellation wakes waiting readers without an async-void
  exception. Non-cancellation errors are not swallowed.
- `src/stream/tileset_executor_preprocessor.dart`: same initialization fix for
  the second worker setup stage.
- `src/stream/caches_tile_provider.dart`: check cancellation before scheduling
  work, then await every scheduled future. Do not abandon an erroring future
  when the map leaves or another request cancels it.
- `src/grid/grid_layer.dart`: cancel delayed cache maintenance on disposal.
- `src/cache/byte_storage_idb.dart`: await command result inside try/finally
  so the database is not released before the future completes; resolves the
  original strict-analysis warning exposed by vendoring.

`offline_map_render_test.dart` reproduces immediate exit with the real native
archive and initializes a poisoned legacy cache. Immediate exit failed on the
original release; the cache regression verifies that old bytes are ignored.
No global error suppression, test skip, arbitrary wait before exit,
SDK downgrade or 10.x/flutter_gpu dependency is used. The new dependency source
is included explicitly in both strict CI analysis commands.

To audit or refresh: download and SHA-verify the original archives, extract
outside the checkout, and compare `lib/` and `LICENSE` with these copies (ignore
line-ending differences). Reapply/review the six changes, run strict analysis,
the real native lifecycle tests, the full suite and both native builds. Do not
upgrade the source silently or remove a patch before its regression passes.
