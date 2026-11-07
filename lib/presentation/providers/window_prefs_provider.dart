import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Запускать свёрнутым в трей» (Windows). Читается в main() до показа окна.
class StartMinimizedNotifier extends StateNotifier<bool> {
  StartMinimizedNotifier([super.state = false]);

  static const key = 'window_start_minimized';

  Future<void> set(bool v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }
}

final startMinimizedProvider = StateNotifierProvider<StartMinimizedNotifier, bool>((ref) => StartMinimizedNotifier());
