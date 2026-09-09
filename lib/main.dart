import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/app_shell.dart';
import 'pages/welcome_guide_page.dart';
import 'services/local_database.dart';
import 'theme/app_theme.dart';
import 'widgets/garden_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.cream,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const _GardenBootstrap());
}

class _GardenBootstrap extends StatefulWidget {
  const _GardenBootstrap();

  @override
  State<_GardenBootstrap> createState() => _GardenBootstrapState();
}

class _GardenBootstrapState extends State<_GardenBootstrap> {
  late Future<bool> _startup;

  @override
  void initState() {
    super.initState();
    _startup = _prepareGarden();
  }

  Future<bool> _prepareGarden() async {
    await LocalDatabase.instance.database;
    return !await LocalDatabase.instance.hasSeenWelcomeGuide();
  }

  void _retry() {
    setState(() => _startup = _prepareGarden());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return BlueHydrangeaApp(showWelcomeGuide: snapshot.data!);
        }
        return MaterialApp(
          title: '给你的蓝色绣球花',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: _GardenStartupPage(failed: snapshot.hasError, onRetry: _retry),
        );
      },
    );
  }
}

class _GardenStartupPage extends StatelessWidget {
  const _GardenStartupPage({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GardenBackground(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: failed
                ? Column(
                    key: const ValueKey('startup-error'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Butterfly(size: 42),
                      const SizedBox(height: 18),
                      const Text(
                        '小花园刚刚没有打开',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '数据都还在，轻轻再试一次就好。',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('再打开一次'),
                      ),
                    ],
                  )
                : const Column(
                    key: ValueKey('startup-loading'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HydrangeaCluster(size: 148),
                      SizedBox(height: 16),
                      Text(
                        '正在为宝宝打开小花园…',
                        style: TextStyle(
                          color: AppColors.deepBlue,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 18),
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class BlueHydrangeaApp extends StatelessWidget {
  const BlueHydrangeaApp({super.key, required this.showWelcomeGuide});

  final bool showWelcomeGuide;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '给你的蓝色绣球花',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: showWelcomeGuide ? const WelcomeGuidePage() : const AppShell(),
    );
  }
}
