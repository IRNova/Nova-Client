import 'package:flutter/material.dart';

import '../theme/nova_gradients.dart';

/// Text painted with the Nova signature gradient — used for headline accents
/// and brand wordmarks, matching the gradient-text treatment on the site.
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final Gradient? gradient;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final Gradient g = gradient ?? NovaGradients.signature;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) => g.createShader(bounds),
      child: Text(
        text,
        textAlign: textAlign,
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}
