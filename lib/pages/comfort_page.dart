import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/garden_background.dart';
import '../widgets/garden_components.dart';

class ComfortPage extends StatelessWidget {
  const ComfortPage({super.key});

  static const _comforts = [
    '我知道有时候我的表达方式不够好，但我一直是希望你开心的。',
    '你不用急着变好，也不用急着原谅谁，先照顾好自己的心情。',
    '等你愿意的时候，我会认真听你说。',
    '如果你现在不想说话，也没有关系，我还是希望你被温柔对待。',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GardenBackground(
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.mistBlue.withValues(alpha: .9),
                title: const Text('安静的花园角落'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 28, 22, 50),
                sliver: SliverList.list(
                  children: [
                    Text(
                      '如果你现在\n有一点难过',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '就先在这里停一下。\n慢慢呼吸，什么都不用马上解决。',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 16,
                        height: 1.8,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ..._comforts.indexed.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: GardenCard(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.softBlue.withValues(
                                    alpha: .34,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${item.$1 + 1}',
                                  style: const TextStyle(
                                    color: AppColors.deepBlue,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.$2,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            color: AppColors.hydrangea,
                            size: 30,
                          ),
                          SizedBox(height: 10),
                          Text(
                            '你不用独自消化所有情绪。',
                            style: TextStyle(
                              color: AppColors.deepBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
