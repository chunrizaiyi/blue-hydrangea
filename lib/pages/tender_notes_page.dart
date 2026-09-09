import 'dart:async';

import 'package:flutter/material.dart';

import '../models/garden_models.dart';
import '../services/image_service.dart';
import '../services/local_database.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_background.dart';
import '../widgets/garden_components.dart';

class TenderNotesPage extends StatefulWidget {
  const TenderNotesPage({super.key});

  @override
  State<TenderNotesPage> createState() => _TenderNotesPageState();
}

class _TenderNotesPageState extends State<TenderNotesPage> {
  List<TenderNote>? _notes;
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
      final notes = await LocalDatabase.instance.tenderNotes();
      if (mounted && revision == _loadRevision) {
        setState(() => _notes = notes);
      }
    } catch (_) {
      if (mounted && revision == _loadRevision) {
        setState(() => _notes ??= const []);
        showGardenMessage(context, '这些温柔小事暂时没有读取成功，稍后再试一次好吗？');
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
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddTenderNotePage()));
    if (saved == true) await _reload();
  }

  Future<void> _edit(TenderNote note) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddTenderNotePage(initialNote: note)),
    );
    if (saved == true) await _reload();
  }

  Future<void> _delete(TenderNote note) async {
    if (note.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除这条记录吗？'),
        content: Text('“${note.title}”删除后将无法恢复。'),
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
    await LocalDatabase.instance.deleteTenderNote(note.id!);
    if (note.imagePath != null) {
      await ImageService.deleteKeptImage(note.imagePath!);
    }
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    showGardenMessage(context, '这条记录已经删除。');
  }

  @override
  Widget build(BuildContext context) {
    final visibleNotes = _notes
        ?.where((note) => gardenDateIsInRange(note.date, _dateRange))
        .toList();
    return GardenBackground(
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 30, 22, 20),
              sliver: SliverToBoxAdapter(
                child: GardenPageHeader(
                  title: '我视角下的他',
                  subtitle: '把那些让我心动、让我欣赏的小事，好好收藏起来。',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GardenDateFilterButton(
                        range: _dateRange,
                        onPressed: _pickDateFilter,
                      ),
                      const SizedBox(width: 7),
                      IconButton.filledTonal(
                        tooltip: '记下一件温柔小事',
                        onPressed: _add,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_notes == null)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visibleNotes!.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: GardenFilterReveal(
                  key: ValueKey('empty-$_filterRevision'),
                  child: EmptyGarden(
                    message: _notes!.isEmpty
                        ? '第一件温柔小事，等你写下来。'
                        : '这段日期里还没有温柔小事。',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 34),
                sliver: SliverList.separated(
                  itemCount: visibleNotes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final note = visibleNotes[index];
                    return GardenFilterReveal(
                      key: ValueKey('$_filterRevision-${note.id ?? index}'),
                      child: _TenderNoteCard(
                        note: note,
                        onEdit: () => _edit(note),
                        onDelete: () => _delete(note),
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

class _TenderNoteCard extends StatelessWidget {
  const _TenderNoteCard({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  final TenderNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GardenCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note.imagePath != null) ...[
            LocalImage(path: note.imagePath!),
            const SizedBox(height: 17),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  gentleDate(note.date),
                  style: const TextStyle(
                    color: AppColors.hydrangea,
                    fontSize: 12,
                    letterSpacing: .5,
                  ),
                ),
              ),
              IconButton(
                tooltip: '修改这条记录',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.hydrangea,
                  size: 21,
                ),
              ),
              IconButton(
                tooltip: '删除这条记录',
                visualDensity: VisualDensity.compact,
                onPressed: onDelete,
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.muted,
                  size: 21,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(note.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 9),
          Text(
            note.content,
            style: const TextStyle(color: AppColors.ink, height: 1.75),
          ),
        ],
      ),
    );
  }
}

class AddTenderNotePage extends StatefulWidget {
  const AddTenderNotePage({super.key, this.initialNote});

  final TenderNote? initialNote;

  @override
  State<AddTenderNotePage> createState() => _AddTenderNotePageState();
}

class _AddTenderNotePageState extends State<AddTenderNotePage> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late DateTime _date;
  String? _imagePath;
  String? _originalImagePath;
  var _saving = false;
  var _didSave = false;

  bool get _isEditing => widget.initialNote != null;

  @override
  void initState() {
    super.initState();
    final note = widget.initialNote;
    _title = TextEditingController(text: note?.title);
    _content = TextEditingController(text: note?.content);
    _date = note?.date ?? DateTime.now();
    _imagePath = note?.imagePath;
    _originalImagePath = note?.imagePath;
  }

  @override
  void dispose() {
    if (!_didSave && _imagePath != null && _imagePath != _originalImagePath) {
      unawaited(ImageService.deleteKeptImage(_imagePath!));
    }
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      showGardenMessage(context, '写下标题和想说的话，再轻轻收好。');
      return;
    }
    setState(() => _saving = true);
    try {
      final updatedNote = TenderNote(
        id: widget.initialNote?.id,
        title: _title.text.trim(),
        content: _content.text.trim(),
        date: _date,
        imagePath: _imagePath,
      );
      if (_isEditing) {
        await LocalDatabase.instance.updateTenderNote(updatedNote);
      } else {
        final added = await LocalDatabase.instance.addTenderNote(updatedNote);
        if (!added) {
          if (!mounted) return;
          showGardenMessage(context, '“我视角下的他”最多保存 1500 条，先删除一条再继续添加吧。');
          return;
        }
      }
      if (_originalImagePath != null && _originalImagePath != _imagePath) {
        await ImageService.deleteKeptImage(_originalImagePath!);
      }
      _didSave = true;
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) showGardenMessage(context, '这件小事暂时没有保存成功，请再试一次。');
    } finally {
      if (mounted && !_didSave) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    String? path;
    try {
      path = await ImageService.pickAndKeep();
    } catch (_) {
      if (mounted) showGardenMessage(context, '照片暂时没有取到，再试一次好吗？');
      return;
    }
    if (path == null || !mounted) return;
    final previous = _imagePath;
    if (previous != null && previous != _originalImagePath) {
      await ImageService.deleteKeptImage(previous);
    }
    if (mounted) setState(() => _imagePath = path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '修改这件温柔小事' : '记下一件温柔小事')),
      body: GardenBackground(
        showFlowers: false,
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: '标题',
                  hintText: '比如：你认真努力的时候',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _content,
                minLines: 5,
                maxLines: 9,
                decoration: const InputDecoration(
                  labelText: '我想对你说',
                  hintText: '在我眼里，你一直都很闪光……',
                ),
              ),
              const SizedBox(height: 14),
              GardenCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.calendar_month_outlined,
                        color: AppColors.deepBlue,
                      ),
                      title: const Text('这一天'),
                      subtitle: Text(gentleDate(_date)),
                      onTap: () async {
                        final value = await pickGardenDate(context, _date);
                        if (value != null && mounted) {
                          setState(() => _date = value);
                        }
                      },
                    ),
                    if (_imagePath != null) ...[
                      LocalImage(path: _imagePath!, height: 150),
                      const SizedBox(height: 8),
                    ],
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.deepBlue,
                      ),
                      title: Text(_imagePath == null ? '放一张照片（可选）' : '换一张照片'),
                      onTap: _saving ? null : _pickImage,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(
                  _saving ? '正在保存……' : (_isEditing ? '保存修改' : '收藏这件小事'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
