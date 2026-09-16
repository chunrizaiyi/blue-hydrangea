import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/ai/deepseek_credentials_dialog.dart';
import '../features/daily_phrase/daily_phrase_service.dart';
import '../features/emotion_support/emotion_support_service.dart';
import '../models/garden_models.dart';
import '../services/local_database.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_background.dart';
import '../widgets/garden_components.dart';

class MailboxPage extends StatefulWidget {
  const MailboxPage({super.key});

  @override
  State<MailboxPage> createState() => _MailboxPageState();
}

class _MailboxPageState extends State<MailboxPage> with WidgetsBindingObserver {
  static const _modes = [
    ('理清自己的情绪', Icons.psychology_alt_outlined),
    ('不知道怎么和他说', Icons.chat_bubble_outline_rounded),
    ('想理解他的想法', Icons.favorite_border_rounded),
    ('我们刚发生了矛盾', Icons.spa_outlined),
  ];
  static const _feelings = [
    '难过',
    '委屈',
    '生气',
    '焦虑',
    '失望',
    '害怕',
    '孤单',
    '内疚',
    '说不清',
  ];
  static const _goals = [
    '帮我理清情绪',
    '帮我理解这次矛盾',
    '帮我想怎么表达',
    '判断现在是否适合沟通',
    '先安慰我一下',
  ];
  static const _rewriteStyles = ['更温柔一点', '更直接一点', '更简短一点', '更有边界感', '不带责怪'];

  final _situation = TextEditingController();
  final _feedback = TextEditingController();
  final _service = EmotionSupportService();
  final _selectedFeelings = <String>{};
  final _questionAnswers = <TextEditingController>[];

  String _mode = _modes.first.$1;
  String _goal = _goals.first;
  String _rewriteStyle = _rewriteStyles.first;
  String? _moodText;
  List<String> _questions = const [];
  EmotionSupportAnalysis? _analysis;
  String? _error;
  bool _busy = false;
  bool _keyLoading = true;
  bool _hasKey = false;
  bool _openingOverlay = false;
  bool _feedbackExpanded = false;
  int _requestRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshKey());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _busy) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestRevision++;
    _service.cancel();
    _disposeQuestionAnswers();
    _situation.clear();
    _feedback.clear();
    _situation.dispose();
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _refreshKey() async {
    try {
      final hasKey = await DailyPhraseCredentials.hasKey();
      if (mounted) setState(() => _hasKey = hasKey);
    } catch (_) {
      if (mounted) setState(() => _error = '密钥设置暂时无法读取，请点击右上角重新设置。');
    } finally {
      if (mounted) setState(() => _keyLoading = false);
    }
  }

  Future<void> _settings() async {
    if (_busy || _openingOverlay) return;
    _openingOverlay = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DeepSeekCredentialsDialog(hasKey: _hasKey),
      );
      if (mounted) await _refreshKey();
    } finally {
      _openingOverlay = false;
    }
  }

  Future<void> _chooseMood() async {
    if (_busy || _openingOverlay) return;
    _openingOverlay = true;
    try {
      final entries = await LocalDatabase.instance.moods();
      if (!mounted) return;
      final today = DateUtils.dateOnly(DateTime.now());
      final todays = entries
          .where((entry) => DateUtils.dateOnly(entry.date) == today)
          .toList(growable: false);
      if (todays.isEmpty) {
        showGardenMessage(context, '今天还没有心情记录，直接写发生了什么也可以。');
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
                    '选一条今天的心情\n只使用你主动点中的这一条。',
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
      final note = String.fromCharCodes(picked.note.runes.take(600));
      setState(() {
        _moodText =
            '${gentleDate(picked.date)} · ${picked.mood}'
            '${note.isEmpty ? '' : '\n$note'}';
        _clearGenerated();
      });
    } catch (_) {
      if (mounted) showGardenMessage(context, '今天的心情暂时没有读到，可以直接写下来。');
    } finally {
      _openingOverlay = false;
    }
  }

  EmotionSupportInput get _input => EmotionSupportInput(
    mode: _mode,
    goal: _goal,
    situation: _situation.text.trim(),
    feelings: _selectedFeelings.toList(growable: false),
    moodRecord: _moodText,
  );

  void _disposeQuestionAnswers() {
    for (final controller in _questionAnswers) {
      controller.clear();
      controller.dispose();
    }
    _questionAnswers.clear();
  }

  void _setQuestions(List<String> questions) {
    _disposeQuestionAnswers();
    _questions = questions;
    _questionAnswers.addAll(
      List.generate(questions.length, (_) => TextEditingController()),
    );
  }

  void _clearGenerated() {
    _requestRevision++;
    _service.cancel();
    _disposeQuestionAnswers();
    _questions = const [];
    _analysis = null;
    _feedback.clear();
    _feedbackExpanded = false;
    _error = null;
    _busy = false;
  }

  void _cancel() {
    _requestRevision++;
    _service.cancel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = '本次等待已取消。已经发送的请求仍可能由 DeepSeek 处理并计费。';
    });
  }

  Future<bool> _ensureReady() async {
    if (_busy || _openingOverlay || _keyLoading) return false;
    if (!_hasKey) {
      await _settings();
      return false;
    }
    if (_situation.text.trim().isEmpty && _moodText == null) {
      setState(() => _error = '先写下发生了什么，或者选一条今天的心情吧。');
      return false;
    }
    return true;
  }

  Future<void> _analyze({bool withAnswers = false}) async {
    if (!await _ensureReady()) return;
    final answers = withAnswers
        ? _questionAnswers.map((controller) => controller.text.trim()).toList()
        : const <String>[];
    if (withAnswers && answers.every((answer) => answer.isEmpty)) {
      setState(() => _error = '可以简单回答一个问题，或者返回补充原来的描述。');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final revision = ++_requestRevision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await _service.analyze(
        input: _input,
        questions: withAnswers ? _questions : const [],
        answers: answers,
      );
      if (!mounted || revision != _requestRevision) return;
      setState(() {
        if (response.analysis != null) {
          _disposeQuestionAnswers();
          _questions = const [];
          _analysis = response.analysis;
        } else {
          _analysis = null;
          _setQuestions(response.questions);
        }
      });
    } on EmotionSupportException catch (error) {
      if (mounted && revision == _requestRevision) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && revision == _requestRevision) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refine() async {
    final analysis = _analysis;
    final feedback = _feedback.text.trim();
    if (analysis == null || feedback.isEmpty || !await _ensureReady()) {
      if (analysis != null && feedback.isEmpty) {
        setState(() => _error = '写一点哪里不准确，或还有什么想补充的。');
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final revision = ++_requestRevision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await _service.analyze(
        input: _input,
        previous: analysis,
        feedback: feedback,
      );
      if (!mounted || revision != _requestRevision) return;
      setState(() {
        _analysis = response.analysis;
        _feedback.clear();
        _feedbackExpanded = false;
      });
    } on EmotionSupportException catch (error) {
      if (mounted && revision == _requestRevision) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && revision == _requestRevision) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _rewriteOpeners() async {
    final analysis = _analysis;
    if (analysis == null || !await _ensureReady()) return;
    final revision = ++_requestRevision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final openers = await _service.rewriteOpeners(
        input: _input,
        analysis: analysis,
        style: _rewriteStyle,
      );
      if (!mounted || revision != _requestRevision) return;
      setState(() {
        _analysis = analysis.copyWith(
          gentleOpener: openers['gentle'],
          directOpener: openers['direct'],
          pauseOpener: openers['pause'],
        );
      });
    } on EmotionSupportException catch (error) {
      if (mounted && revision == _requestRevision) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && revision == _requestRevision) {
        setState(() => _busy = false);
      }
    }
  }

  void _reset() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _clearGenerated();
      _situation.clear();
      _selectedFeelings.clear();
      _moodText = null;
      _mode = _modes.first.$1;
      _goal = _goals.first;
      _rewriteStyle = _rewriteStyles.first;
    });
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showGardenMessage(context, '已经替宝宝复制好啦。');
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return GardenBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 40),
          children: [
            GardenPageHeader(
              title: '情绪解语',
              subtitle: '慢慢说，我陪你把心里的话理清楚。',
              trailing: IconButton.filledTonal(
                tooltip: 'DeepSeek 密钥设置',
                onPressed: _busy ? null : _settings,
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
            const SizedBox(height: 22),
            _IntroGardenCard(hasKey: _hasKey, keyLoading: _keyLoading),
            const SizedBox(height: 18),
            GardenCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('宝宝现在更想做什么？'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in _modes)
                        ChoiceChip(
                          avatar: Icon(mode.$2, size: 17),
                          label: Text(mode.$1),
                          selected: _mode == mode.$1,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() {
                                  _mode = mode.$1;
                                  _clearGenerated();
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _SectionLabel('发生什么了？'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _situation,
                    enabled: !_busy,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      hintText: '想怎么说都可以，不需要组织得很完整。',
                      alignLabelWithHint: true,
                    ),
                    onChanged: (_) => setState(_clearGenerated),
                  ),
                  const SizedBox(height: 10),
                  const _SectionLabel('现在比较接近哪些感受？'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final feeling in _feelings)
                        FilterChip(
                          label: Text(feeling),
                          selected: _selectedFeelings.contains(feeling),
                          onSelected: _busy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    _selectedFeelings.add(feeling);
                                  } else {
                                    _selectedFeelings.remove(feeling);
                                  }
                                  _clearGenerated();
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('这次更希望得到什么帮助？'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final goal in _goals)
                        ChoiceChip(
                          label: Text(goal),
                          selected: _goal == goal,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() {
                                  _goal = goal;
                                  _clearGenerated();
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _busy ? null : _chooseMood,
                    icon: const Icon(Icons.favorite_border_rounded, size: 18),
                    label: Text(_moodText == null ? '引用一条今天的心情（可选）' : '换一条心情'),
                  ),
                  if (_moodText != null)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
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
                            tooltip: '移除引用，不删除原心情',
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _moodText = null;
                                    _clearGenerated();
                                  }),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || _keyLoading ? null : () => _analyze(),
              icon: const Butterfly(size: 23, color: Colors.white),
              label: Text(
                _keyLoading
                    ? '正在读取设置…'
                    : !_hasKey
                    ? '先设置 DeepSeek 密钥'
                    : _analysis == null && _questions.isEmpty
                    ? '陪我理一理'
                    : '重新整理',
              ),
            ),
            if (_busy) _WorkingCard(onCancel: _cancel),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.deepBlue,
                    height: 1.65,
                  ),
                ),
              ),
            AnimatedSize(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 520),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, .025),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _questions.isNotEmpty
                    ? _ClarifyingCard(
                        key: const ValueKey('questions'),
                        questions: _questions,
                        controllers: _questionAnswers,
                        enabled: !_busy,
                        onSubmit: () => _analyze(withAnswers: true),
                      )
                    : _analysis != null
                    ? _AnalysisView(
                        key: const ValueKey('analysis'),
                        analysis: _analysis!,
                        rewriteStyle: _rewriteStyle,
                        rewriteStyles: _rewriteStyles,
                        feedbackController: _feedback,
                        feedbackExpanded: _feedbackExpanded,
                        busy: _busy,
                        onCopy: _copy,
                        onRewriteStyleChanged: (value) =>
                            setState(() => _rewriteStyle = value),
                        onRewrite: _rewriteOpeners,
                        onToggleFeedback: () => setState(
                          () => _feedbackExpanded = !_feedbackExpanded,
                        ),
                        onRefine: _refine,
                        onReset: _reset,
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              '点按整理后，本次填写和主动引用的内容会发送至 DeepSeek。'
              '不会自动读取照片、回忆、纪念日或其他心情记录；本页内容不写入本地数据库。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroGardenCard extends StatelessWidget {
  const _IntroGardenCard({required this.hasKey, required this.keyLoading});

  final bool hasKey;
  final bool keyLoading;

  @override
  Widget build(BuildContext context) => Container(
    height: 142,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .56),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: .72)),
    ),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        const Positioned(
          right: 4,
          bottom: -34,
          child: HydrangeaCluster(size: 160),
        ),
        const Positioned(left: 22, top: 24, child: Butterfly(size: 38)),
        const Positioned(
          left: 22,
          top: 76,
          right: 142,
          child: Text(
            '不急着判断对错，先把心里的感觉放下来。',
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
              height: 1.55,
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 15,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.mistBlue.withValues(alpha: .9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              keyLoading
                  ? '正在连接'
                  : hasKey
                  ? 'AI 已准备好'
                  : '等待设置密钥',
              style: const TextStyle(
                color: AppColors.deepBlue,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
  );
}

class _WorkingCard extends StatelessWidget {
  const _WorkingCard({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: GardenCard(
      child: Column(
        children: [
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Butterfly(size: 24),
              SizedBox(width: 10),
              Text('正在把散落的心情轻轻整理好…', style: TextStyle(color: AppColors.muted)),
            ],
          ),
          TextButton(onPressed: onCancel, child: const Text('取消等待')),
        ],
      ),
    ),
  );
}

class _ClarifyingCard extends StatelessWidget {
  const _ClarifyingCard({
    super.key,
    required this.questions,
    required this.controllers,
    required this.enabled,
    required this.onSubmit,
  });

  final List<String> questions;
  final List<TextEditingController> controllers;
  final bool enabled;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: GardenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Butterfly(size: 27),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '我想再听宝宝说一点',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '不需要回答得很完整，想到什么就写什么。',
            style: TextStyle(color: AppColors.muted, height: 1.6),
          ),
          for (var index = 0; index < questions.length; index++) ...[
            const SizedBox(height: 18),
            Text(
              '${index + 1}. ${questions[index]}',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.55),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controllers[index],
              enabled: enabled,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(hintText: '在这里慢慢说…'),
            ),
          ],
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: enabled ? onSubmit : null,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: const Text('根据这些继续整理'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _AnalysisView extends StatelessWidget {
  const _AnalysisView({
    super.key,
    required this.analysis,
    required this.rewriteStyle,
    required this.rewriteStyles,
    required this.feedbackController,
    required this.feedbackExpanded,
    required this.busy,
    required this.onCopy,
    required this.onRewriteStyleChanged,
    required this.onRewrite,
    required this.onToggleFeedback,
    required this.onRefine,
    required this.onReset,
  });

  final EmotionSupportAnalysis analysis;
  final String rewriteStyle;
  final List<String> rewriteStyles;
  final TextEditingController feedbackController;
  final bool feedbackExpanded;
  final bool busy;
  final ValueChanged<String> onCopy;
  final ValueChanged<String> onRewriteStyleChanged;
  final VoidCallback onRewrite;
  final VoidCallback onToggleFeedback;
  final VoidCallback onRefine;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      children: [
        if (analysis.safetyLevel != 'normal' &&
            analysis.safetyMessage.isNotEmpty)
          _ResultCard(
            icon: Icons.health_and_safety_outlined,
            title: analysis.safetyLevel == 'urgent' ? '先照顾好此刻的安全' : '先保护好自己',
            tint: const Color(0xFFF3E3E3),
            child: Text(
              analysis.safetyMessage,
              style: const TextStyle(height: 1.75),
            ),
          ),
        _ResultCard(
          icon: Icons.favorite_border_rounded,
          title: '我听见宝宝的心情了',
          child: Text(analysis.holding, style: const TextStyle(height: 1.8)),
        ),
        _ResultCard(
          icon: Icons.bubble_chart_outlined,
          title: '心里真正介意的，可能是这些',
          child: Column(
            children: [
              for (final item in analysis.possibleOrigins)
                _NumberedLine(
                  number: analysis.possibleOrigins.indexOf(item) + 1,
                  text: item,
                ),
            ],
          ),
        ),
        _ResultCard(
          icon: Icons.lightbulb_outline_rounded,
          title: '你真正想让他知道什么',
          tint: const Color(0xFFEAE5F5),
          child: Text(analysis.coreNeed, style: const TextStyle(height: 1.8)),
        ),
        _ResultCard(
          icon: Icons.forum_outlined,
          title: '如果现在想和他说',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OpenerTile(
                label: '轻轻说',
                text: analysis.gentleOpener,
                onCopy: onCopy,
              ),
              _OpenerTile(
                label: '认真说',
                text: analysis.directOpener,
                onCopy: onCopy,
              ),
              _OpenerTile(
                label: '先暂停',
                text: analysis.pauseOpener,
                onCopy: onCopy,
              ),
              const SizedBox(height: 12),
              const Text(
                '想换一种表达方式？',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 6,
                children: [
                  for (final style in rewriteStyles)
                    ChoiceChip(
                      label: Text(style),
                      selected: rewriteStyle == style,
                      onSelected: busy
                          ? null
                          : (_) => onRewriteStyleChanged(style),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy ? null : onRewrite,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: const Text('只改写这三句话'),
              ),
            ],
          ),
        ),
        _ResultCard(
          icon: Icons.route_outlined,
          title: '下一步可以这样做',
          child: Column(
            children: [
              for (final item in analysis.nextSteps)
                _NumberedLine(
                  number: analysis.nextSteps.indexOf(item) + 1,
                  text: item,
                ),
            ],
          ),
        ),
        _ResultCard(
          iconWidget: const Butterfly(size: 27),
          title: '一只小蝴蝶想告诉你',
          tint: const Color(0xFFE8EDF9),
          child: Text(
            analysis.reminder,
            style: const TextStyle(fontSize: 16, height: 1.85),
          ),
        ),
        GardenCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed: busy ? null : onToggleFeedback,
                icon: Icon(
                  feedbackExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.edit_note_rounded,
                ),
                label: Text(feedbackExpanded ? '收起补充' : '这里不太准确，或者我还想说一点'),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeInOutCubic,
                child: feedbackExpanded
                    ? Column(
                        children: [
                          const SizedBox(height: 10),
                          TextField(
                            controller: feedbackController,
                            enabled: !busy,
                            minLines: 3,
                            maxLines: 6,
                            maxLength: 900,
                            decoration: const InputDecoration(
                              hintText: '比如：不是这个原因、你理解反了，或者我还有一件事没有说…',
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: busy ? null : onRefine,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('根据补充重新整理'),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: busy ? null : onReset,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('放下这次内容，重新开始'),
        ),
        const SizedBox(height: 8),
        const Text(
          'DeepSeek 生成 · 用于整理感受和准备沟通，不代表对你或他人的诊断与判定',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.6),
        ),
      ],
    ),
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    this.icon,
    this.iconWidget,
    required this.title,
    required this.child,
    this.tint = AppColors.mistBlue,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String title;
  final Widget child;
  final Color tint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: GardenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child:
                    iconWidget ??
                    Icon(icon, color: AppColors.deepBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

class _NumberedLine extends StatelessWidget {
  const _NumberedLine({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.softBlue.withValues(alpha: .35),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(fontSize: 11, color: AppColors.deepBlue),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(child: Text(text, style: const TextStyle(height: 1.7))),
      ],
    ),
  );
}

class _OpenerTile extends StatelessWidget {
  const _OpenerTile({
    required this.label,
    required this.text,
    required this.onCopy,
  });

  final String label;
  final String text;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
    decoration: BoxDecoration(
      color: AppColors.mistBlue.withValues(alpha: .66),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.deepBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Text(text, style: const TextStyle(height: 1.7)),
            ],
          ),
        ),
        IconButton(
          tooltip: '复制这句话',
          onPressed: () => onCopy(text),
          icon: const Icon(Icons.copy_rounded, size: 18),
        ),
      ],
    ),
  );
}
