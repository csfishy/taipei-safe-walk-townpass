import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_models.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// 預設地圖中心：臺北市政府（公開地標，只用來開地圖，不代表任何使用者位置）。
const _kDefaultCenter = ll.LatLng(25.0375, 121.5637);

/// 設定／編輯「家」：在地圖上點選位置，按「儲存」才交給 [onSave]（M1 負責存在裝置上）。
/// 目前沒有接地址搜尋，所以只能在地圖上選點。座標不顯示成文字、不寫日誌。
class SafeWalkHomeSettingView extends StatefulWidget {
  const SafeWalkHomeSettingView({
    super.key,
    this.initial,
    required this.onSave,
    this.onClear,
    required this.onBack,
  });

  /// 目前已儲存的家；null 代表第一次設定。
  final LatLng? initial;
  final Future<void> Function(LatLng at) onSave;
  final Future<void> Function()? onClear;
  final VoidCallback onBack;

  @override
  State<SafeWalkHomeSettingView> createState() =>
      _SafeWalkHomeSettingViewState();
}

class _SafeWalkHomeSettingViewState extends State<SafeWalkHomeSettingView> {
  LatLng? _pin;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pin = widget.initial;
  }

  Future<void> _run(Future<void> Function() action, String failMessage) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) widget.onBack();
    } catch (_) {
      // 不把例外內容（可能含座標）顯示或記錄下來。
      if (mounted) setState(() => _error = failMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttribution() async {
    const url = 'https://www.openstreetmap.org/copyright';
    try {
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      // Fixed fallback text never contains the selected location.
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('無法開啟授權說明，請瀏覽 $url')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = _pin;
    final editing = widget.initial != null;
    return Scaffold(
      backgroundColor: SwColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: pin == null
                          ? _kDefaultCenter
                          : ll.LatLng(pin.lat, pin.lng),
                      initialZoom: pin == null ? 14 : 17,
                      minZoom: 3,
                      maxZoom: 19,
                      backgroundColor: SwColors.surface,
                      interactionOptions: const InteractionOptions(
                        flags:
                            InteractiveFlag.pinchZoom |
                            InteractiveFlag.drag |
                            InteractiveFlag.flingAnimation,
                      ),
                      onTap: _busy
                          ? null
                          : (_, at) => setState(
                              () => _pin = LatLng(at.latitude, at.longitude),
                            ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'town_pass',
                        maxNativeZoom: 19,
                        tileProvider: SafeWalkMap.createTileProvider(),
                      ),
                      if (pin != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: ll.LatLng(pin.lat, pin.lng),
                              width: 48,
                              height: 48,
                              alignment: Alignment.topCenter,
                              child: const Icon(
                                Icons.home_rounded,
                                size: 40,
                                color: SwColors.brandText,
                                semanticLabel: '家的位置',
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: SwRoundButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      label: '返回',
                      onTap: () {
                        if (!_busy) widget.onBack();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: SwColors.surface,
              boxShadow: SwShadow.sheet,
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      editing ? '編輯「家」' : '設定「家」',
                      style: SwText.heading,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    pin == null
                        ? '在地圖上點一下你家的位置。目前還不支援輸入地址搜尋。'
                        : '已選擇位置，可再點地圖更換。家的設定儲存在裝置上。',
                    style: SwText.secondary,
                  ),
                  Text(
                    '地圖自動載入 OpenStreetMap 圖磚，服務會收到檢視範圍與 IP；編輯時範圍包含已儲存的家。',
                    style: SwText.secondary,
                  ),
                  TextButton(
                    onPressed: _openAttribution,
                    child: const Text('© OpenStreetMap contributors'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: SwText.bodyStrong.copyWith(color: SwColors.sos),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final save = SwPrimaryButton(
                        label: _busy ? '儲存中…' : '儲存',
                        icon: Icons.check_rounded,
                        onTap: pin == null || _busy
                            ? null
                            : () => _run(
                                () => widget.onSave(pin),
                                '儲存失敗，請再試一次。',
                              ),
                      );
                      if (!editing || widget.onClear == null) {
                        return SizedBox(width: double.infinity, child: save);
                      }
                      return SwButtonPair(
                        first: save,
                        second: SwOutlineButton(
                          icon: Icons.delete_outline_rounded,
                          label: '移除',
                          onTap: _busy
                              ? null
                              : () => _run(widget.onClear!, '移除失敗，請再試一次。'),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
