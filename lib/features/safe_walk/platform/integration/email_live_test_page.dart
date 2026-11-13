import 'package:flutter/material.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_transport.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/nearby_alert_transport.dart';
import 'package:town_pass/util/tp_colors.dart';

/// Test-only shell. Changing identity unmounts the old flow before logout,
/// disposing its location/polling lifetimes. No test email reaches AccountService.
class EmailLiveTestPage extends StatefulWidget {
  const EmailLiveTestPage({
    super.key,
    required this.transport,
    required this.flowBuilder,
  });
  final EmailLiveTestTransport transport;
  final Widget Function(NearbyAlertTransport) flowBuilder;
  @override
  State<EmailLiveTestPage> createState() => _EmailLiveTestPageState();
}

class _EmailLiveTestPageState extends State<EmailLiveTestPage> {
  final _email = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _loading = true;
  bool _busy = false;
  bool _showEntry = true;
  bool _consent = false;
  int _generation = 0;
  String? _message;
  EmailLiveTestTransport get _transport => widget.transport;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = _transport.prefs.getString(EmailLiveTestTransport.emailKey);
      if (saved != null) _email.text = saved;
      await _transport.restoreExistingIdentity();
      _showEntry = !_transport.hasSession && !_transport.hasSeenPrompt;
      if (saved != null && !_transport.hasSession) _showEntry = true;
    } on NearbyAlertException catch (e) {
      _message = e.message;
      _showEntry = true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate() || !_consent) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _transport.login(_email.text);
      if (mounted) {
        setState(() {
          _showEntry = false;
          _generation++;
        });
      }
    } on NearbyAlertException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _skip() async {
    setState(() => _busy = true);
    try {
      await _transport.skip();
      if (mounted) setState(() => _showEntry = false);
    } on NearbyAlertException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    setState(() {
      _busy = true;
      _loading = true;
      _generation++;
    });
    // Unmount the flow first, so its pending operations cannot cross identities.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final revoked = await _transport.logout();
      _message = revoked ? '本裝置已登出測試帳號。' : '本機已登出；遠端撤銷未確認，測試 session 將到期。';
    } on NearbyAlertException catch (e) {
      _message = e.message;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _loading = false;
          _showEntry = false;
          _consent = false;
          _email.clear();
        });
      }
    }
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: TPColors.secondary100,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _transport.hasSession
                            ? 'Live 測試｜${_transport.email}（未驗證）'
                            : 'Live 測試｜訪客',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!_loading)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : (_transport.hasSession
                                  ? _logout
                                  : () => setState(() => _showEntry = true)),
                        child: Text(_transport.hasSession ? '登出本裝置' : '輸入信箱'),
                      ),
                  ],
                ),
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_message!, key: const Key('test-account-message')),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _showEntry
                  ? _entry()
                  : KeyedSubtree(
                      key: ValueKey(_generation),
                      child: widget.flowBuilder(_transport),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entry() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '輸入 e-mail 開始 Live 測試',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              const Text(
                '不寄驗證碼。相同信箱會登入同一測試帳號，知道該信箱的人也能登入。'
                '僅使用你與同意參與者的測試資料，請勿放入敏感或真實危難資訊。',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _email,
                enabled: !_busy,
                autocorrect: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'e-mail',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    EmailLiveTestTransport.normalizeEmail(v ?? '') == null
                    ? '請輸入有效的 e-mail。'
                    : null,
                onFieldSubmitted: (_) {
                  if (!_busy && _consent) _login();
                },
              ),
              CheckboxListTile(
                value: _consent,
                contentPadding: EdgeInsets.zero,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _consent = v ?? false),
                title: const Text('我了解這是未驗證信箱的測試帳號；加入協助者與發送位置會另外確認。'),
              ),
              FilledButton(
                onPressed: _busy || !_consent ? null : _login,
                child: Text(_busy ? '連線中…' : '建立／登入測試帳號'),
              ),
              TextButton(
                onPressed: _busy ? null : _skip,
                child: const Text('稍後再說'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
