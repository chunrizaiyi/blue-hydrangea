import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../daily_phrase/daily_phrase_service.dart';

class DeepSeekCredentialsDialog extends StatefulWidget {
  const DeepSeekCredentialsDialog({super.key, required this.hasKey});

  final bool hasKey;

  @override
  State<DeepSeekCredentialsDialog> createState() =>
      _DeepSeekCredentialsDialogState();
}

class _DeepSeekCredentialsDialogState extends State<DeepSeekCredentialsDialog> {
  final _key = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _key.clear();
    _key.dispose();
    super.dispose();
  }

  Future<void> _commit({bool remove = false}) async {
    if (_saving) return;
    final value = _key.text.trim();
    if (!remove && !RegExp(r'^[\x21-\x7e]{8,512}$').hasMatch(value)) {
      setState(() => _error = '请输入完整的 API 密钥，不要带空格或换行。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (remove) {
        await DailyPhraseCredentials.remove();
      } else {
        await DailyPhraseCredentials.save(value);
      }
      if (!mounted) return;
      _key.clear();
      setState(() => _saving = false);
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '设备未能完成密钥操作，请稍后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('连接你的 DeepSeek'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.hasKey ? '已设置密钥。出于安全考虑，不回显旧密钥。' : '请填写你自己账户的 API 密钥。'),
            const SizedBox(height: 16),
            TextField(
              controller: _key,
              enabled: !_saving,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              maxLength: 512,
              decoration: const InputDecoration(
                labelText: 'API Key',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '仅直连 api.deepseek.com，使用 DeepSeek Flash 非思考模式。\n\n'
              '密钥由 Android 加密保存在本设备，不进入数据库或系统备份。'
              '换手机需重新填写。生成会消耗你账户的 API 额度；保存密钥不会发起请求。\n\n'
              '这是个人自用接入方式，请勿把你的密钥分享给他人。',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.muted,
                height: 1.6,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.deepBlue),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (widget.hasKey)
          TextButton(
            onPressed: _saving ? null : () => _commit(remove: true),
            child: const Text('移除密钥'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _saving ? null : _commit,
          child: Text(_saving ? '处理中…' : '保存密钥'),
        ),
      ],
    ),
  );
}
