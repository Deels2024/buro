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
        debugShowCheckedModeBanner: false,
        theme: BureauTheme.light,
        builder: (context, child) {
          if (child == null) return const SizedBox.shrink();
          return ColoredBox(
            color: BureauColors.webCanvas,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
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
            AppSessionState.signedOut => const OnboardingPage(),
            AppSessionState.signedIn => const UserShell(),
          },
        ),
      ),
    );
  }
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
