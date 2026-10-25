import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(
    ProviderScope(
      // API errors are shown with a "Try again" button; don't retry silently in the background.
      retry: (_, _) => null,
      child: const SellixApp(),
    ),
  );
}
