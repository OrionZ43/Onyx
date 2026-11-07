import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/onyx_tokens.dart';

/// Тумблер темы. Material — стандартный M3 `Switch`; Onyx — компактный
/// 30×18 с шампань-ручкой; Signal — 40×24, белый трек и чёрная ручка.
class OnyxSwitch extends StatelessWidget {
  const OnyxSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) return Switch(value: value, onChanged: onChanged);
    final signal = t.isSignal;
    final w = signal ? 40.0 : 30.0, h = signal ? 24.0 : 18.0;
    final knob = signal ? 15.0 : 12.0;
    final track = value ? (signal ? t.text : const Color(0xFF2A2418)) : (signal ? t.surfaceHigh : t.surfaceTop);
    final border = value ? (signal ? t.text : const Color(0xFF4A3F2C)) : t.lineStrong;
    final thumb = value ? (signal ? t.bg : t.accent) : t.textFaint;
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              },
        child: AnimatedContainer(
          duration: OnyxMotion.fast,
          curve: OnyxMotion.enter,
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(color: border, width: signal ? 1.5 : 1),
          ),
          child: AnimatedAlign(
            duration: OnyxMotion.fast,
            curve: OnyxMotion.enter,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: (h - knob) / 2 - (signal ? 1.5 : 1)),
              child: Container(width: knob, height: knob, decoration: BoxDecoration(shape: BoxShape.circle, color: thumb)),
            ),
          ),
        ),
      ),
    );
  }
}
