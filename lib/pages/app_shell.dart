import 'dart:async';

import 'package:flutter/material.dart';

import '../services/focus_timer_bridge.dart';
import '../theme/app_theme.dart';
import 'focus_clock_page.dart';
import 'home_page.dart';
import 'mailbox_page.dart';
import 'memories_page.dart';
import 'mood_page.dart';
import 'tender_notes_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pageTransitionController;
  StreamSubscription<void>? _openFocusClockSubscription;
  var _index = 0;
  var _previousIndex = 0;
  var _direction = 1.0;
  var _openingFocusClock = false;
  final Set<int> _visitedPages = <int>{0};

  static const _pages = [
    HomePage(),
    TenderNotesPage(),
    MailboxPage(),
    MemoriesPage(),
    MoodPage(),
  ];

  @override
  void initState() {
    super.initState();
    _pageTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1,
    );
    final timerBridge = FocusTimerBridge.instance;
    _openFocusClockSubscription = timerBridge.openFocusClockRequests.listen((
      _,
    ) {
      unawaited(_consumeLiveClockRequest());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_consumeColdStartClockRequest());
    });
  }

  @override
  void dispose() {
    _openFocusClockSubscription?.cancel();
    _pageTransitionController.dispose();
    super.dispose();
  }

  Future<void> _consumeColdStartClockRequest() async {
    final requested = await FocusTimerBridge.instance.consumeOpenTimerRequest();
    if (requested) await _openFocusClock();
  }

  Future<void> _consumeLiveClockRequest() async {
    // Native keeps this marker so a cold-start callback cannot be lost. When
    // the live stream reaches an already running shell, consume it here so the
    // next ordinary launch does not reopen the clock unexpectedly.
    await FocusTimerBridge.instance.consumeOpenTimerRequest();
    await _openFocusClock();
  }

  Future<void> _openFocusClock() async {
    final timerBridge = FocusTimerBridge.instance;
    if (!mounted || _openingFocusClock || timerBridge.clockIsVisible) return;

    _openingFocusClock = true;
    timerBridge.clockIsVisible = true;
    try {
      await Navigator.of(
        context,
        rootNavigator: true,
      ).push<void>(MaterialPageRoute(builder: (_) => const FocusClockPage()));
    } finally {
      timerBridge.clockIsVisible = false;
      _openingFocusClock = false;
    }
  }

  void _selectPage(int value) {
    if (value == _index || _pageTransitionController.isAnimating) return;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    setState(() {
      _previousIndex = _index;
      _direction = value > _index ? 1 : -1;
      _index = value;
      _visitedPages.add(value);
    });
    if (reduceMotion) {
      _pageTransitionController.value = 1;
    } else {
      _pageTransitionController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: AnimatedBuilder(
        animation: _pageTransitionController,
        builder: (context, child) {
          final incoming = Curves.easeOutQuart.transform(
            _pageTransitionController.value,
          );
          final outgoing = Curves.easeInOutCubic.transform(
            _pageTransitionController.value,
          );
          return ClipRect(
            child: Stack(
              children: List.generate(_pages.length, (pageIndex) {
                final isCurrent = pageIndex == _index;
                final isPrevious =
                    pageIndex == _previousIndex &&
                    _pageTransitionController.value < 1;
                final isVisible = isCurrent || isPrevious;
                final opacity = isCurrent ? incoming : 1 - outgoing;
                final horizontalOffset = isCurrent
                    ? 24 * _direction * (1 - incoming)
                    : -12 * _direction * outgoing;
                final verticalOffset = isCurrent ? 3 * (1 - incoming) : 0.0;
                return Positioned.fill(
                  child: Offstage(
                    offstage: !isVisible,
                    child: TickerMode(
                      enabled: isCurrent,
                      child: IgnorePointer(
                        ignoring:
                            !isCurrent || _pageTransitionController.value < .45,
                        child: ExcludeSemantics(
                          excluding: !isCurrent,
                          child: Opacity(
                            opacity: opacity.clamp(0, 1),
                            child: Transform.translate(
                              offset: Offset(horizontalOffset, verticalOffset),
                              child: RepaintBoundary(
                                child: _visitedPages.contains(pageIndex)
                                    ? _pages[pageIndex]
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        height: 70,
        selectedIndex: _index,
        animationDuration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 400),
        onDestinationSelected: _selectPage,
        backgroundColor: AppColors.cream.withValues(alpha: .96),
        indicatorColor: AppColors.softBlue.withValues(alpha: .4),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.local_florist_outlined),
            selectedIcon: _BloomingNavIcon(Icons.local_florist),
            label: '花园',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            selectedIcon: _BloomingNavIcon(Icons.favorite),
            label: '我视角下的他',
          ),
          NavigationDestination(
            icon: Icon(Icons.mail_outline),
            selectedIcon: _BloomingNavIcon(Icons.mail),
            label: '信箱',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_album_outlined),
            selectedIcon: _BloomingNavIcon(Icons.photo_album),
            label: '回忆',
          ),
          NavigationDestination(
            icon: Icon(Icons.bubble_chart_outlined),
            selectedIcon: _BloomingNavIcon(Icons.bubble_chart),
            label: '心情',
          ),
        ],
      ),
    );
  }
}

class _BloomingNavIcon extends StatelessWidget {
  const _BloomingNavIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return Icon(icon);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .72, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0, 1), child: child),
      ),
      child: Icon(icon),
    );
  }
}
