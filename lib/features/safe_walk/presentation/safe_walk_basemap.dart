import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'offline_basemap_resource.dart';
import 'offline_basemap_loader_stub.dart'
    if (dart.library.io) 'offline_basemap_loader_io.dart'
    as loader;
export 'offline_basemap_resource.dart';

const offlineMapSnapshotDate = '2026-11-11';
const basemapAttribution = '© OpenStreetMap contributors · Protomaps';

bool isInOfflineMapBounds(double lat, double lng) =>
    lat >= 24.95 && lat <= 25.22 && lng >= 121.44 && lng <= 121.68;

/// Shared by the navigation map and the home picker. No network layer is
/// created while the native offline archive is loading or displayed.
class SafeWalkBasemap extends StatefulWidget {
  const SafeWalkBasemap({
    super.key,
    this.onlineProvider,
    this.tileObserver,
    this.forceOnlineForTesting = false,
  });
  final TileProvider Function()? onlineProvider;
  final void Function(TileImage)? tileObserver;
  @visibleForTesting
  final bool forceOnlineForTesting;

  @visibleForTesting
  static Future<OfflineBasemap> Function()? offlineLoaderForTesting;
  @visibleForTesting
  static bool? isWebForTesting;

  @override
  State<SafeWalkBasemap> createState() => _SafeWalkBasemapState();
}

class _SafeWalkBasemapState extends State<SafeWalkBasemap> {
  OfflineBasemap? _offline;
  bool _failed = false;
  bool get _web =>
      widget.forceOnlineForTesting ||
      (SafeWalkBasemap.isWebForTesting ?? kIsWeb);

  @override
  void initState() {
    super.initState();
    if (!_web) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final result =
          await (SafeWalkBasemap.offlineLoaderForTesting?.call() ??
              loader.loadOfflineBasemap());
      if (!mounted) {
        await result.close();
        return;
      }
      setState(() => _offline = result);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    final offline = _offline;
    if (offline != null) unawaited(offline.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final outside = !isInOfflineMapBounds(
      camera.center.latitude,
      camera.center.longitude,
    );
    final online = _web || _failed;
    final message = _web
        ? null
        : _failed
        ? '離線地圖無法載入，已改用線上底圖；目前連不上服務時可能空白'
        : outside
        ? '離線地圖範圍外'
        : _offline == null
        ? '正在準備離線地圖…'
        : '離線底圖：$offlineMapSnapshotDate 快照';
    return Stack(
      children: [
        if (online)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'town_pass',
            maxNativeZoom: 19,
            tileProvider:
                widget.onlineProvider?.call() ?? NetworkTileProvider(),
            errorTileCallback: (tile, error, stack) =>
                widget.tileObserver?.call(tile),
            tileBuilder: widget.tileObserver == null
                ? null
                : (context, child, tile) {
                    widget.tileObserver!(tile);
                    return child;
                  },
          )
        else if (_offline != null && !outside)
          _offline!.layer,
        if (message != null)
          Positioned(
            top: 4,
            left: 4,
            right: 4,
            child: IgnorePointer(
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(message, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
