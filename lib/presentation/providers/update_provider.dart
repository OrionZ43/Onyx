import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log_service.dart';
import '../../infrastructure/update_service.dart';

final updateServiceProvider = Provider((ref) => UpdateService());

final updateControllerProvider =
    AsyncNotifierProvider<UpdateController, UpdateInfo?>(() {
  return UpdateController();
});

class UpdateController extends AsyncNotifier<UpdateInfo?> {
  @override
  Future<UpdateInfo?> build() async {
    // Initial delay to avoid slowing down app startup
    await Future.delayed(const Duration(seconds: 3));
    return _checkForUpdate();
  }

  Future<UpdateInfo?> _checkForUpdate() async {
    try {
      final updateService = ref.read(updateServiceProvider);
      return await updateService.checkForUpdate();
    } catch (e) {
      log.w('Проверка обновлений не удалась: $e', tag: 'UPDATE');
      return null;
    }
  }

  Future<void> checkNow() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _checkForUpdate());
  }
}