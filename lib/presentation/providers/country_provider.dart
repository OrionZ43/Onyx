// Страна сервера для флага и группировки (#68).
//
// Порядок: выбор пользователя → страна из названия (emoji-флаг, страна или
// город, код) → страна выхода из проверки сервера (Node.exitCountry, Deep
// Probe — «Оникс»). Выбор пользователя хранится по адресу сервера
// (serverKey): все транспорты одного сервера получают одну страну.
// Только для вида — маршрутизацию и выбор сервера не меняет.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/node.dart';
import '../util/country.dart';

/// Страны, выбранные пользователем: адрес сервера → код страны.
class CountryOverrides extends StateNotifier<Map<String, String>> {
  /// [initial] — для тестов: без чтения настроек.
  CountryOverrides([Map<String, String>? initial]) : super(initial ?? const {}) {
    if (initial == null) _load();
  }

  static const key = 'node_country_overrides';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || !mounted) return;
    try {
      state = {...Map<String, String>.from(json.decode(raw) as Map), ...state};
    } catch (_) {
      // Испорченное значение — просто без ручного выбора.
    }
  }

  /// [code] null или '' — снова определять автоматически.
  Future<void> set(String serverKey, String? code) async {
    final next = {...state};
    if (code == null || code.isEmpty) {
      next.remove(serverKey);
    } else {
      next[serverKey] = code.toLowerCase();
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json.encode(next));
  }
}

final countryOverridesProvider =
    StateNotifierProvider<CountryOverrides, Map<String, String>>((ref) => CountryOverrides());

class CountryResolver {
  const CountryResolver(this.overrides);
  final Map<String, String> overrides;

  /// Страна для флага, группировки и поиска.
  Country of(Node n) {
    final picked = overrides[n.serverKey];
    if (picked != null) {
      final c = countryByCode(picked);
      if (c.isKnown) return c;
    }
    return detected(n);
  }

  /// Страна без выбора пользователя: из названия, иначе страна выхода из
  /// проверки сервера (Node.exitCountry — Deep Probe, Cloudflare trace через
  /// сам сервер, «Оникс»).
  Country detected(Node n) {
    final byName = countryOfName(n.name);
    if (byName.isKnown) return byName;
    final exit = n.exitCountry;
    return exit == null ? Country.unknown : countryByCode(exit);
  }

  /// Откуда страна — для подписи в меню сервера и в выборе страны.
  CountrySource sourceOf(Node n) {
    if (isPicked(n) && countryByCode(overrides[n.serverKey]!).isKnown) return CountrySource.picked;
    if (countryOfName(n.name).isKnown) return CountrySource.name;
    if (n.exitCountry != null && countryByCode(n.exitCountry!).isKnown) return CountrySource.probe;
    return CountrySource.none;
  }

  /// Как страна определилась бы без выбора пользователя — для строки
  /// «Определять автоматически»: «по названию», «по проверке сервера» или null.
  String? detectedHow(Node n) {
    if (countryOfName(n.name).isKnown) return 'по названию';
    if (n.exitCountry != null && countryByCode(n.exitCountry!).isKnown) return 'по проверке сервера';
    return null;
  }

  /// Страну выбрал пользователь.
  bool isPicked(Node n) => overrides.containsKey(n.serverKey);
}

/// Откуда взялась страна сервера.
enum CountrySource {
  picked('Выбрана вручную'),
  name('Определена по названию'),
  probe('Определена по проверке сервера'),
  none('Пока не определилась — уточнится после проверки');

  const CountrySource(this.label);
  final String label;
}

final countryResolverProvider =
    Provider<CountryResolver>((ref) => CountryResolver(ref.watch(countryOverridesProvider)));
