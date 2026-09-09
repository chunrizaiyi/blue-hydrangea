import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/garden_models.dart';
import '../services/local_database.dart';
import '../services/mood_statistics.dart';
import '../services/mood_time.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_background.dart';
import '../widgets/garden_components.dart';

const _moodChoices = [('开心', '😊'), ('普通', '🙂'), ('有点累', '😔'), ('不开心', '😣')];

class MoodPage extends StatefulWidget {
  const MoodPage({super.key});

  @override
  State<MoodPage> createState() => _MoodPageState();
}

class _MoodPageState extends State<MoodPage>
    with SingleTickerProviderStateMixin {
  final _note = TextEditingController();
  List<MoodEntry>? _history;
  DateTimeRange? _dateRange;
  var _filterRevision = 0;
  var _loadRevision = 0;
  late final AnimationController _floatController;
  var _selected = '普通';
  var _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reloadHistory());
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  Future<void> _reloadHistory() async {
    final revision = ++_loadRevision;
    try {
      final history = await LocalDatabase.instance.moods();
      if (mounted && revision == _loadRevision) {
        setState(() => _history = history);
      }
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() => _history ??= const []);
        showGardenMessage(context, '心情记录暂时没有读取成功，稍后再试一次好吗？');
      }
    }
  }

  Future<void> _pickDateFilter() async {
    final selection = await showGardenDateFilterPopup(context, _dateRange);
    if (selection == null || !mounted) return;
    setState(() {
      _dateRange = selection.range;
      _filterRevision++;
    });
  }

  Future<void> _showStatistics() async {
    if (_history == null) {
      showGardenMessage(context, '心情记录还在轻轻整理，请稍等一下。');
      return;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭心情统计',
      barrierColor: AppColors.deepBlue.withValues(alpha: .28),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 380),
      pageBuilder: (context, _, __) => SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: _MoodStatisticsOverlay(entries: List.of(_history!)),
          ),
        ),
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: .96, end: 1.0).animate(curved),
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .025),
                end: Offset.zero,
              ).animate(curved),
              child: RepaintBoundary(child: child),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _note.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    final recordedAt = DateTime.now();
    try {
      final added = await LocalDatabase.instance.saveMood(
        mood: _selected,
        note: _note.text.trim(),
        date: recordedAt,
      );
      if (!mounted) return;
      if (!added) {
        showGardenMessage(context, '心情最多保存 1500 条，先删除一条再继续记录吧。');
        return;
      }
      _note.clear();
      await _reloadHistory();
      if (mounted) {
        showGardenMessage(context, '${moodTimeLabel(recordedAt)} 的心情已经被轻轻收好了。');
      }
    } catch (_) {
      if (mounted) showGardenMessage(context, '这条心情暂时没有保存成功，请再试一次。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editMood(MoodEntry entry) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditMoodSheet(entry: entry),
    );
    if (saved != true || !mounted) return;
    await _reloadHistory();
    if (!mounted) return;
    showGardenMessage(context, '这一天还在，只是换成了你现在想留下的样子。');
  }

  Future<void> _deleteMood(MoodEntry entry) async {
    if (entry.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条心情吗？'),
        content: Text(
          '${gentleDate(entry.date)} · ${moodTimeLabel(entry.date)} 的这条心情，删除后将无法恢复。',
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
    await LocalDatabase.instance.deleteMood(entry.id!);
    await _reloadHistory();
    if (mounted) showGardenMessage(context, '这条心情已经删除。');
  }

  String _emojiFor(String mood) => _moodChoices
      .firstWhere((item) => item.$1 == mood, orElse: () => (mood, '🌿'))
      .$2;

  Widget _buildMoodEntry(MoodEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => _editMood(entry),
        child: GardenCard(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
          child: Row(
            children: [
              Text(_emojiFor(entry.mood), style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.mood.isEmpty ? '这一天被记住了' : entry.mood,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (entry.note.isNotEmpty)
                      Text(
                        entry.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 100,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      gentleDate(entry.date),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      moodTimeLabel(entry.date),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppColors.hydrangea,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: '修改这条心情',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _editMood(entry),
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: AppColors.hydrangea,
                            size: 19,
                          ),
                        ),
                        IconButton(
                          tooltip: '删除这条心情',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _deleteMood(entry),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.muted,
                            size: 19,
                          ),
                        ),
                      ],
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

  Widget _buildMoodComposer() {
    return GardenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '此刻更接近哪一种？',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _moodChoices.map((choice) {
              final selected = _selected == choice.$1;
              return Semantics(
                button: true,
                selected: selected,
                label: choice.$1,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(() => _selected = choice.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: 64,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.softBlue.withValues(alpha: .45)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppColors.hydrangea
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(choice.$2, style: const TextStyle(fontSize: 27)),
                        const SizedBox(height: 4),
                        Text(
                          choice.$1,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? AppColors.deepBlue
                                : AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(hintText: '想留下一句话吗？（可以不写）'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '正在收好……' : '新增这条心情'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleHistory = _history
        ?.where((entry) => gardenDateIsInRange(entry.date, _dateRange))
        .toList();
    return GardenBackground(
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 9),
              sliver: SliverList.list(
                children: [
                  GardenPageHeader(
                    title: '今天的心情',
                    subtitle: '不用分析，也没有分数。只是让今天的你，被好好看见。',
                    trailing: AnimatedBuilder(
                      animation: _floatController,
                      builder: (_, child) => Transform.translate(
                        offset: Offset(0, -5 * _floatController.value),
                        child: child,
                      ),
                      child: _StatisticsButterflyButton(
                        onPressed: _showStatistics,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _buildMoodComposer(),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '最近的心情',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GardenDateFilterButton(
                        range: _dateRange,
                        onPressed: _pickDateFilter,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_history == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (visibleHistory!.isEmpty)
              SliverToBoxAdapter(
                child: GardenFilterReveal(
                  key: ValueKey('empty-$_filterRevision'),
                  child: EmptyGarden(
                    message: _history!.isEmpty
                        ? '从今天开始，慢慢记录自己的感受。'
                        : '这段日期里还没有心情记录。',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 27),
                sliver: SliverList.builder(
                  itemCount: visibleHistory.length,
                  itemBuilder: (context, index) {
                    final entry = visibleHistory[index];
                    return GardenFilterReveal(
                      key: ValueKey('$_filterRevision-${entry.id ?? index}'),
                      child: _buildMoodEntry(entry),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsButterflyButton extends StatelessWidget {
  const _StatisticsButterflyButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '打开心情统计',
      child: Semantics(
        button: true,
        label: '打开心情统计',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Container(
              width: 54,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.lavender.withValues(alpha: .7),
                    Colors.white.withValues(alpha: .72),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.hydrangea.withValues(alpha: .22),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Butterfly(size: 35, color: Color(0xFF8E79BC)),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: const BoxDecoration(
                        color: AppColors.deepBlue,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bar_chart_rounded,
                        size: 13,
                        color: Colors.white,
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

class _MoodStatisticsOverlay extends StatefulWidget {
  const _MoodStatisticsOverlay({required this.entries});

  final List<MoodEntry> entries;

  @override
  State<_MoodStatisticsOverlay> createState() => _MoodStatisticsOverlayState();
}

class _MoodStatisticsOverlayState extends State<_MoodStatisticsOverlay> {
  var _period = MoodStatisticsPeriod.week;
  var _anchor = DateTime.now();

  MoodPeriodStatistics get _statistics =>
      calculateMoodStatistics(widget.entries, _period, _anchor);

  String _periodLabelFor(MoodPeriodStatistics statistics) {
    if (_period == MoodStatisticsPeriod.month) {
      return '${statistics.start.year}年 ${statistics.start.month}月';
    }
    final end = statistics.endExclusive.subtract(const Duration(days: 1));
    if (statistics.start.year == end.year) {
      return '${statistics.start.year}年 ${statistics.start.month}月${statistics.start.day}日'
          ' — ${end.month}月${end.day}日';
    }
    return '${statistics.start.year}.${statistics.start.month}.${statistics.start.day}'
        ' — ${end.year}.${end.month}.${end.day}';
  }

  bool _canMoveBackFor(MoodPeriodStatistics statistics) {
    if (widget.entries.isEmpty) return false;
    final oldest = widget.entries
        .map((entry) => entry.date)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return statistics.start.isAfter(moodPeriodStart(oldest, _period));
  }

  bool _canMoveForwardFor(MoodPeriodStatistics statistics) =>
      statistics.start.isBefore(moodPeriodStart(DateTime.now(), _period));

  void _changePeriod(MoodStatisticsPeriod period) {
    setState(() {
      _period = period;
      _anchor = DateTime.now();
    });
  }

  void _movePeriod(int amount) {
    setState(() => _anchor = shiftMoodPeriod(_anchor, _period, amount));
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final statistics = _statistics;
    final periodLabel = _periodLabelFor(statistics);
    final canMoveBack = _canMoveBackFor(statistics);
    final canMoveForward = _canMoveForwardFor(statistics);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.min(430.0, screen.width - 28),
        maxHeight: screen.height * .82,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cream.withValues(alpha: .98),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: .92)),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlue.withValues(alpha: .2),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              Positioned(
                right: -48,
                top: -58,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: AppColors.lavender.withValues(alpha: .42),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _StatisticsMark(size: 48),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '心情小统计',
                                style: TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '看看这一段时间里的心情颜色',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭统计',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<MoodStatisticsPeriod>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: MoodStatisticsPeriod.week,
                            label: Text('按周'),
                            icon: Icon(Icons.view_week_outlined),
                          ),
                          ButtonSegment(
                            value: MoodStatisticsPeriod.month,
                            label: Text('按月'),
                            icon: Icon(Icons.calendar_view_month_rounded),
                          ),
                        ],
                        selected: {_period},
                        onSelectionChanged: (selection) {
                          _changePeriod(selection.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip:
                              '上一${_period == MoodStatisticsPeriod.week ? '周' : '月'}',
                          onPressed: canMoveBack ? () => _movePeriod(-1) : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            child: Text(
                              periodLabel,
                              key: ValueKey(periodLabel),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip:
                              '下一${_period == MoodStatisticsPeriod.week ? '周' : '月'}',
                          onPressed: canMoveForward
                              ? () => _movePeriod(1)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 13),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .72),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: AppColors.softBlue.withValues(alpha: .26),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statistics.total == 0
                                ? '这段时间还没有留下心情'
                                : '这段时间共记录 ${statistics.total} 次',
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _MoodBarChart(counts: statistics.counts),
                        ],
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

class _StatisticsMark extends StatelessWidget {
  const _StatisticsMark({this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Butterfly(size: 38, color: Color(0xFF8E79BC)),
          Positioned(
            right: 0,
            bottom: 1,
            child: Container(
              width: 19,
              height: 19,
              decoration: const BoxDecoration(
                color: AppColors.deepBlue,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.bar_chart_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodBarChart extends StatelessWidget {
  const _MoodBarChart({required this.counts});

  final Map<String, int> counts;

  static const _emojis = ['😊', '🙂', '😔', '😣'];
  static const _colors = [
    AppColors.leaf,
    AppColors.hydrangea,
    Color(0xFF9A8FC2),
    Color(0xFFC58F9D),
  ];

  @override
  Widget build(BuildContext context) {
    final values = moodNames.map((mood) => counts[mood] ?? 0).toList();
    final maximum = math.max(1, values.reduce(math.max));
    final summary = List.generate(
      moodNames.length,
      (index) => '${moodNames[index]} ${values[index]} 次',
    ).join('，');

    return Semantics(
      label: '心情数量柱状图：$summary',
      child: SizedBox(
        height: 210,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(moodNames.length, (index) {
            final value = values[index];
            final ratio = value / maximum;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  children: [
                    Text(
                      '$value',
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              Container(
                                width: 34,
                                decoration: BoxDecoration(
                                  color: AppColors.mistBlue.withValues(
                                    alpha: .58,
                                  ),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              TweenAnimationBuilder<double>(
                                tween: Tween(end: ratio),
                                duration: const Duration(milliseconds: 620),
                                curve: Curves.easeOutQuart,
                                builder: (context, animatedRatio, child) {
                                  return Container(
                                    width: 34,
                                    height:
                                        constraints.maxHeight * animatedRatio,
                                    decoration: BoxDecoration(
                                      color: _colors[index],
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(_emojis[index], style: const TextStyle(fontSize: 20)),
                    Text(
                      moodNames[index],
                      maxLines: 1,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _EditMoodSheet extends StatefulWidget {
  const _EditMoodSheet({required this.entry});

  final MoodEntry entry;

  @override
  State<_EditMoodSheet> createState() => _EditMoodSheetState();
}

class _EditMoodSheetState extends State<_EditMoodSheet> {
  late final TextEditingController _note;
  late String _selected;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.entry.note);
    _selected = _moodChoices.any((choice) => choice.$1 == widget.entry.mood)
        ? widget.entry.mood
        : '普通';
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await LocalDatabase.instance.updateMood(
        MoodEntry(
          id: widget.entry.id,
          mood: _selected,
          note: _note.text.trim(),
          date: widget.entry.date,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) showGardenMessage(context, '修改暂时没有保存成功，请再试一次。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          22,
          0,
          22,
          22 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              Text('修改这天的心情', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                '${gentleDate(widget.entry.date)} · ${moodTimeLabel(widget.entry.date)}\n'
                '备注可以留空，这一天不会消失。',
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _moodChoices.map((choice) {
                  final selected = _selected == choice.$1;
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => _selected = choice.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      width: 68,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.softBlue.withValues(alpha: .45)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected
                              ? AppColors.hydrangea
                              : AppColors.softBlue.withValues(alpha: .25),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(choice.$2, style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 3),
                          Text(choice.$1, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text(
                '想留下的话（可以清空）',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(hintText: '也可以什么都不写。'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '正在保存……' : '保存修改'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
