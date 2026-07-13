import 'package:flutter/material.dart';

import '../theme/nova_gradients.dart';
import '../theme/nova_radii.dart';
import '../theme/nova_theme.dart';

enum NovaButtonVariant { primary, secondary, ghost, danger }

/// The Nova button. The primary variant uses the signature gradient fill with
/// the accent elevation shadow; secondary/ghost are translucent surfaces with a
/// hairline border, matching the site's button styles.
class NovaButton extends StatelessWidget {
  const NovaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = NovaButtonVariant.primary,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final NovaButtonVariant variant;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final bool enabled = onPressed != null && !loading;
    final bool isPrimary = variant == NovaButtonVariant.primary;

    final Color fg = switch (variant) {
      NovaButtonVariant.primary => nova.onAccent,
      NovaButtonVariant.danger => nova.danger,
      _ => nova.text,
    };

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (loading)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null) ...<Widget>[
          Icon(icon, size: 18, color: fg),
        ],
        if ((icon != null || loading)) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: fg),
          ),
        ),
      ],
    );

    final BoxDecoration decoration = switch (variant) {
      NovaButtonVariant.primary => BoxDecoration(
          gradient: NovaGradients.signature,
          borderRadius: NovaRadii.pillR,
          boxShadow: enabled ? NovaElevation.accent(nova.indigoStrong) : null,
        ),
      NovaButtonVariant.danger => BoxDecoration(
          color: nova.danger.withValues(alpha: 0.12),
          borderRadius: NovaRadii.pillR,
          border: Border.all(color: nova.danger.withValues(alpha: 0.4)),
        ),
      NovaButtonVariant.secondary => BoxDecoration(
          color: nova.surface2,
          borderRadius: NovaRadii.pillR,
          border: Border.all(color: nova.borderStrong),
        ),
      NovaButtonVariant.ghost => BoxDecoration(
          color: Colors.transparent,
          borderRadius: NovaRadii.pillR,
          border: Border.all(color: nova.border),
        ),
    };

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: NovaRadii.pillR,
          onTap: enabled ? onPressed : null,
          splashColor: isPrimary
              ? Colors.white.withValues(alpha: 0.12)
              : nova.cyan.withValues(alpha: 0.10),
          child: Ink(
            decoration: decoration,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(
                horizontal: NovaSpace.xl,
                vertical: NovaSpace.md,
              ),
              alignment: Alignment.center,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
