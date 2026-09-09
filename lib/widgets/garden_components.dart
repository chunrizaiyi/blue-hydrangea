import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'garden_background.dart';

class GardenPageHeader extends StatelessWidget {
  const GardenPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, height: 1.6),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class GardenCard extends StatelessWidget {
  const GardenCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .76),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: .72)),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBlue.withValues(alpha: .06),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class LocalImage extends StatelessWidget {
  const LocalImage({super.key, required this.path, this.height = 180});

  final String path;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.file(
        File(path),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          height: height,
          color: AppColors.mistBlue,
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.muted,
          ),
        ),
      ),
    );
  }
}

class EmptyGarden extends StatelessWidget {
  const EmptyGarden({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          const Opacity(opacity: .65, child: HydrangeaCluster(size: 110)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

String gentleDate(DateTime date) => DateFormat('yyyy年 M月 d日').format(date);

Future<DateTime?> pickGardenDate(BuildContext context, DateTime initial) {
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    helpText: '选择这一天',
    cancelText: '先不选',
    confirmText: '就是这天',
  );
}

bool gardenDateIsInRange(DateTime date, DateTimeRange? range) {
  if (range == null) return true;
  final day = DateUtils.dateOnly(date);
  final start = DateUtils.dateOnly(range.start);
  final end = DateUtils.dateOnly(range.end);
  return !day.isBefore(start) && !day.isAfter(end);
}

String gardenDateRangeLabel(DateTimeRange range) {
  final start = DateUtils.dateOnly(range.start);
  final end = DateUtils.dateOnly(range.end);
  if (start == end) return gentleDate(start);
  return '${DateFormat('yyyy.M.d').format(start)} — ${DateFormat('yyyy.M.d').format(end)}';
}

class GardenDateFilterSelection {
  const GardenDateFilterSelection(this.range);

  final DateTimeRange? range;
}

Future<GardenDateFilterSelection?> showGardenDateFilterPopup(
  BuildContext context,
  DateTimeRange? current,
) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<GardenDateFilterSelection>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭日期筛选',
    barrierColor: AppColors.deepBlue.withValues(alpha: .24),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 360),
    pageBuilder: (context, _, __) => SafeArea(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: _GardenDateFilterPopup(current: current),
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

class GardenDateFilterButton extends StatelessWidget {
  const GardenDateFilterButton({
    super.key,
    required this.range,
    required this.onPressed,
  });

  final DateTimeRange? range;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = range != null;
    return IconButton.filledTonal(
      tooltip: active ? '修改日期筛选：${gardenDateRangeLabel(range!)}' : '按日期筛选',
      onPressed: onPressed,
      icon: Badge(
        isLabelVisible: active,
        smallSize: 8,
        backgroundColor: AppColors.deepBlue,
        child: Icon(
          active ? Icons.calendar_month_rounded : Icons.calendar_month_outlined,
        ),
      ),
    );
  }
}

class GardenFilterReveal extends StatelessWidget {
  const GardenFilterReveal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 520),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 13 * (1 - value)),
          child: Transform.scale(
            scale: .985 + .015 * value,
            alignment: Alignment.topCenter,
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

class _GardenDateFilterPopup extends StatefulWidget {
  const _GardenDateFilterPopup({required this.current});

  final DateTimeRange? current;

  @override
  State<_GardenDateFilterPopup> createState() => _GardenDateFilterPopupState();
}

enum _RangeCalendarMode { range, endOnly }

class _GardenDateFilterPopupState extends State<_GardenDateFilterPopup> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _visibleMonth;
  _RangeCalendarMode? _calendarMode;
  var _rangeAwaitingEnd = false;
  var _endEditWasUsed = false;

  @override
  void initState() {
    super.initState();
    final today = DateUtils.dateOnly(DateTime.now());
    _start = widget.current == null
        ? null
        : DateUtils.dateOnly(widget.current!.start);
    _end = widget.current == null
        ? null
        : DateUtils.dateOnly(widget.current!.end);
    final initialMonth = _start ?? today;
    _visibleMonth = DateTime(initialMonth.year, initialMonth.month);
  }

  void _setPreset(DateTime start, DateTime end) {
    setState(() {
      _start = DateUtils.dateOnly(start);
      _end = DateUtils.dateOnly(end);
      _calendarMode = null;
      _rangeAwaitingEnd = false;
      _endEditWasUsed = false;
    });
  }

  void _openRangeCalendar() {
    final initial = _start ?? DateTime.now();
    setState(() {
      _calendarMode = _RangeCalendarMode.range;
      _rangeAwaitingEnd = false;
      _visibleMonth = DateTime(initial.year, initial.month);
    });
  }

  void _openEndCalendar() {
    final initial = _end ?? _start ?? DateTime.now();
    setState(() {
      if (_start != null && _end != null && !_endEditWasUsed) {
        _calendarMode = _RangeCalendarMode.endOnly;
        _endEditWasUsed = true;
      } else {
        _calendarMode = _RangeCalendarMode.range;
        _rangeAwaitingEnd = false;
      }
      _visibleMonth = DateTime(initial.year, initial.month);
    });
  }

  void _selectCalendarDate(DateTime value) {
    final day = DateUtils.dateOnly(value);
    setState(() {
      if (_calendarMode == _RangeCalendarMode.endOnly) {
        if (_start != null && !day.isBefore(_start!)) _end = day;
        return;
      }

      if (!_rangeAwaitingEnd || _start == null) {
        _start = day;
        _end = null;
        _rangeAwaitingEnd = true;
        return;
      }

      final first = _start!;
      if (day.isBefore(first)) {
        _start = day;
        _end = first;
      } else {
        _end = day;
      }
      _rangeAwaitingEnd = false;
      _endEditWasUsed = false;
    });
  }

  void _moveCalendarMonth(int amount) {
    final candidate = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + amount,
    );
    final firstMonth = DateTime(2000);
    final lastDay = DateTime.now().add(const Duration(days: 365));
    final lastMonth = DateTime(lastDay.year, lastDay.month);
    if (candidate.isBefore(firstMonth) || candidate.isAfter(lastMonth)) return;
    setState(() => _visibleMonth = candidate);
  }

  String get _calendarHint {
    if (_calendarMode == _RangeCalendarMode.endOnly) {
      return '开始日期 ${DateFormat('yyyy.M.d').format(_start!)} 已固定，只需点新的结束日期';
    }
    if (_rangeAwaitingEnd && _start != null) {
      return '已选 ${DateFormat('yyyy.M.d').format(_start!)}，再点一次结束日期；同一天也可以';
    }
    if (_start != null && _end != null) {
      return '范围已经选好；继续点日期可以重新选择';
    }
    return '先点开始日期，再点结束日期';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final monthStart = DateTime(today.year, today.month);
    final monthEnd = DateTime(today.year, today.month + 1, 0);
    final screen = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: screen.width < 390 ? screen.width - 28 : 362,
        maxHeight: screen.height * .9,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cream.withValues(alpha: .98),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: .92)),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepBlue.withValues(alpha: .18),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.softBlue.withValues(alpha: .3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.calendar_month_rounded,
                      color: AppColors.deepBlue,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '按日期筛选',
                          style: TextStyle(
                            color: AppColors.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '在同一个日历里点选日期范围',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭筛选',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    label: const Text('今天'),
                    onPressed: () => _setPreset(today, today),
                  ),
                  ActionChip(
                    label: const Text('近7天'),
                    onPressed: () => _setPreset(
                      today.subtract(const Duration(days: 6)),
                      today,
                    ),
                  ),
                  ActionChip(
                    label: const Text('本月'),
                    onPressed: () => _setPreset(monthStart, monthEnd),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _DateFilterField(
                      label: '开始日期',
                      date: _start,
                      active: _calendarMode == _RangeCalendarMode.range,
                      onTap: _openRangeCalendar,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 7),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.muted,
                      size: 18,
                    ),
                  ),
                  Expanded(
                    child: _DateFilterField(
                      label: '结束日期',
                      date: _end,
                      active: _calendarMode == _RangeCalendarMode.endOnly,
                      onTap: _openEndCalendar,
                    ),
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 420),
                switchInCurve: Curves.easeOutQuart,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    alignment: AlignmentDirectional.topStart,
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0, -.025),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                ),
                child: _calendarMode == null
                    ? const SizedBox.shrink(key: ValueKey('closed-calendar'))
                    : Padding(
                        key: const ValueKey('open-calendar'),
                        padding: const EdgeInsets.only(top: 15),
                        child: Column(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              child: Text(
                                _calendarHint,
                                key: ValueKey(_calendarHint),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.hydrangea,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _GardenRangeCalendar(
                              displayedMonth: _visibleMonth,
                              start: _start,
                              end: _end,
                              lockStart:
                                  _calendarMode == _RangeCalendarMode.endOnly,
                              onPreviousMonth: () => _moveCalendarMonth(-1),
                              onNextMonth: () => _moveCalendarMonth(1),
                              onDateSelected: _selectCalendarDate,
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _calendarMode = null),
                              icon: const Icon(Icons.keyboard_arrow_up_rounded),
                              label: const Text('收起日历'),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (widget.current != null)
                    TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const GardenDateFilterSelection(null),
                      ),
                      child: const Text('清除筛选'),
                    )
                  else
                    const Spacer(),
                  if (widget.current != null) const Spacer(),
                  FilledButton.icon(
                    onPressed: _start == null || _end == null
                        ? null
                        : () => Navigator.pop(
                            context,
                            GardenDateFilterSelection(
                              DateTimeRange(start: _start!, end: _end!),
                            ),
                          ),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('查看结果'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GardenRangeCalendar extends StatelessWidget {
  const _GardenRangeCalendar({
    required this.displayedMonth,
    required this.start,
    required this.end,
    required this.lockStart,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDateSelected,
  });

  final DateTime displayedMonth;
  final DateTime? start;
  final DateTime? end;
  final bool lockStart;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDateSelected;

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && DateUtils.isSameDay(a, b);

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(displayedMonth.year, displayedMonth.month);
    final daysInMonth = DateTime(
      displayedMonth.year,
      displayedMonth.month + 1,
      0,
    ).day;
    final leadingDays = firstDay.weekday - DateTime.monday;
    final today = DateUtils.dateOnly(DateTime.now());
    final lastAllowed = today.add(const Duration(days: 365));
    final firstAllowedMonth = DateTime(2000);
    final lastAllowedMonth = DateTime(lastAllowed.year, lastAllowed.month);
    final canGoPrevious = firstDay.isAfter(firstAllowedMonth);
    final canGoNext = firstDay.isBefore(lastAllowedMonth);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.softBlue.withValues(alpha: .3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上个月',
                onPressed: canGoPrevious ? onPreviousMonth : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Text(
                    DateFormat('yyyy年 M月').format(firstDay),
                    key: ValueKey(firstDay),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: '下个月',
                onPressed: canGoNext ? onNextMonth : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Row(
            children: ['一', '二', '三', '四', '五', '六', '日']
                .map(
                  (label) => Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: GridView.builder(
              key: ValueKey(firstDay),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.05,
              ),
              itemBuilder: (context, index) {
                final dayNumber = index - leadingDays + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const SizedBox.shrink();
                }
                final day = DateTime(
                  displayedMonth.year,
                  displayedMonth.month,
                  dayNumber,
                );
                final disabled =
                    day.isBefore(DateTime(2000)) ||
                    day.isAfter(lastAllowed) ||
                    (lockStart && start != null && day.isBefore(start!));
                final isStart = _sameDay(start, day);
                final isEnd = _sameDay(end, day);
                final isEndpoint = isStart || isEnd;
                final isInRange =
                    start != null &&
                    end != null &&
                    !day.isBefore(start!) &&
                    !day.isAfter(end!);
                final isToday = DateUtils.isSameDay(today, day);

                return Semantics(
                  button: !disabled,
                  selected: isEndpoint,
                  label:
                      '${DateFormat('yyyy年M月d日').format(day)}'
                      '${isStart ? '，开始日期' : ''}'
                      '${isEnd ? '，结束日期' : ''}',
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: disabled ? null : () => onDateSelected(day),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isEndpoint
                              ? AppColors.deepBlue
                              : isInRange
                              ? AppColors.softBlue.withValues(alpha: .42)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: isToday && !isEndpoint
                              ? Border.all(color: AppColors.hydrangea)
                              : null,
                        ),
                        child: Text(
                          '$dayNumber',
                          style: TextStyle(
                            color: disabled
                                ? AppColors.muted.withValues(alpha: .38)
                                : isEndpoint
                                ? Colors.white
                                : AppColors.ink,
                            fontWeight: isEndpoint
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DateFilterField extends StatelessWidget {
  const _DateFilterField({
    required this.label,
    required this.date,
    required this.active,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: active
            ? AppColors.softBlue.withValues(alpha: .3)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Text(
              date == null ? '点击选择' : DateFormat('yyyy.M.d').format(date!),
              key: ValueKey(date),
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

void showGardenMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.deepBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
}
