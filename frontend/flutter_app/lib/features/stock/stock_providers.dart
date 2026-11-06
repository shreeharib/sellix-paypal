import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme_mode.dart';
import 'stock_model.dart';

/// The Today payload: business date, agent state, the stock ledger and the day's numbers.
/// Shared with other features. After a stock change, `ref.invalidate(todayProvider)`.
final todayProvider = FutureProvider.autoDispose<Today>(
  (ref) => ref.watch(sellixApiProvider).today(),
);

final catalogProvider = FutureProvider.autoDispose<List<ProductDetail>>(
  (ref) => ref.watch(sellixApiProvider).products(),
);

/// Today's ledger joined to the catalogue: what every stock screen draws.
final stockViewProvider = FutureProvider.autoDispose<StockView>((ref) async {
  final results = await Future.wait<Object>([
    ref.watch(todayProvider.future),
    ref.watch(catalogProvider.future),
  ]);
  return StockView.join(results[0] as Today, results[1] as List<ProductDetail>);
});

final leftoversProvider = FutureProvider.autoDispose<YesterdayLeftoversResponse>(
  (ref) => ref.watch(sellixApiProvider).leftovers(),
);

final upcomingProvider = FutureProvider.autoDispose<List<UpcomingDay>>(
  (ref) => ref.watch(sellixApiProvider).upcomingStock(),
);

/// Category and weekly off. Only wording and the closed note depend on it, so a failure is null.
final shopAnswersProvider = FutureProvider.autoDispose<OnboardingAnswers?>((ref) async {
  try {
    return (await ref.watch(sellixApiProvider).onboarding()).answers;
  } on Exception {
    return null;
  }
});

final carriedLogProvider = Provider<CarriedLog>(
  (ref) => CarriedLog(ref.watch(sharedPreferencesProvider)),
);

/// What this phone already carried from yesterday, per business date.
///
/// BACKEND GAP: the server keeps no record of a rollover. `GET /v1/today/leftovers` keeps listing
/// the same units and `POST /v1/today/rollover` adds them to opening again each time, and
/// `PUT /v1/today/stock` overwrites the opening that holds them. This log stops a double carry on
/// this phone and keeps carried units through a redo of the list. A second phone can't see it.
class CarriedLog {
  CarriedLog(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'stock.carried.';

  Map<String, int> read(DateTime businessDate) {
    final raw = _prefs.getString('$_prefix${businessDateString(businessDate)}');
    if (raw == null) return const {};
    return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
  }

  Future<void> add(DateTime businessDate, Map<String, int> carried) async {
    final key = '$_prefix${businessDateString(businessDate)}';
    for (final old in _prefs.getKeys().where((k) => k.startsWith(_prefix) && k != key).toList()) {
      await _prefs.remove(old);
    }
    await _prefs.setString(key, jsonEncode({...read(businessDate), ...carried}));
  }
}
