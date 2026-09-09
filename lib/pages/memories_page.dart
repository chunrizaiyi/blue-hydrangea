import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/garden_models.dart';
import '../services/image_service.dart';
import '../services/local_database.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_background.dart';
import '../widgets/garden_components.dart';

class MemoriesPage extends StatefulWidget {
  const MemoriesPage({super.key});

  @override
  State<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends State<MemoriesPage> {
  List<Memory>? _memories;
  DateTimeRange? _dateRange;
  var _filterRevision = 0;
  var _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final revision = ++_loadRevision;
    try {
      final memories = await LocalDatabase.instance.memories();
      if (mounted && revision == _loadRevision) {
        setState(() => _memories = memories);
      }
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() => _memories ??= const []);
        showGardenMessage(context, '回忆暂时没有读取成功，稍后再试一次好吗？');
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

  Future<void> _add() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddMemoryPage()));
    if (saved == true) await _reload();
  }

  Future<void> _edit(Memory memory) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddMemoryPage(initialMemory: memory)),
    );
    if (saved == true) await _reload();
  }

  Future<void> _openDetail(Memory memory) async {
    final result = await Navigator.of(context).push<_MemoryDetailResult>(
      _MemoryDetailRoute(
        memory: memory,
        onMemoryChanged: _replaceMemoryLocally,
      ),
    );
    if (!mounted || result == null) return;
    if (result.deleteRequested) {
      await _delete(result.memory, alreadyConfirmed: true);
    } else if (result.changed) {
      await _reload();
    }
  }

  void _replaceMemoryLocally(Memory updated) {
    final memories = _memories;
    if (!mounted || memories == null) return;
    final index = memories.indexWhere((memory) => memory.id == updated.id);
    if (index < 0) return;
    final next = List<Memory>.of(memories)..[index] = updated;
    setState(() => _memories = next);
  }

  Future<void> _delete(Memory memory, {bool alreadyConfirmed = false}) async {
    if (memory.id == null) return;
    var confirmed = alreadyConfirmed;
    if (!confirmed) {
      confirmed =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('删除这段回忆吗？'),
              content: Text(
                '${DateFormat('yyyy年 M月 d日').format(memory.date)} 的回忆和其中的照片，删除后将无法恢复。',
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
          ) ==
          true;
    }
    if (!confirmed) return;
    try {
      await LocalDatabase.instance.deleteMemory(memory.id!);
      await ImageService.deleteKeptImages(memory.allImagePaths);
      await _reload();
      if (mounted) showGardenMessage(context, '这段回忆已经删除。');
    } catch (_) {
      if (mounted) showGardenMessage(context, '这段回忆暂时没有删除成功，请再试一次。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleMemories = _memories
        ?.where((memory) => gardenDateIsInRange(memory.date, _dateRange))
        .toList();
    return GardenBackground(
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 24),
              sliver: SliverToBoxAdapter(
                child: GardenPageHeader(
                  title: '我们的回忆',
                  subtitle: '日子也许普通，但被认真记住以后，就会一直发着柔光。',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GardenDateFilterButton(
                        range: _dateRange,
                        onPressed: _pickDateFilter,
                      ),
                      const SizedBox(width: 7),
                      IconButton.filledTonal(
                        tooltip: '收藏一段回忆',
                        onPressed: _add,
                        icon: const Icon(Icons.add_a_photo_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_memories == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visibleMemories!.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: GardenFilterReveal(
                  key: ValueKey('empty-$_filterRevision'),
                  child: EmptyGarden(
                    message: _memories!.isEmpty
                        ? '以后走过的每一天，都可以从这里收藏。'
                        : '这段日期里还没有收藏的回忆。',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 22, 34),
                sliver: SliverList.builder(
                  itemCount: visibleMemories.length,
                  itemBuilder: (context, index) {
                    final memory = visibleMemories[index];
                    return GardenFilterReveal(
                      key: ValueKey('$_filterRevision-${memory.id ?? index}'),
                      child: _TimelineMemory(
                        memory: memory,
                        isLast: index == visibleMemories.length - 1,
                        onOpen: () => _openDetail(memory),
                        onEdit: () => _edit(memory),
                        onDelete: () => _delete(memory),
                      ),
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

class _TimelineMemory extends StatelessWidget {
  const _TimelineMemory({
    required this.memory,
    required this.isLast,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final Memory memory;
  final bool isLast;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final images = memory.allImagePaths;
    return Stack(
      children: [
        Positioned(
          left: 16,
          top: 26,
          bottom: isLast ? 24 : 0,
          child: Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: AppColors.hydrangea,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    color: AppColors.softBlue.withValues(alpha: .65),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 34, bottom: 20),
          child: Semantics(
            button: true,
            label: '打开 ${DateFormat('yyyy年 M月 d日').format(memory.date)} 的回忆详情',
            child: InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: onOpen,
              child: GardenCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (images.isNotEmpty) ...[
                      _MemoryPhotoStack(
                        paths: images,
                        heroTag: _memoryHeroTag(memory),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            DateFormat('yyyy年 M月 d日').format(memory.date),
                            style: const TextStyle(
                              color: AppColors.hydrangea,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '修改这段回忆',
                          visualDensity: VisualDensity.compact,
                          onPressed: onEdit,
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: AppColors.hydrangea,
                            size: 20,
                          ),
                        ),
                        IconButton(
                          tooltip: '删除这段回忆',
                          visualDensity: VisualDensity.compact,
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.muted,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      memory.note.isEmpty ? '这一天被轻轻留在这里。' : memory.note,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.7,
                        color: memory.note.isEmpty
                            ? AppColors.muted
                            : AppColors.ink,
                        fontStyle: memory.note.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    if (memory.place?.isNotEmpty == true) ...[
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            color: AppColors.muted,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              memory.place!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (images.length > 1) ...[
                            const Icon(
                              Icons.collections_outlined,
                              size: 14,
                              color: AppColors.hydrangea,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${images.length} 张照片',
                              style: const TextStyle(
                                color: AppColors.hydrangea,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          const Text(
                            '轻点展开',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _memoryHeroTag(Memory memory) => 'memory-cover-${memory.id}';

class _MemoryPhotoStack extends StatelessWidget {
  const _MemoryPhotoStack({required this.paths, required this.heroTag});

  final List<String> paths;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final visible = paths.take(3).toList(growable: false);
    return RepaintBoundary(
      child: SizedBox(
        height: 196,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final photoWidth = constraints.maxWidth - 20;
            Widget photo(String path, {required int layer}) {
              final angle = switch (layer) {
                1 => -.045,
                2 => .05,
                _ => 0.0,
              };
              final offset = switch (layer) {
                1 => const Offset(-6, 3),
                2 => const Offset(8, 5),
                _ => Offset.zero,
              };
              return Transform.translate(
                offset: offset,
                child: Transform.rotate(
                  angle: angle,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: layer == 0
                          ? [
                              BoxShadow(
                                color: AppColors.deepBlue.withValues(
                                  alpha: .12,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : const [],
                    ),
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: _MemoryFileImage(
                        path: path,
                        cacheLogicalWidth: photoWidth,
                        cacheLogicalHeight: 196,
                      ),
                    ),
                  ),
                ),
              );
            }

            return Stack(
              clipBehavior: Clip.none,
              fit: StackFit.expand,
              children: [
                if (visible.length >= 3)
                  Positioned.fill(
                    left: 10,
                    right: 10,
                    child: photo(visible[2], layer: 2),
                  ),
                if (visible.length >= 2)
                  Positioned.fill(
                    left: 10,
                    right: 10,
                    child: photo(visible[1], layer: 1),
                  ),
                Positioned.fill(
                  left: 10,
                  right: 10,
                  child: Hero(
                    tag: heroTag,
                    child: photo(visible.first, layer: 0),
                  ),
                ),
                if (paths.length > 1)
                  Positioned(
                    right: 16,
                    bottom: 10,
                    child: _PhotoCountPill(count: paths.length),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MemoryDetailRoute extends PageRouteBuilder<_MemoryDetailResult> {
  _MemoryDetailRoute({
    required Memory memory,
    required ValueChanged<Memory> onMemoryChanged,
  }) : super(
         transitionDuration: const Duration(milliseconds: 500),
         reverseTransitionDuration: const Duration(milliseconds: 380),
         pageBuilder: (_, __, ___) =>
             MemoryDetailPage(memory: memory, onMemoryChanged: onMemoryChanged),
          transitionsBuilder: (_, animation, secondaryAnimation, child) {
           final entrance = CurvedAnimation(
             parent: animation,
             curve: Curves.easeOutCubic,
             reverseCurve: Curves.easeInCubic,
           );
           return FadeTransition(opacity: entrance, child: child);
         },
       );
}

class _MemoryDetailResult {
  const _MemoryDetailResult({
    required this.memory,
    this.changed = false,
    this.deleteRequested = false,
  });

  final Memory memory;
  final bool changed;
  final bool deleteRequested;
}

class MemoryDetailPage extends StatefulWidget {
  const MemoryDetailPage({
    super.key,
    required this.memory,
    required this.onMemoryChanged,
  });

  final Memory memory;
  final ValueChanged<Memory> onMemoryChanged;

  @override
  State<MemoryDetailPage> createState() => _MemoryDetailPageState();
}

class _MemoryDetailPageState extends State<MemoryDetailPage> {
  late final PageController _photoController;
  late final ValueNotifier<int> _photoIndex;
  late Memory _memory;

  @override
  void initState() {
    super.initState();
    _memory = widget.memory;
    _photoController = PageController(viewportFraction: .9);
    _photoIndex = ValueNotifier(0);
  }

  @override
  void dispose() {
    _photoController.dispose();
    _photoIndex.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddMemoryPage(initialMemory: _memory)),
    );
    if (saved != true || !mounted || _memory.id == null) return;
    try {
      final updated = await LocalDatabase.instance.memoryById(_memory.id!);
      if (!mounted) return;
      if (updated == null) {
        Navigator.pop(
          context,
          _MemoryDetailResult(memory: _memory, changed: true),
        );
        return;
      }
      if (_photoController.hasClients) _photoController.jumpToPage(0);
      _photoIndex.value = 0;
      widget.onMemoryChanged(updated);
      setState(() => _memory = updated);
      showGardenMessage(context, '这段回忆已经重新整理好啦。');
    } catch (_) {
      if (mounted) {
        Navigator.pop(
          context,
          _MemoryDetailResult(memory: _memory, changed: true),
        );
      }
    }
  }

  Future<void> _requestDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这段回忆吗？'),
        content: const Text('里面的文字和所有照片都会一起删除，而且无法恢复。'),
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
    if (confirmed == true && mounted) {
      Navigator.pop(
        context,
        _MemoryDetailResult(memory: _memory, deleteRequested: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final memory = _memory;
    final images = memory.allImagePaths;
    return Scaffold(
      appBar: AppBar(
        title: const Text('这一段回忆'),
        actions: [
          IconButton(
            tooltip: '修改',
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: _requestDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: GardenBackground(
        showFlowers: false,
        child: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              if (images.isNotEmpty)
                SliverToBoxAdapter(
                  child: _MemoryDetailGallery(
                    paths: images,
                    heroTag: _memoryHeroTag(memory),
                    controller: _photoController,
                    selectedIndex: _photoIndex,
                    onPageChanged: (value) => _photoIndex.value = value,
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  22,
                  images.isEmpty ? 22 : 16,
                  22,
                  38,
                ),
                sliver: SliverToBoxAdapter(
                  child: GardenCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: const BoxDecoration(
                                color: AppColors.mistBlue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: AppColors.deepBlue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    DateFormat(
                                      'yyyy年 M月 d日',
                                    ).format(memory.date),
                                    style: const TextStyle(
                                      color: AppColors.hydrangea,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (memory.place?.isNotEmpty == true)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        memory.place!,
                                        style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          memory.note.isEmpty
                              ? '这一天没有留下文字，但它确实被我们好好记住了。'
                              : memory.note,
                          style: TextStyle(
                            color: memory.note.isEmpty
                                ? AppColors.muted
                                : AppColors.ink,
                            fontSize: 16,
                            height: 1.85,
                            fontStyle: memory.note.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _edit,
                            icon: const Icon(Icons.edit_note_rounded),
                            label: const Text('修改这段回忆'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemoryDetailGallery extends StatelessWidget {
  const _MemoryDetailGallery({
    required this.paths,
    required this.heroTag,
    required this.controller,
    required this.selectedIndex,
    required this.onPageChanged,
  });

  final List<String> paths;
  final String heroTag;
  final PageController controller;
  final ValueListenable<int> selectedIndex;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * .48, 410.0);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: controller,
            itemCount: paths.length,
            allowImplicitScrolling: true,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) {
              final image = Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepBlue.withValues(alpha: .14),
                        blurRadius: 28,
                        offset: const Offset(0, 13),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: _MemoryFileImage(
                      path: paths[index],
                      cacheLogicalWidth: MediaQuery.sizeOf(context).width,
                      cacheLogicalHeight: height,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              );
              return ValueListenableBuilder<int>(
                valueListenable: selectedIndex,
                child: index == 0 ? Hero(tag: heroTag, child: image) : image,
                builder: (context, currentIndex, child) => AnimatedScale(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  scale: currentIndex == index ? 1 : .965,
                  child: child,
                ),
              );
            },
          ),
        ),
        if (paths.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
            child: Row(
              children: [
                _PhotoCountPill(count: paths.length),
                const Spacer(),
                ValueListenableBuilder<int>(
                  valueListenable: selectedIndex,
                  builder: (context, currentIndex, _) => _MemoryPageIndicator(
                    currentIndex: currentIndex,
                    count: paths.length,
                    onSelected: (index) => controller.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MemoryPageIndicator extends StatelessWidget {
  const _MemoryPageIndicator({
    required this.currentIndex,
    required this.count,
    required this.onSelected,
  });

  final int currentIndex;
  final int count;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const maximumVisibleDots = 5;
    final visibleCount = math.min(count, maximumVisibleDots);
    final maximumStart = math.max(0, count - visibleCount);
    final start = (currentIndex - visibleCount ~/ 2).clamp(0, maximumStart);
    final visibleIndices = List.generate(
      visibleCount,
      (offset) => start + offset,
    );

    return Semantics(
      label: '第 ${currentIndex + 1} 张，共 $count 张照片',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              '${currentIndex + 1} / $count',
              key: ValueKey(currentIndex),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 7),
          ...visibleIndices.map(
            (index) => Semantics(
              button: true,
              selected: index == currentIndex,
              label: '查看第 ${index + 1} 张照片',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: AnimatedContainer(
                    key: ValueKey(index),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    width: index == currentIndex ? 20 : 7,
                    height: 7,
                    margin: const EdgeInsets.only(left: 5),
                    decoration: BoxDecoration(
                      color: index == currentIndex
                          ? AppColors.deepBlue
                          : AppColors.softBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoCountPill extends StatelessWidget {
  const _PhotoCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.deepBlue.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .62)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.collections_outlined, color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryFileImage extends StatelessWidget {
  const _MemoryFileImage({
    required this.path,
    required this.cacheLogicalWidth,
    required this.cacheLogicalHeight,
    this.filterQuality = FilterQuality.low,
  });

  final String path;
  final double cacheLogicalWidth;
  final double cacheLogicalHeight;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (cacheLogicalWidth * dpr).round().clamp(320, 1800);
    final cacheHeight = (cacheLogicalHeight * dpr).round().clamp(240, 1800);
    return Image.file(
      File(path),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      filterQuality: filterQuality,
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.mistBlue,
        alignment: Alignment.center,
        child: const Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.muted,
        ),
      ),
    );
  }
}

class AddMemoryPage extends StatefulWidget {
  const AddMemoryPage({super.key, this.initialMemory});

  final Memory? initialMemory;

  @override
  State<AddMemoryPage> createState() => _AddMemoryPageState();
}

class _AddMemoryPageState extends State<AddMemoryPage> {
  late final TextEditingController _note;
  late final TextEditingController _place;
  late DateTime _date;
  late List<String> _imagePaths;
  late Set<String> _originalImagePaths;
  var _saving = false;
  var _pickingImages = false;
  var _didSave = false;

  bool get _isEditing => widget.initialMemory != null;
  int get _remainingImageSlots => Memory.maxImages - _imagePaths.length;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMemory;
    _note = TextEditingController(text: initial?.note ?? '');
    _place = TextEditingController(text: initial?.place ?? '');
    _date = initial?.date ?? DateTime.now();
    _imagePaths = List<String>.of(initial?.allImagePaths ?? const []);
    _originalImagePaths = _imagePaths.toSet();
  }

  @override
  void dispose() {
    if (!_didSave) {
      final temporaryPaths = _imagePaths.where(
        (path) => !_originalImagePaths.contains(path),
      );
      unawaited(ImageService.deleteKeptImages(temporaryPaths));
    }
    _note.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _pickManyImages() async {
    if (_pickingImages || _saving) return;
    if (_remainingImageSlots <= 0) {
      showGardenMessage(context, '一段回忆最多放 ${Memory.maxImages} 张照片。');
      return;
    }
    setState(() => _pickingImages = true);
    List<String> paths = const [];
    try {
      paths = await ImageService.pickManyAndKeep(
        maxCount: _remainingImageSlots,
      );
      if (!mounted) {
        await ImageService.deleteKeptImages(paths);
        return;
      }
      if (paths.isNotEmpty) setState(() => _imagePaths.addAll(paths));
    } catch (_) {
      if (mounted) showGardenMessage(context, '照片暂时没有取到，再试一次好吗？');
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  Future<void> _takePhoto() async {
    if (_pickingImages || _saving) return;
    if (_remainingImageSlots <= 0) {
      showGardenMessage(context, '一段回忆最多放 ${Memory.maxImages} 张照片。');
      return;
    }
    setState(() => _pickingImages = true);
    String? path;
    try {
      path = await ImageService.takePhotoAndKeep();
      if (path == null) return;
      if (!mounted) {
        await ImageService.deleteKeptImage(path);
        return;
      }
      setState(() => _imagePaths.add(path!));
    } catch (_) {
      if (mounted) showGardenMessage(context, '照片暂时没有取到，再试一次好吗？');
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  Future<void> _removeImage(int index) async {
    if (_saving || index < 0 || index >= _imagePaths.length) return;
    final path = _imagePaths[index];
    setState(() => _imagePaths.removeAt(index));
    if (!_originalImagePaths.contains(path)) {
      await ImageService.deleteKeptImage(path);
    }
  }

  void _reorderImages(int oldIndex, int newIndex) {
    if (_saving || oldIndex == newIndex) return;
    setState(() {
      final path = _imagePaths.removeAt(oldIndex);
      _imagePaths.insert(newIndex, path);
    });
  }

  void _makeCover(int index) {
    if (_saving || index <= 0 || index >= _imagePaths.length) return;
    setState(() {
      final path = _imagePaths.removeAt(index);
      _imagePaths.insert(0, path);
    });
  }

  Future<void> _save() async {
    if (_saving || _pickingImages) return;
    setState(() => _saving = true);
    try {
      final memory = Memory(
        id: widget.initialMemory?.id,
        note: _note.text.trim(),
        date: _date,
        place: _place.text.trim(),
        imagePaths: List<String>.unmodifiable(_imagePaths),
      );
      if (_isEditing) {
        await LocalDatabase.instance.updateMemory(memory);
      } else {
        final added = await LocalDatabase.instance.addMemory(memory);
        if (!added) {
          if (!mounted) return;
          showGardenMessage(context, '回忆最多保存 1500 条，先删除一条再继续添加吧。');
          return;
        }
      }
      final removedOriginals = _originalImagePaths.difference(
        _imagePaths.toSet(),
      );
      await ImageService.deleteKeptImages(removedOriginals);
      _didSave = true;
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) showGardenMessage(context, '这段回忆暂时没有保存成功，请再试一次。');
    } finally {
      if (mounted && !_didSave) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving && !_pickingImages,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          showGardenMessage(
            context,
            _saving ? '照片和回忆正在保存，再等一下下好吗？' : '照片正在轻轻放进来，再等一下下好吗？',
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isEditing ? '修改这段回忆' : '收藏一段回忆')),
        body: GardenBackground(
          showFlowers: false,
          child: SafeArea(
            top: false,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(22),
              children: [
                Text(
                  _isEditing
                      ? '文字和照片都可以重新整理，这一天仍会被好好保留下来。'
                      : '可以写下些什么，也可以把那一天的照片一起放进来。',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                AnimatedSize(
                  duration: const Duration(milliseconds: 380),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _imagePaths.isEmpty
                      ? const SizedBox.shrink()
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '这段回忆里的照片',
                                  style: TextStyle(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_imagePaths.length}/${Memory.maxImages}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              '按住右下角拖动顺序，第一张会成为外面的封面。',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 142,
                              child: ReorderableListView.builder(
                                scrollDirection: Axis.horizontal,
                                buildDefaultDragHandles: false,
                                proxyDecorator: (child, _, animation) =>
                                    AnimatedBuilder(
                                      animation: animation,
                                      child: child,
                                      builder: (context, child) =>
                                          Transform.scale(
                                            scale: 1 + animation.value * .055,
                                            child: Material(
                                              color: Colors.transparent,
                                              elevation: animation.value * 7,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              child: child,
                                            ),
                                          ),
                                    ),
                                itemCount: _imagePaths.length,
                                onReorderItem: _reorderImages,
                                itemBuilder: (context, index) => Padding(
                                  key: ValueKey(_imagePaths[index]),
                                  padding: const EdgeInsets.only(right: 10),
                                  child: _EditableMemoryPhoto(
                                    path: _imagePaths[index],
                                    index: index,
                                    isCover: index == 0,
                                    enabled: !_saving,
                                    onRemove: () => _removeImage(index),
                                    onMakeCover: () => _makeCover(index),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickingImages || _saving
                            ? null
                            : _pickManyImages,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('从相册多选'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickingImages || _saving
                            ? null
                            : _takePhoto,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('直接拍照'),
                      ),
                    ),
                  ],
                ),
                if (_pickingImages) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _note,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '一句话记录（可以留空）',
                    hintText: '那天很普通，但我觉得很幸福。',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _place,
                  decoration: const InputDecoration(
                    labelText: '地点（可以留空）',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  tileColor: Colors.white.withValues(alpha: .72),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  leading: const Icon(
                    Icons.calendar_month_outlined,
                    color: AppColors.deepBlue,
                  ),
                  title: const Text('这一天'),
                  subtitle: Text(gentleDate(_date)),
                  onTap: _saving
                      ? null
                      : () async {
                          final value = await pickGardenDate(context, _date);
                          if (value != null && mounted) {
                            setState(() => _date = value);
                          }
                        },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving || _pickingImages ? null : _save,
                  child: Text(
                    _saving
                        ? '正在保存……'
                        : _isEditing
                        ? '保存修改'
                        : '收藏这段回忆',
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

class _EditableMemoryPhoto extends StatelessWidget {
  const _EditableMemoryPhoto({
    required this.path,
    required this.index,
    required this.isCover,
    required this.enabled,
    required this.onRemove,
    required this.onMakeCover,
  });

  final String path;
  final int index;
  final bool isCover;
  final bool enabled;
  final VoidCallback onRemove;
  final VoidCallback onMakeCover;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _MemoryFileImage(
                path: path,
                cacheLogicalWidth: 112,
                cacheLogicalHeight: 142,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x880D1425)],
                  stops: [.48, 1],
                ),
                border: Border.all(
                  color: isCover ? AppColors.hydrangea : Colors.white,
                  width: isCover ? 2.5 : 2,
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: _SmallPhotoAction(
              tooltip: '移除照片',
              icon: Icons.close_rounded,
              onPressed: enabled ? onRemove : null,
            ),
          ),
          Positioned(
            left: 7,
            bottom: 7,
            child: isCover
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.deepBlue.withValues(alpha: .88),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '封面',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : _SmallPhotoAction(
                    tooltip: '设为封面',
                    icon: Icons.push_pin_outlined,
                    onPressed: enabled ? onMakeCover : null,
                  ),
          ),
          Positioned(
            right: 7,
            bottom: 7,
            child: ReorderableDragStartListener(
              index: index,
              enabled: enabled,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.drag_indicator_rounded,
                  size: 18,
                  color: AppColors.deepBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallPhotoAction extends StatelessWidget {
  const _SmallPhotoAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .9),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: AppColors.deepBlue),
        ),
      ),
    );
  }
}
