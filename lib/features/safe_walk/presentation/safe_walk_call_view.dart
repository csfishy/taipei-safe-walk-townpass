import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/companion_dialogues.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/companion_scenarios.dart';
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

/// 一通模擬來電的進度，由 Flow 保管。結束通話、緊急求助或回首頁時丟棄。
class SafeWalkCallSession {
  bool answered = false;

  /// M5 陪伴劇本 id；null 時用第一個劇本。接聽前可在響鈴畫面切換。
  String? scenarioId;
  int line = 0, seq = 0, seconds = 0;

  /// 已進入最後一句男性台詞，不再要求使用者回覆。
  bool finished = false;
  final List<_Entry> _log = [];
}

/// 模擬來電：三段英文男性角色台詞由 TTS 朗讀，兩段繁中台詞顯示供使用者照讀。
class SafeWalkCallView extends StatefulWidget {
  const SafeWalkCallView({super.key, required this.speaker, required this.onEnd, required this.onEmergency, this.session});

  /// 通話進度；null 時每次都是新的一通。
  final SafeWalkCallSession? session;
  final SafeWalkSpeaker speaker;
  final VoidCallback onEnd, onEmergency;

  @override
  State<SafeWalkCallView> createState() => SafeWalkCallViewState();
}

class SafeWalkCallViewState extends State<SafeWalkCallView> with WidgetsBindingObserver {
  late final SafeWalkCallSession _s = widget.session ?? SafeWalkCallSession();
  List<_Entry> get _log => _s._log;
  String? _speaking;
  bool _waiting = false;
  _Mode _mode = _Mode.quick;

  /// 回覆區（快速回覆／完整句子／自己輸入）可收合，讓對話多露出一點。
  bool _panelOpen = true;
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  Timer? _clock, _reply, _buzz;

  /// 先響鈴：按「接聽」才開始對話與計時；「拒絕」直接離開。已接聽過的通話（從地圖回來）不再響鈴。
  late bool _ringing = !_s.answered;

  /// 臺北通尚未配置語音時，用無聲示範（依字數計時）呈現播放樣式；不呼叫 M1／M5 的喇叭。
  final SafeWalkSpeaker _preview = PreviewSpeaker();
  late SafeWalkSpeaker _voice;
  bool _foreground = true;

  /// 已離開（或正在離開）此畫面；之後的計時器、朗讀與 onDone 一律忽略。
  bool _left = false;

  /// 每次朗讀或中斷遞增，讓上一輪排進來的完成回呼失效。
  int _gen = 0;

  bool get _active => !_left && _foreground;

  /// 鈴聲（speaker 支援時）：接聽、拒絕、離開、背景與 SOS 都要停。
  void _stopRing() {
    final ringer = widget.speaker;
    if (ringer is SafeWalkRinger) (ringer as SafeWalkRinger).stopRing();
  }

  void _stopTurn() {
    _gen++;
    _reply?.cancel();
    _reply = null;
    _voice.stop();
    if (!identical(_voice, widget.speaker)) widget.speaker.stop();
    _speaking = null;
    _waiting = false;
  }

  void _refreshVoice() {
    final next = widget.speaker.available ? widget.speaker : _preview;
    if (identical(next, _voice)) return;
    _stopTurn();
    _voice = next;
  }

  /// 離開意圖發生時呼叫（含 SOS）：同步取消回覆計時器與時鐘、停止朗讀。換頁動畫期間舊頁仍 mounted，也不會再朗讀。
  void leave() {
    if (_left) return;
    _left = true;
    _stopRing();
    _stopTurn();
    _clock?.cancel();
    _buzz?.cancel();
  }

  void _leaveThen(VoidCallback go) {
    leave();
    go();
  }

  @override
  void initState() {
    super.initState();
    _voice = widget.speaker.available ? widget.speaker : _preview;
    _foreground = WidgetsBinding.instance.lifecycleState == null || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    if (!_foreground) return;
    if (!_ringing) {
      _startClock();
      // 離開前已回覆、對方還沒回：接續回覆。
      if (_log.isNotEmpty && !_log.last.caller) _scheduleReply();
      _scrollDown(jump: true);
      return;
    }
    // 響鈴時手機震動（網頁沒有震動）；鈴聲由 speaker 以程式合成的原創音播放（模擬提示音）。
    final ringer = widget.speaker;
    if (ringer is SafeWalkRinger) (ringer as SafeWalkRinger).startRing();
    HapticFeedback.vibrate();
    // 跟光圈一樣響約 18 秒就停（12 次 × 1.5 秒），不會一直震。
    _buzz = Timer.periodic(const Duration(milliseconds: 1500), (t) {
      HapticFeedback.vibrate();
      if (t.tick >= 11) t.cancel();
    });
  }

  @override
  void didUpdateWidget(covariant SafeWalkCallView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshVoice();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_left) return;
    if (state == AppLifecycleState.resumed) {
      if (_foreground) return;
      _foreground = true;
      _refreshVoice();
      if (!_ringing) _startClock();
    } else {
      _foreground = false;
      _stopRing();
      _stopTurn();
      _clock?.cancel();
      _buzz?.cancel();
    }
    if (mounted) setState(() {});
  }

  sw.CompanionScenario get _scenario => m5CompanionScenarios.firstWhere((c) => c.id == _s.scenarioId, orElse: () => m5CompanionScenarios.first);

  /// 最後一句男性台詞已排入；不代表裝置已完成播放。
  bool get _scriptDone => _s.finished;

  List<String> get _replies => companionReplies[_scenario.id]?.elementAtOrNull(_s.line) ?? const ['好。'];

  Future<void> _pickScenario() async {
    final current = _scenario.id;
    final options = [for (final c in m5CompanionScenarios) (c.id, c.label, '一問一答，${c.steps.length} 句')];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SwColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              Semantics(header: true, child: Text('選擇通話情境', style: SwText.heading)),
              const SizedBox(height: 4),
              Text('選一個跟你現在情況相近的劇本。模擬通話，未聯絡任何人。', style: SwText.small),
              const SizedBox(height: 12),
              for (final (id, label, desc) in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SwPressable(
                    onTap: () => Navigator.of(sheet).pop(id),
                    selected: id == current,
                    color: id == current ? SwColors.brandSoft : SwColors.bg,
                    border: BorderSide(color: id == current ? SwColors.brand : SwColors.border),
                    radius: 10,
                    semanticsLabel: '$label，$desc${id == current ? '，目前選擇' : ''}',
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: SwText.bodyStrong),
                              Text(desc, style: SwText.small),
                            ],
                          ),
                        ),
                        if (id == current) const Icon(Icons.check_rounded, color: SwColors.brand),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted && !_left) setState(() => _s.scenarioId = picked);
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _active) setState(() => _s.seconds++);
    });
  }

  void _answer() {
    if (!_active || !_ringing) return;
    _buzz?.cancel();
    _stopRing();
    _s.answered = true;
    setState(() => _ringing = false);
    _s.line = 0;
    _say(_scenario.steps.first.text);
    _startClock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    leave();
    _clock?.cancel();
    _reply?.cancel();
    _voice.stop();
    _draft.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _speak(_Entry e, {VoidCallback? onDone}) {
    if (!_active) return;
    _refreshVoice();
    final gen = ++_gen;
    setState(() => _speaking = e.key);
    _voice.speak(
      e.text,
      onDone: () {
        if (!mounted || !_active || gen != _gen) return;
        if (_speaking == e.key) setState(() => _speaking = null);
        onDone?.call();
      },
    );
  }

  void _toggle(_Entry e) {
    if (!_active) return;
    final wasSpeaking = _speaking == e.key;
    setState(_stopTurn);
    if (!wasSpeaking) _speak(e);
  }

  void _say(String text, {VoidCallback? onDone}) {
    if (!_active) return;
    final e = _Entry('c${_s.seq++}', true, text);
    setState(() => _log.add(e));
    _speak(e, onDone: onDone);
    _scrollDown();
  }

  void _respond(String text, {bool sentence = false}) {
    if (_waiting || !_active) return;
    _stopTurn();
    setState(() {
      _speaking = null;
      _log.add(_Entry('u${_s.seq++}', false, text));
    });
    _scrollDown();
    final ack = sentence ? callTemplateAcks[text] ?? '嗯嗯，好。' : null;
    if (ack == null) {
      _scheduleReply();
      return;
    }
    // 完整句子不是針對這一句台詞寫的：對方先回應你說的話，再接劇本下一句。
    setState(() => _waiting = true);
    _reply = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || !_active) return;
      _say(ack, onDone: () {
        if (_s.finished) {
          setState(() => _waiting = false);
        } else {
          _scheduleReply(delay: Duration.zero);
        }
      });
    });
  }

  /// 你回完之後，對方隔一下接下一句；劇本說完就不再接話。
  void _scheduleReply({Duration delay = const Duration(milliseconds: 900)}) {
    if (!_active) return;
    final steps = _scenario.steps;
    if (_s.line + 1 >= steps.length) {
      setState(() {
        _s.finished = true;
        _waiting = false;
      });
      return;
    }
    _waiting = true;
    _reply = Timer(delay, () {
      if (!mounted || !_active) return;
      setState(() {
        _s.line++;
        _s.finished = _s.line == steps.length - 1;
        _waiting = false;
      });
      _say(steps[_s.line].text);
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
      return _Incoming(scenarioLabel: _scenario.label, onPickScenario: _pickScenario, onAnswer: _answer, onDecline: () => _leaveThen(widget.onEnd), onEmergency: () => _leaveThen(widget.onEmergency));
    }
    final mm = (_s.seconds ~/ 60).toString().padLeft(2, '0'), ss = (_s.seconds % 60).toString().padLeft(2, '0');
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
                        child: Text('家', style: SwText.bodyStrong.copyWith(color: SwColors.onBrand)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Semantics(
                              header: true,
                              label: '$callerName，模擬來電',
                              child: ExcludeSemantics(child: Text(callerName, style: SwText.bodyStrong)),
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
                SwMockBadge(text: _scenario.disclosure),
                Text('情境：${_scenario.label}', style: SwText.smallStrong),
                Text(widget.speaker.available ? '台詞由手機語音朗讀' : '語音尚未配置，播放為無聲示範', style: SwText.small),
              ],
            ),
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
                    for (final (m, label) in [(_Mode.quick, '照著說')])
                      Expanded(
                        child: Semantics(
                          selected: _panelOpen && _mode == m,
                          button: true,
                          child: InkWell(
                            onTap: () => setState(() {
                              _mode = m;
                              _panelOpen = true;
                            }),
                            child: Container(
                              height: swTouch,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: _panelOpen && _mode == m ? SwColors.brand : SwColors.border, width: _panelOpen && _mode == m ? 3 : 1),
                                ),
                              ),
                              child: Text(label, style: SwText.bodyStrong.copyWith(color: _panelOpen && _mode == m ? SwColors.brandText : SwColors.textSecondary)),
                            ),
                          ),
                        ),
                      ),
                    Tooltip(
                      message: _panelOpen ? '收合回覆區' : '展開回覆區',
                      child: InkWell(
                        onTap: () => setState(() => _panelOpen = !_panelOpen),
                        child: Container(
                          width: swTouch,
                          height: swTouch,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: SwColors.border)),
                          ),
                          child: Icon(_panelOpen ? Icons.expand_more_rounded : Icons.expand_less_rounded, color: SwColors.textSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: SwMotion.of(context, 200),
                  curve: SwMotion.curve,
                  alignment: Alignment.topCenter,
                  child: _panelOpen ? Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: _replyPanel()) : const SizedBox(width: double.infinity),
                ),
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
        onTap: _waiting ? null : () => _respond(text, sentence: _mode == _Mode.template),
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
    final note = _waiting || _scriptDone
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_waiting ? '對方回應中，請稍候' : '已到劇本最後一句；如仍有危險，請立即求助', style: SwText.secondary),
          )
        : const SizedBox.shrink();
    switch (_mode) {
      case _Mode.quick:
        return Column(
          children: [
            note,
            if (!_scriptDone && !_waiting)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('請看著螢幕，大聲說出以下台詞，再點一下繼續', style: SwText.secondary),
              ),
            if (!_scriptDone)
              for (final r in _replies) option(r),
          ],
        );
      case _Mode.template:
        if (callTemplates.isEmpty) return Column(children: [note]);
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView(shrinkWrap: true, children: [note, for (final t in callTemplates) option(t)]),
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
                          _stopTurn();
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
        Text(entry.text, style: SwText.body.copyWith(color: caller ? SwColors.text : SwColors.onBrand)),
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

/// 響鈴畫面：臺北通主色底（primary500，配深色字）、頭像外一圈圈擴散的光圈，下方「拒絕」「接聽」。
class _Incoming extends StatefulWidget {
  const _Incoming({required this.scenarioLabel, required this.onPickScenario, required this.onAnswer, required this.onDecline, required this.onEmergency});
  final String scenarioLabel;
  final VoidCallback onPickScenario, onAnswer, onDecline, onEmergency;
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
                              decoration: BoxDecoration(color: SwColors.brandDeep, borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                '模擬來電・不是真人通話，也沒有報警',
                                textAlign: TextAlign.center,
                                style: SwText.small.copyWith(color: SwColors.onBrand),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Semantics(
                              liveRegion: true,
                              label: '$callerName 來電中',
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
                                            child: Text('男', style: SwText.title.copyWith(color: TPColors.primary700)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(callerName, style: SwText.title.copyWith(color: SwColors.onBrand)),
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
                            const SizedBox(height: 20),
                            SwChip(label: '情境：${widget.scenarioLabel}', icon: Icons.tune_rounded, onTap: widget.onPickScenario),
                            const SizedBox(height: 28),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _button(icon: Icons.call_end_rounded, label: '拒絕', bg: SwColors.brandDeep, fg: TPColors.white, onTap: widget.onDecline),
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
