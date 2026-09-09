import 'dart:math';

import 'package:flutter/material.dart';

import '../models/garden_models.dart';
import '../services/local_database.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_background.dart';
import '../widgets/garden_components.dart';

class MailboxPage extends StatelessWidget {
  const MailboxPage({super.key});

  static const _categories = [
    ('今天有点累', Icons.bedtime_outlined, Color(0xFFDCE5F8)),
    ('今天想被安慰', Icons.favorite_border_rounded, Color(0xFFF0E0E8)),
    ('今天有点委屈', Icons.water_drop_outlined, Color(0xFFE0E9F3)),
    ('今天想你了', Icons.send_outlined, Color(0xFFE5DFF2)),
    ('今天只是想看看你写的话', Icons.mail_outline_rounded, Color(0xFFE6EEE8)),
  ];

  Future<void> _openLetter(BuildContext context, String category) async {
    final letters = await LocalDatabase.instance.lettersFor(category);
    if (!context.mounted || letters.isEmpty) return;
    final letter = letters[Random().nextInt(letters.length)];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _OpenedLetter(letter: letter),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GardenBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 36),
          children: [
            const GardenPageHeader(
              title: '绣球花信箱',
              subtitle: '选一个最接近此刻的心情，里面有一封只留给你的信。',
            ),
            const SizedBox(height: 28),
            Container(
              height: 130,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .52),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Stack(
                children: [
                  Positioned(
                    right: 14,
                    bottom: -40,
                    child: HydrangeaCluster(size: 160),
                  ),
                  Positioned(
                    left: 22,
                    top: 25,
                    child: Icon(
                      Icons.mark_email_unread_outlined,
                      size: 48,
                      color: AppColors.deepBlue,
                    ),
                  ),
                  Positioned(
                    left: 22,
                    bottom: 20,
                    child: Text(
                      '今天想拆哪一封？',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ..._categories.map(
              (category) => Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => _openLetter(context, category.$1),
                  child: GardenCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 15,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: category.$3,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            category.$2,
                            color: AppColors.deepBlue,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            category.$1,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenedLetter extends StatelessWidget {
  const _OpenedLetter({required this.letter});

  final Letter letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 90),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.paddingOf(context).bottom + 28,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.softBlue,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 24),
          const Butterfly(size: 38),
          const SizedBox(height: 16),
          Text(
            letter.category,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.mistBlue.withValues(alpha: .68),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Text(
              letter.content,
              style: const TextStyle(fontSize: 17, height: 1.9),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          const Text('这封信一直都在。', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}
