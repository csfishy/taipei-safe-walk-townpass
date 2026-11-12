import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:town_pass/util/tp_colors.dart';

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
    this.onOfflineFallback,
    this.forceOnlineForTesting = false,
  });
  final TileProvider Function()? onlineProvider;
  final void Function(TileImage)? tileObserver;
  final ValueChanged<bool>? onOfflineFallback;
  @visibleForTesting
  final bool forceOnlineForTesting;

  @visibleForTesting
  static Future<OfflineBasemap> Function()? offlineLoaderForTesting;
  static bool get hasOfflineLoaderOverride => offlineLoaderForTesting != null;
  @visibleForTesting
  static bool? isWebForTesting;

  @override
  State<SafeWalkBasemap> createState() => _SafeWalkBasemapState();
}

class _SafeWalkBasemapState extends State<SafeWalkBasemap> {
  OfflineBasemap? _offline;
  TileLayer? _onlineLayer;
  final _retired = <OfflineBasemap>{};
  int _generation = 0;
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
    final generation = ++_generation;
    try {
      final result =
          await (SafeWalkBasemap.offlineLoaderForTesting?.call() ??
              loader.loadOfflineBasemap());
      if (!mounted || generation != _generation) {
        await _release(result);
        return;
      }
      if (result.unavailable?.value == true) {
        await _release(result);
        throw const FormatException('Offline reader unavailable');
      }
      result.unavailable?.addListener(_onUnavailable);
      setState(() => _offline = result);
      widget.onOfflineFallback?.call(false);
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
        widget.onOfflineFallback?.call(true);
      }
    }
  }

  void _onUnavailable() {
    final resource = _offline;
    if (resource == null || resource.unavailable?.value != true) return;
    scheduleMicrotask(() {
      if (!mounted || !identical(resource, _offline)) return;
      resource.unavailable?.removeListener(_onUnavailable);
      setState(() {
        _offline = null;
        _failed = true;
      });
      widget.onOfflineFallback?.call(true);
      // Remove the renderer before closing the database it may still be using.
      _retired.add(resource);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _retired.remove(resource);
        unawaited(_release(resource));
      });
    });
  }

  Future<void> _release(OfflineBasemap resource) async {
    try {
      await resource.close();
    } catch (_) {
      // Cleanup errors must not escape a disposed UI or reveal filesystem paths.
    }
  }

  void _retry() {
    setState(() {
      _failed = false;
      _onlineLayer = null;
    });
    widget.onOfflineFallback?.call(false);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant SafeWalkBasemap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onlineProvider != oldWidget.onlineProvider) _onlineLayer = null;
  }

  @override
  void dispose() {
    _generation++;
    final offline = _offline;
    if (offline != null) {
      offline.unavailable?.removeListener(_onUnavailable);
      unawaited(_release(offline));
    }
    for (final resource in _retired) {
      unawaited(_release(resource));
    }
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
    final bounds = camera.visibleBounds;
    final partial =
        !isInOfflineMapBounds(bounds.south, bounds.west) ||
        !isInOfflineMapBounds(bounds.north, bounds.east);
    final message = _web
        ? null
        : _failed
        ? '離線地圖無法載入，已改用線上底圖；目前連不上服務時可能空白'
        : outside
        ? '離線地圖範圍外'
        : _offline == null
        ? '正在準備離線地圖…'
        : partial
        ? '部分畫面超出離線地圖範圍'
        : '離線底圖：$offlineMapSnapshotDate 快照';
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: TPColors.grayscale200),
        if (online)
          _onlineLayer ??= TileLayer(
            key: UniqueKey(),
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
        else if (_offline != null)
          ClipPath(
            key: const ValueKey('offline-map-coverage'),
            clipper: OfflineMapBoundsClipper(camera),
            child: _offline!.layer,
          ),
        if (message != null)
          Positioned(
            top: 4,
            left: 4,
            right: 4,
            child: IgnorePointer(
              ignoring: !_failed,
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: Theme.of(context).colorScheme.surface
                      .withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_failed && !_web)
                          TextButton(
                            onPressed: _retry,
                            child: const Text('重試離線地圖'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Screen-space coverage mask also works for rotated cameras. Keeping the
/// renderer mounted preserves its work and state while panning across an edge.
class OfflineMapBoundsClipper extends CustomClipper<Path> {
  OfflineMapBoundsClipper(this.camera);
  final MapCamera camera;

  @override
  Path getClip(Size size) {
    final points = [
      const ll.LatLng(25.22, 121.44),
      const ll.LatLng(25.22, 121.68),
      const ll.LatLng(24.95, 121.68),
      const ll.LatLng(24.95, 121.44),
    ].map(camera.latLngToScreenOffset).toList();
    return Path()..addPolygon(points, true);
  }

  @override
  bool shouldReclip(covariant OfflineMapBoundsClipper oldClipper) =>
      oldClipper.camera != camera;
}
