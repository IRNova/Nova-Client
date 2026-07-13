import 'package:flutter/material.dart';

import '../theme/nova_radii.dart';
import '../theme/nova_theme.dart';

/// A surface card — translucent fill + hairline border + 16px radius, the
/// workhorse container of the Nova design language.
class NovaCard extends StatelessWidget {
  const NovaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NovaSpace.lg),
    this.onTap,
    this.raised = false,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Uses the brighter `surface-2` fill for hover/active emphasis.
  final bool raised;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final Widget body = Padding(padding: padding, child: child);

    // Paint the surface on a Material (not a bare DecoratedBox) so that any
    // ListTile/SwitchListTile descendants find a Material ancestor below the
    // card's background — otherwise Flutter asserts their ink/background would
    // be hidden by the card's colored box.
    return Material(
      color: raised ? nova.surface2 : nova.surface,
      shape: RoundedRectangleBorder(
        borderRadius: NovaRadii.cardR,
        side: BorderSide(color: borderColor ?? nova.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// A small uppercased "eyebrow" label in the accent color — used above section
/// headings, matching the site's `--tracking-eyebrow` treatment.
class NovaEyebrow extends StatelessWidget {
  const NovaEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    // Eyebrows are a Latin treatment; never uppercase/letter-space Farsi.
    final bool isFarsi = Directionality.of(context) == TextDirection.rtl;
    return Text(
      isFarsi ? text : text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: nova.cyan,
            letterSpacing: isFarsi ? 0 : 1.6,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
