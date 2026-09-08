import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'data/app_controller.dart';
import 'features/user/user_app.dart';

class BureauNakhodokApp extends StatefulWidget {
  const BureauNakhodokApp({super.key, this.controller});

  final AppController? controller;

  @override
  State<BureauNakhodokApp> createState() => _BureauNakhodokAppState();
}

class _BureauNakhodokAppState extends State<BureauNakhodokApp> {
  late final AppController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? AppController();
    if (_ownsController) _controller.initialize();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: MaterialApp(
        title: 'Бюро находок',
        initialRoute: '/',
        debugShowCheckedModeBanner: false,
        theme: BureauTheme.light,
        builder: (context, child) {
          if (child == null) return const SizedBox.shrink();
          return ColoredBox(
            color: BureauColors.webCanvas,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: BureauColors.canvas,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x160B1F3A),
                        blurRadius: 42,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
        home: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => switch (_controller.state) {
            AppSessionState.initializing => const _AppSplash(),
            AppSessionState.unavailable => _SessionRetry(controller: _controller),
            AppSessionState.signedOut => Uri.base.queryParameters['action'] != null ? const AuthPage() : const OnboardingPage(),
            AppSessionState.signedIn => const UserShell(),
          },
        ),
      ),
    );
  }
}

class _SessionRetry extends StatelessWidget {
  const _SessionRetry({required this.controller});

  final AppController controller;

  Future<void> _signInAgain(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Войти заново?'),
        content: const Text(
          'Сохранённый вход на этом устройстве будет сброшен. '
          'Для нового входа понадобится SMS-код.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сбросить вход'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.resetSavedSession();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сбросить вход. Попробуйте ещё раз.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48),
              const SizedBox(height: 20),
              Text(
                'Не удалось подключиться',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Сохранённый вход пока не удалось восстановить. '
                'Попробуйте подключиться ещё раз.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: controller.initialize,
                child: const Text('Повторить подключение'),
              ),
              TextButton(
                onPressed: () => _signInAgain(context),
                child: const Text('Войти заново'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AppSplash extends StatelessWidget {
  const _AppSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 38,
              backgroundColor: BureauColors.blue,
              child: Text(
                'БН',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
            SizedBox(height: 20),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
