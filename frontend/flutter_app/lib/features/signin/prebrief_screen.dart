import 'package:flutter/material.dart';

import 'welcome_screen.dart';

/// The welcome screen with the pre-brief sheet open. Dismissing it stays on welcome.
class PrebriefScreen extends StatelessWidget {
  const PrebriefScreen({super.key});

  @override
  Widget build(BuildContext context) => const WelcomeScreen(openBrief: true);
}
