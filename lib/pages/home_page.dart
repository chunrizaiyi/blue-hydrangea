import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/garden_models.dart';
import '../services/local_database.dart';
import '../services/quote_service.dart';
import '../services/seamless_white_noise_player.dart';
import '../services/focus_timer_bridge.dart';
import '../services/white_noise_service.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_background.dart';
import '../widgets/garden_components.dart';
import 'comfort_page.dart';
import 'focus_clock_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _introController;
  late final AnimationController _butterflyController;
  late final AnimationController _noiseRevealController;
  final _noisePlayer = SeamlessWhiteNoisePlayer();
  GentleQuote? _quote;
  var _opening = false;
  var _noiseExpanded = false;
  var _noiseKind = WhiteNoiseKind.rain;
  var _noisePlaying = false;
  var _noiseLoading = false;
  var _noiseVolume = .38;
  WhiteNoiseKind? _loadedNoiseKind;
  List<Anniversary> _anniversaries = const [];
  var _anniversaryLoadRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _butterflyController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
    _noiseRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
      reverseDuration: const Duration(milliseconds: 420),
    );
    unawaited(_loadAnniversaries());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _introController.dispose();
    _butterflyController.dispose();
    _noiseRevealController.dispose();
    unawaited(_noisePlayer.dispose().catchError((_) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadAnniversaries());
    }
  }

  Future<void> _loadAnniversaries() async {
    final revision = ++_anniversaryLoadRevision;
    try {
      final anniversaries = await LocalDatabase.instance.anniversaries();
      if (!mounted || revision != _anniversaryLoadRevision) return;
      setState(() => _anniversaries = anniversaries);
    } catch (_) {
      // Keep the last successfully loaded list. The next resume or popup open
      // retries automatically without replacing good data with an empty list.
    }
  }

  Future<void> _showAnniversaries() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭纪念日',
      barrierColor: AppColors.deepBlue.withValues(alpha: .26),
      transitionDuration: const Duration(milliseconds: 460),
      pageBuilder: (context, _, __) => SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: _AnniversaryPopup(
              initialEntries: _anniversaries,
              onChanged: _loadAnniversaries,
            ),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) {
        final entrance = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: .86, end: 1.0).animate(entrance),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(.03, -.06),
                end: Offset.zero,
              ).animate(entrance),
              child: child,
            ),
          ),
        );
      },
    );
  }

  void _toggleNoisePanel() {
    setState(() => _noiseExpanded = !_noiseExpanded);
    if (_noiseExpanded) {
      unawaited(_noiseRevealController.forward());
    } else {
      unawaited(_noiseRevealController.reverse());
    }
  }

  String get _greeting {
    const messages = [
      '今天也想把温柔留给你。',
      '如果你累了，就来这里待一会儿。',
      '愿你今天也被温柔对待。',
      '像蓝色绣球花一样，安静地盛开就很好。',
    ];
    final now = DateTime.now();
    final day = now.difference(DateTime(now.year, 1, 1)).inDays;
    return messages[day % messages.length];
  }

  Future<void> _openButterfly() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final quote = await QuoteService.randomQuote();
      if (mounted) setState(() => _quote = quote);
    } catch (_) {
      if (mounted) showGardenMessage(context, '小蝴蝶暂时迷路了，再点一次试试好吗？');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _toggleNoise() async {
    if (_noiseLoading) return;
    try {
      if (_noisePlaying) {
        await _noisePlayer.pause();
        if (mounted) setState(() => _noisePlaying = false);
        return;
      }

      if (_loadedNoiseKind == _noiseKind) {
        await _noisePlayer.resume();
        if (mounted) setState(() => _noisePlaying = true);
        return;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _noisePlaying = false);
        showGardenMessage(context, '声音暂时没有响应，再试一次好吗？');
      }
      return;
    }
    await _playSelectedNoise();
  }

  Future<void> _playSelectedNoise() async {
    setState(() => _noiseLoading = true);
    try {
      await _noisePlayer.play(_noiseKind, volume: _noiseVolume);
      _loadedNoiseKind = _noiseKind;
      if (mounted) {
        setState(() {
          _noiseLoading = false;
          _noisePlaying = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      _loadedNoiseKind = null;
      setState(() {
        _noiseLoading = false;
        _noisePlaying = false;
      });
      showGardenMessage(context, '声音暂时没有播放成功，再试一次好吗？');
    }
  }

  Future<void> _selectNoise(WhiteNoiseKind kind) async {
    if (_noiseLoading || kind == _noiseKind) return;
    final shouldKeepPlaying = _noisePlaying;
    setState(() => _noiseLoading = true);
    try {
      await _noisePlayer.stop();
    } catch (_) {
      if (mounted) showGardenMessage(context, '声音切换没有成功，再试一次好吗？');
      if (mounted) setState(() => _noiseLoading = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _noiseKind = kind;
      _noisePlaying = false;
      _loadedNoiseKind = null;
      _noiseLoading = false;
    });
    if (shouldKeepPlaying) await _playSelectedNoise();
  }

  void _setNoiseVolume(double value) {
    _noiseVolume = value;
    unawaited(_noisePlayer.setVolume(value).catchError((_) {}));
  }

  Future<void> _showNoiseSources() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _NoiseSourcesSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayAnniversaries = _anniversaries
        .where((entry) => entry.isAnniversaryToday(now))
        .toList();
    return GardenBackground(
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 34),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _introController,
              curve: Curves.easeOut,
            ),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .045), end: Offset.zero)
                  .animate(
                    CurvedAnimation(
                      parent: _introController,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '威威给你的蓝色绣球花',
                          style: TextStyle(
                            color: AppColors.deepBlue,
                            fontSize: 13,
                            letterSpacing: 2.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _AnniversaryEntryButton(
                        count: _anniversaries.length,
                        hasToday: todayAnniversaries.isNotEmpty,
                        onPressed: _showAnniversaries,
                      ),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 620),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        sizeFactor: animation,
                        alignment: Alignment.topCenter,
                        child: ScaleTransition(
                          alignment: Alignment.topCenter,
                          scale: Tween(begin: .96, end: 1.0).animate(animation),
                          child: child,
                        ),
                      ),
                    ),
                    child: todayAnniversaries.isEmpty
                        ? const SizedBox(key: ValueKey('no-anniversary'))
                        : Padding(
                            key: ValueKey(
                              todayAnniversaries
                                  .map((entry) => entry.id)
                                  .join('-'),
                            ),
                            padding: const EdgeInsets.only(top: 14),
                            child: _TodayAnniversaryBanner(
                              entries: todayAnniversaries,
                              now: now,
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 228,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Positioned(
                          right: 10,
                          bottom: -6,
                          child: HydrangeaCluster(size: 212),
                        ),
                        Positioned(
                          left: 4,
                          top: 4,
                          child: SizedBox(
                            width: MediaQuery.sizeOf(context).width * .58,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '欢迎回来。',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineLarge,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _greeting,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 16,
                                    height: 1.75,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 88,
                          top: 12,
                          child: RepaintBoundary(
                            child: AnimatedBuilder(
                              animation: _butterflyController,
                              builder: (context, child) {
                                final t = _butterflyController.value;
                                return Transform.translate(
                                  offset: Offset(
                                    -math.sin(t * math.pi) * 28,
                                    math.sin(t * math.pi * 2) * 9,
                                  ),
                                  child: Transform.rotate(
                                    angle: math.sin(t * math.pi * 2) * .12,
                                    child: child,
                                  ),
                                );
                              },
                              child: const Butterfly(size: 42),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _opening ? null : _openButterfly,
                    icon: _opening
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Butterfly(size: 24, color: Colors.white),
                    label: const Text('点开一只蝴蝶'),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 520),
                    switchInCurve: Curves.easeOutBack,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween(begin: .96, end: 1.0).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _quote == null
                        ? const SizedBox(height: 24)
                        : Padding(
                            key: ValueKey(_quote!.text),
                            padding: const EdgeInsets.only(top: 20),
                            child: GardenCard(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.format_quote_rounded,
                                    color: AppColors.hydrangea,
                                    size: 29,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _quote!.text,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.75,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  _WhiteNoiseFoldout(
                    animation: _noiseRevealController,
                    isExpanded: _noiseExpanded,
                    kind: _noiseKind,
                    isPlaying: _noisePlaying,
                    isLoading: _noiseLoading,
                    volume: _noiseVolume,
                    onExpandToggle: _toggleNoisePanel,
                    onToggle: _toggleNoise,
                    onKindChanged: _selectNoise,
                    onVolumeChanged: _setNoiseVolume,
                    onShowSources: _showNoiseSources,
                  ),
                  const SizedBox(height: 16),
                  const _FocusClockEntry(),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ComfortPage()),
                    ),
                    child: const GardenCard(
                      child: Row(
                        children: [
                          _QuietCornerIcon(),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '如果你现在不开心',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  '这里有一个安静的角落，什么都不用解释。',
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
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

class _AnniversaryEntryButton extends StatelessWidget {
  const _AnniversaryEntryButton({
    required this.count,
    required this.hasToday,
    required this.onPressed,
  });

  final int count;
  final bool hasToday;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hasToday ? '今天有特别纪念日，打开纪念日列表' : '打开纪念日列表',
      child: Tooltip(
        message: '我们的纪念日',
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            width: 46,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: hasToday
                    ? const [Color(0xFFD9D7F7), Color(0xFFB7CCF4)]
                    : [
                        Colors.white.withValues(alpha: .74),
                        AppColors.mistBlue.withValues(alpha: .92),
                      ],
              ),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: .8)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.deepBlue.withValues(alpha: .1),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                const Icon(
                  Icons.favorite_border_rounded,
                  color: AppColors.deepBlue,
                  size: 22,
                ),
                const Positioned(
                  left: 4,
                  bottom: 3,
                  child: Butterfly(size: 15),
                ),
                if (count > 0)
                  Positioned(
                    right: -5,
                    top: -7,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 19),
                      height: 19,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hasToday
                            ? const Color(0xFF846CB4)
                            : AppColors.deepBlue,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cream, width: 1.5),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayAnniversaryBanner extends StatelessWidget {
  const _TodayAnniversaryBanner({required this.entries, required this.now});

  final List<Anniversary> entries;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final first = entries.first;
    final years = first.anniversaryYears(now);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(15, 13, 14, 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF4EAF2).withValues(alpha: .96),
            const Color(0xFFE4E9FA).withValues(alpha: .96),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .82)),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: .08),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .72),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Butterfly(size: 29)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '哇宝宝今天非常特殊噢！记得开心~',
                  style: TextStyle(
                    color: AppColors.deepBlue,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${first.message}，已经整整$years年了。',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entries.length > 1) ...[
                  const SizedBox(height: 3),
                  Text(
                    '今天还有 ${entries.length - 1} 个值得轻轻记住的日子。',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(
            Icons.auto_awesome_rounded,
            color: Color(0xFF9B83B8),
            size: 19,
          ),
        ],
      ),
    );
  }
}

class _AnniversaryPopup extends StatefulWidget {
  const _AnniversaryPopup({
    required this.initialEntries,
    required this.onChanged,
  });

  final List<Anniversary> initialEntries;
  final Future<void> Function() onChanged;

  @override
  State<_AnniversaryPopup> createState() => _AnniversaryPopupState();
}

class _AnniversaryPopupState extends State<_AnniversaryPopup> {
  late List<Anniversary> _entries;
  var _revision = 0;
  var _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _entries = List.of(widget.initialEntries);
  }

  Future<void> _reload() async {
    final revision = ++_loadRevision;
    final entries = await LocalDatabase.instance.anniversaries();
    if (!mounted || revision != _loadRevision) return;
    setState(() {
      _entries = entries;
      _revision++;
    });
    await widget.onChanged();
  }

  Future<void> _add() async {
    if (_entries.length >= LocalDatabase.anniversaryLimit) {
      showGardenMessage(context, '纪念日最多保存 100 条，先删除一条再继续添加吧。');
      return;
    }
    final anniversary = await showDialog<Anniversary>(
      context: context,
      builder: (_) => const _AnniversaryEditorDialog(),
    );
    if (anniversary == null || !mounted) return;
    final added = await LocalDatabase.instance.addAnniversary(anniversary);
    if (!mounted) return;
    if (!added) {
      showGardenMessage(context, '纪念日已经有 100 条了，先留出一个位置吧。');
      return;
    }
    await _reload();
    if (mounted) showGardenMessage(context, '这个值得纪念的日子已经收好了。');
  }

  Future<void> _delete(Anniversary entry) async {
    if (entry.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这个纪念日吗？'),
        content: Text(
          '“${entry.message}”\n${gentleDate(entry.date)}\n\n删除后将无法恢复。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('先留着'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await LocalDatabase.instance.deleteAnniversary(entry.id!);
    await _reload();
    if (mounted) showGardenMessage(context, '这个纪念日已经删除。');
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final now = DateTime.now();
    return Container(
      width: math.min(screen.width - 34, 440),
      height: math.min(screen.height * .72, 650),
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: .98),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: .18),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: const BoxDecoration(
                  color: AppColors.mistBlue,
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Butterfly(size: 29)),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '我们的纪念日',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '每个日子都被好好记住',
                      style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '添加纪念日',
                onPressed: _entries.length >= LocalDatabase.anniversaryLimit
                    ? null
                    : _add,
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 2),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 480),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(.05, .02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _entries.isEmpty
                  ? const Center(
                      key: ValueKey('empty-anniversaries'),
                      child: EmptyGarden(
                        message: '还没有纪念日。\n点一下右上角的加号，把重要的那天放进来吧。',
                      ),
                    )
                  : ListView.separated(
                      key: ValueKey('anniversaries-$_revision'),
                      padding: const EdgeInsets.only(bottom: 4),
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        return _AnniversaryListCard(
                          entry: entry,
                          now: now,
                          onDelete: () => _delete(entry),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnniversaryListCard extends StatelessWidget {
  const _AnniversaryListCard({
    required this.entry,
    required this.now,
    required this.onDelete,
  });

  final Anniversary entry;
  final DateTime now;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final specialToday = entry.isAnniversaryToday(now);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 6, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: specialToday
              ? const [Color(0xFFF3E8F2), Color(0xFFE6EBFB)]
              : [
                  Colors.white.withValues(alpha: .86),
                  AppColors.mistBlue.withValues(alpha: .48),
                ],
        ),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: specialToday
              ? const Color(0xFFC7B6DC)
              : Colors.white.withValues(alpha: .85),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: specialToday
                  ? const Color(0xFFE0D5EF)
                  : AppColors.mistBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(
              specialToday
                  ? Icons.auto_awesome_rounded
                  : Icons.favorite_rounded,
              size: 19,
              color: specialToday
                  ? const Color(0xFF8C6BAC)
                  : AppColors.hydrangea,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displaySentence(now),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  specialToday
                      ? '${gentleDate(entry.date)} · 今天是第 ${entry.anniversaryYears(now)} 个周年'
                      : gentleDate(entry.date),
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除这个纪念日',
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.muted,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnniversaryEditorDialog extends StatefulWidget {
  const _AnniversaryEditorDialog();

  @override
  State<_AnniversaryEditorDialog> createState() =>
      _AnniversaryEditorDialogState();
}

class _AnniversaryEditorDialogState extends State<_AnniversaryEditorDialog> {
  final _message = TextEditingController();
  var _date = DateUtils.dateOnly(DateTime.now());

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
      helpText: '选择值得纪念的那一天',
      cancelText: '先不选',
      confirmText: '就是这天',
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  void _save() {
    final message = _message.text.trim();
    if (message.isEmpty) {
      showGardenMessage(context, '先写下这个日子代表什么吧。');
      return;
    }
    Navigator.pop(context, Anniversary(message: message, date: _date));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('收好一个纪念日'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '想纪念啥呢宝宝？',
                style: TextStyle(
                  color: AppColors.deepBlue,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: _message,
                autofocus: true,
                maxLength: 50,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 15),
              const Text(
                '从哪一天开始',
                style: TextStyle(
                  color: AppColors.deepBlue,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.mistBlue.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.softBlue.withValues(alpha: .4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        color: AppColors.deepBlue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        gentleDate(_date),
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.keyboard_arrow_right_rounded,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('先不添加'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.favorite_rounded, size: 18),
          label: const Text('收好这一天'),
        ),
      ],
    );
  }
}

class _FocusClockEntry extends StatefulWidget {
  const _FocusClockEntry();

  @override
  State<_FocusClockEntry> createState() => _FocusClockEntryState();
}

class _FocusClockEntryState extends State<_FocusClockEntry> {
  var _opening = false;

  Future<void> _openClock() async {
    final bridge = FocusTimerBridge.instance;
    if (_opening || bridge.clockIsVisible) return;
    setState(() => _opening = true);
    bridge.clockIsVisible = true;
    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => const FocusClockPage()));
    } finally {
      bridge.clockIsVisible = false;
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '打开横屏专注时钟',
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _opening ? null : _openClock,
        child: GardenCard(
          padding: const EdgeInsets.fromLTRB(15, 12, 13, 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.mistBlue,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: AppColors.deepBlue,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '横屏专注时钟',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '时钟 · 正计时 · 倒计时 · 番茄钟',
                      style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.softBlue.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.screen_rotation_alt_rounded,
                      size: 15,
                      color: AppColors.deepBlue,
                    ),
                    SizedBox(width: 5),
                    Text(
                      '横屏',
                      style: TextStyle(
                        color: AppColors.deepBlue,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhiteNoiseFoldout extends StatelessWidget {
  const _WhiteNoiseFoldout({
    required this.animation,
    required this.isExpanded,
    required this.kind,
    required this.isPlaying,
    required this.isLoading,
    required this.volume,
    required this.onExpandToggle,
    required this.onToggle,
    required this.onKindChanged,
    required this.onVolumeChanged,
    required this.onShowSources,
  });

  final Animation<double> animation;
  final bool isExpanded;
  final WhiteNoiseKind kind;
  final bool isPlaying;
  final bool isLoading;
  final double volume;
  final VoidCallback onExpandToggle;
  final VoidCallback onToggle;
  final ValueChanged<WhiteNoiseKind> onKindChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onShowSources;

  @override
  Widget build(BuildContext context) {
    final sizeReveal = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, .78, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInOutCubic,
    );
    final visualReveal = CurvedAnimation(
      parent: animation,
      curve: const Interval(.08, 1, curve: Curves.easeOutCubic),
      reverseCurve: Curves.easeInCubic,
    );

    return Column(
      children: [
        Semantics(
          button: true,
          expanded: isExpanded,
          label: '陪你安静一会儿，白噪音折叠栏',
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onExpandToggle,
            child: GardenCard(
              padding: const EdgeInsets.fromLTRB(16, 13, 13, 13),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: animation,
                    child: const Butterfly(size: 37),
                    builder: (context, child) {
                      final flight = math.sin(animation.value * math.pi);
                      final flutter = math.sin(animation.value * math.pi * 6);
                      return SizedBox.square(
                        dimension: 46,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Transform.scale(
                              scale: .72 + flight * .5,
                              child: Opacity(
                                opacity: .12 + flight * .2,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(
                                    color: AppColors.softBlue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(15 * flight, -10 * flight),
                              child: Transform.rotate(
                                angle: flutter * .1 - flight * .06,
                                child: Transform.scale(
                                  scale: 1 + flight * .16,
                                  child: child,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '陪你安静一会儿',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 380),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, transition) =>
                              FadeTransition(
                                opacity: transition,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, .25),
                                    end: Offset.zero,
                                  ).animate(transition),
                                  child: child,
                                ),
                              ),
                          child: Text(
                            isPlaying
                                ? '${kind.label}正在轻轻陪着你'
                                : isExpanded
                                ? '小蝴蝶把声音带来了'
                                : '点点小蝴蝶，让雨和风飞出来',
                            key: ValueKey((isPlaying, isExpanded, kind)),
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: animation,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.deepBlue,
                    ),
                    builder: (context, child) => Transform.rotate(
                      angle: animation.value * math.pi,
                      child: Transform.scale(
                        scale: 1 + math.sin(animation.value * math.pi) * .12,
                        child: child,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        IgnorePointer(
          ignoring: !isExpanded,
          child: ExcludeSemantics(
            excluding: !isExpanded,
            child: AnimatedBuilder(
              animation: Listenable.merge([sizeReveal, visualReveal]),
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: RepaintBoundary(
                  child: _WhiteNoiseCard(
                    revealAnimation: animation,
                    kind: kind,
                    isPlaying: isPlaying,
                    isLoading: isLoading,
                    volume: volume,
                    onToggle: onToggle,
                    onKindChanged: onKindChanged,
                    onVolumeChanged: onVolumeChanged,
                    onShowSources: onShowSources,
                  ),
                ),
              ),
              builder: (context, child) {
                final size = sizeReveal.value.clamp(0.0, 1.0);
                final visual = visualReveal.value;
                final opacity = Curves.easeOut.transform(
                  (animation.value / .62).clamp(0.0, 1.0),
                );
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: size,
                    child: Opacity(
                      opacity: opacity,
                      child: Transform.translate(
                        offset: Offset(36 * (1 - visual), -18 * (1 - visual)),
                        child: Transform.scale(
                          alignment: Alignment.topRight,
                          scale: .92 + .08 * visual,
                          child: child,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _WhiteNoiseCard extends StatelessWidget {
  const _WhiteNoiseCard({
    required this.revealAnimation,
    required this.kind,
    required this.isPlaying,
    required this.isLoading,
    required this.volume,
    required this.onToggle,
    required this.onKindChanged,
    required this.onVolumeChanged,
    required this.onShowSources,
  });

  final Animation<double> revealAnimation;
  final WhiteNoiseKind kind;
  final bool isPlaying;
  final bool isLoading;
  final double volume;
  final VoidCallback onToggle;
  final ValueChanged<WhiteNoiseKind> onKindChanged;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onShowSources;

  @override
  Widget build(BuildContext context) {
    return GardenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StaggerReveal(
            animation: revealAnimation,
            begin: .12,
            end: .54,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: AppColors.mistBlue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(kind.icon, color: AppColors.deepBlue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kind.label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isPlaying ? '正在播放 · 完全离线' : '真实环境录音 · 完全离线',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: isPlaying ? '暂停白噪音' : '播放${kind.label}',
                  onPressed: isLoading ? null : onToggle,
                  icon: isLoading
                      ? const SizedBox.square(
                          dimension: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _StaggerReveal(
            animation: revealAnimation,
            begin: .24,
            end: .68,
            horizontal: 16,
            child: Wrap(
              spacing: 9,
              runSpacing: 8,
              children: WhiteNoiseKind.values
                  .map(
                    (item) => ChoiceChip(
                      avatar: Icon(item.icon, size: 18),
                      label: Text(item.label),
                      selected: item == kind,
                      onSelected: (_) => onKindChanged(item),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 10),
          _StaggerReveal(
            animation: revealAnimation,
            begin: .38,
            end: .8,
            child: Row(
              children: [
                const Icon(
                  Icons.volume_down_rounded,
                  color: AppColors.muted,
                  size: 21,
                ),
                Expanded(
                  child: _NoiseVolumeSlider(
                    value: volume,
                    onChanged: onVolumeChanged,
                  ),
                ),
                const Icon(
                  Icons.volume_up_rounded,
                  color: AppColors.muted,
                  size: 21,
                ),
              ],
            ),
          ),
          _StaggerReveal(
            animation: revealAnimation,
            begin: .52,
            end: .92,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onShowSources,
                icon: const Icon(Icons.info_outline_rounded, size: 17),
                label: const Text('录音来源'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoiseVolumeSlider extends StatefulWidget {
  const _NoiseVolumeSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_NoiseVolumeSlider> createState() => _NoiseVolumeSliderState();
}

class _NoiseVolumeSliderState extends State<_NoiseVolumeSlider> {
  Timer? _flushTimer;
  double? _pendingValue;
  late double _value;
  var _dragging = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _NoiseVolumeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }

  void _queueVolume(double value) {
    setState(() => _value = value);
    _pendingValue = value;
    _flushTimer ??= Timer(const Duration(milliseconds: 45), _flush);
  }

  void _flush() {
    _flushTimer = null;
    final value = _pendingValue;
    _pendingValue = null;
    if (value != null) widget.onChanged(value);
  }

  void _finish(double value) {
    _dragging = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingValue = null;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: _value,
      min: .08,
      max: .75,
      onChangeStart: (_) => _dragging = true,
      onChanged: _queueVolume,
      onChangeEnd: _finish,
    );
  }
}

class _StaggerReveal extends StatelessWidget {
  const _StaggerReveal({
    required this.animation,
    required this.begin,
    required this.end,
    required this.child,
    this.horizontal = 0,
  });

  final Animation<double> animation;
  final double begin;
  final double end;
  final double horizontal;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final interval = ((animation.value - begin) / (end - begin)).clamp(
          0.0,
          1.0,
        );
        final t = Curves.easeOutCubic.transform(interval);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(horizontal * (1 - t), 14 * (1 - t)),
            child: child,
          ),
        );
      },
    );
  }
}

class _NoiseSourcesSheet extends StatelessWidget {
  const _NoiseSourcesSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('真实录音来源', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
              '三段真实环境录音都已制作成约 50 分钟的平滑音轨；雨夜、海风和花园轻梦由它们轻柔叠合，全部离线播放。',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 18),
            ...WhiteNoiseKind.values.map(
              (sound) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(sound.icon, color: AppColors.deepBlue),
                title: Text('${sound.label} · ${sound.sourceTitle}'),
                subtitle: Text(sound.sourceId),
              ),
            ),
            const Divider(height: 24),
            const Text(
              whiteNoiseLicense,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

extension on WhiteNoiseKind {
  IconData get icon => switch (this) {
    WhiteNoiseKind.rain => Icons.water_drop_outlined,
    WhiteNoiseKind.ocean => Icons.waves_rounded,
    WhiteNoiseKind.breeze => Icons.air_rounded,
    WhiteNoiseKind.rainyNight => Icons.nights_stay_outlined,
    WhiteNoiseKind.coastalBreeze => Icons.sailing_rounded,
    WhiteNoiseKind.gardenDream => Icons.local_florist_outlined,
  };
}

class _QuietCornerIcon extends StatelessWidget {
  const _QuietCornerIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.mistBlue,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.nights_stay_outlined, color: AppColors.deepBlue),
    );
  }
}
