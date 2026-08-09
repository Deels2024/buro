import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/user/user_app.dart';

class BureauNakhodokApp extends StatelessWidget {
  const BureauNakhodokApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Бюро находок',
      debugShowCheckedModeBanner: false,
      theme: BureauTheme.light,
      home: const OnboardingPage(),
    );
  }
}
