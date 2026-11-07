import 'dart:async';

import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;

class _Entry {
  _Entry(this.key, this.caller, this.text);
  final String key;
  final bool caller;
  final String text;
}

enum _Mode { quick, template, input }

/// 模擬來電：只有對方台詞會朗讀（點泡泡重播／再點停止）；自己的回應只顯示文字；「自己輸入」是輸入對方要說的話。
class SafeWalkCallView extends StatefulWidget {
  const SafeWalkCallView({
    super.key,
    required this.position,
    required this.points,
    required this.anomalies,
    required this.speaker,
    required this.onMap,
    required this.onEnd,
    required this.onEmergency,
  });
  final sw.Position? position;
  final List<sw.AssistancePoint> points;
  final List<Anomaly> anomalies;
  final SafeWalkSpeaker speaker;
  final VoidCallback onMap, onEnd, onEmergency;

  @override
  State<SafeWalkCallView> createState() => _SafeWalkCallViewState();
}

class _SafeWalkCallViewState extends State<SafeWalkCallView> {
  int _line = 0;
  final _log = <_Entry>[];
  String? _speaking;
  bool _waiting = false;
  _Mode _mode = _Mode.quick;
  int _seq = 0, _seconds = 0;
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  Timer? _clock, _reply;
  bool _pipLeft = false;

  @override
  void initState() {
    super.initState();
    _say(FakeCallScript.lines[0].text);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
  }

  @override
  void dispose() {
    _clock?.cancel();
    _reply?.cancel();
    widget.speaker.stop();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _speak(_Entry e) {
    setState(() => _speaking = e.key);
    widget.speaker.speak(
      e.text,
      onDone: () {
        if (mounted && _speaking == e.key) setState(() => _speaking = null);
      },
    );
  }

  void _toggle(_Entry e) {
    if (_speaking == e.key) {
      widget.speaker.stop();
      setState(() => _speaking = null);
    } else {
      _speak(e);
    }
  }

  void _say(String text) {
    final e = _Entry('c${_seq++}', true, text);
    setState(() => _log.add(e));
    _speak(e);
    _scrollDown();
  }

  void _respond(String text) {
    if (_waiting) return;
    widget.speaker.stop();
    setState(() {
      _speaking = null;
      _log.add(_Entry('u${_seq++}', false, text));
      _waiting = true;
    });
    _scrollDown();
    final next = FakeCallScript.lines[_line].next;
    _reply = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _line = next;
        _waiting = false;
      });
      _say(FakeCallScript.lines[next].text);
    });
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  });

  @override
  Widget build(BuildContext context) {
    final mm = (_seconds ~/ 60).toString().padLeft(2, '0'), ss = (_seconds % 60).toString().padLeft(2, '0');
    final start = widget.position == null ? DemoGeo.start : LatLng(widget.position!.coordinates.lat, widget.position!.coordinates.lng);
    return Scaffold(
      backgroundColor: SwColors.bg,
      body: Column(
        children: [
          Container(
            color: SwColors.surface,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: SwRoundButton(icon: Icons.arrow_back_ios_new_rounded, label: '返回', onTap: widget.onEnd),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: SwColors.brandDeep),
                        child: Text('家', style: SwText.heading.copyWith(color: SwColors.onDeep)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Semantics(
                              header: true,
                              label: '${FakeCallScript.caller}，模擬來電',
                              child: ExcludeSemantics(child: Text(FakeCallScript.caller, style: SwText.heading)),
                            ),
                            Text('模擬來電・$mm:$ss', style: SwText.secondary.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: SwColors.surface,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const SwMockBadge(text: FakeCallScript.disclosure),
                Text(widget.speaker.available ? '台詞由手機語音朗讀' : '語音尚未配置，只顯示文字', style: SwText.small),
              ],
            ),
          ),
          const Divider(height: 1, color: SwColors.border),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final pipW = (box.maxWidth * .36).clamp(120.0, 180.0);
                final pipH = pipW * 1.35;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: ListView.separated(
                        controller: _scroll,
                        padding: EdgeInsets.fromLTRB(16, pipH + 28, 16, 16),
                        itemCount: _log.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _Bubble(entry: _log[i], speaking: _speaking == _log[i].key, onTap: _log[i].caller ? () => _toggle(_log[i]) : null),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: SwMotion.of(context, 260),
                      curve: SwMotion.curve,
                      top: 12,
                      left: _pipLeft ? 12 : box.maxWidth - pipW - 12,
                      width: pipW,
                      height: pipH,
                      child: GestureDetector(
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v.abs() > 100) setState(() => _pipLeft = v < 0);
                        },
                        child: _Pip(start: start, points: widget.points, anomalies: widget.anomalies, onTap: widget.onMap),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: SwColors.surface,
              border: Border(top: BorderSide(color: SwColors.border)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    for (final (m, label) in [(_Mode.quick, '快速回覆'), (_Mode.template, '完整句子'), (_Mode.input, '自己輸入')])
                      Expanded(
                        child: Semantics(
                          selected: _mode == m,
                          button: true,
                          child: InkWell(
                            onTap: () => setState(() => _mode = m),
                            child: Container(
                              height: swTouch,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: _mode == m ? SwColors.brandDeep : SwColors.border, width: _mode == m ? 3 : 1),
                                ),
                              ),
                              child: Text(label, style: SwText.bodyStrong.copyWith(color: _mode == m ? SwColors.brandDeep : SwColors.textSecondary)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: _replyPanel()),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: SwColors.surface,
              border: Border(top: BorderSide(color: SwColors.border)),
            ),
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
            child: Row(
              children: [
                SwPressable(
                  onTap: widget.onEnd,
                  color: SwColors.surface,
                  pressedColor: SwColors.brandSoft,
                  border: const BorderSide(color: SwColors.border),
                  radius: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: swTouchLarge,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.call_end_rounded, color: SwColors.textSecondary),
                        const SizedBox(width: 8),
                        Text('結束通話', style: SwText.bodyStrong),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                SwSosButton(
                  onTap: () {
                    widget.speaker.stop();
                    widget.onEmergency();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyPanel() {
    Widget option(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SwPressable(
        onTap: _waiting ? null : () => _respond(text),
        color: SwColors.surface,
        pressedColor: SwColors.brandSoft,
        border: BorderSide(color: _waiting ? SwColors.border : SwColors.brand),
        radius: 10,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SizedBox(
          width: double.infinity,
          child: Text(text, style: SwText.bodyStrong.copyWith(color: _waiting ? SwColors.textSecondary : SwColors.brandDeep)),
        ),
      ),
    );
    final wait = _waiting
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('對方回應中，請稍候', style: SwText.secondary),
          )
        : const SizedBox.shrink();
    switch (_mode) {
      case _Mode.quick:
        return Column(children: [wait, for (final r in FakeCallScript.lines[_line].replies) option(r)]);
      case _Mode.template:
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(shrinkWrap: true, children: [wait, for (final t in FakeCallScript.templates) option(t)]),
        );
      case _Mode.input:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('輸入要讓「對方」說的話，送出後會唸出來', style: SwText.secondary),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _draft,
                    style: SwText.body,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                ),
                const SizedBox(width: 8),
                SwPrimaryButton(
                  label: '讓對方說',
                  onTap: _draft.text.trim().isEmpty
                      ? null
                      : () {
                          _say(_draft.text.trim());
                          _draft.clear();
                          setState(() {});
                        },
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry, required this.speaking, required this.onTap});
  final _Entry entry;
  final bool speaking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final caller = entry.caller;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caller ? '對方' : '我',
          style: SwText.small.copyWith(fontWeight: FontWeight.w700, color: caller ? SwColors.textSecondary : SwColors.onDeep),
        ),
        const SizedBox(height: 2),
        Text(
          entry.text,
          style: SwText.heading.copyWith(fontSize: 20, fontWeight: FontWeight.w500, height: 1.5, color: caller ? SwColors.text : SwColors.onDeep),
        ),
        if (caller) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(speaking ? Icons.graphic_eq_rounded : Icons.replay_rounded, size: 18, color: speaking ? SwColors.brandDeep : SwColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                speaking ? '朗讀中・點一下停止' : '點一下重播',
                style: SwText.small.copyWith(color: speaking ? SwColors.brandDeep : SwColors.textSecondary, fontWeight: speaking ? FontWeight.w700 : FontWeight.w400),
              ),
            ],
          ),
        ],
      ],
    );
    const r = Radius.circular(16);
    return Align(
      alignment: caller ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
        child: caller
            ? Semantics(
                liveRegion: speaking,
                child: SwPressable(
                  onTap: onTap,
                  color: SwColors.surface,
                  pressedColor: SwColors.brandSoft,
                  border: BorderSide(color: speaking ? SwColors.secondaryFocus : SwColors.border, width: 2),
                  radius: 16,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: body,
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: SwColors.brandDeep,
                  borderRadius: BorderRadius.only(topLeft: r, topRight: r, bottomLeft: r, bottomRight: Radius.circular(4)),
                ),
                child: body,
              ),
      ),
    );
  }
}

/// 像 Google Maps 縮小時的子母畫面：浮在對話上、可左右滑到另一側，點一下回到完整地圖。
class _Pip extends StatelessWidget {
  const _Pip({required this.start, required this.points, required this.anomalies, required this.onTap});
  final LatLng start;
  final List<sw.AssistancePoint> points;
  final List<Anomaly> anomalies;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meters = routeMeters(DemoGeo.homeRoute);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.25, end: 1),
      duration: SwMotion.of(context, 320),
      curve: SwMotion.curve,
      builder: (_, s, child) => Transform.scale(scale: s, alignment: Alignment.topRight, child: child),
      child: Semantics(
        button: true,
        label: '縮小的地圖，回家約 ${walkMinutes(meters)} 分鐘，點一下回到地圖',
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: SwColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: SwShadow.float),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: ExcludeSemantics(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DemoMap(start: start, points: points, anomalies: anomalies, path: DemoGeo.homeRoute, compact: true),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: SwColors.brandDeep, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          '${walkMinutes(meters)} 分',
                          style: SwText.small.copyWith(color: SwColors.onDeep, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(color: SwColors.surface, shape: BoxShape.circle, boxShadow: SwShadow.card),
                        child: const Icon(Icons.open_in_full_rounded, size: 16, color: SwColors.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
