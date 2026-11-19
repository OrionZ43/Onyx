import 'package:flutter/foundation.dart';

/// Платформа для решений в UI. В отличие от `dart:io` `Platform`, учитывает
/// `debugDefaultTargetPlatformOverride` — golden-тесты рисуют «телефон» на
/// Windows-хосте.
bool get uiIsAndroid => defaultTargetPlatform == TargetPlatform.android;
bool get uiIsWindows => defaultTargetPlatform == TargetPlatform.windows;
