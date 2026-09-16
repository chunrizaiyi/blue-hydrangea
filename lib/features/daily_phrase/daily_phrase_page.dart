import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/garden_models.dart';
import '../../services/local_database.dart';
import '../../theme/app_theme.dart';
import '../../widgets/garden_background.dart';
import '../../widgets/garden_components.dart';
import '../ai/deepseek_credentials_dialog.dart';
import 'daily_phrase_service.dart';

/// An inline, ephemeral session. Removing this widget clears all session content.
class DailyPhrasePanel extends StatefulWidget {
  const DailyPhrasePanel({super.key});

  @override
  State<DailyPhrasePanel> createState() => _DailyPhrasePanelState();
}

class _DailyPhrasePanelState extends State<DailyPhrasePanel>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _service = DailyPhraseService();
  String _tone = '轻轻陪伴';
  String? _moodText;
  String? _result;
  String? _error;
  bool _busy = false;
  bool _opening = false;
  bool _hasKey = false;
  bool _keyLoading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshKey());
  }

  Future<void> _refreshKey() async {
    try {
      final hasKey = await DailyPhraseCredentials.hasKey();
      if (mounted) setState(() => _hasKey = hasKey);
    } catch (_) {
      if (mounted) setState(() => _error = '密钥设置暂时无法读取，可以点击面板右侧的设置按钮重试。');
    } finally {
      if (mounted) setState(() => _keyLoading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _busy) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _request++;
    _service.cancel();
    _input.clear();
    _input.dispose();
    _result = null;
    _moodText = null;
    super.dispose();
  }

  void _cancel() {
    _request++;
    _service.cancel();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = '本次等待已取消。已发送的请求可能仍由 DeepSeek 处理并计费。';
      });
    }
  }

  Future<void> _settings() async {
    if (_busy || _opening) return;
    _opening = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DeepSeekCredentialsDialog(hasKey: _hasKey),
      );
      if (mounted) await _refreshKey();
    } finally {
      _opening = false;
    }
  }

  Future<void> _chooseMood() async {
    if (_busy || _opening) return;
    _opening = true;
    try {
      final entries = await LocalDatabase.instance.moods();
      if (!mounted) return;
      final today = DateUtils.dateOnly(DateTime.now());
      final todays = entries
          .where((entry) => DateUtils.dateOnly(entry.date) == today)
          .toList(growable: false);
      if (todays.isEmpty) {
        showGardenMessage(context, '今天还没有心情记录，直接写一句此刻想说的话也可以。');
        return;
      }
      final picked = await showModalBottomSheet<MoodEntry>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .62,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: Text(
                    '选一条今天的心情\n只使用你点中的这一条；长备注使用前 600 字。',
                    textAlign: TextAlign.center,
                    style: TextStyle(height: 1.7),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: todays.length,
                    itemBuilder: (_, index) {
                      final entry = todays[index];
                      return ListTile(
                        leading: const Icon(Icons.spa_outlined),
                        title: Text(
                          '${entry.mood} · '
                          '${entry.date.hour.toString().padLeft(2, '0')}:'
                          '${entry.date.minute.toString().padLeft(2, '0')}',
                        ),
                        subtitle: Text(
                          entry.note.isEmpty ? '这一刻，没有留下文字。' : entry.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.pop(sheetContext, entry),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || picked == null) return;
      setState(() {
        final note = String.fromCharCodes(picked.note.runes.take(600));
        _moodText =
            '${gentleDate(picked.date)} · ${picked.mood}'
            '${note.isEmpty ? '' : '\n$note'}';
        _result = null;
        _error = null;
      });
    } catch (_) {
      if (mounted) showGardenMessage(context, '今天的心情暂时没有读到，你可以直接输入一句话。');
    } finally {
      _opening = false;
    }
  }

  Future<void> _generate() async {
    if (_busy || _opening || _keyLoading) return;
    if (!_hasKey) {
      await _settings();
      return;
    }
    final text = [
      if (_moodText != null) '选择的心情：\n$_moodText',
      if (_input.text.trim().isNotEmpty) '此刻想说：\n${_input.text.trim()}',
    ].join('\n\n');
    if (text.isEmpty) {
      setState(() => _error = '先写一句话，或选一条今天的心情吧。');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final revision = ++_request;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phrase = await _service.generate(text: text, tone: _tone);
      if (!mounted || revision != _request) return;
      setState(() => _result = phrase);
    } on DailyPhraseException catch (error) {
      if (mounted && revision == _request) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && revision == _request) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 30),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const HydrangeaCluster(size: 54),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '让此刻，开出一小朵温柔。',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '本次内容只陪你一会儿，收起后就会清空。',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'DeepSeek 密钥设置',
              onPressed: _busy ? null : _settings,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.mistBlue.withValues(alpha: .58),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: .72)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '宝宝，此刻想说些什么？',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _input,
                enabled: !_busy,
                minLines: 3,
                maxLines: 7,
                maxLength: 600,
                decoration: const InputDecoration(
                  hintText: '随意写一句就好，也可以只选一条今天的心情。',
                  alignLabelWithHint: true,
                ),
                onChanged: (_) => setState(() {
                  _result = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: _busy ? null : _chooseMood,
                icon: const Icon(Icons.favorite_border_rounded, size: 18),
                label: Text(_moodText == null ? '选一条今天的心情' : '换一条心情'),
              ),
              if (_moodText != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 12),
                  decoration: BoxDecoration(
                    color: AppColors.mistBlue,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _moodText!,
                            style: const TextStyle(height: 1.6),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '移除此项材料，不删除原心情',
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _moodText = null;
                                _result = null;
                              }),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final tone in ['轻轻陪伴', '温柔鼓励', '安静想念'])
                    ChoiceChip(
                      label: Text(tone),
                      selected: _tone == tone,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _tone = tone;
                              _result = null;
                            }),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: _busy || _keyLoading ? null : _generate,
          icon: const Butterfly(size: 23, color: Colors.white),
          label: Text(
            _keyLoading
                ? '正在读取设置…'
                : !_hasKey
                ? '先设置 DeepSeek 密钥'
                : _result == null
                ? '生成一朵花语'
                : '重新生成一朵',
          ),
        ),
        if (_busy)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
                const Text(
                  '正在整理你选中的几片花瓣…',
                  style: TextStyle(color: AppColors.muted),
                ),
                TextButton(onPressed: _cancel, child: const Text('取消等待')),
              ],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.deepBlue, height: 1.65),
            ),
          ),
        AnimatedSize(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 360),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, .035),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _result == null
                ? const SizedBox.shrink(key: ValueKey('empty'))
                : Padding(
                    key: ValueKey(_result),
                    padding: const EdgeInsets.only(top: 18),
                    child: GardenCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Butterfly(size: 26),
                              SizedBox(width: 10),
                              Text(
                                '只送给此刻的你',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            _result!,
                            style: const TextStyle(fontSize: 17, height: 1.9),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'DeepSeek 生成 · 不代表对你或他人的判断',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          '点按生成后会将本次填写与选中的内容发送至 DeepSeek。'
          '收起后不保留内容，也不影响原有心情记录。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, height: 1.65, color: AppColors.muted),
        ),
      ],
    );
  }
}
