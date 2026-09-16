import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/local_database.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_background.dart';
import '../widgets/garden_components.dart';
import 'app_shell.dart';

class WelcomeGuidePage extends StatefulWidget {
  const WelcomeGuidePage({super.key});

  @override
  State<WelcomeGuidePage> createState() => _WelcomeGuidePageState();
}

class _WelcomeGuidePageState extends State<WelcomeGuidePage>
    with TickerProviderStateMixin {
  final _pageController = PageController();
  late final AnimationController _entryController;
  late final AnimationController _driftController;
  var _page = 0;
  var _finishing = false;

  static const _moments = [
    _GuideMoment(
      eyebrow: '欢迎来到这里',
      title: '一朵只为你盛开的蓝色绣球花',
      message: '这里收着威威想给你的温柔，也收着每一个值得珍藏的小瞬间。',
    ),
    _GuideMoment(
      eyebrow: '点点小蝴蝶',
      title: '让雨声、海浪和微风陪你一会儿',
      message: '累的时候不用做什么，打开小蝴蝶，安静地听一会儿就好。',
    ),
    _GuideMoment(
      eyebrow: '只属于你们',
      title: '所有心情与回忆，都留在这部手机里',
      message: '记录保存在本机。使用今日花语或情绪解语并点按生成时，本次填写与主动选中的文字会交给 DeepSeek；其他记录不会自动上传。',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..forward();
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _entryController.dispose();
    _driftController.dispose();
    super.dispose();
  }

  void _onPageChanged(int value) {
    setState(() => _page = value);
    _entryController
      ..reset()
      ..forward();
  }

  Future<void> _next() async {
    if (_page < _moments.length - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 560),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await LocalDatabase.instance.markWelcomeGuideSeen();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 720),
          pageBuilder: (_, animation, secondaryAnimation) => const AppShell(),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                ),
                child: child,
              ),
        ),
      );
    } catch (_) {
      if (mounted) {
        showGardenMessage(context, '小花园暂时没有准备好，再点一次试试好吗？');
        setState(() => _finishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GardenBackground(
        showFlowers: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '威威给你的蓝色绣球花',
                        style: TextStyle(
                          color: AppColors.deepBlue,
                          fontSize: 13,
                          letterSpacing: 2.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _finishing ? null : _finish,
                      child: const Text('跳过'),
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _moments.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, index) => _GuideScene(
                      index: index,
                      moment: _moments[index],
                      entry: _entryController,
                      drift: _driftController,
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _moments.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: index == _page ? 24 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: index == _page
                            ? AppColors.deepBlue
                            : AppColors.softBlue.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _finishing ? null : _next,
                    icon: _finishing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : _page == _moments.length - 1
                        ? const Butterfly(size: 23, color: Colors.white)
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      _page == _moments.length - 1 ? '进入我的小花园' : '继续',
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

class _GuideScene extends StatelessWidget {
  const _GuideScene({
    required this.index,
    required this.moment,
    required this.entry,
    required this.drift,
  });

  final int index;
  final _GuideMoment moment;
  final Animation<double> entry;
  final Animation<double> drift;

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(
      parent: entry,
      curve: const Interval(.15, 1, curve: Curves.easeOut),
    );
    final rise = Tween<Offset>(
      begin: const Offset(0, .08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: entry, curve: Curves.easeOutCubic));

    return Column(
      children: [
        Expanded(
          flex: 6,
          child: Center(
            child: _GuideIllustration(index: index, entry: entry, drift: drift),
          ),
        ),
        Expanded(
          flex: 4,
          child: FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: rise,
              child: Column(
                children: [
                  Text(
                    moment.eyebrow,
                    style: const TextStyle(
                      color: AppColors.hydrangea,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    moment.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    moment.message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 15,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideIllustration extends StatelessWidget {
  const _GuideIllustration({
    required this.index,
    required this.entry,
    required this.drift,
  });

  final int index;
  final Animation<double> entry;
  final Animation<double> drift;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([entry, drift]),
      builder: (context, child) {
        final entrance = Curves.easeOutBack.transform(entry.value);
        final breeze = math.sin(drift.value * math.pi);
        return Opacity(
          opacity: entry.value.clamp(0, 1),
          child: Transform.scale(
            scale: .72 + .28 * entrance,
            child: SizedBox(
              width: 300,
              height: 310,
              child: switch (index) {
                0 => _BloomScene(breeze: breeze),
                1 => _SoundScene(breeze: breeze, entrance: entrance),
                _ => _PrivateScene(breeze: breeze),
              },
            ),
          ),
        );
      },
    );
  }
}

class _BloomScene extends StatelessWidget {
  const _BloomScene({required this.breeze});

  final double breeze;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .42),
            boxShadow: [
              BoxShadow(
                color: AppColors.softBlue.withValues(alpha: .22),
                blurRadius: 42,
                spreadRadius: 12,
              ),
            ],
          ),
        ),
        const HydrangeaCluster(size: 245),
        Positioned(
          right: 20 + breeze * 22,
          top: 38 - breeze * 8,
          child: Transform.rotate(
            angle: .1 - breeze * .18,
            child: const Butterfly(size: 46),
          ),
        ),
      ],
    );
  }
}

class _SoundScene extends StatelessWidget {
  const _SoundScene({required this.breeze, required this.entrance});

  final double breeze;
  final double entrance;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        GardenCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Butterfly(size: 38),
                  const SizedBox(width: 12),
                  Text(
                    '陪你安静一会儿',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Transform.translate(
                offset: Offset(20 * (1 - entrance), 0),
                child: const Wrap(
                  spacing: 8,
                  children: [
                    _SoundPetal(icon: Icons.water_drop_outlined, label: '雨声'),
                    _SoundPetal(icon: Icons.waves_rounded, label: '海浪'),
                    _SoundPetal(icon: Icons.air_rounded, label: '微风'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 2 + breeze * 18,
          top: 28 - breeze * 10,
          child: Transform.rotate(
            angle: breeze * .16,
            child: const Butterfly(size: 40, color: AppColors.hydrangea),
          ),
        ),
      ],
    );
  }
}

class _SoundPetal extends StatelessWidget {
  const _SoundPetal({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.mistBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: AppColors.deepBlue),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _PrivateScene extends StatelessWidget {
  const _PrivateScene({required this.breeze});

  final double breeze;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: .62,
          child: Transform.translate(
            offset: Offset(0, breeze * 4),
            child: const HydrangeaCluster(size: 250),
          ),
        ),
        Container(
          width: 116,
          height: 116,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: .9),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlue.withValues(alpha: .12),
                blurRadius: 30,
              ),
            ],
          ),
          child: const Icon(
            Icons.favorite_rounded,
            size: 52,
            color: AppColors.deepBlue,
          ),
        ),
        const Positioned(
          right: 92,
          bottom: 90,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cream,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(9),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 24,
                color: AppColors.hydrangea,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideMoment {
  const _GuideMoment({
    required this.eyebrow,
    required this.title,
    required this.message,
  });

  final String eyebrow;
  final String title;
  final String message;
}
