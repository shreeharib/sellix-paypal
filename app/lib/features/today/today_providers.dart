import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/providers.dart';

final todayProvider = FutureProvider.autoDispose<Today>(
  (ref) => ref.watch(sellixApiProvider).today(),
);
