import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_ui.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;
import 'package:town_pass/util/tp_colors.dart';

/// An emergency alert addressed to this person as a nearby helper. It carries
/// no sender identity: the backend never reveals who pressed SOS.
final class SafeWalkNearbyAlert {
  const SafeWalkNearbyAlert({
    required this.alertId,
    required this.location,
    required this.createdAt,
    this.fromContact = false,
    this.senderName,
  });

  final String alertId;
  final sw.Coordinates location;
  final DateTime createdAt;

  /// True when the sender is someone who paired with this person as a trusted
  /// contact; [senderName] is then the name they chose. For a nearby helper
  /// both stay empty: the sender is never revealed.
  final bool fromContact;
  final String? senderName;
}

/// One of this person's own trusted contacts. Who they are is not revealed.
final class SafeWalkContactLink {
  const SafeWalkContactLink({required this.id, required this.since});
  final String id;
  final DateTime since;
}

/// Someone this person is a trusted contact of, by the name they chose.
final class SafeWalkFollowing {
  const SafeWalkFollowing({
    required this.id,
    required this.name,
    required this.since,
  });
  final String id;
  final String name;
  final DateTime since;
}

/// A one-time code for pairing a trusted contact. Shown once.
final class SafeWalkContactInvite {
  const SafeWalkContactInvite({required this.code, required this.expiresAt});
  final String code;
  final DateTime expiresAt;
}

/// A place where this person asked to be notified about SOS alerts. The centre
/// is stored rounded to about 100 m.
final class SafeWalkGuardArea {
  const SafeWalkGuardArea({required this.center, required this.radiusMeters});

  final sw.Coordinates center;
  final int radiusMeters;
}

/// What the screens need from the helper side of "notify people nearby".
/// M1 implements it; M3 only presents it. Alerts are delivered inside the app
/// while it is open; there is no push, so nothing arrives when it is closed.
abstract interface class SafeWalkNearbyHelper implements Listenable {
  /// Non-null means joining cannot work right now (backend not set up or unreachable, no identity
  /// configured). The card shows it and offers no button.
  String? get unavailableReason;

  bool get isOn;
  bool get isBusy;

  /// The latest status or failure, in words the person can act on.
  String? get message;
  bool get messageIsError;

  /// Alerts not yet dismissed, newest first.
  List<SafeWalkNearbyAlert> get incoming;

  /// Whether the backend stores guard areas; the card shows that section only
  /// when it does.
  bool get guardAreasSupported;

  /// This person's guard areas (at most 3), as stored.
  List<SafeWalkGuardArea> get guardAreas;

  /// Reads the current position, after the person confirmed, and adds a guard
  /// area there with [radiusMeters] (500 or 1000).
  Future<void> addGuardAreaHere(int radiusMeters);

  Future<void> removeGuardArea(int index);

  /// Whether the backend can pair trusted contacts; the contacts card is shown
  /// only when it can.
  bool get contactsSupported;

  /// Contact operations have their own progress and message, separate from the
  /// helper card's.
  bool get contactsBusy;
  String? get contactsMessage;
  bool get contactsMessageIsError;

  /// People who will be notified in the app when this person sends an SOS.
  List<SafeWalkContactLink> get myContacts;

  /// People this person is a trusted contact of.
  List<SafeWalkFollowing> get following;

  /// The code just made, until [clearInvite].
  SafeWalkContactInvite? get invite;

  /// Makes a one-time code. [displayName] is how this person appears to the
  /// contact (1 to 20 characters).
  Future<void> createInvite(String displayName);
  void clearInvite();

  /// Uses a code someone gave this person, becoming their trusted contact.
  Future<void> acceptInvite(String code);
  Future<void> removeContact(String linkId);
  Future<void> unfollow(String linkId);

  /// Called only after the person confirmed the consent text.
  Future<void> enable();

  /// Stops helping and asks the backend to delete the stored position.
  Future<void> disable();

  void dismiss(String alertId);
}

/// 首頁的「成為附近協助者」。兩段式：先看同意說明，同意後才取得位置並加入。
class SafeWalkNearbyHelperCard extends StatefulWidget {
  const SafeWalkNearbyHelperCard({super.key, required this.helper});

  final SafeWalkNearbyHelper helper;

  @override
  State<SafeWalkNearbyHelperCard> createState() =>
      _SafeWalkNearbyHelperCardState();
}

class _SafeWalkNearbyHelperCardState extends State<SafeWalkNearbyHelperCard> {
  bool _confirming = false;
  bool _addingArea = false;
  int _radius = 500;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.helper,
    builder: (context, _) {
      final helper = widget.helper;
      final reason = helper.unavailableReason;
      if (reason != null && !helper.isOn) {
        return SwStateMessage(
          icon: Icons.notifications_off_outlined,
          title: '附近協助者：目前無法使用',
          message: reason,
        );
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SwColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: SwShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: SwColors.brand,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('附近協助者', style: SwText.bodyStrong),
                      Text(
                        helper.isOn
                            ? '協助中：App 開啟時，附近有人求助會在這裡通知你'
                            : '附近有人按下求助時，在 App 內通知你',
                        style: SwText.secondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._body(helper),
          ],
        ),
      );
    },
  );

  List<Widget> _body(SafeWalkNearbyHelper helper) {
    if (helper.isBusy) {
      return [
        Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: SwColors.brand,
              ),
            ),
            const SizedBox(width: 12),
            Text('處理中…', style: SwText.bodyStrong),
          ],
        ),
      ];
    }
    final status = helper.message == null
        ? const <Widget>[]
        : [
            SwStateMessage(
              icon: helper.messageIsError
                  ? Icons.error_outline_rounded
                  : Icons.info_outline_rounded,
              title: helper.messageIsError ? '沒有成功' : '目前狀態',
              message: helper.message!,
              error: helper.messageIsError,
            ),
            const SizedBox(height: 12),
          ];
    if (helper.isOn) {
      return [
        ...status,
        if (helper.guardAreasSupported) ..._areaSection(helper),
        _button('停止協助並刪除我的位置', Icons.stop_circle_outlined, () async {
          setState(() => _confirming = false);
          await helper.disable();
        }, filled: false),
      ];
    }
    if (_confirming) {
      return [
        ...status,
        Text('加入後：', style: SwText.bodyStrong),
        const SizedBox(height: 4),
        for (final line in _consentLines) ...[
          Text('・$line', style: SwText.body),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 8),
        _button('同意並加入', Icons.check_rounded, () async {
          setState(() => _confirming = false);
          await helper.enable();
        }),
        const SizedBox(height: 8),
        _button(
          '取消',
          Icons.close_rounded,
          () => setState(() => _confirming = false),
          filled: false,
        ),
      ];
    }
    return [
      ...status,
      _button(
        '加入附近協助者',
        Icons.notifications_active_rounded,
        () => setState(() => _confirming = true),
      ),
    ];
  }

  static String _radiusLabel(int meters) =>
      meters >= 1000 ? '${meters ~/ 1000} 公里' : '$meters 公尺';

  List<Widget> _areaSection(SafeWalkNearbyHelper helper) {
    final areas = helper.guardAreas;
    return [
      Text('守護區', style: SwText.bodyStrong),
      const SizedBox(height: 4),
      Text(
        '求助發生在這些區域內時，會替你留下通知；你在 30 分鐘內開啟 App 就會看到。目前沒有推播，不會主動提醒你。',
        style: SwText.secondary,
      ),
      const SizedBox(height: 8),
      if (areas.isEmpty) ...[
        Text('還沒有守護區。', style: SwText.body),
        const SizedBox(height: 8),
      ],
      for (var i = 0; i < areas.length; i++) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                '${areas[i].center.lat.toStringAsFixed(3)}, '
                '${areas[i].center.lng.toStringAsFixed(3)}・半徑 ${_radiusLabel(areas[i].radiusMeters)}',
                style: SwText.body,
              ),
            ),
            SwPressable(
              onTap: () => helper.removeGuardArea(i),
              color: SwColors.surface,
              pressedColor: SwColors.brandSoft,
              border: const BorderSide(color: SwColors.border),
              radius: 12,
              semanticsLabel: '移除守護區 ${i + 1}',
              child: SizedBox(
                width: 72,
                height: swTouch,
                child: Center(child: Text('移除', style: SwText.bodyStrong)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      if (areas.length >= 3)
        Text('最多 3 個守護區。', style: SwText.secondary)
      else if (!_addingArea)
        _button(
          '把目前位置設為守護區',
          Icons.add_location_alt_outlined,
          () => setState(() => _addingArea = true),
          filled: false,
        )
      else ...[
        Text('範圍', style: SwText.bodyStrong),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in const [500, 1000])
              SwPressable(
                onTap: () => setState(() => _radius = r),
                selected: _radius == r,
                color: _radius == r ? SwColors.brandSoft : SwColors.surface,
                border: BorderSide(
                  color: _radius == r ? SwColors.brand : SwColors.border,
                  width: _radius == r ? 2 : 1,
                ),
                radius: 24,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                semanticsLabel: '範圍 ${_radiusLabel(r)}',
                child: SizedBox(
                  height: swTouch,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Text(_radiusLabel(r), style: SwText.bodyStrong)],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '會取得你目前的位置，四捨五入到約 100 公尺後存到伺服器，直到你移除它、停止協助或刪除帳號。',
          style: SwText.body,
        ),
        const SizedBox(height: 4),
        Text('若這是你的住家或公司，等於讓伺服器知道你大概的所在。', style: SwText.body),
        const SizedBox(height: 8),
        _button('確認設定', Icons.check_rounded, () async {
          setState(() => _addingArea = false);
          await helper.addGuardAreaHere(_radius);
        }),
        const SizedBox(height: 8),
        _button(
          '取消',
          Icons.close_rounded,
          () => setState(() => _addingArea = false),
          filled: false,
        ),
      ],
      const SizedBox(height: 12),
    ];
  }

  static const _consentLines = [
    '會在伺服器建立一個匿名帳號代表這支手機（不含姓名、電話或任何個人資料）；重新安裝後會是新的帳號。',
    'App 開啟期間，每 4 分鐘左右取得並上傳你的位置，只保存最新一筆。',
    '離開安心行、關閉 App 或停止協助後，位置最多 10 分鐘內自動刪除。',
    '500 公尺內有人按下求助時，會在 App 內通知你；對方看不到你是誰，你也看不到對方是誰。',
    'App 關閉時不會收到通知。',
    '這不是正式救援服務，你沒有義務前往。請先確認自身安全，必要時撥打 110／119。',
  ];

  Widget _button(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool filled = true,
  }) => SizedBox(
    width: double.infinity,
    child: SwPressable(
      onTap: onTap,
      color: filled ? SwColors.brand : SwColors.surface,
      pressedColor: filled ? TPColors.primary400 : SwColors.brandSoft,
      border: filled ? null : const BorderSide(color: SwColors.border),
      radius: 12,
      semanticsLabel: label,
      child: SizedBox(
        height: swTouchLarge,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: filled ? SwColors.onBrand : SwColors.text),
            const SizedBox(width: 8),
            Text(
              label,
              style: SwText.bodyStrong.copyWith(
                color: filled ? SwColors.onBrand : SwColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 有人在附近求助時，蓋在任何畫面上方的橫幅。沒有聲稱已查證、已報警或有人趕到。
class SafeWalkNearbyAlertBanner extends StatelessWidget {
  const SafeWalkNearbyAlertBanner({
    super.key,
    required this.helper,
    required this.onOpenEmergency,
  });

  final SafeWalkNearbyHelper helper;

  /// 打開求助頁（110／119）；橫幅同時收起。
  final VoidCallback onOpenEmergency;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: helper,
    builder: (context, _) {
      final alerts = helper.incoming;
      if (alerts.isEmpty) return const SizedBox.shrink();
      final alert = alerts.first;
      final at = alert.createdAt.toLocal();
      final time =
          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Semantics(
            liveRegion: true,
            container: true,
            child: Material(
              elevation: 8,
              color: TPColors.red50,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SwColors.sos, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.notifications_active_rounded,
                          color: SwColors.sos,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _title(alert, alerts.length),
                            style: SwText.heading.copyWith(color: SwColors.sos),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '位置：${alert.location.lat.toStringAsFixed(5)}, '
                      '${alert.location.lng.toStringAsFixed(5)}（$time 送出）',
                      style: SwText.bodyStrong,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      alert.fromContact
                          ? '這是你的緊急聯絡人發出的求助，位置可能不準確。請先試著聯絡對方，並確認自身安全、不要獨自涉險；需要時撥打 110／119。'
                          : '這則求助未經查證，位置可能不準確。請先確認自身安全，不要獨自涉險；需要時撥打 110／119。',
                      style: SwText.body,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _BannerButton(
                            label: '知道了',
                            onTap: () => helper.dismiss(alert.alertId),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BannerButton(
                            label: '110／119',
                            filled: true,
                            onTap: () {
                              helper.dismiss(alert.alertId);
                              onOpenEmergency();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

String _title(SafeWalkNearbyAlert alert, int count) {
  final base = alert.fromContact
      ? '${(alert.senderName ?? '').trim().isEmpty ? '你的緊急聯絡人' : alert.senderName!.trim()} 向你求助'
      : '附近有人求助';
  return count == 1 ? base : '$base（共 $count 則）';
}

class _BannerButton extends StatelessWidget {
  const _BannerButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => SwPressable(
    onTap: onTap,
    color: filled ? SwColors.sos : SwColors.surface,
    pressedColor: filled ? SwColors.sosPressed : SwColors.brandSoft,
    border: filled ? null : const BorderSide(color: SwColors.border),
    radius: 12,
    semanticsLabel: label,
    child: SizedBox(
      height: swTouchLarge,
      child: Center(
        child: Text(
          label,
          style: SwText.bodyStrong.copyWith(
            color: filled ? SwColors.onDeep : SwColors.text,
          ),
        ),
      ),
    ),
  );
}

/// 首頁的「緊急聯絡人」：用邀請碼配對，按 SOS 時對方在自己的 App 內收到通知。
/// 不是簡訊。邀請碼只顯示一次、24 小時內有效、只能用一次，由本人用信任的方式交給對方。
class SafeWalkTrustedContactsCard extends StatefulWidget {
  const SafeWalkTrustedContactsCard({super.key, required this.helper});

  final SafeWalkNearbyHelper helper;

  @override
  State<SafeWalkTrustedContactsCard> createState() =>
      _SafeWalkTrustedContactsCardState();
}

class _SafeWalkTrustedContactsCardState
    extends State<SafeWalkTrustedContactsCard> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _inviting = false;
  bool _copied = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  static String _date(DateTime d) {
    final t = d.toLocal();
    return '${t.month}/${t.day}';
  }

  static String _clock(DateTime d) {
    final t = d.toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.helper,
    builder: (context, _) {
      final helper = widget.helper;
      final reason = helper.unavailableReason;
      if (reason != null &&
          helper.myContacts.isEmpty &&
          helper.following.isEmpty) {
        return SwStateMessage(
          icon: Icons.group_off_outlined,
          title: '緊急聯絡人：目前無法使用',
          message: reason,
        );
      }
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SwColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: SwShadow.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group_rounded, color: SwColors.brand),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('緊急聯絡人', style: SwText.bodyStrong),
                      Text(
                        '按 SOS 時，你邀請的人會在他們的 App 內收到通知',
                        style: SwText.secondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (helper.contactsBusy)
              Row(
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: SwColors.brand,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('處理中…', style: SwText.bodyStrong),
                ],
              )
            else ...[
              if (helper.contactsMessage != null) ...[
                SwStateMessage(
                  icon: helper.contactsMessageIsError
                      ? Icons.error_outline_rounded
                      : Icons.info_outline_rounded,
                  title: helper.contactsMessageIsError ? '沒有成功' : '目前狀態',
                  message: helper.contactsMessage!,
                  error: helper.contactsMessageIsError,
                ),
                const SizedBox(height: 12),
              ],
              ..._mine(helper),
              const SizedBox(height: 12),
              ..._following(helper),
            ],
          ],
        ),
      );
    },
  );

  List<Widget> _mine(SafeWalkNearbyHelper helper) {
    final contacts = helper.myContacts;
    return [
      Text('我的緊急聯絡人（${contacts.length}／5）', style: SwText.bodyStrong),
      const SizedBox(height: 4),
      if (contacts.isEmpty) Text('還沒有緊急聯絡人。', style: SwText.body),
      for (var i = 0; i < contacts.length; i++) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                '第 ${i + 1} 位・${_date(contacts[i].since)} 加入',
                style: SwText.body,
              ),
            ),
            _smallButton(
              '移除',
              '移除第 ${i + 1} 位緊急聯絡人',
              () => helper.removeContact(contacts[i].id),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      if (helper.invite != null)
        ..._inviteCode(helper, helper.invite!)
      else if (contacts.length >= 5)
        Text('最多 5 位緊急聯絡人。', style: SwText.secondary)
      else if (!_inviting)
        _button(
          '邀請緊急聯絡人',
          Icons.person_add_alt_1_rounded,
          () => setState(() => _inviting = true),
        )
      else ...[
        TextField(
          controller: _name,
          maxLength: nearbyNameLimit,
          decoration: const InputDecoration(
            labelText: '對方會看到的名字（最多 20 字）',
            border: OutlineInputBorder(),
          ),
        ),
        Text(
          '對方輸入邀請碼後，你按 SOS 時，他會在自己的 App 收到通知，看到你的位置和這個名字。邀請碼 24 小時內有效、只能用一次；你可以隨時移除他。',
          style: SwText.body,
        ),
        const SizedBox(height: 8),
        _button('產生邀請碼', Icons.vpn_key_rounded, () async {
          final name = _name.text.trim();
          if (name.isEmpty) return;
          setState(() => _inviting = false);
          await helper.createInvite(name);
        }),
        const SizedBox(height: 8),
        _button(
          '取消',
          Icons.close_rounded,
          () => setState(() => _inviting = false),
          filled: false,
        ),
      ],
    ];
  }

  List<Widget> _inviteCode(
    SafeWalkNearbyHelper helper,
    SafeWalkContactInvite invite,
  ) {
    final spaced = '${invite.code.substring(0, 4)} ${invite.code.substring(4)}';
    return [
      Text(
        '邀請碼（${_clock(invite.expiresAt)} 前有效，只能用一次）',
        style: SwText.bodyStrong,
      ),
      const SizedBox(height: 4),
      Semantics(
        label: '邀請碼 ${invite.code.split('').join(' ')}',
        child: SelectableText(
          spaced,
          style: SwText.title.copyWith(letterSpacing: 4),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        '請用你信任的方式把它傳給對方（不會經過簡訊，也不會經過這個 App）。對方在自己的臺北安心行輸入後，就會成為你的緊急聯絡人。這個碼只會顯示這一次。',
        style: SwText.body,
      ),
      const SizedBox(height: 8),
      _button(_copied ? '已複製' : '複製邀請碼', Icons.copy_rounded, () async {
        await Clipboard.setData(ClipboardData(text: invite.code));
        if (mounted) setState(() => _copied = true);
      }, filled: false),
      const SizedBox(height: 8),
      _button('完成', Icons.check_rounded, () {
        setState(() => _copied = false);
        helper.clearInvite();
      }),
    ];
  }

  List<Widget> _following(SafeWalkNearbyHelper helper) {
    final people = helper.following;
    return [
      Text('我是誰的緊急聯絡人', style: SwText.bodyStrong),
      const SizedBox(height: 4),
      if (people.isEmpty) Text('目前沒有。', style: SwText.body),
      for (final person in people) ...[
        Row(
          children: [
            Expanded(child: Text(person.name, style: SwText.body)),
            _smallButton(
              '不再接收',
              '不再接收 ${person.name} 的求助',
              () => helper.unfollow(person.id),
              width: 96,
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      TextField(
        controller: _code,
        textCapitalization: TextCapitalization.characters,
        maxLength: 12,
        decoration: const InputDecoration(
          labelText: '輸入對方給你的邀請碼',
          border: OutlineInputBorder(),
        ),
      ),
      Text(
        '加入後，對方按 SOS 時你會在 App 內收到通知並看到對方的位置。只有 App 開啟時才收得到（目前沒有推播）。這不是正式救援，你沒有義務前往。',
        style: SwText.body,
      ),
      const SizedBox(height: 8),
      _button('加入', Icons.group_add_rounded, () async {
        final code = _code.text;
        _code.clear();
        await helper.acceptInvite(code);
      }, filled: false),
    ];
  }

  Widget _smallButton(
    String label,
    String semantics,
    VoidCallback onTap, {
    double width = 72,
  }) => SwPressable(
    onTap: onTap,
    color: SwColors.surface,
    pressedColor: SwColors.brandSoft,
    border: const BorderSide(color: SwColors.border),
    radius: 12,
    semanticsLabel: semantics,
    child: SizedBox(
      width: width,
      height: swTouch,
      child: Center(child: Text(label, style: SwText.bodyStrong)),
    ),
  );

  Widget _button(
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool filled = true,
  }) => SizedBox(
    width: double.infinity,
    child: SwPressable(
      onTap: onTap,
      color: filled ? SwColors.brand : SwColors.surface,
      pressedColor: filled ? TPColors.primary400 : SwColors.brandSoft,
      border: filled ? null : const BorderSide(color: SwColors.border),
      radius: 12,
      semanticsLabel: label,
      child: SizedBox(
        height: swTouchLarge,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: filled ? SwColors.onBrand : SwColors.text),
            const SizedBox(width: 8),
            Text(
              label,
              style: SwText.bodyStrong.copyWith(
                color: filled ? SwColors.onBrand : SwColors.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The longest name a person can show their contacts, in characters.
const nearbyNameLimit = 20;
