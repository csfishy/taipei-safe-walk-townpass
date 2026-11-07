import 'dart:async';

import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/contracts/safe_walk_navigation_scope.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

/// Live preview consumes M1 state. It never obtains GPS or builds a request.
class SafeWalkLiveMapView extends StatefulWidget {
  const SafeWalkLiveMapView({
    super.key,
    required this.onBack,
    required this.onCall,
    required this.onEmergency,
  });

  final VoidCallback onBack, onCall, onEmergency;

  @override
  State<SafeWalkLiveMapView> createState() => _SafeWalkLiveMapViewState();
}

class _SafeWalkLiveMapViewState extends State<SafeWalkLiveMapView>
    with WidgetsBindingObserver {
  // Initial viewport only. This is never presented as a GPS observation.
  static const _taipeiCenter = LatLng(25.0478, 121.5170);
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  SafeWalkNavigationScope? _navigation;
  sw.Coordinates? _destination;
  String? _inputError, _notice, _previousResultId;
  bool _requested = false, _foreground = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _navigation = SafeWalkNavigationScope.maybeOf(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_foreground) return;
      setState(() => _foreground = true);
      return; // Only the explicit start button can reopen a session.
    }
    if (!_foreground) return;
    _navigation?.onNavigationClosed();
    setState(() {
      _foreground = false;
      _generation++;
      _requested = false;
      _notice = '步行預覽已暫停；回到前景後請按開始或重試。';
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _selectDestination(sw.Coordinates destination) {
    if (!_foreground) return;
    if (_destination?.lat == destination.lat &&
        _destination?.lng == destination.lng) {
      return;
    }
    // Invalidate the old intent before publishing the new selection.
    _navigation?.onDestinationChanged();
    setState(() {
      _generation++;
      _requested = false;
      _destination = destination;
      _inputError = null;
      _notice = '目的地已選擇；尚未定位或查詢路線。';
      _latitude.text = destination.lat.toString();
      _longitude.text = destination.lng.toString();
    });
  }

  void _useCoordinates() {
    final lat = double.tryParse(_latitude.text.trim());
    final lng = double.tryParse(_longitude.text.trim());
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      setState(() => _inputError = '請輸入有效座標：緯度 -90～90，經度 -180～180。');
      return;
    }
    FocusScope.of(context).unfocus();
    _selectDestination(sw.Coordinates(lat: lat, lng: lng));
  }

  void _changeConsent(bool location, bool value) {
    if (!_foreground) return;
    final scope = _navigation;
    if (location) {
      scope?.onLocationConsentChanged?.call(value);
    } else {
      scope?.onRoutingConsentChanged(value);
    }
    if (!value) {
      setState(() {
        _generation++;
        _requested = false;
        _notice = '同意已撤回，已停止這次預覽；不會自動重新查詢。';
      });
    }
  }

  bool _canStart(SafeWalkNavigationScope? scope) =>
      _foreground &&
      _destination != null &&
      scope != null &&
      scope.mode == sw.DataMode.live &&
      scope.liveNavigationAvailable &&
      scope.hasLocationConsent &&
      scope.hasRoutingConsent &&
      scope.onPlanDestination != null &&
      !scope.locationLoading &&
      !scope.routeLoading;

  void _start() {
    final scope = _navigation;
    if (scope == null || !_canStart(scope)) return;
    final destination = _destination!;
    final generation = ++_generation;
    setState(() {
      _requested = true;
      _previousResultId = scope.routeResult?.requestId;
      _notice = null;
    });
    scope.onNavigationOpened();
    unawaited(
      scope.onPlanDestination!(destination).catchError((Object error) {
        if (!mounted || !_foreground || generation != _generation) return;
        setState(() => _notice = '無法完成步行預覽，請重試。');
      }),
    );
  }

  void _cancel() {
    _navigation?.onCancelRoute();
    setState(() {
      _generation++;
      _requested = false;
      _notice = '已取消步行預覽；再次查詢需由你按開始或重試。';
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = _navigation;
    final position = scope?.position?.source == sw.PositionSource.gps
        ? scope!.position
        : null;
    final result =
        _requested &&
            _foreground &&
            scope?.routeResult?.requestId != _previousResultId
        ? scope?.routeResult
        : null;
    final candidate =
        result is sw.RouteSuccess &&
            result.mode == sw.DataMode.live &&
            result.routes.isNotEmpty
        ? result.routes.first
        : null;
    final path = position != null && candidate != null
        ? candidate.geometry.coordinates
              .map((c) => LatLng(c.latitude, c.longitude))
              .toList(growable: false)
        : const <LatLng>[];
    final busy = scope?.locationLoading == true || scope?.routeLoading == true;
    final available =
        scope?.mode == sw.DataMode.live &&
        scope?.liveNavigationAvailable == true &&
        scope?.onPlanDestination != null;
    return Scaffold(
      backgroundColor: SwColors.bg,
      body: SafeArea(
        bottom: false,
        child: _LivePreviewLayout(
          header: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SwRoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  label: '返回',
                  onTap: widget.onBack,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('步行路線預覽', style: SwText.heading),
                  ),
                ),
              ],
            ),
          ),
          content: SingleChildScrollView(
            key: const Key('safe-walk-live-map-list'),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('真實服務預覽・尚未完成實機驗收，非即時導航或安全保證', style: SwText.smallStrong),
                const SizedBox(height: 8),
                Text(
                  position == null
                      ? '尚未定位；目前為臺北地圖視野，不是你的位置。'
                      : '已定位：${position.coordinates.lat.toStringAsFixed(6)}, ${position.coordinates.lng.toStringAsFixed(6)}',
                  style: SwText.body,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 260,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: DemoMap(
                      liveRendering: true,
                      hasStart: position != null,
                      start: position == null
                          ? _taipeiCenter
                          : LatLng(
                              position.coordinates.lat,
                              position.coordinates.lng,
                            ),
                      points: const [],
                      anomalies: const [],
                      path: path,
                      pin: _destination == null
                          ? null
                          : LatLng(_destination!.lat, _destination!.lng),
                      onPick: (at) => _selectDestination(
                        sw.Coordinates(lat: at.lat, lng: at.lng),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '點地圖選目的地，或輸入座標後按「設定目的地」。底圖會向 tile.openstreetmap.org 載入視野圖磚。',
                  style: SwText.small,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _latitude,
                  key: const Key('safe-walk-destination-lat'),
                  style: SwText.body,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '目的地緯度',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _longitude,
                  key: const Key('safe-walk-destination-lng'),
                  style: SwText.body,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: '目的地經度',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwPrimaryButton(label: '設定目的地', onTap: _useCoordinates),
                if (_inputError != null)
                  Text(
                    _inputError!,
                    style: SwText.body.copyWith(color: SwColors.sos),
                  ),
                if (_destination != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '已選目的地：${_destination!.lat.toStringAsFixed(6)}, ${_destination!.lng.toStringAsFixed(6)}',
                      style: SwText.bodyStrong,
                    ),
                  ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  key: const Key('safe-walk-location-consent'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: scope?.hasLocationConsent ?? false,
                  onChanged: scope?.onLocationConsentChanged == null
                      ? null
                      : (value) => _changeConsent(true, value == true),
                  title: Text('同意本次由臺北通取得手機位置', style: SwText.body),
                  subtitle: Text(
                    '按開始或重試才定位；不持續追蹤。系統可能另詢問定位權限。',
                    style: SwText.small,
                  ),
                ),
                CheckboxListTile(
                  key: const Key('safe-walk-routing-consent'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: scope?.hasRoutingConsent ?? false,
                  onChanged: scope == null
                      ? null
                      : (value) => _changeConsent(false, value == true),
                  title: Text(
                    '另同意將精確起點與目的地傳至 routing.openstreetmap.de',
                    style: SwText.body,
                  ),
                  subtitle: Text(
                    '第三方用來計算步行路線；可隨時撤回。定位權限不等於這項同意。',
                    style: SwText.small,
                  ),
                ),
                if (!available)
                  Text('步行路線服務尚未配置；不會使用示範路線補上。', style: SwText.body),
                if (scope?.locationLoading == true)
                  Text('正在取得位置…', style: SwText.bodyStrong),
                if (scope?.routeLoading == true)
                  Text('正在查詢步行路線…', style: SwText.bodyStrong),
                if (scope?.locationError != null)
                  Text(
                    scope!.locationError!,
                    style: SwText.body.copyWith(color: SwColors.sos),
                  ),
                if (scope?.routeError != null)
                  Text(
                    scope!.routeError!,
                    style: SwText.body.copyWith(color: SwColors.sos),
                  ),
                if (_notice != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(_notice!, style: SwText.body),
                  ),
                if (result != null && result.mode != sw.DataMode.live)
                  Text('收到非 Live 路線，已拒絕顯示；請重新開始。', style: SwText.body),
                if (result is sw.RouteFailure &&
                    result.mode == sw.DataMode.live) ...[
                  Text(
                    result.status == sw.RouteFailureStatus.cancelled
                        ? '路線已取消'
                        : '無法取得步行路線',
                    style: SwText.bodyStrong,
                  ),
                  Text(result.reason, style: SwText.body),
                ],
                if (candidate != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '步行距離：${candidate.distanceMeters.round()} 公尺',
                    style: SwText.bodyStrong,
                  ),
                  Text(
                    candidate.durationSeconds == null
                        ? '預估時間：未知'
                        : '預估時間：${(candidate.durationSeconds! / 60).ceil()} 分鐘（Provider 估計）',
                    style: SwText.body,
                  ),
                  Text('路線來源：${candidate.provider}', style: SwText.small),
                  for (final text in candidate.explanations)
                    Text('說明：$text', style: SwText.small),
                ],
                if (result != null && result.mode == sw.DataMode.live)
                  for (final warning in {
                    ...result.warnings,
                    ...?candidate?.warnings,
                  })
                    Text('限制：$warning', style: SwText.small),
                const SizedBox(height: 12),
                SwPrimaryButton(
                  key: const Key('safe-walk-live-start'),
                  label: '開始或重試預覽',
                  onTap: _canStart(scope) ? _start : null,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('safe-walk-live-cancel'),
                  onPressed: scope == null ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, swTouch),
                  ),
                  child: Text(
                    busy ? '取消目前操作' : '取消預覽',
                    style: SwText.bodyStrong,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '僅反映步行路網；不保證治安、照明、無障礙或目前可通行。此預覽不提供逐路口指示。',
                  style: SwText.small,
                ),
              ],
            ),
          ),
          actions: SwActionBar(
            secondary: SwSecondaryAction(
              icon: Icons.phone_in_talk_rounded,
              label: '模擬來電',
              onTap: widget.onCall,
            ),
            onEmergency: widget.onEmergency,
          ),
        ),
      ),
    );
  }
}

/// Tiny landscape/keyboard viewports must be able to scroll header and SOS too.
class _LivePreviewLayout extends StatelessWidget {
  const _LivePreviewLayout({
    required this.header,
    required this.content,
    required this.actions,
  });
  final Widget header, content, actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxHeight < 250
        ? SingleChildScrollView(
            child: Column(children: [header, content, actions]),
          )
        : Column(
            children: [
              header,
              Expanded(child: content),
              actions,
            ],
          ),
  );
}

class SafeWalkUnavailableView extends StatelessWidget {
  const SafeWalkUnavailableView({
    super.key,
    required this.title,
    required this.onBack,
    required this.onEmergency,
  });
  final String title;
  final VoidCallback onBack, onEmergency;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SwColors.bg,
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SwRoundButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  label: '返回',
                  onTap: onBack,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: SwText.heading)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('$title 尚未配置', style: SwText.bodyStrong),
                Text('此功能未接入真實服務；不使用示範資料，也未送出任何回報。', style: SwText.body),
              ],
            ),
          ),
          SwActionBar.single(onEmergency: onEmergency),
        ],
      ),
    ),
  );
}
