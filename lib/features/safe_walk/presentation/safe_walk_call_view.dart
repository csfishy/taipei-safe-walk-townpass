import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:town_pass/features/safe_walk/presentation/demo_map.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_speaker.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart' as sw;
import 'package:town_pass/util/tp_colors.dart';

class _Entry {
  _Entry(this.key, this.caller, this.text);
  final String key;
  final bool caller;
  final String text;
}

enum _Mode { quick, template, input }

/// 一通模擬來電的進度，由 Flow 保管：從地圖回到通話時接續（不再響鈴、對話與計時不重來）。結束通話或離開安心行時丟棄。
class SafeWalkCallSession {
  bool answered = false;
  int line = 0, seq = 0, seconds = 0;
  final List<_Entry> _log = [];
}

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
    this.session,
    this.routePath = DemoGeo.homeRoute,
    this.routeMinutes,
    this.destination = '家',
    this.routeStatus,
  });

  /// 目前目的地的路線（null＝計算中或失敗，顯示 [routeStatus]）。預設為示範回家路線。
  /// 通話進度；null 時每次都是新的一通。
  final SafeWalkCallSession? session;
  final List<LatLng>? routePath;
  final int? routeMinutes;
  final String destination;
  final String? routeStatus;
  final sw.Position? position;
  final List<sw.AssistancePoint> points;
  final List<Anomaly> anomalies;
  final SafeWalkSpeaker speaker;
  final VoidCallback onMap, onEnd, onEmergency;

  @override
  State<SafeWalkCallView> createState() => SafeWalkCallViewState();
}

class SafeWalkCallViewState extends State<SafeWalkCallView> {
  late final SafeWalkCallSession _s = widget.session ?? SafeWalkCallSession();
  List<_Entry> get _log => _s._log;
  String? _speaking;
  bool _waiting = false;
  _Mode _mode = _Mode.quick;
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  Timer? _clock, _reply, _buzz;

  /// 先響鈴：按「接聽」才開始對話與計時；「拒絕」直接離開。已接聽過的通話（從地圖回來）不再響鈴。
  late bool _ringing = !_s.answered;

  /// 臺北通尚未配置語音時，用無聲示範（依字數計時）呈現播放樣式；不呼叫 M1／M5 的喇叭。
  late final SafeWalkSpeaker _voice = widget.speaker.available ? widget.speaker : PreviewSpeaker();

  /// 已離開（或正在離開）此畫面；之後的計時器、朗讀與 onDone 一律忽略。
  bool _left = false;

  /// 每次離開遞增，讓離開前排進來的朗讀完成回呼失效。
  int _gen = 0;

  /// 離開意圖發生時呼叫（含 SOS）：同步取消回覆計時器與時鐘、停止朗讀。換頁動畫期間舊頁仍 mounted，也不會再朗讀。
  void leave() {
    if (_left) return;
    _left = true;
    _gen++;
    _reply?.cancel();
    _clock?.cancel();
    _buzz?.cancel();
    _voice.stop();
    if (!identical(_voice, widget.speaker)) widget.speaker.stop();
  }

  void _leaveThen(VoidCallback go) {
    leave();
    go();
  }

  @override
  void initState() {
    super.initState();
    if (!_ringing) {
      _startClock();
      // 離開前已回覆、對方還沒回：接續回覆。
      if (_log.isNotEmpty && !_log.last.caller) _scheduleReply();
      _scrollDown(jump: true);
      return;
    }
    // 響鈴時手機震動（網頁沒有震動）；鈴聲音檔需另外核准，先不播放。
    HapticFeedback.vibrate();
    _buzz = Timer.periodic(const Duration(milliseconds: 1500), (_) => HapticFeedback.vibrate());
  }

  void _startClock() => _clock = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted && !_left) setState(() => _s.seconds++);
  });

  void _answer() {
    if (_left || !_ringing) return;
    _buzz?.cancel();
    _s.answered = true;
    setState(() => _ringing = false);
    _say(FakeCallScript.lines[0].text);
    _startClock();
  }

  @override
  void dispose() {
    leave();
    _clock?.cancel();
    _reply?.cancel();
    _voice.stop();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _speak(_Entry e) {
    if (_left) return;
    final gen = _gen;
    setState(() => _speaking = e.key);
    _voice.speak(
      e.text,
      onDone: () {
        if (!mounted || _left || gen != _gen) return;
        if (_speaking == e.key) setState(() => _speaking = null);
      },
    );
  }

  void _toggle(_Entry e) {
    if (_speaking == e.key) {
      _gen++;
      _voice.stop();
      setState(() => _speaking = null);
    } else {
      _speak(e);
    }
  }

  void _say(String text) {
    if (_left) return;
    final e = _Entry('c${_s.seq++}', true, text);
    setState(() => _log.add(e));
    _speak(e);
    _scrollDown();
  }

  void _respond(String text) {
    if (_waiting || _left) return;
    _voice.stop();
    setState(() {
      _speaking = null;
      _log.add(_Entry('u${_s.seq++}', false, text));
      _waiting = true;
    });
    _scrollDown();
    _scheduleReply();
  }

  void _scheduleReply() {
    _waiting = true;
    final next = FakeCallScript.lines[_s.line].next;
    _reply = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || _left) return;
      setState(() {
        _s.line = next;
        _waiting = false;
      });
      _say(FakeCallScript.lines[next].text);
    });
  }

  void _scrollDown({bool jump = false}) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_left || !_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    jump ? _scroll.jumpTo(end) : _scroll.animateTo(end, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  });

  @override
  Widget build(BuildContext context) {
    if (_ringing) {
      return _Incoming(onAnswer: _answer, onDecline: () => _leaveThen(widget.onEnd), onEmergency: () => _leaveThen(widget.onEmergency));
    }
    final mm = (_s.seconds ~/ 60).toString().padLeft(2, '0'), ss = (_s.seconds % 60).toString().padLeft(2, '0');
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
                        child: SwRoundButton(icon: Icons.arrow_back_ios_new_rounded, label: '返回', onTap: () => _leaveThen(widget.onEnd)),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: SwColors.brand),
                        child: Text('家', style: SwText.heading.copyWith(color: SwColors.onBrand)),
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
                Text(widget.speaker.available ? '台詞由手機語音朗讀' : '語音尚未配置，播放為無聲示範', style: SwText.small),
              ],
            ),
          ),
          const Divider(height: 1, color: SwColors.border),
          // 邊聊邊看路：上方固定一條「下一步」導航（小地圖＋下一步怎麼走），對話在下面捲動，互不遮擋。
          _NextStep(
            start: widget.routePath?.firstOrNull ?? start,
            path: widget.routePath,
            minutes: widget.routeMinutes,
            destination: widget.destination,
            status: widget.routeStatus,
            points: widget.points,
            anomalies: widget.anomalies,
            onTap: () => _leaveThen(widget.onMap),
          ),
          const Divider(height: 1, color: SwColors.border),
          Expanded(
            child: ListView.separated(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: _log.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _Bubble(entry: _log[i], speaking: _speaking == _log[i].key, silent: !widget.speaker.available, onTap: _log[i].caller ? () => _toggle(_log[i]) : null),
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
                                  bottom: BorderSide(color: _mode == m ? SwColors.brand : SwColors.border, width: _mode == m ? 3 : 1),
                                ),
                              ),
                              child: Text(label, style: SwText.bodyStrong.copyWith(color: _mode == m ? SwColors.brandText : SwColors.textSecondary)),
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
          SwActionBar(
            secondary: SwSecondaryAction(icon: Icons.call_end_rounded, label: '結束通話', onTap: () => _leaveThen(widget.onEnd)),
            onEmergency: () => _leaveThen(widget.onEmergency),
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
          child: Text(text, style: SwText.bodyStrong.copyWith(color: _waiting ? SwColors.textSecondary : SwColors.brandText)),
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
        return Column(children: [wait, for (final r in FakeCallScript.lines[_s.line].replies) option(r)]);
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
  const _Bubble({required this.entry, required this.speaking, required this.onTap, this.silent = false});
  final _Entry entry;
  final bool speaking;

  /// 臺北通尚未配置語音：播放樣式照樣呈現，但文字註明是無聲示範。
  final bool silent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final caller = entry.caller;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(caller ? '對方' : '我', style: SwText.smallStrong.copyWith(color: caller ? SwColors.textSecondary : SwColors.onBrand)),
        const SizedBox(height: 2),
        Text(entry.text, style: SwText.heading.copyWith(height: 1.5, color: caller ? SwColors.text : SwColors.onBrand)),
        if (caller) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(speaking ? Icons.graphic_eq_rounded : Icons.replay_rounded, size: 18, color: speaking ? SwColors.brand : SwColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                speaking ? (silent ? '播放中（無聲示範）・點一下停止' : '朗讀中・點一下停止') : '點一下重播',
                style: (speaking ? SwText.smallStrong : SwText.small).copyWith(color: speaking ? SwColors.brandText : SwColors.textSecondary),
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
                  color: SwColors.brand,
                  borderRadius: BorderRadius.only(topLeft: r, topRight: r, bottomLeft: r, bottomRight: Radius.circular(4)),
                ),
                child: body,
              ),
      ),
    );
  }
}

/// 上方導航條：左邊小地圖（點了回到地圖），右邊寫下一步怎麼走與剩餘時間。示範路線，非即時導航。
class _NextStep extends StatelessWidget {
  const _NextStep({
    required this.start,
    required this.path,
    required this.minutes,
    required this.destination,
    required this.status,
    required this.points,
    required this.anomalies,
    required this.onTap,
  });
  final LatLng start;
  final List<LatLng>? path;
  final int? minutes;
  final String destination;
  final String? status;
  final List<sw.AssistancePoint> points;
  final List<Anomaly> anomalies;
  final VoidCallback onTap;
  static const _turn = {StepDir.north: 0.0, StepDir.east: .25, StepDir.south: .5, StepDir.west: .75};

  @override
  Widget build(BuildContext context) {
    final route = path ?? const <LatLng>[];
    final steps = route.length < 2 ? <RouteStep>[] : routeSteps(route);
    final now = steps.firstOrNull;
    final dest = destination == '家' ? '回家' : '到$destination';
    final then = steps.length > 1 ? '接著往${stepDirLabel[steps[1].dir]}' : '接著抵達$destination';
    final mins = minutes ?? walkMinutes(routeMeters(route));
    final headline = now == null ? (status ?? '還沒有路線') : '往${stepDirLabel[now.dir]}走 ${now.meters} 公尺';
    final sub = now == null ? '點一下打開地圖看詳情' : '$then・$dest約 $mins 分';
    return Material(
      color: SwColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: now == null ? '$headline，點一下打開地圖' : '下一步：$headline，$then。$dest約 $mins 分鐘。點一下打開地圖',
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SwColors.border),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DemoMap(start: start, points: points, anomalies: anomalies, path: route, compact: true),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(color: SwColors.surface, shape: BoxShape.circle, boxShadow: SwShadow.card),
                            child: const Icon(Icons.open_in_full_rounded, size: 14, color: SwColors.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: SwColors.brand, shape: BoxShape.circle),
                    child: now == null
                        ? const Icon(Icons.route_outlined, color: SwColors.onBrand, size: 24)
                        : RotationTransition(
                            turns: AlwaysStoppedAnimation(_turn[now.dir]!),
                            child: const Icon(Icons.arrow_upward_rounded, color: SwColors.onBrand, size: 26),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(headline, style: SwText.heading),
                        Text(sub, style: SwText.secondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 響鈴畫面：臺北通主色底（primary500，配深色字）、頭像外一圈圈擴散的光圈，下方「拒絕」「接聽」。
class _Incoming extends StatefulWidget {
  const _Incoming({required this.onAnswer, required this.onDecline, required this.onEmergency});
  final VoidCallback onAnswer, onDecline, onEmergency;
  @override
  State<_Incoming> createState() => _IncomingState();
}

class _IncomingState extends State<_Incoming> with SingleTickerProviderStateMixin {
  // 響約 18 秒後光圈停住（真手機也不會無限響）；系統關閉動畫時不擴散。
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));

  @override
  void initState() {
    super.initState();
    _ring(12);
  }

  Future<void> _ring(int times) async {
    for (var i = 0; i < times && mounted; i++) {
      await _pulse.forward(from: 0).orCancel.catchError((_) {});
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _button({required IconData icon, required String label, required Color bg, required Color fg, required VoidCallback onTap, double size = 72}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        button: true,
        label: label,
        child: SwPressable(
          onTap: onTap,
          color: bg,
          pressedColor: bg.withValues(alpha: .8),
          radius: size / 2,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: fg, size: size * .42),
          ),
        ),
      ),
      const SizedBox(height: 8),
      ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Text(label, style: SwText.bodyStrong.copyWith(color: SwColors.onBrand)),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Scaffold(
      backgroundColor: TPColors.primary500,
      body: Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [TPColors.primary400, TPColors.primary500]),
              ),
              child: SafeArea(
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, box) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: TPColors.white.withValues(alpha: .5), borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                '模擬來電・不是真人通話，也沒有報警',
                                textAlign: TextAlign.center,
                                style: SwText.small.copyWith(color: SwColors.onBrand),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Semantics(
                              liveRegion: true,
                              label: '家人來電中',
                              child: ExcludeSemantics(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: 200,
                                      height: 200,
                                      child: AnimatedBuilder(
                                        animation: _pulse,
                                        builder: (_, child) => CustomPaint(painter: _Rings(still ? 0 : _pulse.value), child: child),
                                        child: Center(
                                          child: Container(
                                            width: 104,
                                            height: 104,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(color: TPColors.white, shape: BoxShape.circle, boxShadow: SwShadow.float),
                                            child: Text('家', style: SwText.display.copyWith(color: TPColors.primary700)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text('家人', style: SwText.display.copyWith(color: SwColors.onBrand)),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.vibration_rounded, color: SwColors.onBrand, size: 20),
                                        const SizedBox(width: 6),
                                        Text('來電中…', style: SwText.body.copyWith(color: SwColors.onBrand)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _button(icon: Icons.call_end_rounded, label: '拒絕', bg: TPColors.white.withValues(alpha: .5), fg: SwColors.onBrand, onTap: widget.onDecline),
                                _button(icon: Icons.call_rounded, label: '接聽', bg: TPColors.white, fg: SwColors.brandText, onTap: widget.onAnswer, size: 84),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SwActionBar.single(onEmergency: widget.onEmergency),
        ],
      ),
    );
  }
}

/// 從頭像往外擴散、逐漸變淡的兩圈光圈。
class _Rings extends CustomPainter {
  const _Rings(this.t);
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final k in [0.0, .5]) {
      final p = (t + k) % 1;
      canvas.drawCircle(c, 52 + 48 * p, Paint()..color = TPColors.white.withValues(alpha: .28 * (1 - p)));
    }
  }

  @override
  bool shouldRepaint(_Rings old) => old.t != t;
}
